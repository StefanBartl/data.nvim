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
