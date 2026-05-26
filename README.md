# jjuipane

A Neovim plugin that provides a toggleable terminal pane for running `jjui` (Jujutsu VCS UI) in a right-side vertical split.

## Features

1. **Tracks its own state** — Maintains internal state for visibility, window ID, buffer ID, and previous window ID across calls. State resets on pane close/exit.
2. **Toggles a split right window** — Opens a vertical split on the right side of the current window. Toggling again closes the pane and restores focus to the original window.
3. **Starts `jjui` in a terminal** — When made visible, launches `jjui` (or a custom command) as a terminal process in the pane window.
4. **Has customizable key bindings** — Allows users to define a normal-mode keymap for toggling the pane via the `setup()` function.
5. **Cleans up when terminal exits** — Automatically closes the window and deletes the buffer when the terminal process exits or when the buffer is externally wiped.
6. **Fails gracefully on command errors** — If the configured command cannot be found or `termopen` fails, the pane is closed, state is reset, and the user is warned via `vim.notify` with the reason for the failure.

## Installation

Place the plugin in your Neovim runtime path, or use your preferred plugin manager:

```lua
-- lazy.nvim
{
  "yourusername/jjuipane",
  config = function()
    require("jjuipane").setup({
      keymap = "<leader>j",
      width = 80,
      shellcmd = "jjui",
    })
  end,
}
```

## Usage

### Basic Setup

```lua
require("jjuipane").setup({
  keymap = "<leader>j",  -- Press <leader>j in normal mode to toggle
})
```

### User Command

After calling `setup()`, a user command is available (default: `:JjuiPane`):

```vim
" Toggle the pane with default width
:JjuiPane

" Toggle the pane with a specific width
:JjuiPane 100
```

### Lua API

```lua
local jjuipane = require("jjuipane")

-- Toggle the pane open/closed
jjuipane.toggle()

-- Toggle with custom options
jjuipane.toggle({ cmd = "jjui", width = 100 })

-- Force-close the pane
jjuipane.close()

-- Check if the pane is currently visible
if jjuipane.is_visible() then
  print("Pane is open")
end

-- Get a snapshot of internal state
local state = jjuipane.get_state()
print("Window ID:", state.win_id)
print("Buffer ID:", state.buf_id)
```

## Configuration

### `setup(opts)` Options

The `setup()` function accepts a table with the following fields:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `keymap` | `string \| nil` | `nil` | Normal-mode keymap for toggling the pane. Example: `"<leader>j"` |
| `cmd` | `string` | `"JjuiPane"` | Name of the user command to create. Example: `"JJUI"` |
| `width` | `number` | `80` | Default width (in columns) for the vertical split. Example: `100` |
| `shellcmd` | `string` | `"jjui"` | Command to run in the terminal. Example: `"jjui log"` |

### Example Configurations

#### Minimal

```lua
require("jjuipane").setup()
```

This creates the `:JjuiPane` command with default settings (80-column width, runs `jjui`).

#### With Keymap

```lua
require("jjuipane").setup({
  keymap = "<leader>j",
})
```

Adds a normal-mode keymap `<leader>j` to toggle the pane.

#### Custom Command Name and Width

```lua
require("jjuipane").setup({
  cmd = "JJUI",
  width = 120,
})
```

Creates the `:JJUI` command with a 120-column width.

#### Custom Shell Command

```lua
require("jjuipane").setup({
  shellcmd = "jjui log",
  width = 100,
})
```

Runs `jjui log` instead of the default `jjui` command.

#### Full Configuration

```lua
require("jjuipane").setup({
  keymap = "<leader>j",
  cmd = "JJUI",
  width = 100,
  shellcmd = "jjui",
})
```

## Public API

### `setup(opts)`

Register the user command and optional keymap.

**Parameters:**
- `opts` (table, optional) — Configuration options (see table above)

### `toggle(cfg)`

Toggle the jjui terminal pane open/closed.

**Parameters:**
- `cfg` (table, optional) — Runtime options:
  - `cmd` (string) — Command to run in the terminal (overrides default)
  - `width` (number) — Width for the split (overrides default)

**Behavior:**
- If pane is visible: closes it and restores focus to the previous window
- If pane is hidden: opens it as a right-side vertical split

### `close()`

Force-close the pane and reset internal state. Idempotent — safe to call after external buffer/window removal (e.g., `:bw`, `:q`).

### `is_visible()`

Check if the pane is currently visible.

**Returns:** `boolean`

### `get_state()`

Get a snapshot of the internal state.

**Returns:** `table` with fields:
- `visible` (boolean) — Whether the pane is currently open
- `win_id` (number \| nil) — Neovim window ID of the pane
- `buf_id` (number \| nil) — Neovim buffer ID backing the terminal
- `prev_win_id` (number \| nil) — Window that had focus before pane opened

## Buffer Options

The terminal buffer is configured with the following options:

- `number` — `false` (no line numbers)
- `relativenumber` — `false` (no relative line numbers)
- `signcolumn` — `"no"` (no sign column)
- `wrap` — `false` (no line wrapping)
- `swapfile` — `false` (no swap file)

## Autocmds

The plugin sets up two autocmds for cleanup:

1. **`TermClose`** — Fires when the terminal process exits, automatically closing the pane.
2. **`BufWipeout`** — Fires if the buffer is externally wiped, automatically resetting state.

Both autocmds are buffer-local and run once.

## Error Handling

The plugin guards against command execution failures in three layers:

1. **Synchronous exceptions** — If `termopen` itself throws an error (e.g., invalid argument type), the split window and buffer are closed immediately and the user is warned with the error message.

2. **Command not found** — If the shell cannot locate the command (exit code 127), the pane is automatically closed and a warning is shown:

   ```
   jjuipane: command not found: <cmd>
   ```

3. **Unexpected return value** — If `termopen` returns something other than a job ID number, the split is cleaned up and a warning is shown with the available details.

In all failure cases, no window or buffer is left behind — the pane is fully removed and internal state is reset.

## Requirements

- Neovim 0.12 or later (uses `nvim_open_win` with `split = "right"`)
- `jjui` command available in your PATH (or a custom `shellcmd`)

## License

See LICENSE file for details.