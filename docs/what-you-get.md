# What you get with the defaults

Calling `require("data").setup()` with no arguments (or `opts = {}` under lazy.nvim):

- `:JSON` (five actions: `pretty`, `compact`, `lines`, `keys`, `sort`) and `:YAML`
  (the same four, minus `compact`) are registered and ready — see
  [commands.md](commands.md).
- No default keymaps and no default autocmds are bound. data.nvim's actions are Ex
  commands, not motions or toggles, so there is nothing to bind by default (see
  `data.config.DEFAULTS`'s `keymaps.preset`, currently always `false`).
- `<Tab>` completion on every `:JSON`/`:YAML` subcommand and flag, for free (the
  composer command layer — see [architecture.md](architecture.md)).
- `pretty` defaults to 2-space indent; override per-invocation (`:JSON pretty 4`)
  or via [configuration.md](configuration.md)'s `json.indent`/`yaml.indent`.
- `lines`/`keys` default to `.` as the path separator; override per-invocation
  (`:YAML lines --sep=/`) or via `json.sep`/`yaml.sep`.
