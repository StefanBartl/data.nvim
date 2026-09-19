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

-- A deep copy, not the shared DEFAULTS table itself: M.options is public
-- (see the @field above), and a write through it before setup() has ever
-- run must not corrupt DEFAULTS for the rest of the session.
M.options = vim.deepcopy(DEFAULTS)

---@internal
--- Warn about any key in `opts` that `schema` doesn't recognize, or whose
--- leaf value's type doesn't match its default's -- `lib.lua.config.deep_merge`
--- accepts any key/type unconditionally (that's its job: a typo like
--- `{ jsno = {...} }` becomes a real, merged-in `jsno` field with no error),
--- so a mistake here would otherwise vanish completely silently. Deferred
--- via `vim.schedule` the same way `data.init`'s own `notify` is: `setup()`
--- can run synchronously during plugin load, before scheduling a
--- notification is safe.
---@param schema table    # DEFAULTS or one of its nested tables
---@param opts table       # the corresponding level of the user's opts
---@param prefix string    # dot-path so far, "" at the top level
---@return nil
local function validate(schema, opts, prefix)
  for k, v in pairs(opts) do
    local path = (prefix == "" and k or (prefix .. "." .. k))
    local default_v = schema[k]
    if default_v == nil then
      vim.schedule(function()
        raw_notify.warn(("unknown config key '%s' -- ignored"):format(path))
      end)
    elseif type(default_v) == "table" then
      if type(v) == "table" then
        validate(default_v, v, path)
      else
        vim.schedule(function()
          raw_notify.warn(
            ("config key '%s' should be a table, got %s -- ignored"):format(path, type(v))
          )
        end)
      end
    elseif type(v) ~= type(default_v) then
      vim.schedule(function()
        raw_notify.warn(
          ("config key '%s' should be %s, got %s -- using default"):format(
            path,
            type(default_v),
            type(v)
          )
        )
      end)
    end
  end
end

--- Apply user options. Safe to call once from `setup()`.
---
--- `lib_config.deep_merge` copies `base` only one level at a time: every key
--- `opts` doesn't touch is carried over as `out[k] = v`, a reference to that
--- DEFAULTS sub-table, not a copy of it (see its own doc comment -- that's
--- deliberate there, a pure two-argument helper has no business assuming its
--- caller wants a deep copy). Assigning its result straight to `M.options`
--- therefore re-aliased DEFAULTS's untouched sub-tables on every real
--- `setup()` call, undoing the module-load-time `vim.deepcopy` above for the
--- entire rest of the session: `M.options.yaml` became `DEFAULTS.yaml` again
--- the moment `opts` didn't mention `yaml`, and a write through the public
--- `options` field (the exact access pattern `M.get`'s own doc comment warns
--- about) would corrupt DEFAULTS itself. `vim.deepcopy` on the merge result
--- severs that aliasing.
---@param opts DataConfig|nil
---@return nil
function M.setup(opts)
  if type(opts) ~= "table" then
    opts = {}
  else
    validate(DEFAULTS, opts, "")
  end
  M.options = vim.deepcopy(lib_config.deep_merge(DEFAULTS, opts))
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
