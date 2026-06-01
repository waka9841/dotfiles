-- Pull in the wezterm API
local wezterm = require 'wezterm'

-- This will hold the configuration.
local config = wezterm.config_builder()

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
-- periodic_save の成功通知だけは抑制してノイズを減らす
local resurrect_notify_events = {
  'resurrect.error',
  'resurrect.state_manager.save_state.finished',
}
local is_periodic_save = false
wezterm.on('resurrect.state_manager.periodic_save.start', function()
  is_periodic_save = true
end)
for _, event in ipairs(resurrect_notify_events) do
  wezterm.on(event, function(...)
    if event == 'resurrect.state_manager.save_state.finished' and is_periodic_save then
      is_periodic_save = false
      return
    end
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

    if p.is_active then
      table.insert(elements, { Background = { Color = '#9ece6a' } })
      table.insert(elements, { Foreground = { Color = '#1a1b26' } })
    else
      table.insert(elements, { Background = { Color = '#3b4261' } })
      table.insert(elements, { Foreground = { Color = '#a9b1d6' } })
    end
    table.insert(elements, { Text = string.format(' #%d %s %s ', p.index + 1, pos, label) })
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
  end),
})
-- Cmd+Shift+R: 保存済み状態をfuzzy finderから選んで復元
table.insert(config.keys, {
  key = 'r',
  mods = 'SHIFT|SUPER',
  action = wezterm.action_callback(function(win, pane)
    resurrect.fuzzy_loader.fuzzy_load(win, pane, function(id, label)
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
    end)
  end),
})

return config
