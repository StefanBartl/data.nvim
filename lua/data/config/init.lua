---@module 'data.config'
--- Runtime configuration store for data.nvim.
---
--- Deep-merges user options over `data.config.DEFAULTS` and exposes a single
--- `get(path)` accessor (dot-separated path) so other modules never read a
--- raw options table directly.

local DEFAULTS = require("data.config.DEFAULTS")
local lib_config = require("lib.lua.config")
local raw_notify = require("lib.nvim.notify").create("[data]")

---@class DataConfigModule
---@field options DataConfig
local M = {}

-- The config object: a fresh copy of DEFAULTS on every setup(), unknown keys,
-- non-table sections and leaf values of the wrong type reported and dropped
-- before the merge (the schema is inferred from DEFAULTS). Notifying is
-- deferred via `vim.schedule` the same way `data.init`'s own `notify` is:
-- `setup()` can run synchronously during plugin load, before scheduling a
-- notification is safe.
local cfg = lib_config.new(DEFAULTS, {
  name = "data",
  notify = function(message)
    vim.schedule(function()
      raw_notify.warn(message)
    end)
  end,
  on_change = function(current)
    M.options = current
  end,
})

-- M.options is public (see the @field above). It is the live config table,
-- replaced by every setup(); a write through it before setup() has run
-- changes this config, never DEFAULTS (the object holds its own copy).
M.options = cfg.get()

--- Apply user options. Every call starts from DEFAULTS.
---@param opts DataConfig|nil
---@return nil
function M.setup(opts)
  cfg.setup(type(opts) == "table" and opts or nil)
end

--- Read a value by dot-path, e.g. `get("json.indent")`. A table-valued
--- result is a deep copy, never a live reference into `M.options` -- a
--- caller that sorts/mutates it (as an earlier bug in a sibling plugin did)
--- must not be able to corrupt the shared config for the rest of the
--- session.
---@param path string
---@return any
function M.get(path)
  local v = lib_config.get(M.options, path)
  if type(v) == "table" then
    return vim.deepcopy(v)
  end
  return v
end

--- A deep-copied snapshot of the whole resolved config, for the rare caller
--- that needs the entire table rather than one dot-path (`data.bindings`
--- threading `cfg` into `keymaps.setup`/`autocmds.setup`) -- see `M.get`'s
--- own doc comment for why this is a copy, not `M.options` itself.
---@return DataConfig
function M.get_all()
  return vim.deepcopy(M.options)
end

return M
