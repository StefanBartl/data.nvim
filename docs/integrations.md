# Integrations

## color_my_ascii.nvim — fenced-block scope

**Optional.** When [`color_my_ascii.nvim`](https://github.com/StefanBartl/color_my_ascii.nvim)
is installed and the cursor sits inside a fenced code block tagged
` ```json `/` ```yaml `/` ```xml ` (e.g. in a Markdown note), a `:JSON`/`:YAML`/`:XML`
invocation with **no explicit range** acts on that block's interior instead of
the whole buffer:

````markdown
Some notes.

```json
{"a":1,"b":2}
```

More notes.
````

Put the cursor inside the fenced block above and run `:JSON pretty` — only the
block is reformatted, the rest of the note is untouched. An explicit range or
visual selection (`:5,8JSON pretty`, `'<,'>JSON pretty`) always wins over this,
same as it wins over the whole-buffer default.

Nothing to install beyond `color_my_ascii.nvim` itself — data.nvim calls its
public [fence API](https://github.com/StefanBartl/color_my_ascii.nvim/blob/main/docs/api.md#fence-api-for-plugin-authors)
(`color_my_ascii.fences.block_at`) via `pcall`, so its absence is a silent,
total no-op: `:checkhealth data` reports whether it was found, and whole-buffer
scope is used either way. Disable the feature outright with
`fenced_scope.enable = false` in [`setup()`](configuration.md).

The same API, called without a fixed `lang` filter, is also how `:Data`
guesses which format a fenced block is — see
[commands.md](commands.md#data--format-auto-detected). `fenced_scope.enable
= false` turns this signal off for `:Data` too, same as for the other three
commands' scope.

## pickers.nvim — `:JSON`/`:YAML`/`:XML`/`:Data filter`

**Required for this one action, unlike every other integration on this page.**
`filter` reduces the flattened `path`/`value` entries `lines`/`keys` already
render down to the ones matching a clause stack, built interactively via
[`pickers.nvim`](https://github.com/StefanBartl/pickers.nvim)'s
[`pickers.refine`](https://github.com/StefanBartl/pickers.nvim/blob/main/docs/FEATURES/REFINE.md)
module — a pure model+UI filter stack with no picker-engine dependency of its
own (it never opens, closes or refreshes a picker; data.nvim doesn't either).

Without `pickers.nvim` installed, every other `data.nvim` command still works
exactly as documented; only `filter` fails, with a clear notification rather
than silently doing nothing. `:checkhealth data` reports whether
`pickers.refine` was found. See [commands.md](commands.md) for the prompt flow.
