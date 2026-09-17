---@meta
---@module 'data.@types'

---@class DataJsonConfig
--- Default indent width for `pretty`/`sort` (default 2).
---@field indent integer
--- Default path separator for `lines`/`keys` (default ".").
---@field sep string

---@class DataYamlConfig
--- Default indent width for `pretty`/`sort` (default 2).
---@field indent integer
--- Default path separator for `lines`/`keys` (default ".").
---@field sep string

---@class DataXmlConfig
--- Default indent width for `pretty`/`sort` (default 2).
---@field indent integer
--- Default path separator for `lines`/`keys` (default ".").
---@field sep string

---@class DataRegisterConfig
--- Register a bare `--reg` (no `=name`) reads from. Default "+", the system
--- clipboard -- the case the register scope exists for is "I copied a
--- payload out of a ticket tool". On a Neovim without a clipboard provider,
--- a bare `--reg` falls back to `"` and says so; an explicitly named
--- `--reg=+` does not (see data.scope.register).
---@field default string

---@class DataTargetConfig
--- Where `--split` (and the register scope's default target) opens its
--- scratch window: "above"|"below"|"left"|"right", or "auto" to use a plain
--- `:new` honoring the user's own 'splitbelow'/'splitright'. Default
--- "right" -- a vertical split, as the concept described it.
---@field split string

---@class DataPreviewConfig
--- Show a diff.nvim before/after preview before an in-place `:JSON filter`/
--- `:YAML filter`/`:XML filter`/`:Data filter` replaces its scope, and ask
--- whether to apply it. Default false; `--preview`/`--no-preview` override
--- it per invocation. Requires diff.nvim (see data.preview).
---@field filter boolean
--- diff.nvim `view=` for that preview: "inline", "float", "vsplit", "split"
--- or "tab". The side-by-side three need diff.nvim ff2f424 or newer to show
--- the right left-hand side -- see data.preview.
---@field view string

---@class DataKeymapsConfig
--- Reserved for a future default keymap preset. Always false today:
--- data.nvim's actions are Ex commands, not motions, so there is no
--- default preset yet.
---@field preset boolean

---@class DataFencedScopeConfig
--- Default true. When the cursor sits inside a matching ```json/```yaml/```xml
--- fenced block and color_my_ascii is installed, act on the block instead of
--- the whole buffer (see data.scope.resolve). A no-op either way when
--- color_my_ascii isn't installed.
---@field enable boolean

---@class DataConfig
---@field json DataJsonConfig
---@field yaml DataYamlConfig
---@field xml DataXmlConfig
---@field fenced_scope DataFencedScopeConfig
---@field register DataRegisterConfig
---@field target DataTargetConfig
---@field preview DataPreviewConfig
---@field keymaps DataKeymapsConfig

---@alias Data.RenderMode "pretty"|"compact"|"lines"|"keys"|"sort"|"ndjson"

---@class Data.RenderOpts
---@field indent? integer # `pretty`/`sort` only.
---@field sep? string     # `lines`/`keys` only.

---@class Data.Formatter
---@field decode fun(text: string): (any, string|nil)
---@field render fun(value: any, mode: Data.RenderMode, opts?: Data.RenderOpts): (string[]|nil, string|nil)

--- The source/target flags every `:JSON`/`:YAML`/`:XML`/`:Data` route
--- accepts, parsed out of the command line by the composer and threaded
--- through `data.run`/`convert`/`filter` to `data.scope.source`/`sink`.
---
--- `reg`/`out_reg` carry `true` for the bare flag form (`--reg`), which
--- means "the configured default register", and a string for `--reg=x`.
---@class Data.IOFlags
---@field reg? string|boolean      # --reg / --reg=<name>: read the input from a register instead of the buffer
---@field inplace? boolean         # --inplace: replace the buffer scope (default for a buffer/selection source)
---@field split? boolean           # --split: open the result in a scratch split (default for a register source)
---@field out_reg? string|boolean  # --out-reg / --out-reg=<name>: write the result into a register
---@field preview? boolean         # --preview: diff the result against the scope and ask before an in-place write (`filter` only)
---@field no_preview? boolean      # --no-preview: skip that, overriding a `preview.filter = true` config

--- A failure one of the scope modules reports back to its caller instead of
--- notifying directly -- see `data.scope.source`'s doc comment.
---@class Data.Problem
---@field msg string
---@field level "error"|"warn"

--- One invocation's resolved input.
---@class Data.Source
---@field kind "buffer"|"register"
---@field lines string[]
---@field bufnr integer   # the buffer the command ran in -- the `--inplace` target, whatever the source was
---@field reg? string     # kind == "register": which register it was read from
---@field note? string    # a non-fatal remark the caller should surface (see data.scope.register.name)
---@field s0? integer     # 0-based inclusive start of the buffer span `--inplace` would replace
---@field e0? integer     # 0-based inclusive end of that span

--- One invocation's resolved target.
---@class Data.Sink
---@field kind "inplace"|"split"|"register"
---@field reg? string     # kind == "register": which register to write

--- One before/after preview, as `data.preview.confirm` takes it.
---@class Data.PreviewOpts
---@field before string[] # the scope as it stands now
---@field after string[]  # what the action would replace it with
---@field label string    # short action name, e.g. "json filter" -- becomes both holder buffer names, and through them the rendered diff's own `---`/`+++` header
---@field prompt string   # the `vim.ui.select` prompt

---@class Data.SinkWriteOpts
---@field filetype? string # 'filetype' for a `--split` scratch buffer; nil when the output isn't in the source format (`lines`/`keys`/`filter`)
---@field label? string    # human-readable name for the scratch buffer, e.g. "json pretty (+)"

return {}
