# Requirements

- Neovim **0.9+** (uses `vim.json.decode`/`vim.json.encode`'s `vim.NIL` sentinel and
  `vim.health`).
- [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — **hard dependency**, not
  optional. data.nvim's `:JSON` command is built on
  `lib.nvim.bindings.usercmd.composer`, and its `lines`/`keys` render modes need
  `lib.lua.tables.path_flatten` (ships with lib.nvim as of the version released
  alongside data.nvim's first commit — `:checkhealth data` reports a missing
  `path_flatten` explicitly rather than failing silently).

No external CLI tools, no other plugins required. `pickers.nvim` is an optional
future integration for the planned filter UI ([scope.md](scope.md)), not a
dependency today.
