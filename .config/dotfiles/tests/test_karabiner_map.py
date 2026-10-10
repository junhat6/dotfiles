"""Verify truthful keymap generation, including rejected unsupported semantics."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location('karabiner_map', ROOT / '.config/dotfiles/scripts/karabiner_map.py')
MAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAP)


class KarabinerMap(unittest.TestCase):
    def setUp(self):
        # A fixed input fixture keeps future real keymap changes from requiring
        # edits to renderer tests. The freshness check covers the real JSON.
        def single(key, to, alone=None):
            m = {'type': 'basic', 'from': {'key_code': key, 'modifiers': {'optional': ['any']}},
                 'to': [{'key_code': to}]}
            if alone:
                m['to'][0]['lazy'] = True
                m['to_if_alone'] = [{'key_code': alone}]
            return m
        self.config = {'profiles': [{
            'name': 'Fixture', 'selected': True,
            'simple_modifications': [
                {'from': {'key_code': 'left_option'}, 'to': [{'key_code': 'delete_or_backspace'}]},
                {'from': {'key_code': 'left_control'}, 'to': [{'key_code': 'right_option'}]},
                {'from': {'key_code': 'delete_or_backspace'}, 'to': [{'key_code': 'vk_none'}]},
            ],
            'complex_modifications': {'rules': [{'manipulators': [
                {'type': 'basic', 'from': {'key_code': k, 'modifiers': {'mandatory': ['option'], 'optional': ['caps_lock']}},
                 'to': [{'key_code': to}]} for k, to in zip('hjkl', ['left_arrow', 'down_arrow', 'up_arrow', 'right_arrow'])
            ] + [single('tab', 'left_alt', 'tab'), single('caps_lock', 'left_control', 'escape'),
                 single('left_command', 'left_command', 'japanese_eisuu'), single('right_command', 'japanese_kana')]}]},
        }]}

    def test_single_tap_and_chord_mappings(self):
        _, keys, bindings, chords = MAP.model(self.config)
        self.assertEqual(bindings['left_option'], [('押す', 'delete_or_backspace')])
        self.assertEqual(bindings['left_control'], [('押す', 'right_option')])
        self.assertEqual(bindings['right_command'], [('押す', 'japanese_kana')])
        self.assertEqual(bindings['delete_or_backspace'], [('押す', 'vk_none')])
        self.assertNotIn('right_shift', bindings)
        self.assertEqual(bindings['tab'], [('単押し', 'tab'), ('併用', 'left_option')])
        self.assertEqual([c['to'] for c in chords], ['left_arrow', 'down_arrow', 'up_arrow', 'right_arrow'])
        self.assertTrue(all(c['optional'] == ['caps_lock'] for c in chords))
        right = next(k for k in keys if k['code'] == 'right_arrow')
        self.assertAlmostEqual(right['x'] + right['units'], 15)

    def test_changed_assignment_regenerates_both_outputs(self):
        config = copy.deepcopy(self.config)
        profile = next(p for p in config['profiles'] if p.get('selected'))
        remap = next(m for m in profile['simple_modifications'] if m['from']['key_code'] == 'left_option')
        remap['from']['key_code'] = 'right_option'
        outputs = MAP.generate(json.dumps(config).encode())
        svg = ET.fromstring(outputs[MAP.OUTPUTS[0]])
        changed = svg.find(".//*[@data-key='right_option']/{http://www.w3.org/2000/svg}text[last()]")
        self.assertEqual(changed.text, 'Delete')
        readme = outputs[MAP.OUTPUTS[1]]
        self.assertIn('| 右Option | 押す → Delete（後方削除） |', readme)
        self.assertNotIn('| 左Option |', readme)

    def test_unsupported_conditions_are_not_silently_omitted(self):
        m = self.config['profiles'][0]['complex_modifications']['rules'][0]['manipulators'][0]
        m['conditions'] = [{'type': 'frontmost_application_if', 'bundle_identifiers': ['com.example.app']}]
        with self.assertRaisesRegex(ValueError, 'unsupported fields conditions'):
            MAP.generate(json.dumps(self.config).encode())

    def test_unsupported_device_specific_mapping_is_rejected(self):
        self.config['profiles'][0]['devices'] = [{'identifiers': {'vendor_id': 123}, 'simple_modifications': []}]
        with self.assertRaisesRegex(ValueError, 'device-specific'):
            MAP.generate(json.dumps(self.config).encode())

    def test_simple_then_complex_resolution(self):
        self.config['profiles'][0]['simple_modifications'].append({'from': {'key_code': 'left_shift'}, 'to': [{'key_code': 'right_command'}]})
        _, _, bindings, _ = MAP.model(self.config)
        self.assertEqual(bindings['left_shift'], [('押す', 'japanese_kana')])

    def test_simple_remap_uses_resulting_chord(self):
        self.config['profiles'][0]['simple_modifications'].append({'from': {'key_code': 'h'}, 'to': [{'key_code': 'l'}]})
        _, _, _, chords = MAP.model(self.config)
        self.assertEqual(next(c['to'] for c in chords if c['code'] == 'h'), 'right_arrow')

    def test_xml_escaping_and_reproducibility(self):
        self.config['profiles'][0]['name'] = '<test> & "profile"'
        source = json.dumps(self.config).encode()
        outputs = MAP.generate(source)
        ET.fromstring(outputs[MAP.OUTPUTS[0]])
        self.assertEqual(outputs, MAP.generate(source))


if __name__ == '__main__':
    unittest.main()
