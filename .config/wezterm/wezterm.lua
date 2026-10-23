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
-- ~/.claude/pane-state/<pane_id>.json => {"state":"blocked|waiting|working|done|idle","ts":...}
-- 生の値をそのまま返す(減衰判定やフォールバックは effective_pane_state 側で行う)
local function read_pane_state_raw(pane_id)
  local path = wezterm.home_dir .. '/.claude/pane-state/' .. tostring(pane_id) .. '.json'
  local f = io.open(path, 'r')
  if not f then return nil, nil end
  local content = f:read('*a')
  f:close()
  local state = content:match('"state"%s*:%s*"([^"]+)"')
  local ts = tonumber(content:match('"ts"%s*:%s*(%d+)'))
  return state, ts
end

-- 状態の緊急度(タブ内に複数ペインがあるとき最も緊急な状態を採用)
-- blocked(許可待ち) > waiting(質問待ち) > working(作業中) > done(応答完了直後) > idle(待機中)
local STATE_PRIORITY = { blocked = 5, waiting = 4, working = 3, done = 2, idle = 1 }
-- bg: アクティブ(彩度明るめ) / dim: 非アクティブ(彩度暗め)
local STATE_COLORS = {
  blocked = { bg = '#f7768e', dim = '#6d3a44', glyph = '●' }, -- 許可待ち(最緊急): 赤
  waiting = { bg = '#ff9e64', dim = '#7a5636', glyph = '◆' }, -- 質問待ち:         オレンジ
  working = { bg = '#e0af68', dim = '#6e5a38', glyph = '◌' }, -- 作業中:           黄
  done    = { bg = '#9ece6a', dim = '#56683f', glyph = '✓' }, -- 応答完了直後:      緑
  idle    = { bg = '#565f89', dim = '#363c58', glyph = '・' }, -- 待機中:           グレー
}
-- done は生成(ts)から DONE_DECAY_SECONDS 秒経つとフック追加なしで idle 扱いに自然減衰させる
local DONE_DECAY_SECONDS = 300

-- 画面バッファのフォールバック検出(状態ファイルが存在しないペインに限り使用)。
-- コスト対策として呼び出し側で「アクティブタブ内のペインのみ」に限定すること。
-- 見逃し優先(誤検知よりも検出漏れの方を許容する)でパターンは保守的に絞る。
-- 検出結果は表示にのみ使い、ファイルには書かない。
local function buffer_fallback_state(pane_id)
  local ok, pane = pcall(wezterm.mux.get_pane, pane_id)
  if not ok or not pane then return nil end
  local ok2, text = pcall(function() return pane:get_lines_as_text() end) -- 引数省略=ビューポートのみ
  if not ok2 or not text then return nil end
  local tail = text:sub(-2000)
  if tail:find('Do you want to', 1, true) and tail:find('❯ 1. Yes', 1, true) then
    return 'waiting'
  end
  if tail:find('Esc to interrupt', 1, true) then
    return 'working'
  end
  return nil
end

-- 表示用の実効状態を決定する共通ロジック。
-- 状態ファイル → done の経過秒数による減衰判定 → (ファイルが無い場合のみ)画面バッファ fallback。
-- format-tab-title / update-right-status / デバッグキーはすべてこの関数経由で状態を取得する。
local function effective_pane_state(pane_id, allow_buffer_fallback)
  local state, ts = read_pane_state_raw(pane_id)
  if state then
    if state == 'done' and ts and (os.time() - ts) > DONE_DECAY_SECONDS then
      return 'idle'
    end
    return state -- 旧値 'idle' がそのまま残っている場合もそのまま idle として表示(後方互換)
  end
  if allow_buffer_fallback then
    return buffer_fallback_state(pane_id)
  end
  return nil
end

-- タブ内の全ペインを走査して最も緊急な Claude 状態を返す(なければ nil)
-- allow_buffer_fallback はアクティブタブのときのみ true にする(コスト対策)
local function tab_claude_state(tab)
  local best, best_prio = nil, 0
  for _, p in ipairs(tab.panes) do
    local s = effective_pane_state(p.pane_id, tab.is_active)
    local prio = s and STATE_PRIORITY[s] or 0
    if prio > best_prio then
      best, best_prio = s, prio
    end
  end
  return best
end

-- ── waiting/blocked 遷移時のプッシュ通知 ──────────────────────────────
-- Cmd+Shift+M でトグルする通知のグローバル ON/OFF
local notify_muted = false
-- ペイン単位の直前状態キャッシュ(遷移検出用)。通知はこのキャッシュとの差分でのみ発火するため、
-- 同一遷移で二重通知しない(自然にデバウンスされる)。
local pane_prev_state = {}
local NOTIFY_STATES = { waiting = true, blocked = true }

-- pane_id がどのタブに属するか(全ウィンドウ内タブを走査)
local function find_tab_for_pane(window, pane_id)
  local mux_win = window:mux_window()
  if not mux_win then return nil end
  for _, tab in ipairs(mux_win:tabs()) do
    for _, p in ipairs(tab:panes()) do
      if p:pane_id() == pane_id then return tab end
    end
  end
  return nil
end

-- 通知要否の判定: 「タブが非アクティブ」または「ウィンドウが非フォーカス」なら通知する
local function is_pane_visible(window, pane_id)
  local tab = find_tab_for_pane(window, pane_id)
  if not tab then return true end -- 所在不明の場合は通知を抑制する側に倒す
  local active_tab = window:active_tab()
  local tab_active = active_tab and tab:tab_id() == active_tab:tab_id()
  return tab_active and window:is_focused()
end

local function send_claude_notification(window, pane_id, state)
  if notify_muted then return end
  local label = state == 'blocked' and '許可待ち' or '入力待ち'
  local name = '?'
  local ok, pane = pcall(wezterm.mux.get_pane, pane_id)
  if ok and pane then
    local cwd = pane:get_current_working_dir()
    if cwd then
      local path = cwd.file_path or tostring(cwd)
      name = path:match('([^/]+)/?$') or path
    end
  end
  window:toast_notification('Claude Code', string.format('Pane %d (%s) が%s', pane_id, name, label), nil, 4000)
  wezterm.background_child_process({ 'afplay', '/System/Library/Sounds/Glass.aiff' })
end

-- state 遷移を検知して必要なら通知する共通関数。
-- update-right-status の 1 秒 tick と user-var-changed ハンドラの両方から呼ぶ。
local function check_pane_transition(window, pane_id, new_state)
  if not new_state then return end
  local prev = pane_prev_state[pane_id]
  if new_state ~= prev then
    if NOTIFY_STATES[new_state] and not NOTIFY_STATES[prev] then
      if not is_pane_visible(window, pane_id) then
        send_claude_notification(window, pane_id, new_state)
      end
    end
    pane_prev_state[pane_id] = new_state
  end
end

-- keybinds.lua (別モジュール)のデバッグキーから状態判定ロジックを再利用するためのグローバル公開
_G.ClaudePaneState = {
  read_pane_state_raw = read_pane_state_raw,
  effective_pane_state = effective_pane_state,
  buffer_fallback_state = buffer_fallback_state,
  STATE_PRIORITY = STATE_PRIORITY,
  STATE_COLORS = STATE_COLORS,
}

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

-- unix domain (mux サーバー) の定義。
-- 定義してあるだけでは通常の起動経路に影響しない。`wezterm connect unix` や
-- ドメイン指定でのペイン生成に使える受け皿として残してある。
config.unix_domains = { { name = 'unix' } }

-- プロセス永続化(既定 OFF)。
-- 下行を有効にすると無引数起動が `wezterm connect unix` 相当になり、GUI を閉じても
-- ペイン内プロセス(Claude Code 等)が mux サーバー上で生き続ける。
--
-- 既定で OFF にしている理由:
--   1. mux サーバーは OS のデーモンではないので PC 再起動と同時に死ぬ。
--      つまり PC 再起動というシナリオでは永続化の恩恵が無い。
--   2. 一方 `wezterm connect` 経由では gui-startup イベントが発火しない仕様のため、
--      有効にすると下の Wezurrect 自動復元(wezterm.on('gui-startup', ...))が走らなくなる。
--   → PC 再起動時は「永続化の恩恵ゼロ・自動復元だけ喪失」で純粋な劣化になる。
-- 有効化して得なのは「うっかり Cmd+Q」「wezterm のクラッシュ・アップデート」のみ。
-- config.default_gui_startup_args = { 'connect', 'unix' }

-- マウスでのリンク遷移
-- Claude Code のような TUI はマウスレポートを有効化するため、クリックが
-- アプリ側に奪われ既定の CTRL+クリックではリンクが開けない。
-- mouse_reporting=true を指定し、マウスレポート中でも CTRL+クリックで開けるようにする。
-- Down は Nop にしてアプリへの誤伝播(Down だけ届く)を防ぐ。
local act = wezterm.action
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.OpenLinkAtMouseCursor,
    mouse_reporting = true,
  },
  {
    event = { Down = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.Nop,
    mouse_reporting = true,
  },
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
-- update-right-status / user-var-changed の両方から呼べるよう描画ロジックを関数に切り出す
local function render_right_status(window)
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

    -- 色相=Claude状態 / 彩度・明度=アクティブか否か(既にアクティブタブなのでバッファfallback許可)
    local cstate = effective_pane_state(p.pane:pane_id(), true)
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
end

wezterm.on('update-right-status', function(window, pane)
  -- 全ペイン(非アクティブタブ含む)を走査して waiting/blocked 遷移を検知し、必要なら通知する
  -- (表示自体はアクティブタブのみ対象だが、通知判定は全タブが対象)
  local mux_win = window:mux_window()
  if mux_win then
    for _, tab in ipairs(mux_win:tabs()) do
      for _, p in ipairs(tab:panes()) do
        local pid = p:pane_id()
        check_pane_transition(window, pid, read_pane_state_raw(pid))
      end
    end
  end
  render_right_status(window)
end)

-- Claude Code フックが送る SetUserVar (claude_state) をイベント駆動の即時反映トリガーとして使う。
-- あくまでファイル方式が正で、これは1秒tickを待たない副次経路(mux経由でのuser-var伝播は
-- detach/re-attach後に消える既知issueがあるため、ファイルとの二重系にしてある)。
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name ~= 'claude_state' then return end
  check_pane_transition(window, pane:pane_id(), value)
  render_right_status(window)
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

-- Cmd+Shift+M: Claude Code の waiting/blocked 通知のON/OFFをトグル(mute)
table.insert(config.keys, {
  key = 'm',
  mods = 'SHIFT|SUPER',
  action = wezterm.action_callback(function(win, pane)
    notify_muted = not notify_muted
    local label = notify_muted and '🔇 Claude通知を停止しました' or '🔔 Claude通知を再開しました'
    flash_status(win, label)
  end),
})

return config
