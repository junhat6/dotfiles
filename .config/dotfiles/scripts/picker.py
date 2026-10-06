#!/usr/bin/env python3
"""Read-only shared-file discovery and preview; explicit editor launch."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

from dotfiles import MANIFEST, Repository

LIMIT = 128 * 1024


def safe_file(repo, path):
    if any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise ValueError('control characters in shared path')
    candidate = repo.root / path
    if candidate.is_symlink() or any(p.is_symlink() for p in candidate.parents if p != repo.root):
        raise ValueError('symlink in shared path')
    if not candidate.resolve().is_relative_to(repo.root):
        raise ValueError('shared path escapes root')
    if candidate.exists() and not candidate.is_file():
        raise ValueError('shared path is not a regular file')
    return candidate


def statuses(repo):
    fields = iter(repo.git('status', '--porcelain=v1', '-z', '--untracked-files=all').split(b'\0'))
    result = {}
    for field in fields:
        if not field:
            continue
        status = field[:2].decode('ascii')
        path = os.fsdecode(field[3:])
        result[path] = status
        if 'R' in status or 'C' in status:
            old = next(fields, b'')
            # Renamed-away shared files remain inspectable as deleted entries.
            if old:
                result[os.fsdecode(old)] = 'D '
    return result


def entries(repo, changed=False):
    safe_file(repo, MANIFEST)
    shared = repo.manifest()['shared']
    state = statuses(repo)
    result = []
    tracked = repo.tracked()
    for path in sorted(shared):
        try:
            file = safe_file(repo, path)
        except ValueError:
            continue
        status = state.get(path, '  ')
        if not file.exists() and status == '  ':
            status = ' D'
        if file.exists() and status == '  ' and path not in tracked:
            status = '??'
        item = {'key': hashlib.sha256(path.encode()).hexdigest()[:24], 'path': path,
                'file': str(file), 'status': status, 'changed': status != '  ',
                'deleted': not file.exists()}
        if not changed or item['changed']:
            result.append(item)
    return result


def resolve(repo, key):
    for item in entries(repo):
        if item['key'] == key:
            safe_file(repo, item['path'])
            return item
    raise ValueError('unknown shared-file key')


def clean(text):
    return ''.join(c if c in '\n\t' or ord(c) >= 32 and ord(c) != 127 else '?' for c in text)


def bounded(data):
    if b'\0' in data:
        return '[binary content omitted]\n'
    text = clean(data[:LIMIT].decode('utf-8', errors='replace'))
    return text + ('\n[preview truncated]\n' if len(data) > LIMIT else '')


def large_file(repo, item):
    file = safe_file(repo, item['path'])
    if file.exists() and file.stat().st_size > LIMIT:
        return True
    for revision in (':' + item['path'], 'HEAD:' + item['path']):
        try:
            if int(repo.git('cat-file', '-s', revision)) > LIMIT:
                return True
        except subprocess.CalledProcessError:
            pass
    return False


def preview(repo, key, plain=False):
    item = resolve(repo, key)
    path = item['path']
    out = [path + '\n']
    if item['changed']:
        large = large_file(repo, item)
        for label, args in [('STAGED', ['--cached']), ('UNSTAGED', [])]:
            out.append('\n── ' + label + ' ──\n')
            if large:
                out.append('[large file: diff omitted; preview limit 128 KiB]\n')
                continue
            data = repo.git('diff', '--no-ext-diff', '--no-textconv', '--no-color', *args,
                            '--', ':(literal)' + path)
            out.append(bounded(data) if data else '(no changes)\n')
    file = safe_file(repo, path)
    if item['deleted']:
        out.append('\n[deleted file — Enter will not recreate it]\n')
    elif not item['changed'] or item['status'] == '??':
        out.append('\n── CONTENT ──\n')
        with file.open('rb') as stream:
            data = stream.read(LIMIT + 1)
        text = bounded(data)
        out.extend(f'{n:5}  {line}\n' for n, line in enumerate(text.splitlines(), 1))
    text = ''.join(out)
    if plain:
        return text
    colored = []
    for line in text.splitlines(keepends=True):
        color = '32' if line.startswith('+') else '31' if line.startswith('-') else '36' if line.startswith('──') else None
        colored.append('\x1b[' + color + 'm' + line.rstrip('\n') + '\x1b[0m' + ('\n' if line.endswith('\n') else '') if color else line)
    return ''.join(colored)


def rows(repo, changed=False):
    return ''.join(f"{x['key']}\t{x['status']}\t{x['path']}\n" for x in entries(repo, changed))


def editor_env():
    return {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}


def edit(repo, changed=False, query=None):
    data = rows(repo, changed)
    if not data:
        print('dotfiles: no changed shared files; use dedit to browse all' if changed else 'dotfiles: no approved shared files', file=sys.stderr)
        return 0
    base = [sys.executable, str(Path(__file__).resolve()), '--root', str(repo.root), '--backend', repo.backend]
    command = shlex.join(base)
    reload_current = 'if [ "$FZF_PROMPT" = "changes > " ]; then ' + command + ' list --changed; else ' + command + ' list; fi'
    try:
        width = os.get_terminal_size(sys.stderr.fileno()).columns
    except OSError:
        width = 120
    preview_window = 'right:60%:wrap' if width >= 100 else 'down:50%:wrap'
    args = ['fzf', '--height=80%', '--layout=reverse', '--border', '--color=light', '--delimiter=\t', '--with-nth=2..', '--nth=2..', '--no-multi',
            '--prompt=' + ('changes > ' if changed else 'dotfiles > '), '--header=Enter edit · Ctrl-S changed · Ctrl-A all\nCtrl-/ preview · Ctrl-G lazygit',
            '--preview=' + command + ' preview {1}', '--preview-window=' + preview_window,
            '--bind=ctrl-s:change-prompt(changes > )+reload(' + command + ' list --changed)',
            '--bind=ctrl-a:change-prompt(dotfiles > )+reload(' + command + ' list)', '--bind=ctrl-/:toggle-preview',
            '--bind=ctrl-g:execute(' + command + ' gui)+reload(' + reload_current + ')']
    if query is not None:
        args += ['--query', query]
    selected = subprocess.run(args, input=data, text=True, stdout=subprocess.PIPE, env=editor_env())
    if selected.returncode in (1, 130):
        return 0
    if selected.returncode:
        return selected.returncode
    key = selected.stdout.rstrip('\n').split('\t', 1)[0]
    if not key:
        return 0
    item = resolve(repo, key)
    if item['deleted']:
        print('dotfiles: deleted file; inspect its diff or restore it explicitly', file=sys.stderr)
        return 0
    return subprocess.run(['nvim', '--', item['file']], env=editor_env()).returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default=os.environ.get('HOME'))
    parser.add_argument('--backend', choices=['auto', 'git', 'yadm'], default='auto')
    sub = parser.add_subparsers(dest='command', required=True)
    listing = sub.add_parser('list')
    listing.add_argument('--changed', action='store_true')
    listing.add_argument('--json', action='store_true')
    viewing = sub.add_parser('preview')
    viewing.add_argument('key')
    viewing.add_argument('--plain', action='store_true')
    editing = sub.add_parser('edit')
    editing.add_argument('--changed', action='store_true')
    editing.add_argument('--query')
    sub.add_parser('gui', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    try:
        repo = Repository(args.root, args.backend)
        if args.command == 'list':
            print(json.dumps(entries(repo, args.changed), ensure_ascii=False) if args.json else rows(repo, args.changed), end='\n' if args.json else '')
        elif args.command == 'preview':
            print(preview(repo, args.key, args.plain), end='')
        elif args.command == 'gui':
            command = ['lazygit'] if repo.backend == 'git' else ['yadm', 'enter', 'lazygit']
            return subprocess.run(command, cwd=repo.root, env=editor_env()).returncode
        else:
            return edit(repo, args.changed, args.query)
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print('dotfiles picker: ' + str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
