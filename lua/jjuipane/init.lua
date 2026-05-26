local M = {}

--- ── Module state ────────────────────────────────────────────────────────
--- Persistent across calls; resets on pane close / exit.
local state = {
  visible     = false,   -- true while the jjui window exists
  win_id      = nil,     -- neovim window id of the pane
  buf_id      = nil,     -- neovim buffer id backing the terminal
  prev_win_id = nil,     -- window that had focus before pane opened
}

local AUGROUP       = "JjuiPane"
local DEFAULT_CMD   = "jjui"
local DEFAULT_WIDTH = 80

--- ── Internal helpers ─────────────────────────────────────────────────

local function _reset_state()
  state.visible     = false
  state.win_id      = nil
  state.buf_id      = nil
  state.prev_win_id = nil
  pcall(vim.api.nvim_create_augroup, AUGROUP, { clear = true })
end

local function _close_bufwin()
  if state.win_id and vim.api.nvim_win_is_valid(state.win_id) then
    vim.api.nvim_win_close(state.win_id, false)
  end
  if state.buf_id and vim.api.nvim_buf_is_valid(state.buf_id) then
    vim.api.nvim_buf_delete(state.buf_id, { force = true })
  end
end

--- Open the jjui terminal pane in a right vertical split.
local function _open(cfg)
  cfg = cfg or {}
  local cmd = cfg.cmd or DEFAULT_CMD
  local width = cfg.width or DEFAULT_WIDTH

  if state.visible then
    return -- guard against double-open
  end

  -- 1. Remember the original window
  state.prev_win_id = vim.api.nvim_get_current_win()

  -- 2. Create a scratch buffer for the new split
  local buf = vim.api.nvim_create_buf(false, true)

  -- 3. Open a right-side vertical split using nvim_open_win
  local win = vim.api.nvim_open_win(buf, true, {
    split = "right",
    width = width,
  })

  -- 4. Launch `jjui` as the terminal program.
  -- `termopen` reuses the current buffer when it is a fresh terminal buffer.
  vim.fn.termopen(cmd)

  -- 5. Capture the actual buffer (termopen may replace it)
  buf = vim.api.nvim_win_get_buf(win)

  -- 6. Tidy buffer-level options
  local bo = { buf = buf }
  vim.api.nvim_set_option_value("number",          false, bo)
  vim.api.nvim_set_option_value("relativenumber",  false, bo)
  vim.api.nvim_set_option_value("signcolumn",      "no",    bo)
  vim.api.nvim_set_option_value("wrap",            false,   bo)
  vim.api.nvim_set_option_value("swapfile",        false,   bo)

  -- 7. Autocmds: detect terminal death and external buffer/window removal
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

  vim.api.nvim_create_autocmd("TermClose", {
    group  = group,
    buffer = buf,
    once   = true,
    callback = function()
      vim.schedule(function() M.close() end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group  = group,
    buffer = buf,
    once   = true,
    callback = function()
      vim.schedule(function() M.close() end)
    end,
  })

  -- 8. Persist ids and mark open
  state.win_id  = win
  state.buf_id  = buf
  state.visible = true
end

--- ── Public API ────────────────────────────────────────────────────────────

--- Toggle the jjui terminal pane open / closed.
---
--- Open  → vertical right split running `cmd` (default `jjui`).
--- Close → remove window + buffer, restore focus to original window.
---
-- @param cfg? table  Optional: `cmd` (string), `width` (number)
function M.toggle(cfg)
  if state.visible
      and state.win_id
      and vim.api.nvim_win_is_valid(state.win_id) then

    -- ── close path ─────────────────────────────────────────────────────
    local restore_win = state.prev_win_id  -- save BEFORE reset
    _close_bufwin()
    _reset_state()

    if restore_win and vim.api.nvim_win_is_valid(restore_win) then
      vim.api.nvim_set_current_win(restore_win)
    end
  else
    _open(cfg)
  end
end

--- Force-close / reset.  Idempotent — safe after external `:bw`, `:q` etc.
function M.close()
  _close_bufwin()
  _reset_state()
end

--- Snapshot of internal state.
-- @return table
function M.get_state()
  return vim.deepcopy(state)
end

--- Is the pane visible right now?
-- @return boolean
function M.is_visible()
  return state.visible
end

--- Register the user command and optional keymap.
---
-- @param opts? table
-- | Field    | Type   | Default      | Description                         |
-- | keymap   | string | nil          | Normal-mode keymap for toggle       |
-- | cmd      | string | JjuiPane     | User-command name                   |
-- | width    | number | 80           | Default split width                 |
-- | shellcmd | string | jjui         | Command to run in the terminal      |
function M.setup(opts)
  opts = opts or {}

  DEFAULT_WIDTH = opts.width or DEFAULT_WIDTH
  if opts.shellcmd then
    DEFAULT_CMD = opts.shellcmd
  end

  local uname = opts.cmd or "JjuiPane"

  vim.api.nvim_create_user_command(uname, function(info)
    local w = nil
    if info.args and #info.args > 0 then
      w = tonumber(info.args)
    end
    M.toggle({ width = w })
  end, {
    desc  = "Toggle the jjui terminal pane",
    nargs = "?",
  })

  if opts.keymap then
    vim.keymap.set("n", opts.keymap, M.toggle, {
      silent = true,
      desc   = "Toggle jjui pane",
    })
  end
end

return M
