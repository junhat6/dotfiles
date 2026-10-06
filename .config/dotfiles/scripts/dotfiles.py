#!/usr/bin/env python3
"""Explicit HOME ownership; stdlib only. Never automatically stage or push."""
import argparse
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import subprocess
import sys
import tempfile
from xml.parsers.expat import ExpatError

MANIFEST = '.config/dotfiles/ownership.json'
FORBIDDEN = ['.claude/settings.local.json', '.gitconfig.local', '.gitconfig.work', '.zshrc.local', '.config/nvim/lazy-lock.json', '.config/nvim/lazyvim.json', '.config/dotfiles/Brewfile.local', '.config/ghostty/*', '.eval-loop/*', 'Library/LaunchAgents/*', '.claude/projects/*', '.claude/logs/*', '.claude/plugins/*', '.claude/history*', '.codex/*', '.ssh/*', '.gnupg/*']


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def run(cmd, cwd, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class Repository:
    def __init__(self, root, backend='auto', revision=None):
        self.root = Path(root).resolve()
        if backend == 'auto':
            backend = 'git' if (self.root / '.git').exists() else 'yadm'
        self.backend = backend
        self.revision = revision

    def git(self, *args):
        command = ['git'] if self.backend == 'git' else ['yadm']
        return run(command + list(args), self.root).stdout

    def content(self, path, index=False):
        if self.revision:
            return self.git('show', self.revision + ':' + path)
        if index:
            return self.git('show', ':' + path)
        return (self.root / path).read_bytes()

    def manifest(self, index=False):
        m = json.loads(self.content(MANIFEST, index))
        if m.get('version') != 1 or set(m) != {'version', 'shared', 'local', 'excluded', 'generated', 'discovery_roots'}:
            raise ValueError('invalid ownership schema')
        for field in ('shared', 'local', 'excluded', 'discovery_roots'):
            if not isinstance(m[field], list) or any(not isinstance(x, str) for x in m[field]) or len(m[field]) != len(set(m[field])):
                raise ValueError('invalid or duplicate ownership entries: ' + field)
        for path in m['shared'] + m['local'] + m['discovery_roots']:
            if not path or str(PurePosixPath(path)) != path or PurePosixPath(path).is_absolute() or '..' in PurePosixPath(path).parts or '\\' in path or any(c in path for c in '*?['):
                raise ValueError('ownership requires exact safe relative paths: ' + path)
        for path in m['shared']:
            if matches(path, FORBIDDEN + m['excluded']) or path in m['local']:
                raise ValueError('forbidden shared path: ' + path)
            if path.startswith('.claude/') and path not in {'.claude/CLAUDE.md', '.claude/settings.json', '.claude/statusline-command.sh'} and not path.startswith(('.claude/commands/', '.claude/rules/', '.claude/hooks/')):
                raise ValueError('Claude runtime cannot be shared: ' + path)
        for item in m['generated']:
            if set(item) != {'template', 'output'} or item['template'] not in m['shared'] or not item['output'].startswith('Library/LaunchAgents/') or Path(item['output']).name != item['output'].split('/')[-1] or '..' in PurePosixPath(item['output']).parts:
                raise ValueError('invalid generated ownership')
        return m

    def tracked(self):
        if self.revision:
            return {p.decode() for p in self.git('ls-tree', '-r', '--name-only', '-z', self.revision).split(b'\0') if p}
        return {p.decode() for p in self.git('ls-files', '-z').split(b'\0') if p}

    def candidates(self, m):
        result = []
        for base in m['discovery_roots']:
            directory = self.root / base
            if not directory.exists():
                continue
            for path in directory.rglob('*'):
                if not path.is_file() or path.is_symlink():
                    continue
                rel = path.relative_to(self.root).as_posix()
                if rel not in m['shared'] and rel not in m['local'] and not matches(rel, m['excluded'] + FORBIDDEN):
                    result.append(rel)
        return sorted(set(result))

    def unknown_config_directories(self, m):
        config = self.root / '.config'
        known = {x.split('/')[1] for x in m['shared'] + m['local'] if x.startswith('.config/')}
        return sorted('.config/' + p.name for p in config.iterdir() if p.is_dir() and p.name not in known) if config.exists() else []

    def rendered(self, item, home, index=False):
        text = self.content(item['template'], index).decode()
        from xml.sax.saxutils import escape
        result = text.replace('@HOME@', escape(str(home)))
        if '@HOME@' in result or '{{' in result:
            raise ValueError('unresolved template: ' + item['template'])
        plistlib.loads(result.encode())
        return result.encode()

    def check(self, index=False, generated=True, discover=True):
        errors = []
        m = self.manifest(index)
        tracked = self.tracked()
        for path in sorted(tracked - set(m['shared'])):
            errors.append('unapproved tracked path: ' + path)
        if index and not self.revision:
            for entry in self.git('ls-files', '--stage', '-z').split(b'\0'):
                if entry and entry.split(b' ', 1)[0] not in {b'100644', b'100755'}:
                    errors.append('non-regular index entry: ' + entry.decode())
        for path in m['shared']:
            try:
                data = self.content(path, index)
                if not index and not self.revision and (self.root / path).is_symlink():
                    errors.append('shared path must be a regular file: ' + path)
                shell = None
                if path in {'.zshrc', '.zprofile'} or path.endswith('.zsh'):
                    shell = 'zsh'
                elif path.endswith('.sh') or path in {'.local/bin/dotfiles', '.local/bin/git-pull-summary', '.config/yadm/bootstrap', '.config/dotfiles/git-hooks/pre-commit', '.config/dotfiles/git-hooks/pre-push'}:
                    shell = 'bash'
                if shell:
                    result = subprocess.run([shell, '-n'], input=data, capture_output=True)
                    if result.returncode:
                        errors.append('invalid shell syntax: ' + path + ': ' + result.stderr.decode().strip())
                if path.endswith('.py'):
                    import ast
                    try:
                        ast.parse(data, filename=path)
                    except SyntaxError as exc:
                        errors.append('invalid Python syntax: ' + path + ': ' + str(exc))
                if path == '.gitconfig':
                    result = subprocess.run(['git', 'config', '--file', '/dev/stdin', '--list'], input=data, capture_output=True)
                    if result.returncode:
                        errors.append('invalid Git syntax: ' + path)
                if path.endswith('.json'):
                    doc = json.loads(data)
                    if path == '.claude/settings.json' and ('defaultMode' in doc.get('permissions', {}) or 'hooks' in doc):
                        errors.append('host permission mode/hooks must be local')
                if path.endswith('.plist'):
                    plistlib.loads(data.replace(b'@HOME@', b'/portable/home'))
                    if '@HOME@' not in data.decode() or '{{' in data.decode():
                        errors.append('template must use portable @HOME@: ' + path)
                if path == '.config/mise/config.toml' and (b'gemini-cli' in data or b'\nopencode =' in data):
                    errors.append('removed tools in mise')
                if path == '.config/dotfiles/Brewfile' and any(x in data for x in [b'cask "ghostty"', b'brew "chezmoi"', b'brew "stow"']):
                    errors.append('removed packages in Brewfile')
            except (OSError, ValueError, ExpatError, plistlib.InvalidFileException, subprocess.CalledProcessError) as exc:
                errors.append('invalid or missing shared file: ' + path + ': ' + str(exc))
        if discover:
            errors.extend('new candidate (register deliberately or exclude): ' + x for x in self.candidates(m))
        if generated:
            for item in m['generated']:
                output = self.root / item['output']
                try:
                    if output.is_symlink() or output.read_bytes() != self.rendered(item, self.root, index):
                        errors.append('generated drift: ' + item['output'] + ' (run dotfiles render)')
                except (OSError, ValueError, ExpatError, plistlib.InvalidFileException):
                    errors.append('generated missing/invalid: ' + item['output'] + ' (run dotfiles render)')
        return errors


def atomic_write(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('refusing symlink: ' + str(path))
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(data)
    try:
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def bootstrap_local(home, managed):
    path = home / '.claude/settings.local.json'
    if path.is_symlink():
        raise ValueError('refusing local settings symlink')
    settings = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(settings, dict):
        raise ValueError('local settings must be an object')
    permissions = settings.setdefault('permissions', {})
    if not isinstance(permissions, dict):
        raise ValueError('local permissions must be an object')
    if 'defaultMode' not in permissions:
        permissions['defaultMode'] = 'auto' if managed.exists() else 'bypassPermissions'
        atomic_write(path, (json.dumps(settings, ensure_ascii=False, indent=2) + '\n').encode(), 0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=os.environ.get('HOME'))
    parser.add_argument('--backend', choices=['auto', 'git', 'yadm'], default='auto')
    sub = parser.add_subparsers(dest='command', required=True)
    status = sub.add_parser('status')
    status.add_argument('--json', action='store_true')
    check = sub.add_parser('check')
    check.add_argument('--index', action='store_true')
    check.add_argument('--revision', help='validate a committed Git tree (e.g. HEAD)')
    check.add_argument('--source', action='store_true', help='checkout validation: no generated HOME outputs/discovery')
    add = sub.add_parser('add')
    add.add_argument('paths', nargs='+')
    files = sub.add_parser('files', help='list approved shared files for terminal/editor pickers')
    files.add_argument('--changed', action='store_true')
    files.add_argument('--json', action='store_true')
    preview = sub.add_parser('preview', help='preview staged/unstaged changes for a picker key')
    preview.add_argument('key')
    preview.add_argument('--plain', action='store_true')
    edit = sub.add_parser('edit', help='search shared files with diff preview and open in Neovim')
    edit.add_argument('--changed', action='store_true')
    edit.add_argument('--query', default='')
    sub.add_parser('render')
    boot = sub.add_parser('bootstrap-local')
    boot.add_argument('--managed-settings', default='/Library/Application Support/ClaudeCode/managed-settings.json')
    args = parser.parse_args()
    repo = Repository(args.root, args.backend, getattr(args, 'revision', None))
    try:
        if args.command in {'files', 'preview', 'edit'}:
            from picker import main as picker_main
            picker_args = ['--root', str(repo.root), '--backend', repo.backend,
                           'list' if args.command == 'files' else args.command]
            if getattr(args, 'changed', False):
                picker_args.append('--changed')
            if getattr(args, 'json', False):
                picker_args.append('--json')
            if args.command == 'preview':
                picker_args.append(args.key)
                if args.plain:
                    picker_args.append('--plain')
            if args.command == 'edit' and args.query:
                picker_args.extend(['--query', args.query])
            return picker_main(picker_args)
        if args.command == 'bootstrap-local':
            bootstrap_local(repo.root, Path(args.managed_settings))
            return 0
        m = repo.manifest()
        if args.command == 'render':
            # Validate every output before replacing any.
            outputs = [(repo.root / x['output'], repo.rendered(x, repo.root)) for x in m['generated']]
            for path, data in outputs:
                atomic_write(path, data)
            return 0
        if args.command == 'status':
            result = {'git': repo.git('status', '--short', '--untracked-files=no').decode(), 'candidates': repo.candidates(m), 'unknown_config_directories': repo.unknown_config_directories(m), 'errors': repo.check()}
            if args.json:
                print(json.dumps(result, ensure_ascii=False))
            else:
                print(result['git'], end='')
                print('\n'.join(result['errors']))
                for path in result['unknown_config_directories']:
                    print('unregistered config directory (review ownership): ' + path)
            return int(bool(result['errors']))
        if args.command == 'add':
            paths = []
            for supplied in args.paths:
                candidate = Path(supplied)
                if not candidate.is_absolute():
                    candidate = Path.cwd() / candidate
                # lexically normalize while rejecting symlink traversal.
                rel = Path(os.path.abspath(candidate)).relative_to(repo.root).as_posix()
                if rel not in m['shared'] or (repo.root / rel).is_symlink() or any(p.is_symlink() for p in (repo.root / rel).parents if p != repo.root):
                    raise ValueError('register an exact shared file before adding: ' + rel)
                paths.append(rel)
            repo.git('add', '--', *paths)
            return 0
        errors = repo.check(args.index, not args.source, not args.source)
        if errors:
            print('\n'.join(errors), file=sys.stderr)
            return 1
        print('dotfiles ownership/content checks passed')
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as exc:
        print('dotfiles: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
