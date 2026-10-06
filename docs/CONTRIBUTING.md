# Contributing

## Running the tests

```bash
scripts/test.sh                  # every spec
scripts/test.sh --file config    # only spec files whose name contains "config"
```

The suite runs on [testing.nvim](https://github.com/StefanBartl/testing.nvim).
`scripts/test.sh` looks up testing.nvim and every dependency (`lib.nvim`,
`color_my_ascii.nvim`, `diff.nvim`, `pickers.nvim`) in four places, in this
order: `$<NAME>_DIR` (for example `LIB_NVIM_DIR`), `.deps/<name>`, a sibling
`../<name>` checkout, `stdpath('data')/lazy/<name>`. A dependency that is
missing stops the run with exit code 1 and a message naming all four places.

`color_my_ascii.nvim`, `pickers.nvim` and `diff.nvim` are optional for the
plugin itself, but the test run loads them, so the specs that need one
(`scope_resolve_spec.lua`, `filter_spec.lua`, `preview_spec.lua`) really run
instead of registering nothing. See [integrations.md](integrations.md). Each of
those three specs also has a counterpart that runs against a double
(`filter_failure_spec.lua`, `preview_failure_spec.lua`,
`filter_lifecycle_spec.lua`), so no code path is covered only on a machine that
has all three installed.

[`TESTS/README.md`](../TESTS/README.md) is the register of what the suite
covers, what it deliberately leaves out and why, and which known defects are
pinned with a `BUG:`-marked assertion rather than fixed. Read it before adding
a spec, and update it when you do.

## Style

`stylua --check .` and `luacheck .` must be clean before a PR — exactly the two
commands CI runs, and both cover `TESTS/` as well as `lua/`. Both configs
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
