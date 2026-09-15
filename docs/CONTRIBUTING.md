# Contributing

## Running the tests

```bash
LIB_NVIM_DIR=/path/to/lib.nvim scripts/test.sh
```

`scripts/minimal_init.lua` also looks for a sibling `../lib.nvim` checkout or a
`.deps/lib.nvim` clone, and for `plenary.nvim` the same way (`PLENARY_DIR`,
`.deps/plenary.nvim`, or `../plenary.nvim`) — see that file for the exact search
order. `scripts/test.sh path/to_spec.lua` runs a single spec file.

`COLOR_MY_ASCII_DIR` (or a sibling `../color_my_ascii.nvim`/`.deps/color_my_ascii.nvim`)
is looked up the same way but is optional: the fenced-scope specs in
`scope_resolve_spec.lua` skip themselves when it isn't found, rather than failing
the run — see [integrations.md](integrations.md).

## Style

`stylua --check .` and `luacheck lua TESTS` must be clean before a PR. Both configs
(`stylua.toml`, `.luacheckrc`) are in the repo root.

## Adding a format

`:YAML` and `:XML` are both worked examples of this process — see either diff
for a concrete template.

1. Build the missing primitive in `lib.nvim` first — data.nvim itself should stay
   a thin adapter, per [architecture.md](architecture.md).
2. Add `lua/data/format/<name>.lua` mirroring `format/json.lua`'s shape
   (`decode(text)`, `render(value, mode, opts)`), register it in
   `lua/data/format/init.lua`.
3. Call `bindings/usrcmds.lua`'s `make_verb("<name>", "<NAME>", <include_compact>)`
   from `M.setup()` — the route factory is already parameterized by format name,
   so a new format is one line, not a duplicated route table.
4. Extend `lua/data/health.lua` to check the new `lib.nvim` primitive the same way
   it checks `path_flatten`/`yaml.encode`/`xml`.
5. Add `format_<name>_spec.lua` and a `:<NAME>` section in `usrcmds_spec.lua`,
   mirroring the YAML/XML specs.
