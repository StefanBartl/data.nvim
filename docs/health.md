# Health check

`:checkhealth data` reports:

| Check | Meaning if it fails |
| --- | --- |
| Neovim version | Below 0.9 — some `vim.json`/`vim.health` behavior this plugin relies on may differ. |
| `lib.nvim` detected | Missing entirely — `:JSON` cannot be registered at all (hard dependency, see [requirements.md](requirements.md)). |
| `lib.lua.tables.path_flatten` available | `lib.nvim` is installed but older than the version data.nvim shipped alongside — `:JSON lines`/`:JSON keys` will error at call time even though `:JSON pretty`/`compact` work fine. Update `lib.nvim`. |
| yaml/xml info line | Always shown, not a failure: a reminder that `:YAML`/`:XML` don't exist yet because `lib.nvim` has no YAML encoder or XML module (see [scope.md](scope.md)). |
