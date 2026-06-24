-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- キーバインドの反応をターミナル内に必ず表示する(macOS の通知許可に依存しない)
-- 左ステータスにメッセージを出し、数秒後に自動で消す
local function flash_status(window, text)
  window:set_left_status(wezterm.format {
    { Background = { Color = '#9ece6a' } },
    { Foreground = { Color = '#1a1b26' } },
    { Text = ' ' .. text .. ' ' },
  })
  wezterm.time.call_after(2.5, function()
    window:set_left_status('')
  end)
end

-- Claude Code の状態をペイン単位の state ファイルから読む(フックが書き込む)
-- ~/.claude/pane-state/<pane_id>.json => {"state":"working|waiting|idle","ts":...}
local function read_pane_state(pane_id)
  local path = wezterm.home_dir .. '/.claude/pane-state/' .. tostring(pane_id) .. '.json'
  local f = io.open(path, 'r')
  if not f then return nil end
  local content = f:read('*a')
  f:close()
  return content:match('"state"%s*:%s*"([^"]+)"')
end

-- 状態の緊急度(タブ内に複数ペインがあるとき最も緊急な状態を採用)
local STATE_PRIORITY = { waiting = 3, working = 2, idle = 1 }
-- bg: アクティブ(彩度明るめ) / dim: 非アクティブ(彩度暗め)
local STATE_COLORS = {
  waiting = { bg = '#f7768e', dim = '#6d3a44', glyph = '●' }, -- 要入力: 赤
  working = { bg = '#e0af68', dim = '#6e5a38', glyph = '◌' }, -- 作業中: 黄
  idle    = { bg = '#9ece6a', dim = '#56683f', glyph = '✓' }, -- 完了:   緑
}

-- タブ内の全ペインを走査して最も緊急な Claude 状態を返す(なければ nil)
local function tab_claude_state(tab)
  local best, best_prio = nil, 0
  for _, p in ipairs(tab.panes) do
    local s = read_pane_state(p.pane_id)
    local prio = s and STATE_PRIORITY[s] or 0
    if prio > best_prio then
      best, best_prio = s, prio
    end
  end
  return best
end

-- ステータス/タブの再描画間隔(状態色の追従用)
config.status_update_interval = 1000

-- タブタイトルを Claude 状態で色付けする
-- 色相=Claude状態 / 彩度・明度=アクティブか否か(右ステータスのペイン表示と同じ方式)
wezterm.on('format-tab-title', function(tab, tabs, panes, conf, hover, max_width)
  local title = tab.active_pane.title
  local state = tab_claude_state(tab)
  local sc = state and STATE_COLORS[state]
  if sc then
    if tab.is_active then
      return {
        { Background = { Color = sc.bg } },             -- 鮮やか
        { Foreground = { Color = '#1a1b26' } },
        { Text = string.format(' %s %d %s ', sc.glyph, tab.tab_index + 1, title) },
      }
    else
      return {
        { Background = { Color = sc.dim } },            -- 沈んだ
        { Foreground = { Color = '#c0caf5' } },
        { Text = string.format(' %s %d %s ', sc.glyph, tab.tab_index + 1, title) },
      }
    end
  end
  -- Claude 状態なし: 同色相(青)で彩度・明度のみ変える
  if tab.is_active then
    return {
      { Background = { Color = '#7aa2f7' } },           -- 鮮やかな青
      { Foreground = { Color = '#1a1b26' } },
      { Text = string.format(' %d %s ', tab.tab_index + 1, title) },
    }
  end
  return {
    { Background = { Color = '#3b4261' } },             -- 沈んだ紺(同色相)
    { Foreground = { Color = '#a9b1d6' } },
    { Text = string.format(' %d %s ', tab.tab_index + 1, title) },
  }
end)

-- This is where you actually apply your config choices

-- For example, changing the color scheme:
-- config.color_scheme = 'AdventureTime'
config.color_scheme = 'duskfox'
config.font_size = 12.0
config.window_background_opacity = 0.8
config.initial_rows = 35
config.initial_cols = 130

config.inactive_pane_hsb = {
    saturation = 0.1,
    brightness = 0.3,
  }

-- pane border
config.colors = {
  split = '#9ece6a',
}

-- session restore (Wezurrect: メンテ継続中の resurrect.wezterm フォーク)
-- 本家 MLFlexer/resurrect.wezterm は 2026-05-24 にアーカイブ済みのため乗り換え。
-- API はドロップイン互換。更新は明示的に wezterm.plugin.update_all() を叩いた時のみ。
local resurrect = wezterm.plugin.require 'https://github.com/YedPool/Wezurrect'
-- 保存するスクロールバック行数を制限(保存/復元のパフォーマンス向上)
resurrect.state_manager.set_max_nlines(2000)
-- 5分ごとに現在のワークスペース/ウィンドウ/タブ状態を自動保存
resurrect.state_manager.periodic_save {
  interval_seconds = 300,
  save_workspaces = true,
  save_windows = true,
  save_tabs = true,
}
-- 起動時に前回保存した状態を自動復元
wezterm.on('gui-startup', resurrect.state_manager.resurrect_on_gui_startup)

-- Claude Code セッションを session_id 単位で正確に復元(Tier 2)
-- ~/.claude/settings.json に SessionStart/Stop フックを冪等に追記し、
-- ペインごとの session_id を ~/.claude/pane-sessions/<pane_id>.json に記録する。
-- 復元時は `cd <cwd>` → `claude --resume <session-id>` が自動実行される。
resurrect.process_handlers.setup_claude_session_hooks()

-- エラー/失敗をデスクトップ通知に出す(サイレント失敗を防ぐ早期警告)
-- 保存成功は手動保存(Cmd+Shift+S)側でクリーンな toast を出すためここでは扱わない
local resurrect_notify_events = {
  'resurrect.error',
}
for _, event in ipairs(resurrect_notify_events) do
  wezterm.on(event, function(...)
    local args = { ... }
    local msg = event
    for _, v in ipairs(args) do
      msg = msg .. ' ' .. tostring(v)
    end
    local win = wezterm.gui.gui_windows()[1]
    if win then
      win:toast_notification('WezTerm - session restore', msg, nil, 4000)
    end
  end)
end

-- Right status: show all panes in the current tab
wezterm.on('update-right-status', function(window, pane)
  local tab = window:active_tab()
  local panes = tab:panes_with_info()
  if #panes <= 1 then
    window:set_right_status('')
    return
  end
  -- Collect unique rows/cols to determine position labels
  local rows = {}
  local cols = {}
  local row_set = {}
  local col_set = {}
  for _, p in ipairs(panes) do
    if not row_set[p.top] then
      row_set[p.top] = true
      table.insert(rows, p.top)
    end
    if not col_set[p.left] then
      col_set[p.left] = true
      table.insert(cols, p.left)
    end
  end
  table.sort(rows)
  table.sort(cols)

  -- Build row/col index lookup
  local row_idx = {}
  for i, v in ipairs(rows) do row_idx[v] = i end
  local col_idx = {}
  for i, v in ipairs(cols) do col_idx[v] = i end

  local v_labels = #rows == 2 and { '上', '下' } or { '上', '中', '下' }
  local h_labels = #cols == 2 and { '左', '右' } or { '左', '中', '右' }
  local multi_row = #rows > 1
  local multi_col = #cols > 1

  -- Sort panes top-to-bottom, left-to-right for display order
  local sorted = {}
  for _, p in ipairs(panes) do table.insert(sorted, p) end
  table.sort(sorted, function(a, b)
    if a.top ~= b.top then return a.top < b.top end
    return a.left < b.left
  end)

  local elements = {}
  for i, p in ipairs(sorted) do
    local cwd = p.pane:get_current_working_dir()
    local label = tostring(p.pane:get_title())
    if cwd then
      local path = cwd.file_path or tostring(cwd)
      label = path:match('([^/]+)/?$') or path
    end

    -- Position label
    local pos = ''
    if multi_row and multi_col then
      pos = (v_labels[row_idx[p.top]] or '') .. (h_labels[col_idx[p.left]] or '')
    elseif multi_row then
      pos = v_labels[row_idx[p.top]] or ''
    elseif multi_col then
      pos = h_labels[col_idx[p.left]] or ''
    end

    -- 色相=Claude状態 / 彩度・明度=アクティブか否か
    local cstate = read_pane_state(p.pane:pane_id())
    local sc = cstate and STATE_COLORS[cstate]
    local glyph = ''
    if sc then
      glyph = sc.glyph .. ' '
      if p.is_active then
        table.insert(elements, { Background = { Color = sc.bg } })  -- 鮮やか
        table.insert(elements, { Foreground = { Color = '#1a1b26' } })
      else
        table.insert(elements, { Background = { Color = sc.dim } })  -- 沈んだ
        table.insert(elements, { Foreground = { Color = '#c0caf5' } })
      end
    elseif p.is_active then
      table.insert(elements, { Background = { Color = '#7aa2f7' } })  -- 鮮やかな青
      table.insert(elements, { Foreground = { Color = '#1a1b26' } })
    else
      table.insert(elements, { Background = { Color = '#3b4261' } })  -- 沈んだ紺(同色相)
      table.insert(elements, { Foreground = { Color = '#a9b1d6' } })
    end
    table.insert(elements, { Text = string.format(' %s#%d %s %s ', glyph, p.index + 1, pos, label) })
    if i < #sorted then
      table.insert(elements, { Background = { Color = 'none' } })
      table.insert(elements, { Text = ' ' })
    end
  end
  window:set_right_status(wezterm.format(elements))
end)

-- keybindings
local keybinds = require 'keybinds'
config.disable_default_key_bindings = true
config.keys = keybinds.keys
config.key_tables = keybinds.key_tables

-- session save/load keybinds (Wezurrect)
-- Cmd+Shift+S: 現在のワークスペース状態を手動保存
table.insert(config.keys, {
  key = 's',
  mods = 'SHIFT|SUPER',
  action = wezterm.action_callback(function(win, pane)
    resurrect.state_manager.save_state(resurrect.workspace_state.get_workspace_state())
    win:toast_notification('WezTerm', 'セッションを保存しました', nil, 2000)
    flash_status(win, '✓ セッションを保存しました')
  end),
})
-- Cmd+Shift+R: 保存済み状態をfuzzy finderから選んで復元
table.insert(config.keys, {
  key = 'r',
  mods = 'SHIFT|SUPER',
  action = wezterm.action_callback(function(win, pane)
    resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
      if not id then return end -- fuzzy finder をキャンセルした場合
      local type = string.match(id, '^([^/]+)') -- '/' より前(workspace/window/tab)
      id = string.match(id, '([^/]+)$') -- '/' より後
      id = string.match(id, '(.+)%..+$') -- 拡張子を除去
      local opts = {
        relative = true,
        restore_text = true,
        on_pane_restore = resurrect.tab_state.default_on_pane_restore,
      }
      if type == 'workspace' then
        local state = resurrect.state_manager.load_state(id, 'workspace')
        resurrect.workspace_state.restore_workspace(state, opts)
      elseif type == 'window' then
        local state = resurrect.state_manager.load_state(id, 'window')
        resurrect.window_state.restore_window(pane:window(), state, opts)
      elseif type == 'tab' then
        local state = resurrect.state_manager.load_state(id, 'tab')
        resurrect.tab_state.restore_tab(pane:tab(), state, opts)
      end
      win:toast_notification('WezTerm', 'セッションを復元しました (' .. type .. ')', nil, 2000)
      flash_status(win, '✓ セッションを復元しました (' .. type .. ')')
    end)
  end),
})

return config
