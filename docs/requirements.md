# Requirements

- Neovim **0.9+** (uses `vim.json.decode`/`vim.json.encode`'s `vim.NIL` sentinel and
  `vim.health`).
- [`lib.nvim`](https://github.com/StefanBartl/lib.nvim) — **hard dependency**, not
  optional. data.nvim's `:JSON`/`:YAML`/`:XML` commands are built on
  `lib.nvim.bindings.usercmd.composer`; `lines`/`keys` need `lib.lua.tables.path_flatten`,
  `:YAML` needs `lib.lua.yaml.encode`, and `:XML` needs `lib.lua.xml` (all ship with
  lib.nvim as of the version released alongside the data.nvim feature that needs them —
  `:checkhealth data` reports any of them missing explicitly rather than failing
  silently).

No external CLI tools, no other plugins required.
[`color_my_ascii.nvim`](https://github.com/StefanBartl/color_my_ascii.nvim) is an
optional soft dependency for fenced-block scope
([integrations.md](integrations.md)) — its absence is a silent, total no-op.
[`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim) is an optional
dependency required for exactly one action, `:JSON`/`:YAML`/`:XML filter`
([integrations.md](integrations.md)) — every other command works without it.
