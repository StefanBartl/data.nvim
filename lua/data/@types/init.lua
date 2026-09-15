---@meta
---@module 'data.@types'

---@class DataJsonConfig
---@field indent integer # Default indent width for `pretty`/`sort` (default 2).
---@field sep string     # Default path separator for `lines`/`keys` (default ".").

---@class DataKeymapsConfig
---@field preset boolean # Reserved for a future default keymap preset. Always false today: data.nvim's actions are Ex commands, not motions, so there is no default preset yet.

---@class DataConfig
---@field json DataJsonConfig
---@field keymaps DataKeymapsConfig

---@alias Data.RenderMode "pretty"|"compact"|"lines"|"keys"|"sort"

---@class Data.RenderOpts
---@field indent? integer # `pretty`/`sort` only.
---@field sep? string     # `lines`/`keys` only.

---@class Data.Formatter
---@field decode fun(text: string): (any, string|nil)
---@field render fun(value: any, mode: Data.RenderMode, opts?: Data.RenderOpts): (string[]|nil, string|nil)

return {}
