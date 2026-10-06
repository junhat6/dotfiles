"""Integration with the installed LazyVim/Gitsigns/Snacks runtime; no shared-file writes."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

HOME_CONFIG = Path.home() / '.config/nvim'
PLUGIN_DATA = Path.home() / '.local/share/nvim/lazy'


@unittest.skipUnless(shutil.which('nvim') and (PLUGIN_DATA / 'gitsigns.nvim').exists()
                     and (PLUGIN_DATA / 'snacks.nvim').exists()
                     and (HOME_CONFIG / 'lua/dotfiles/init.lua').exists(),
                     'configured Neovim integration runtime unavailable')
class NeovimIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.normal = (Path(self.tmp.name) / 'normal project').resolve()
        self.normal.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        manifest = self.normal / '.config/dotfiles/ownership.json'
        manifest.parent.mkdir(parents=True)
        manifest.write_text(json.dumps({'version': 1, 'shared': ['normal.txt', 'space file.txt', 'gone.txt'],
                                        'local': [], 'excluded': [], 'generated': [], 'discovery_roots': []}))
        for name in ('normal.txt', 'space file.txt', 'gone.txt'):
            (self.normal / name).write_text('baseline\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        (self.normal / 'normal.txt').write_text('changed\n')
        (self.normal / 'gone.txt').unlink()

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        subprocess.run(['git', *args], cwd=self.normal, capture_output=True, check=True)

    def lua(self, body):
        script = Path(self.tmp.name) / 'verify.lua'
        output = Path(self.tmp.name) / 'result.json'
        script.write_text('local ok, result = xpcall(function()\n' + body + '\nend, debug.traceback)\n'
                          'vim.fn.writefile({vim.json.encode({ok=ok,result=result})}, vim.env.DOTFILES_TEST_OUTPUT)\n')
        env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        env.pop('DOTFILES_ROOT', None)
        env.update(DOTFILES_TEST_SCRIPT=str(script), DOTFILES_TEST_OUTPUT=str(output),
                   DOTFILES_TEST_NORMAL=str(self.normal))
        result = subprocess.run(['nvim', '--headless', '-i', 'NONE',
                                 '+lua dofile(vim.env.DOTFILES_TEST_SCRIPT)', '+qa!'],
                                cwd=self.normal, env=env, capture_output=True, timeout=25)
        self.assertTrue(output.exists(), result.stderr.decode())
        report = json.loads(output.read_text())
        self.assertTrue(report['ok'], str(report['result']) + result.stderr.decode())
        return report['result']

    def test_yadm_and_normal_git_are_buffer_scoped(self):
        path = Path.home() / '.tmux.conf'
        before = hashlib.sha256(path.read_bytes()).digest()
        result = self.lua(r'''
vim.cmd('edit ' .. vim.fn.fnameescape(vim.env.HOME .. '/.tmux.conf'))
local shared = vim.api.nvim_get_current_buf()
require('lazy').load({plugins={'gitsigns.nvim'}})
assert(vim.wait(5000, function()
  local status = vim.b[shared].gitsigns_status_dict
  return status and status.root == vim.env.HOME and status.gitdir:match('/yadm/repo%.git$')
end, 20), 'yadm buffer did not attach')
vim.api.nvim_buf_set_lines(shared, -1, -1, false, {'# buffer-only integration verification'})
assert(vim.wait(5000, function()
  local status = vim.b[shared].gitsigns_status_dict
  return status and (status.added or 0) > 0
end, 20), 'yadm buffer changes not detected')
vim.cmd('vsplit ' .. vim.fn.fnameescape(vim.env.DOTFILES_TEST_NORMAL .. '/normal.txt'))
local normal = vim.api.nvim_get_current_buf()
assert(vim.wait(5000, function()
  local status = vim.b[normal].gitsigns_status_dict
  return status and status.root == vim.env.DOTFILES_TEST_NORMAL and (status.changed or 0) > 0
end, 20), 'normal repository did not take precedence')
assert(vim.b[shared].gitsigns_status_dict.root == vim.env.HOME)
assert(vim.bo[shared].modified, 'unsaved shared edits lost')
assert(vim.api.nvim_buf_get_lines(shared,-2,-1,false)[1] == '# buffer-only integration verification')
assert(vim.env.GIT_DIR == nil and vim.env.GIT_WORK_TREE == nil, 'Git environment leaked')
assert(vim.g.colors_name == 'catppuccin-latte', 'palette changed')
return {shared=vim.b[shared].gitsigns_status_dict.root, normal=vim.b[normal].gitsigns_status_dict.root,
        added=vim.b[shared].gitsigns_status_dict.added}
''')
        self.assertEqual(result['shared'], str(Path.home()))
        self.assertEqual(result['normal'], str(self.normal))
        self.assertEqual(hashlib.sha256(path.read_bytes()).digest(), before)

    def test_picker_previews_and_selection_preserve_unsaved_buffer(self):
        result = self.lua(r'''
vim.env.DOTFILES_ROOT = vim.env.DOTFILES_TEST_NORMAL
local dotfiles = require('dotfiles')
local entries = dotfiles.entries(false)
assert(#entries == 3)
local changed = dotfiles.entries(true)
assert(#changed == 2, 'changed-only listing excludes deletion or modification')
local key
for _, item in ipairs(entries) do if item.path == 'normal.txt' then key=item.key end end
assert(dotfiles.preview(key):find('+changed', 1, true), 'preview missed real changes')
vim.api.nvim_buf_set_lines(0, 0, -1, false, {'unsaved editor content'})
local unsaved = vim.api.nvim_get_current_buf()
local picker = dotfiles.pick(false)
assert(vim.wait(5000, function() return picker:count() == 3 end, 20), 'picker not populated')
picker:action('dotfiles_changes')
assert(vim.wait(5000, function() return picker:count() == 2 end, 20), 'changed mode not applied')
picker:action('dotfiles_all')
assert(vim.wait(5000, function() return picker:count() == 3 end, 20), 'all mode not restored')
picker.input:set('space file', '')
picker:find()
assert(vim.wait(5000, function() return picker.list:count() == 1 end, 20), 'search did not isolate file')
picker:action('confirm')
assert(vim.wait(3000, function() return vim.api.nvim_buf_get_name(0):match('/space file%.txt$') end, 20), 'selection opened wrong file')
assert(vim.api.nvim_buf_is_valid(unsaved) and vim.bo[unsaved].modified, 'unsaved buffer discarded')
assert(vim.api.nvim_buf_get_lines(unsaved,0,-1,false)[1] == 'unsaved editor content')
assert(vim.env.GIT_DIR == nil and vim.env.GIT_WORK_TREE == nil)
return {entries=#entries, changed=#changed, selected=vim.api.nvim_buf_get_name(0)}
''')
        self.assertEqual(result['entries'], 3)
        self.assertEqual(result['changed'], 2)
        self.assertEqual(result['selected'], str(self.normal / 'space file.txt'))


if __name__ == '__main__':
    unittest.main()
