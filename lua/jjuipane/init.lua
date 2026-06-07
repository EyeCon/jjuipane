local M = {}

--- ── Module state ────────────────────────────────────────────────────────
--- Persistent across calls; resets on pane close / exit.
local state = {
  visible     = false,   -- true while the jjui window exists
  win_id      = nil,     -- neovim window id of the pane
  buf_id      = nil,     -- neovim buffer id backing the terminal
  prev_win_id = nil,     -- window that had focus before pane opened
  keymap      = nil,     -- keybinding to toggle the pane
}

local AUGROUP       = "JjuiPane"
local DEFAULT_CMD   = "jjui"
local DEFAULT_WIDTH = 80
local DEFAULT_KEYMAP = nil

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

  -- 1. Remember the original window and resolve the cwd to the active file's directory
  state.prev_win_id = vim.api.nvim_get_current_win()
  local prev_buf = vim.api.nvim_win_get_buf(state.prev_win_id)
  local active_path = vim.api.nvim_buf_get_name(prev_buf)
  local cwd = vim.fn.getcwd()
  if active_path and active_path ~= "" then
    local dir = vim.fs.dirname(active_path)
    if dir and vim.fn.isdirectory(dir) == 1 then
      cwd = dir
    end
  end

  -- 2. Create a scratch buffer for the new split
  local buf = vim.api.nvim_create_buf(false, true)

  -- 3. Open a right-side vertical split using nvim_open_win
  local win = vim.api.nvim_open_win(buf, true, {
    split = "right",
    width = width,
  })

  -- 4. Launch `jjui` as the terminal program.
  --    `termopen` reuses the current buffer when it is a fresh terminal buffer.
  --    It returns a job ID (number) synchronously; command-not-found and other
  --    launch failures surface asynchronously via `on_exit` (exit code 127
  --    means the shell could not find the command).
  local open_ok, result = pcall(vim.fn.termopen, cmd, {
    cwd = cwd,
    on_exit = function(_job_id, exit_code, _event)
      -- Exit code 129 typically means SIGHUP (hangup) when closing window
      -- Exit code 137 typically means SIGKILL when window is forcibly closed
      -- Suppress warnings for signal-based terminations
      if exit_code ~= 0 and exit_code ~= 129 and exit_code ~= 137 then
        vim.schedule(function()
          local reason = exit_code == 127
              and ("command not found: " .. cmd)
              or ("exited with code " .. exit_code)
          vim.notify(
            "jjuipane: " .. reason,
            vim.log.levels.WARN
          )
          M.close()
        end)
      end
    end,
  })

  if not open_ok then
    -- termopen itself threw an error (e.g. invalid argument type)
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify("jjuipane: " .. tostring(result), vim.log.levels.WARN)
    return
  end

  if type(result) ~= "number" then
    -- Unexpected return — not a job ID. Clean up.
    local msg = (type(result) == "table" and result.message)
        and ("jjuipane: " .. result.message)
        or ("jjuipane: failed to start command: " .. cmd)
    vim.api.nvim_win_close(win, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.notify(msg, vim.log.levels.WARN)
    return
  end

  -- 5. Capture the actual buffer (termopen may replace it)
  buf = vim.api.nvim_win_get_buf(win)

  -- 6. Tidy window- and buffer-level options
  local wo = { win = win }
  vim.api.nvim_set_option_value("number", false, wo)
  vim.api.nvim_set_option_value("relativenumber", false, wo)
  vim.api.nvim_set_option_value("signcolumn", "no", wo)
  vim.api.nvim_set_option_value("wrap", false, wo)
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

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

  -- 7. Add keybinding to close pane in terminal (both normal and insert modes)
  if DEFAULT_KEYMAP then
    local key = DEFAULT_KEYMAP:gsub("^<leader>", "<Leader>")
    vim.keymap.set("t", key, "<Cmd>JjuiPane<CR>", {
      buffer = buf,
      remap = true,
      desc = "Close jjui pane",
    })
  end

  -- 8. Ensure terminal starts in insert mode
  vim.api.nvim_win_call(win, function()
    vim.cmd("startinsert")
  end)

  -- 9. Persist ids and mark open
  state.win_id  = win
  state.buf_id  = buf
  state.visible = true
  state.keymap = DEFAULT_KEYMAP
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
  DEFAULT_KEYMAP = opts.keymap
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
