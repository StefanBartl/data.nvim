---@meta
---@module 'data.@types'

---@class DataJsonConfig
---@field indent integer # Default indent width for `pretty`/`sort` (default 2).
---@field sep string     # Default path separator for `lines`/`keys` (default ".").

---@class DataYamlConfig
---@field indent integer # Default indent width for `pretty`/`sort` (default 2).
---@field sep string     # Default path separator for `lines`/`keys` (default ".").

---@class DataXmlConfig
---@field indent integer # Default indent width for `pretty`/`sort` (default 2).
---@field sep string     # Default path separator for `lines`/`keys` (default ".").

---@class DataKeymapsConfig
---@field preset boolean # Reserved for a future default keymap preset. Always false today: data.nvim's actions are Ex commands, not motions, so there is no default preset yet.

---@class DataFencedScopeConfig
---@field enable boolean # Default true. When the cursor sits inside a matching ```json/```yaml/```xml fenced block and color_my_ascii is installed, act on the block instead of the whole buffer (see data.scope.resolve). A no-op either way when color_my_ascii isn't installed.

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
