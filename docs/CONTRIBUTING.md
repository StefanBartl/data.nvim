# Contributing

## Running the tests

```bash
LIB_NVIM_DIR=/path/to/lib.nvim scripts/test.sh
```

`scripts/minimal_init.lua` also looks for a sibling `../lib.nvim` checkout or a
`.deps/lib.nvim` clone, and for `plenary.nvim` the same way (`PLENARY_DIR`,
`.deps/plenary.nvim`, or `../plenary.nvim`) — see that file for the exact search
order. `scripts/test.sh path/to_spec.lua` runs a single spec file.

## Style

`stylua --check .` and `luacheck lua TESTS` must be clean before a PR. Both configs
(`stylua.toml`, `.luacheckrc`) are in the repo root.

## Adding a format (YAML/XML)

1. Build the missing primitive in `lib.nvim` first (a YAML encoder, or an XML
   decoder+encoder) — data.nvim itself should stay a thin adapter, per
   [architecture.md](architecture.md).
2. Add `lua/data/format/<name>.lua` mirroring `format/json.lua`'s shape
   (`decode(text)`, `render(value, mode, opts)`), register it in
   `lua/data/format/init.lua`.
3. Add the `:YAML`/`:XML` verb in `lua/data/bindings/usrcmds.lua`, mirroring
   `:JSON`'s routes.
4. Extend `lua/data/health.lua` to check the new `lib.nvim` primitive the same way
   it checks `path_flatten`.
