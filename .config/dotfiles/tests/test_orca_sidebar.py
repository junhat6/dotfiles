import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/orca-sidebar.js'
ORCA = Path('/Applications/Orca.app/Contents/MacOS/Orca')


def node_command():
    if shutil.which('node'):
        return [shutil.which('node')], dict(os.environ)
    if ORCA.exists():
        return [str(ORCA)], {**os.environ, 'ELECTRON_RUN_AS_NODE': '1'}
    return None, None


def run_js(body):
    command, env = node_command()
    code = f"const m = require({json.dumps(str(SCRIPT))});\n{body}"
    result = subprocess.run([*command, '-e', code], env=env, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


GROUPS = [{'id': 'fav', 'name': 'よく使う', 'parentGroupId': None}, {'id': 'arc', 'name': 'アーカイブ', 'parentGroupId': None}]


@unittest.skipIf(node_command()[0] is None, 'node も Orca も無い')
class OrcaSidebarTest(unittest.TestCase):
    def plan(self, repos, groups, tabs):
        return run_js(f"""
const tabbed = m.tabbedRepoIds({json.dumps(tabs)});
console.log(JSON.stringify(m.planMoves({{ repos: {json.dumps(repos)}, groups: {json.dumps(groups)}, tabbed }})));
""")

    def test_tabbed_repo_ids_ignores_empty_tab_lists(self):
        tabs = {'a::/x': [{}], 'a::/x-wt': [{}], 'b::/y': [], 'c::/z': [{}, {}]}
        ids = run_js(f"console.log(JSON.stringify([...m.tabbedRepoIds({json.dumps(tabs)})].sort()))")
        self.assertEqual(ids, ['a', 'c'])

    def test_moves_by_tab_presence_including_folder_projects(self):
        repos = [
            {'id': 'git', 'displayName': 'repo', 'projectGroupId': None},
            {'id': 'cfg', 'displayName': '.config dotfiles', 'projectGroupId': 'fav'},
            {'id': 'old', 'displayName': 'old', 'projectGroupId': 'arc'},
        ]
        plan = self.plan(repos, GROUPS, {'git::/g': [{}], 'old::/o': [{}]})
        self.assertEqual(plan['missing'], [])
        self.assertEqual(plan['moves'], [
            {'repoId': 'git', 'name': 'repo', 'to': 'よく使う'},
            {'repoId': 'cfg', 'name': '.config dotfiles', 'to': 'アーカイブ'},
            {'repoId': 'old', 'name': 'old', 'to': 'よく使う'},
        ])

    def test_no_move_when_already_in_place(self):
        repos = [{'id': 'a', 'displayName': 'a', 'projectGroupId': 'fav'}, {'id': 'b', 'displayName': 'b', 'projectGroupId': 'arc'}]
        self.assertEqual(self.plan(repos, GROUPS, {'a::/a': [{}]})['moves'], [])

    def test_user_made_group_is_left_alone(self):
        repos = [{'id': 'w', 'displayName': 'work', 'projectGroupId': 'mine'}]
        groups = [*GROUPS, {'id': 'mine', 'name': '仕事', 'parentGroupId': None}]
        self.assertEqual(self.plan(repos, groups, {})['moves'], [])

    def test_missing_groups_are_reported_before_moving(self):
        repos = [{'id': 'a', 'displayName': 'a', 'projectGroupId': None}]
        plan = self.plan(repos, [], {'a::/a': [{}]})
        self.assertEqual(plan, {'missing': ['よく使う', 'アーカイブ'], 'moves': []})

    def test_nested_group_with_same_name_is_not_used(self):
        groups = [{'id': 'nested', 'name': 'よく使う', 'parentGroupId': 'p'}, GROUPS[1]]
        self.assertEqual(self.plan([], groups, {})['missing'], ['よく使う'])

    def test_transient_errors(self):
        result = run_js("""console.log(JSON.stringify([
  m.isTransient({code: 'runtime_unavailable', message: 'x'}),
  m.isTransient({code: 'runtime_timeout', message: 'x'}),
  m.isTransient({code: 'method_not_found', message: 'Unknown method'}),
  m.isTransient(new Error('invalid_params'))
]))""")
        self.assertEqual(result, [True, True, False, False])

    def test_broken_environment_disables_until_orca_version_changes(self):
        import tempfile
        command, env = node_command()
        with tempfile.TemporaryDirectory() as home:
            env = {**env, 'HOME': home, 'ORCA_SIDEBAR_NO_NOTIFY': '1', 'ORCA_SIDEBAR_ENVS': ''}
            # Orca の保存データが無い HOME → 構造が変わった時と同じく致命的な失敗
            first = subprocess.run([*command, str(SCRIPT)], env=env, capture_output=True, text=True)
            disabled = Path(home) / 'Library/Application Support/orca-sidebar/disabled.json'
            if first.returncode == 0 and not disabled.exists():
                self.skipTest('Orca が起動していない (終了中は何もしない仕様)')
            self.assertEqual(first.returncode, 1)
            self.assertIn('停止:', first.stdout)
            self.assertTrue(disabled.exists())
            second = subprocess.run([*command, str(SCRIPT)], env=env, capture_output=True, text=True)
            self.assertEqual((second.returncode, second.stdout), (0, ''))
            reset = subprocess.run([*command, str(SCRIPT), '--reset'], env=env, capture_output=True, text=True)
            self.assertEqual(reset.returncode, 0)
            self.assertFalse(disabled.exists())


if __name__ == '__main__':
    unittest.main()
