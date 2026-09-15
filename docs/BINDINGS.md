# data.nvim — Binding Cheatsheet

Every user command, keymap, and autocommand `data.nvim` defines. Kept in sync with
`lua/data/bindings/`. Regenerate the usercmd table with
`:lua require("lib.nvim.bindings.usercmd.composer").document("docs/BINDINGS.md")`.

## User Commands

`:JSON`, `:YAML`, `:XML`, each `[action] [args] [flags]` — range-aware (no range =
whole buffer).

| Invocation | Range | Args | Flags | Description |
| --- | --- | --- | --- | --- |
| `:JSON` / `:YAML` / `:XML` | — | — | — | Default action: same as `pretty`. |
| `pretty [indent]` | yes | `indent?: INT` | — | Pretty-print (default 2-space indent). |
| `compact` | yes | — | — | Collapse onto one line. **JSON and XML only.** |
| `lines [--sep=X]` | yes | — | `--sep: STRING` | One `path: value` per leaf, nested keys dotted. |
| `keys [--sep=X]` | yes | — | `--sep: STRING` | Only the (dotted) key paths, no values. |
| `sort [indent]` | yes | `indent?: INT` | — | Pretty-print with object keys sorted (see `docs/commands.md`). |
| `ndjson [indent]` | yes | `indent?: INT` | — | **`:JSON` only.** Pretty-print each line as its own JSON object. |
| `to yaml` | yes | `format: STRING` | — | **`:JSON` only.** Convert the scope to YAML. |
| `to json` | yes | `format: STRING` | — | **`:YAML` only.** Convert the scope to JSON. |

Full action semantics: [commands.md](commands.md).

## Keymaps

None by default (`data.nvim`'s actions are Ex commands, not motions/toggles) — see
[what-you-get.md](what-you-get.md). `keymaps.preset` in `data.config.DEFAULTS` is
reserved for a future preset.

## Autocommands

None — `data.nvim` only acts on an explicit `:JSON`/`:YAML`/`:XML` invocation.
