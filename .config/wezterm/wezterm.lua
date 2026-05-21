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

return config
