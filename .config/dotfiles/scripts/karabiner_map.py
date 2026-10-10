#!/usr/bin/env python3
"""Generate the GitHub-readable MacBook US keymap from Karabiner JSON; stdlib only."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from xml.sax.saxutils import escape

CONFIG = '.config/karabiner/karabiner.json'
OUTPUTS = ('.config/karabiner/keymap.svg', '.config/karabiner/README.md')
ALIASES = {'left_alt': 'left_option', 'right_alt': 'right_option', 'alt': 'option'}
NAMES = {
    'left_option': '左Option', 'right_option': '右Option', 'option': 'Option',
    'left_control': '左Control', 'right_control': '右Control', 'control': 'Control',
    'left_command': '左Command', 'right_command': '右Command', 'command': 'Command',
    'left_shift': '左Shift', 'right_shift': '右Shift', 'shift': 'Shift',
    'caps_lock': 'Caps Lock', 'tab': 'Tab', 'escape': 'Esc', 'return_or_enter': 'Return',
    'spacebar': 'Space', 'fn': 'Fn', 'delete_or_backspace': 'Delete（後方削除）',
    'delete_forward': '前方削除', 'japanese_eisuu': '英数', 'japanese_kana': 'かな',
    'vk_none': '無効', 'left_arrow': '←', 'down_arrow': '↓', 'up_arrow': '↑', 'right_arrow': '→',
}


def canonical(name):
    return ALIASES.get(name, name)


def name(code):
    code = canonical(code)
    return NAMES.get(code, code.upper() if len(code) == 1 or code.startswith('f') and code[1:].isdigit() else code)


def layout():
    """ANSI key positions in units; independent of any remapping or prose."""
    def k(code, printed=None, units=1):
        return {'code': code, 'printed': printed or name(code), 'units': units}
    rows = [
        [k('escape', 'esc', 1.5)] + [k('f' + str(i)) for i in range(1, 13)] + [k('touch_id', 'Touch ID', 1.5)],
        [k(c) for c in '`1234567890-='] + [k('delete_or_backspace', 'delete', 2)],
        [k('tab', 'tab', 1.5)] + [k(c) for c in 'qwertyuiop[]'] + [k('backslash', '\\', 1.5)],
        [k('caps_lock', 'caps lock', 1.75)] + [k(c) for c in "asdfghjkl;'"] + [k('return_or_enter', 'return', 2.25)],
        [k('left_shift', 'shift', 2.25)] + [k(c) for c in 'zxcvbnm,./'] + [k('right_shift', 'shift', 2.75)],
        [k('fn', 'fn / 🌐'), k('left_control', 'control'), k('left_option', 'option'),
         k('left_command', 'command', 1.25), k('spacebar', 'space', 5.25),
         k('right_command', 'command', 1.25), k('right_option', 'option'),
         k('left_arrow', '←', 13/12), k('up_arrow', '↑', 13/12), k('right_arrow', '→', 13/12)],
    ]
    for r, row in enumerate(rows):
        x = 0
        for item in row:
            item.update(x=x, row=r)
            if r == 5 and item['code'] in {'left_arrow', 'right_arrow'}:
                item.update(y_offset=26, height=24)
            if r == 5 and item['code'] == 'up_arrow':
                item.update(height=24)
            x += item['units']
    rows[5].append(dict(code='down_arrow', printed='↓', units=13/12, x=11.75+13/12, row=5, y_offset=26, height=24))
    return [item for row in rows for item in row]


def require_fields(obj, allowed, context):
    unknown = set(obj) - set(allowed)
    if unknown:
        raise ValueError(context + ': unsupported fields ' + ', '.join(sorted(unknown)) + '; extend the keymap renderer before changing this rule')


def output(events, allow_modifiers=False):
    if len(events) != 1:
        raise ValueError('keymap renderer requires one output event; extend it for sequences')
    event = events[0]
    allowed = {'key_code', 'lazy', 'repeat'}
    if allow_modifiers:
        allowed.add('modifiers')
    require_fields(event, allowed, 'to event')
    code = event.get('key_code')
    if not isinstance(code, str):
        raise ValueError('keymap renderer requires a named key_code output')
    return canonical(code)


def model(config):
    profiles = [p for p in config['profiles'] if p.get('selected')]
    if len(profiles) != 1:
        raise ValueError('exactly one selected profile is required')
    profile = profiles[0]
    if profile.get('devices') or profile.get('fn_function_keys'):
        raise ValueError('extend the renderer for device-specific or function-key modifications')
    simple = {}
    for item in profile.get('simple_modifications', []):
        require_fields(item, {'from', 'to'}, 'simple modification')
        require_fields(item['from'], {'key_code'}, 'simple from')
        code = canonical(item['from']['key_code'])
        if code in simple:
            raise ValueError('duplicate simple mapping: ' + code)
        simple[code] = output(item['to'])
    singles, chords = {}, []
    for rule in profile.get('complex_modifications', {}).get('rules', []):
        for manipulator in rule['manipulators']:
            require_fields(manipulator, {'type', 'from', 'to', 'to_if_alone', 'parameters', 'description'}, 'manipulator')
            if manipulator['type'] != 'basic':
                raise ValueError('extend the renderer for non-basic manipulators')
            origin = manipulator['from']
            require_fields(origin, {'key_code', 'modifiers'}, 'complex from')
            code = canonical(origin['key_code'])
            mods = origin.get('modifiers', {})
            require_fields(mods, {'mandatory', 'optional'}, 'from modifiers')
            mandatory = [canonical(m) for m in mods.get('mandatory', [])]
            optional = [canonical(m) for m in mods.get('optional', [])]
            held = output(manipulator.get('to', []), allow_modifiers=bool(mandatory))
            if mandatory:
                if 'to_if_alone' in manipulator:
                    raise ValueError('extend the renderer for tap behavior on a chord')
                to_modifiers = manipulator['to'][0].get('modifiers', [])
                if not isinstance(to_modifiers, list) or any(not isinstance(m, str) for m in to_modifiers):
                    raise ValueError('to.modifiers must be a list of named modifiers')
                chords.append({'code': code, 'mandatory': mandatory, 'optional': optional,
                               'to': held, 'to_modifiers': [canonical(m) for m in to_modifiers]})
            else:
                if code in singles:
                    raise ValueError('extend the renderer for multiple/contextual mappings of ' + code)
                if optional != ['any']:
                    raise ValueError('extend the renderer for modifier-dependent single-key mappings')
                alone = manipulator.get('to_if_alone')
                if alone and not manipulator['to'][0].get('lazy'):
                    raise ValueError('extend the renderer for non-lazy tap/hold behavior')
                singles[code] = ([('単押し', output(alone)), ('併用', held)] if alone else
                                 [('併用' if manipulator['to'][0].get('lazy') else '押す', held)])
    keys = layout()
    known = {k['code'] for k in keys}
    if (set(simple) | set(singles) | {c['code'] for c in chords}) - known:
        raise ValueError('a mapped key is missing from the MacBook US layout; extend layout()')
    if set(singles) & {c['code'] for c in chords}:
        raise ValueError('extend the renderer for overlapping single-key and chord rules')
    bindings = {}
    for key in keys:
        code = key['code']
        intermediate = simple.get(code, code)
        actions = singles.get(intermediate, [('押す', intermediate)])
        if code in simple or intermediate in singles:
            bindings[code] = actions
    # Simple Modifications run before Complex Modifications. A physical H
    # remapped to L must display the L chord, never the original H chord.
    physical_chords = []
    for key in keys:
        for chord in chords:
            if simple.get(key['code'], key['code']) == chord['code']:
                physical_chords.append(dict(chord, code=key['code']))
    return profile['name'], keys, bindings, physical_chords


def short(code):
    return {'delete_or_backspace': 'Delete', 'left_option': 'Option', 'right_option': 'Option',
            'left_control': 'Control', 'right_control': 'Control', 'left_command': 'Command',
            'right_command': 'Command'}.get(code, name(code))


def key_label(code):
    return {'left_option': '⌥', 'right_option': '⌥', 'option': '⌥',
            'left_control': '⌃', 'right_control': '⌃', 'control': '⌃',
            'left_command': '⌘', 'right_command': '⌘', 'command': '⌘',
            'left_shift': '⇧', 'right_shift': '⇧', 'shift': '⇧'}.get(code, short(code))


def destination(chord, compact=False):
    mods = chord.get('to_modifiers', [])
    if mods == ['left_option'] and chord['to'] in {'left_arrow', 'right_arrow'}:
        word = '単語' + short(chord['to'])
        return word if compact else 'Option + ' + short(chord['to']) + '（' + word + '）'
    return ' + '.join([short(m) for m in mods] + [short(chord['to'])])


def render_svg(profile, keys, bindings, chords, digest):
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" role="img" aria-labelledby="title desc" fill="none" stroke-linecap="round" stroke-linejoin="round">',
             '<title id="title">MacBook US配列：Karabinerの現在の割り当て</title>',
             '<desc id="desc">' + escape('。'.join(name(k) + ': ' + ' / '.join(when + ' ' + name(to) for when, to in actions) for k, actions in bindings.items())) + '</desc>',
             '<!-- Generated by .config/dotfiles/scripts/karabiner_map.py. Do not edit. -->',
             '<rect width="1200" height="900" rx="16" fill="#f8fafc"/>']
    def text(x, y, value, size=18, color='#17233b', weight=400, anchor='start'):
        parts.append('<text x="%s" y="%s" font-family="-apple-system, BlinkMacSystemFont, Helvetica, Arial, Noto Sans CJK JP, sans-serif" font-size="%s" font-weight="%s" fill="%s" text-anchor="%s">%s</text>' % (x, y, size, weight, color, anchor, escape(value)))
    def path(d, color='#8090a6'):
        parts.append('<path d="%s" stroke="%s" stroke-width="1.5"/>' % (d, color))
    text(32, 49, 'MacBook US配列 · 現在のKarabiner割り当て', 30, weight=600)
    text(32, 82, '選択プロファイル：' + profile + '  ｜  印字は上、割り当ては下', 17, '#51627a')
    text(32, 118, '青：変更・兼用キー    オレンジ：Delete    グレー：変更なし／無効', 16, '#51627a')
    unit, left, top, pitch = 75, 37.5, 294, 58
    positions = {k['code']: k for k in keys}
    parts.append('<rect x="27" y="283" width="1146" height="360" rx="16" fill="#dce2e9"/>')
    for key in keys:
        code = key['code']
        x, y = left + key['x'] * unit + 3, top + key['row'] * pitch + key.get('y_offset', 0)
        width, height = key['units'] * unit - 6, key.get('height', 50)
        actions = bindings.get(code, [])
        chord = next((c for c in chords if c['code'] == code), None)
        disabled = actions == [('押す', 'vk_none')]
        deletion = actions == [('押す', 'delete_or_backspace')]
        fill = '#f8e0b3' if deletion else '#cadff3' if actions or chord else '#263244'
        ink = '#17233b' if actions or chord else '#f4f7fc'
        if disabled:
            fill, ink = '#bac3cf', '#394b61'
        parts.append('<g data-key="%s"><rect x="%.2f" y="%.2f" width="%.2f" height="%s" rx="6" fill="%s"/>' % (escape(code), x, y, width, height, fill))
        text(x+width/2, y+(19 if actions or chord else height/2+6), key['printed'], 16, ink, 500, 'middle')
        if actions:
            label = ' / '.join(key_label(to) if len(actions) > 1 else short(to) for _, to in actions)
            text(x+width/2, y+39, label, 16, ink, anchor='middle')
        elif chord:
            label = destination(chord, compact=True) if chord.get('to_modifiers') else '+'.join(key_label(m) for m in chord['mandatory']) + ' → ' + short(chord['to'])
            text(x+width/2, y+39, label, 16, ink, anchor='middle')
        if code in {'f', 'j'}:
            path('M %.2f %.2f h 12' % (x+width/2-6, y+height-6), ink)
        parts.append('</g>')
    def note(code, x, y):
        text(x, y, '右上Delete' if code == 'delete_or_backspace' else name(code), 20, weight=600)
        actions = bindings.get(code, [])
        if not actions:
            text(x, y+28, '通常のControl' if code == 'left_control' else 'Karabinerは変更なし', 16)
        for i, (when, to) in enumerate(actions):
            text(x, y+28*(i+1), when + ' → ' + short(to), 17)
    note('tab', 32, 174)
    note('caps_lock', 300, 174)
    note('delete_or_backspace', 974, 174)
    title = 'Option＋キー（Tab併用でも操作）' if all(c['mandatory'] == ['option'] for c in chords) else '組み合わせ'
    text(566, 174, title, 19, weight=600)
    for i, chord in enumerate(chords):
        value = ' + '.join([name(m) for m in chord['mandatory']] + [name(chord['code'])]) + ' → ' + destination(chord, compact=True)
        text(566+(i//4)*200, 201+(i%4)*23, value, 16)
    if len(chords) > 8:
        raise ValueError('more than eight chords: extend SVG callout layout')
    # Outer leader lines keep the labels clear of the keys.
    for code, lane, endpoint, endpoint_y in [('tab', 20, 32, 250), ('caps_lock', 8, 300, 264)]:
        k = positions[code]
        cy = top + k['row']*pitch + 25
        path('M %.2f %.2f H %s V %s H %s' % (left+3, cy, lane, endpoint_y, endpoint))
    k = positions['delete_or_backspace']
    path('M 1160 377 H 1188 V 247 H 974')
    bottom_notes = [('fn', 32), ('left_control', 216), ('left_option', 400),
                    ('left_command', 584), ('right_command', 768), ('right_option', 952)]
    for i, (code, x) in enumerate(bottom_notes):
        k = positions[code]
        cx = left+(k['x']+k['units']/2)*unit
        lane_y = 718-i*13
        path('M %.2f 634 V %s H %s V 740' % (cx, lane_y, x+12))
        note(code, x, 772)
    text(32, 867, '兼用キーの「併用」＝別のキーと組み合わせる操作。図はKarabinerの割り当てのみ（macOS・アプリ側の設定は含まない）。', 15, '#51627a')
    text(1168, 889, 'config SHA-256: ' + digest[:12], 12, '#51627a', anchor='end')
    parts.append('</svg>')
    return '\n'.join(parts) + '\n'


def render_readme(profile, bindings, chords, digest):
    lines = ['<!-- Generated by .config/dotfiles/scripts/karabiner_map.py. Do not edit. -->',
             '# MacBook US配列の現在の割り当て', '',
             '![MacBook US配列のキー割り当てと注釈](keymap.svg)', '',
             '図をクリックすると拡大できます。キー位置はMacBook US配列の模式図です。', '',
             '**正本：** [karabiner.json](karabiner.json)', '',
             '**選択プロファイル：** ' + profile, '',
             '**設定のSHA-256：** `' + digest + '`', '',
             '## 変更しているキー', '',
             '| 物理キーの印字 | 現在の操作 |', '| --- | --- |']
    for code, actions in bindings.items():
        lines.append('| ' + name(code) + ' | ' + ' ／ '.join(when + ' → ' + name(to) for when, to in actions) + ' |')
    lines += ['', '「単押し」は短く押して離したときの動作です。「併用」は押しながら別のキーを使ったときの修飾キー動作です。単押しはキーを離した時点で送信され、長く押した場合の判定時間はKarabinerの設定に従います。', '',
              '## 組み合わせ', '', '| 入力 | 出力 | 併用できる追加の修飾キー |', '| --- | --- | --- |']
    for chord in chords:
        origin = ' + '.join([name(m) for m in chord['mandatory']] + [name(chord['code'])])
        extra = 'すべて' if 'any' in chord['optional'] else '、'.join(name(m) for m in chord['optional']) or 'なし'
        lines.append('| ' + origin + ' | ' + destination(chord) + ' | ' + extra + ' |')
    if not chords:
        lines.append('| なし | — | — |')
    lines += ['', '組み合わせの修飾キーは機能名です。物理キーの印字とは異なる場合があるため、上の表と合わせて確認してください。許可されていない追加の修飾キーを押した場合は、その組み合わせルールが適用されません。', '',
              '図や表に変更がないキーは、Karabinerでは再割り当てしていません。Fn／地球儀キーの単押し、メディアキー、macOSやアプリのショートカットは、それぞれの設定に従います。', '',
              '行頭・行末移動、単語移動、WezTermのLEADERは [Vim以外の文字編集](../dotfiles/README.md#vim以外の文字編集) を参照してください。Shiftを加えた選択操作は一般的な文章入力欄向けです。ターミナルの選択・編集はシェルやTUIアプリのキーバインドに従います。', '',
              '## 更新方法（人・AIエージェント共通）', '',
              '1. `karabiner.json` を編集します。',
              '2. リポジトリのルート（yadmの場合はHOME）で再生成します。', '',
              '   ```bash', '   python3 .config/dotfiles/scripts/karabiner_map.py', '   python3 .config/dotfiles/scripts/karabiner_map.py --check', '   ```', '',
              '3. SVGを開き、文字や注釈の重なりと割り当てを確認します。',
              '4. JSON・このREADME・SVGを同じコミットに含めます。', '',
              'READMEとSVGは生成物ですが、GitHubで表示するためGit管理します。図や表だけを手編集せず、割り当てはJSON、図の配置や説明の形式は [生成スクリプト](../dotfiles/scripts/karabiner_map.py) を修正してください。', '',
              '既存の `dotfiles check`、pre-commit/pre-push、GitHub Actionsは再生成漏れを検知します。ステージ済みファイルとpush対象のコミットも検証します。', '',
              '条件分岐・デバイス別設定・未対応のイベントを追加した場合、生成はエラーで停止します。スクリプトとテストを拡張して、図が実際より単純な動作を示さないようにしてください。', '',
              '配列の参考：[Apple — MacBook AirのMagic Keyboard](https://support.apple.com/guide/macbook-air/magic-keyboard-apdab672d5e9/mac)。図は独自のSVGで、Appleの製品画像はリポジトリに含めていません。', '']
    return '\n'.join(lines)


def generate(source):
    profile, keys, bindings, chords = model(json.loads(source))
    digest = hashlib.sha256(source).hexdigest()
    return dict(zip(OUTPUTS, [render_svg(profile, keys, bindings, chords, digest), render_readme(profile, bindings, chords, digest)]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--check', action='store_true', help='check freshness without writing')
    args = parser.parse_args()
    try:
        outputs = generate((args.root / CONFIG).read_bytes())
        for rel, content in outputs.items():
            path = args.root / rel
            if args.check:
                if not path.is_file() or path.read_text() != content:
                    raise ValueError('stale keymap: ' + rel + '; run python3 .config/dotfiles/scripts/karabiner_map.py')
            else:
                if path.is_symlink():
                    raise ValueError('refusing symlink output: ' + rel)
                temporary = path.with_suffix(path.suffix + '.tmp')
                temporary.write_text(content)
                temporary.replace(path)
                print('Generated ' + rel)
        return 0
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
