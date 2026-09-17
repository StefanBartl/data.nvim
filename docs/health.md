# Health check

`:checkhealth data` reports:

| Check | Meaning if it fails |
| --- | --- |
| Neovim version | Below 0.9 — some `vim.json`/`vim.health` behavior this plugin relies on may differ. |
| `lib.nvim` detected | Missing entirely — none of `:JSON`/`:YAML`/`:XML` can be registered at all (hard dependency, see [requirements.md](requirements.md)). |
| `lib.lua.tables.path_flatten` available | `lib.nvim` is installed but older than the version data.nvim shipped alongside — `lines`/`keys` will error at call time even though `pretty`/`compact` work fine. Update `lib.nvim`. |
| `lib.lua.yaml.encode` available | Same idea, for `:YAML` specifically — an older `lib.nvim` without the YAML encoder makes every `:YAML` action fail at call time. Update `lib.nvim`. |
| `lib.lua.xml` available | Same idea, for `:XML` — an older `lib.nvim` without `lib.lua.xml` makes every `:XML` action fail at call time. Update `lib.nvim`. |
| `lib.nvim.window.open_scratch_split` available | Same idea, for `--split` (and every register-scope invocation, whose default target is a split) — an older `lib.nvim` without it makes those fail at call time while every in-place action keeps working. Update `lib.nvim`. |
| `color_my_ascii` / `pickers.nvim` / `diff.nvim` detected | Never a failure — all three are optional. Without `color_my_ascii` there is no fenced-block scope; without `pickers.nvim` `filter` is unavailable; without `diff.nvim` `filter --preview` is. See [integrations.md](integrations.md). |
| subset info line | Always shown, not a failure: a reminder that YAML/XML support is intentionally minimal (no anchors/flow-style/DTDs/namespaces) — see [scope.md](scope.md). |
