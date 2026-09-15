# What you get with the defaults

Calling `require("data").setup()` with no arguments (or `opts = {}` under lazy.nvim):

- `:JSON` and its five actions (`pretty`, `compact`, `lines`, `keys`, `sort`) are
  registered and ready — see [commands.md](commands.md).
- No default keymaps and no default autocmds are bound. data.nvim's actions are Ex
  commands, not motions or toggles, so there is nothing to bind by default (see
  `data.config.DEFAULTS`'s `keymaps.preset`, currently always `false`).
- `<Tab>` completion on every `:JSON` subcommand and flag, for free (the composer
  command layer — see [architecture.md](architecture.md)).
- `:JSON pretty` defaults to 2-space indent; override per-invocation
  (`:JSON pretty 4`) or via [configuration.md](configuration.md)'s `json.indent`.
- `:JSON lines`/`:JSON keys` default to `.` as the path separator; override
  per-invocation (`:JSON lines --sep=/`) or via `json.sep`.
