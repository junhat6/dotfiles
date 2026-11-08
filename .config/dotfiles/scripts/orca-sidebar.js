#!/usr/bin/env node
'use strict';
// Orca のサイドバーを「タブが開いているか」で自動仕分けする。
//   タブあり → 「よく使う」 / タブなし → 「アーカイブ」
// 実行: ELECTRON_RUN_AS_NODE=1 /Applications/Orca.app/Contents/MacOS/Orca orca-sidebar.js [--dry-run] [--reset]
//
// 設計の要点:
// - タブの記録は操作側 (MacBook) の profile-state.db にだけある。リモート (Mac mini) 分も含む。
// - グループ所属はプロジェクトがあるホストに保存される。移動は各ホストの runtime へ RPC で送る。
// - グループ移動の公式 CLI は無い。Orca 同梱 CLI の RuntimeClient で非公開 RPC
//   (projectGroup.create / update / moveProject) を呼ぶ。Orca 更新で壊れたら止まって通知する。
// - 利用者が自分で作った別グループに入れたプロジェクトには触らない。
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const HOME = os.homedir();
const APP = process.env.ORCA_APP || '/Applications/Orca.app';
const ORCA_DATA = path.join(HOME, 'Library/Application Support/orca');
const CLIENT_JS = path.join(APP, 'Contents/Resources/app.asar.unpacked/out/cli/runtime-client.js');
const STATE_DIR = path.join(HOME, 'Library/Application Support/orca-sidebar');
const DISABLED_FILE = path.join(STATE_DIR, 'disabled.json');
const FAV = 'よく使う';
const ARC = 'アーカイブ';
const ENVS = (process.env.ORCA_SIDEBAR_ENVS ?? 'mac mini').split(',').map((s) => s.trim()).filter(Boolean);
const TIMEOUT_MS = 15000;

// ---------- 純粋ロジック (テスト対象) ----------

// unifiedTabs: { "<repoId>::<worktreePath>": [tab, ...] } → タブのある repoId の集合
function tabbedRepoIds(unifiedTabs) {
  const ids = new Set();
  for (const [key, tabs] of Object.entries(unifiedTabs || {})) {
    if (Array.isArray(tabs) && tabs.length > 0) ids.add(key.split('::')[0]);
  }
  return ids;
}

function findGroup(groups, name) {
  return groups.find((g) => g.name === name && !g.parentGroupId) || null;
}

// 1 ホスト分の移動計画。グループが無ければ missing に名前を返す (作成は呼び出し側)。
function planMoves({ repos, groups, tabbed }) {
  const fav = findGroup(groups, FAV);
  const arc = findGroup(groups, ARC);
  const missing = [!fav && FAV, !arc && ARC].filter(Boolean);
  if (missing.length) return { missing, moves: [] };
  const managed = new Set([null, fav.id, arc.id]);
  const moves = [];
  for (const r of repos) {
    const current = r.projectGroupId ?? null;
    if (!managed.has(current)) continue; // 自作グループは尊重する
    const target = tabbed.has(r.id) ? fav.id : arc.id;
    if (current !== target) {
      moves.push({ repoId: r.id, name: r.displayName, to: target === fav.id ? FAV : ARC });
    }
  }
  return { missing, moves };
}

// ---------- 入出力 ----------

const log = (msg) => console.log(`${new Date().toISOString()} ${msg}`);

function orcaVersion() {
  try {
    return execFileSync('/usr/bin/plutil', ['-extract', 'CFBundleShortVersionString', 'raw', path.join(APP, 'Contents/Info.plist')], { encoding: 'utf8' }).trim();
  } catch {
    return 'unknown';
  }
}

function orcaRunning() {
  try {
    execFileSync('/usr/bin/pgrep', ['-x', 'Orca'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function notify(message) {
  if (process.env.ORCA_SIDEBAR_NO_NOTIFY) return;
  const esc = (s) => s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  try {
    execFileSync('/usr/bin/osascript', ['-e', `display notification "${esc(message)}" with title "Orca サイドバー仕分け"`]);
  } catch {}
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readTabs() {
  const index = readJson(path.join(ORCA_DATA, 'orca-profile-index.json'));
  const db = path.join(ORCA_DATA, 'profiles', index.activeProfileId, 'profile-state.db');
  const out = execFileSync('/usr/bin/sqlite3', ['-readonly', '-json', db,
    "select domain, payload from profile_state_documents where domain in ('workspaceSession','workspaceSessionsByHostId')"], { encoding: 'utf8' });
  const docs = Object.fromEntries(JSON.parse(out || '[]').map((r) => [r.domain, JSON.parse(r.payload)]));
  if (!docs.workspaceSession || !docs.workspaceSessionsByHostId) {
    throw new Error('profile-state.db にタブの記録 (workspaceSession) が見つからない');
  }
  return docs;
}

function environmentId(name) {
  const envs = readJson(path.join(ORCA_DATA, 'orca-environments.json')).environments || [];
  const env = envs.find((e) => e.name === name);
  if (!env) throw new Error(`Orca に環境 "${name}" が登録されていない`);
  return env.id;
}

// 接続できないだけ (相手がスリープ中など) は一時的な失敗として扱い、止めない。
function isTransient(err) {
  const code = String(err?.code ?? '');
  return /unavailable|timeout|timed_out|unreachable|offline|connect|closed|ECONN|ETIMEDOUT|EHOSTUNREACH/i.test(code + ' ' + (err?.message ?? ''));
}

async function syncHost(RuntimeClient, label, envName, unifiedTabs, dryRun) {
  const client = new RuntimeClient(undefined, TIMEOUT_MS, null, envName);
  const call = async (method, params) => (await client.call(method, params)).result;
  const tabbed = tabbedRepoIds(unifiedTabs);
  let groups = (await call('projectGroup.list')).groups;
  const repos = (await call('repo.list')).repos;
  let plan = planMoves({ repos, groups, tabbed });

  if (plan.missing.length) {
    if (dryRun) {
      log(`[${label}] (dry-run) グループを作成予定: ${plan.missing.join(', ')}`);
      const fake = plan.missing.map((name) => ({ id: `new:${name}`, name, parentGroupId: null }));
      plan = planMoves({ repos, groups: groups.concat(fake), tabbed });
    } else {
      for (const name of plan.missing) {
        const g = (await call('projectGroup.create', { name, createdFrom: 'manual' })).group;
        await call('projectGroup.update', { groupId: g.id, updates: { tabOrder: name === FAV ? 0 : 1, isCollapsed: name === ARC } });
        log(`[${label}] グループを作成: ${name}`);
      }
      groups = (await call('projectGroup.list')).groups;
      plan = planMoves({ repos, groups, tabbed });
      if (plan.missing.length) throw new Error(`グループ作成後も見つからない: ${plan.missing.join(', ')}`);
    }
  }

  const ids = Object.fromEntries(groups.map((g) => [g.name, g.id]));
  for (const m of plan.moves) {
    if (dryRun) {
      log(`[${label}] (dry-run) ${m.name} → ${m.to}`);
      continue;
    }
    await call('projectGroup.moveProject', { repo: m.repoId, groupId: ids[m.to] });
    log(`[${label}] ${m.name} → ${m.to}`);
  }
  return plan.moves.length;
}

async function main(argv) {
  const dryRun = argv.includes('--dry-run');
  const version = orcaVersion();

  if (argv.includes('--reset')) {
    fs.rmSync(DISABLED_FILE, { force: true });
    log('停止状態を解除した');
    return 0;
  }
  if (fs.existsSync(DISABLED_FILE)) {
    const d = readJson(DISABLED_FILE);
    if (d.orcaVersion === version) return 0; // 同じ版で壊れたまま。Orca が更新されたら自動で再挑戦する
    fs.rmSync(DISABLED_FILE, { force: true });
    log(`Orca ${d.orcaVersion} → ${version} に更新されたので再開する`);
  }
  if (!dryRun && !orcaRunning()) return 0; // 終了中に Orca を起こさない

  try {
    const { RuntimeClient } = require(CLIENT_JS);
    const docs = readTabs();
    const hosts = [{ label: 'local', env: null, tabs: docs.workspaceSession.unifiedTabs }];
    for (const name of ENVS) {
      const hostTabs = docs.workspaceSessionsByHostId[`runtime:${environmentId(name)}`];
      hosts.push({ label: name, env: name, tabs: hostTabs?.unifiedTabs ?? {} });
    }
    const totalTabs = hosts.reduce((n, h) => n + tabbedRepoIds(h.tabs).size, 0);
    if (totalTabs === 0) {
      // 記録の読み違いで全件をアーカイブしないための安全弁
      log('タブが 1 つも見つからないので何もしない');
      return 0;
    }
    for (const h of hosts) {
      try {
        await syncHost(RuntimeClient, h.label, h.env, h.tabs, dryRun);
      } catch (err) {
        if (!isTransient(err)) throw err;
        if (dryRun) log(`[${h.label}] 接続できないので飛ばす: ${err.message}`);
      }
    }
    return 0;
  } catch (err) {
    const reason = `${err?.code ? `${err.code}: ` : ''}${err?.message ?? err}`;
    log(`停止: ${reason}`);
    if (!dryRun) {
      fs.mkdirSync(STATE_DIR, { recursive: true });
      fs.writeFileSync(DISABLED_FILE, JSON.stringify({ orcaVersion: version, reason, at: new Date().toISOString() }, null, 2));
      notify(`動かなくなったので停止しました (Orca ${version})。ログ: ~/.claude/logs/orca-sidebar.log`);
    }
    return 1;
  }
}

module.exports = { tabbedRepoIds, planMoves, isTransient, FAV, ARC };

if (require.main === module) {
  main(process.argv.slice(2)).then((code) => process.exit(code));
}
