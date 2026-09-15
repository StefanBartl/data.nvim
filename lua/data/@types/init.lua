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
---@field keymaps DataKeymapsConfig

---@alias Data.RenderMode "pretty"|"compact"|"lines"|"keys"|"sort"|"ndjson"

---@class Data.RenderOpts
---@field indent? integer # `pretty`/`sort` only.
---@field sep? string     # `lines`/`keys` only.

---@class Data.Formatter
---@field decode fun(text: string): (any, string|nil)
---@field render fun(value: any, mode: Data.RenderMode, opts?: Data.RenderOpts): (string[]|nil, string|nil)

return {}
