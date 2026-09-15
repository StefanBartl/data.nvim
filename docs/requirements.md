# Requirements

- Neovim **0.9+** (uses `vim.json.decode`/`vim.json.encode`'s `vim.NIL` sentinel and
  `vim.health`).
- [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — **hard dependency**, not
  optional. data.nvim's `:JSON`/`:YAML` commands are built on
  `lib.nvim.bindings.usercmd.composer`; `lines`/`keys` need `lib.lua.tables.path_flatten`
  and `:YAML` needs `lib.lua.yaml.encode` (both ship with lib.nvim as of the version
  released alongside data.nvim's YAML support — `:checkhealth data` reports either one
  missing explicitly rather than failing silently).

No external CLI tools, no other plugins required. `pickers.nvim` is an optional
future integration for the planned filter UI ([scope.md](scope.md)), not a
dependency today.
