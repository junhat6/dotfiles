#!/usr/bin/env python3
"""Explicit HOME ownership; stdlib only. Never automatically stage or push."""
import argparse
import fnmatch
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import sys
import tempfile
from xml.parsers.expat import ExpatError

MANIFEST = '.config/dotfiles/ownership.json'
# Claude Code reads exactly one user settings file. Orca and other tools write
# machine-specific keys (hooks, permission mode) into it, so the file itself is
# local; only the keys in CLAUDE_SHARED are shared and merged in by `render`.
CLAUDE_SHARED = '.config/dotfiles/claude-settings.json'
CLAUDE_TARGET = '.claude/settings.json'
# Context7 の API キーの正本は 1Password。Claude の起動ごとに Touch ID を求めないよう、
# `dotfiles context7-key` で端末ごとに一度だけキーチェーンへ取り込み、headersHelper
# (scripts/context7-headers.sh) はキーチェーンから読む。
# 人が画面の前にいない端末 (Mac mini) は、Automation 保管庫だけを読めるサービスアカウントの
# トークンをキーチェーンに置き (`dotfiles op-token`)、承認なしで op を使う。サービスアカウントは
# Private 保管庫を読めないため、キーは Automation 保管庫に置く。
CONTEXT7_OP_REF = 'op://Automation/Context7/credential'
OP_TOKEN_SERVICE = 'op-service-account-token'
CONTEXT7_KEY = re.compile(r'[A-Za-z0-9_-]{20,200}')
# Machine-local vault pin for the Obsidian session capture LaunchAgent. Without it,
# watch-and-save.sh auto-selects between two configured vaults and stops otherwise.
SESSION_CAPTURE = '.config/dotfiles/session-capture.local.json'
FORBIDDEN = ['.claude/settings.json', '.claude/settings.local.json', SESSION_CAPTURE, '.gitconfig.local', '.gitconfig.work', '.zshrc.local', '.config/nvim/lazy-lock.json', '.config/nvim/lazyvim.json', '.config/dotfiles/Brewfile.local', '.config/ghostty/*', '.eval-loop/*', 'Library/LaunchAgents/*', '.claude/projects/*', '.claude/logs/*', '.claude/plugins/*', '.claude/history*', '.codex/*', '.ssh/*', '.gnupg/*']


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def run(cmd, cwd, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def session_capture_environment(home):
    """OBSIDIAN_DIR/CODEX_OBSIDIAN_DIR from SESSION_CAPTURE, verified against the vault's Git."""
    path = home / SESSION_CAPTURE
    if path.is_symlink():
        raise ValueError('refusing session capture settings symlink')
    if not path.exists():
        return {}
    settings = json.loads(path.read_bytes())
    if not isinstance(settings, dict) or set(settings) != {'vault', 'repository'} or any(not isinstance(value, str) or not value for value in settings.values()):
        raise ValueError('session capture requires vault and repository strings')
    vault = Path(settings['vault'])
    repository = settings['repository']
    if not vault.is_absolute() or not vault.is_dir() or repository.count('/') != 1 or any(part in {'', '.', '..'} for part in repository.split('/')):
        raise ValueError('session capture requires an existing absolute vault path and owner/repository')
    env = dict(os.environ)
    env.pop('GIT_DIR', None)
    env.pop('GIT_WORK_TREE', None)
    origin = subprocess.run(['git', 'remote', 'get-url', 'origin'], cwd=vault, env=env,
                            check=True, capture_output=True, text=True).stdout.strip().removesuffix('.git')
    if not origin.endswith(('github.com/' + repository, 'github.com:' + repository)):
        raise ValueError('session capture vault has an unexpected Git origin')
    probes = ['claude/__session_probe__.md', 'Codex/__session_probe__.md']
    ignored = subprocess.run(['git', 'check-ignore', '--', *probes], cwd=vault, env=env,
                             capture_output=True, text=True)
    if set(ignored.stdout.splitlines()) != set(probes):
        raise ValueError('session capture folders must be ignored by Git')
    return {'OBSIDIAN_DIR': str(vault / 'claude'), 'CODEX_OBSIDIAN_DIR': str(vault / 'Codex')}


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
            if path.startswith('.claude/') and path not in {'.claude/CLAUDE.md', '.claude/statusline-command.sh'} and not path.startswith(('.claude/commands/', '.claude/rules/', '.claude/hooks/')):
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

    def claude_settings(self, index=False):
        """(target path, current, merged): shared top-level keys replace the local ones."""
        shared = json.loads(self.content(CLAUDE_SHARED, index))
        if not isinstance(shared, dict):
            raise ValueError('shared Claude settings must be an object')
        target = self.root / CLAUDE_TARGET
        if target.is_symlink():
            raise ValueError('refusing symlink: ' + CLAUDE_TARGET)
        current = json.loads(target.read_text()) if target.exists() else {}
        if not isinstance(current, dict):
            raise ValueError(CLAUDE_TARGET + ' must be an object')
        return target, current, {**current, **shared}

    def rendered(self, item, home, index=False):
        text = self.content(item['template'], index).decode()
        from xml.sax.saxutils import escape
        result = text.replace('@HOME@', escape(str(home)))
        if '@HOME@' in result or '{{' in result:
            raise ValueError('unresolved template: ' + item['template'])
        document = plistlib.loads(result.encode())
        if item.get('output') == 'Library/LaunchAgents/com.claude.obsidian-sync.plist':
            environment = session_capture_environment(home)
            if environment:
                document.setdefault('EnvironmentVariables', {}).update(environment)
                return plistlib.dumps(document, sort_keys=False)
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
        if self.revision:
            for entry in self.git('ls-tree', '-r', '-z', self.revision).split(b'\0'):
                if entry and entry.split(b' ', 1)[0] not in {b'100644', b'100755'}:
                    errors.append('non-regular committed entry: ' + entry.decode())
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
                    if path == CLAUDE_SHARED and (not isinstance(doc, dict) or 'hooks' in doc or 'defaultMode' in doc.get('permissions', {})):
                        errors.append('host permission mode/hooks must be local: ' + path)
                    # 共有キーは合成で丸ごと置き換わるため、端末で入れた plugin が同期のたびに消える
                    if path == CLAUDE_SHARED and isinstance(doc, dict) and ({'enabledPlugins', 'extraKnownMarketplaces'} & set(doc)):
                        errors.append('plugins/marketplaces must be local: ' + path)
                if path.endswith('.plist'):
                    plistlib.loads(data.replace(b'@HOME@', b'/portable/home'))
                    if '@HOME@' not in data.decode() or '{{' in data.decode():
                        errors.append('template must use portable @HOME@: ' + path)
            except (OSError, ValueError, ExpatError, plistlib.InvalidFileException, subprocess.CalledProcessError) as exc:
                errors.append('invalid or missing shared file: ' + path + ': ' + str(exc))
        keymap_script = '.config/dotfiles/scripts/karabiner_map.py'
        if keymap_script in m['shared']:
            try:
                # Use the same tree for generator, config, and generated documents:
                # never validate staged/committed content against unstaged files.
                namespace = {'__name__': 'karabiner_map', '__file__': str(self.root / keymap_script)}
                exec(compile(self.content(keymap_script, index), keymap_script, 'exec'), namespace)
                expected = namespace['generate'](self.content(namespace['CONFIG'], index))
                for path, text in expected.items():
                    if self.content(path, index) != text.encode():
                        errors.append('stale keymap: ' + path + ' (run python3 .config/dotfiles/scripts/karabiner_map.py)')
            except (OSError, ValueError, KeyError, TypeError, SyntaxError, subprocess.CalledProcessError) as exc:
                errors.append('invalid keymap: ' + str(exc))
        if discover:
            errors.extend('new candidate (register deliberately or exclude): ' + x for x in self.candidates(m))
        if generated and CLAUDE_SHARED in m['shared']:
            try:
                _, current, merged = self.claude_settings(index)
                if current != merged:
                    errors.append('generated drift: ' + CLAUDE_TARGET + ' (run dotfiles render)')
            except (OSError, ValueError) as exc:
                errors.append('generated missing/invalid: ' + CLAUDE_TARGET + ': ' + str(exc))
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


def op_env():
    """Use this Mac's service account token when stored; otherwise fall back to the desktop app (Touch ID)."""
    found = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', OP_TOKEN_SERVICE, '-w'],
                           capture_output=True, text=True)
    token = found.stdout.strip() if found.returncode == 0 else ''
    return {**os.environ, 'OP_SERVICE_ACCOUNT_TOKEN': token} if token else None


def store_op_token(token):
    if not token.startswith('ops_'):
        raise ValueError('サービスアカウントのトークンは ops_ で始まります')
    subprocess.run(['/usr/bin/security', '-i'], check=True, capture_output=True,
                   input=('add-generic-password -U -a op -s ' + OP_TOKEN_SERVICE +
                          ' -T /usr/bin/security -w ' + token + '\n').encode())


def read_context7_key(reference):
    """Read the key from 1Password (service account if stored, else desktop app integration)."""
    try:
        result = subprocess.run(['op', 'read', '--no-newline', reference], capture_output=True, text=True, env=op_env())
    except FileNotFoundError:
        raise ValueError('op が見つかりません (brew install --cask 1password-cli)')
    if result.returncode:
        raise ValueError('1Password から読めませんでした: ' + result.stderr.strip())
    return result.stdout.strip()


def store_context7_key(key):
    """Keep the API key in this Mac's Keychain (never in dotfiles). Uses stdin, not argv."""
    if not CONTEXT7_KEY.fullmatch(key):
        raise ValueError('Context7 API key has an unexpected format')
    # 既存の項目を上書きすると、macOS がログインキーチェーンのパスワードを画面で求めて止まる
    # (画面の前に人がいない Mac mini では待ち続ける)。同じ値なら書き込まない。
    current = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', 'context7-api-key', '-w'],
                             capture_output=True, text=True)
    if current.returncode == 0 and current.stdout.strip() == key:
        return False
    subprocess.run(['/usr/bin/security', '-i'], check=True, capture_output=True,
                   input=('add-generic-password -U -a context7 -s context7-api-key '
                          '-T /usr/bin/security -w ' + key + '\n').encode())
    return True


def bootstrap_local(home, managed):
    """Set this machine's default permission mode once, in the user settings file.

    Claude Code ignores `auto`/`bypassPermissions` from settings.local.json (v2.1.257+),
    so the mode lives in the now machine-local ~/.claude/settings.json. A mode left in
    settings.local.json by older versions of this script is carried over.
    """
    path = home / CLAUDE_TARGET
    legacy = home / '.claude/settings.local.json'
    for candidate in (path, legacy):
        if candidate.is_symlink():
            raise ValueError('refusing settings symlink: ' + str(candidate))
    settings = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(settings, dict):
        raise ValueError('user settings must be an object')
    permissions = settings.setdefault('permissions', {})
    if not isinstance(permissions, dict):
        raise ValueError('user permissions must be an object')
    if 'defaultMode' not in permissions:
        old = json.loads(legacy.read_text()) if legacy.exists() else {}
        old_mode = old.get('permissions', {}).get('defaultMode') if isinstance(old, dict) and isinstance(old.get('permissions'), dict) else None
        permissions['defaultMode'] = old_mode or ('auto' if managed.exists() else 'bypassPermissions')
        path.parent.mkdir(parents=True, exist_ok=True)
        atomic_write(path, (json.dumps(settings, ensure_ascii=False, indent=2) + '\n').encode())


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
    sub.add_parser('update', help='fetch origin/main and fast-forward HOME without overwriting local edits')
    auto = sub.add_parser('auto-update', help='manage per-machine macOS automatic updates')
    auto.add_argument('action', choices=['enable', 'disable', 'status'])
    sub.add_parser('render')
    c7 = sub.add_parser('context7-key', help="copy the Context7 API key from 1Password into this Mac's Keychain")
    c7.add_argument('--ref', default=CONTEXT7_OP_REF, help='1Password secret reference (op://vault/item/field)')
    sub.add_parser('op-token', help="store this Mac's 1Password service account token in the Keychain (read from prompt/stdin)")
    boot = sub.add_parser('bootstrap-local')
    boot.add_argument('--managed-settings', default='/Library/Application Support/ClaudeCode/managed-settings.json')
    args = parser.parse_args()
    repo = Repository(args.root, args.backend, getattr(args, 'revision', None))
    try:
        if args.command in {'update', 'auto-update'}:
            from sync import update, auto_update
            return update(repo) if args.command == 'update' else auto_update(repo, args.action)
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
        if args.command == 'context7-key':
            if store_context7_key(read_context7_key(args.ref)):
                print('dotfiles: 1Password のキーをキーチェーンへ取り込みました (Claude の次回起動から使われます)')
            else:
                print('dotfiles: キーチェーンのキーは 1Password と同じです (変更なし)')
            return 0
        if args.command == 'op-token':
            import getpass
            token = getpass.getpass('1Password service account token: ') if sys.stdin.isatty() else sys.stdin.readline()
            store_op_token(token.strip())
            print('dotfiles: キーチェーンに保存しました。この Mac の op は承認なしで Automation 保管庫を読めます')
            return 0
        if args.command == 'bootstrap-local':
            bootstrap_local(repo.root, Path(args.managed_settings))
            return 0
        m = repo.manifest()
        if args.command == 'render':
            # Validate every output before replacing any.
            outputs = [(repo.root / x['output'], repo.rendered(x, repo.root)) for x in m['generated']]
            settings = repo.claude_settings() if CLAUDE_SHARED in m['shared'] else None
            for path, data in outputs:
                atomic_write(path, data)
            if settings and settings[1] != settings[2]:
                atomic_write(settings[0], (json.dumps(settings[2], ensure_ascii=False, indent=2) + '\n').encode())
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
