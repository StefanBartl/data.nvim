---@module 'data.format.yaml'
--- Thin adapter over `lib.lua.yaml` + `lib.lua.tables.path_flatten` for
--- data.nvim's YAML render modes. Pure Lua underneath -- unlike
--- `format/json.lua`, YAML decode/encode never touch `vim.json`.
---
--- No `compact` action: `lib.lua.yaml`'s subset has no flow style (`{}`/
--- `[]` inline collections -- see that module's own doc comment), so there
--- is no single-line form to produce. Unlike JSON, where "compact" is just
--- the same value written without whitespace, a YAML "compact" would need a
--- representation this decoder cannot read back.

local yaml = require("lib.lua.yaml")
local tables = require("lib.lua.tables")
local null = require("lib.lua.null")

local M = {}

---@internal
--- Render a leaf value for `lines`/`keys` display -- same rules as
--- `data.format.json`'s identical helper (kept separate rather than shared,
--- since the two formats' notion of a "table leaf" fragment differs: JSON
--- vs. YAML encoding of the same empty/scalar value).
---@param v any
---@return string
local function display(v)
  if null.is_null(v) then
    return "null"
  end
  local t = type(v)
  if t == "string" then
    return v
  end
  if t == "table" then
    if next(v) == nil then
      -- `yaml.encode({})` returns "" (an empty document, correct at the top
      -- level -- see that module's own doc comment), which would otherwise
      -- render an empty nested object/array leaf as a blank string here,
      -- indistinguishable from an actual empty-string leaf value.
      return "{}"
    end
    return (yaml.encode(v)) or vim.inspect(v)
  end
  return tostring(v)
end

--- Decode a YAML string into a Lua value.
---@param text string
---@return any decoded
---@return string|nil err
function M.decode(text)
  return yaml.simple_parse(text)
end

--- Render a decoded value in one of data.nvim's YAML modes.
---
--- `pretty` and `sort` are identical, for the same reason as
--- `data.format.json`: `simple_parse` doesn't preserve the source's key
--- order, and `lib.lua.yaml.encode` sorts keys by default.
---@param value any
---@param mode Data.RenderMode
---@param opts? Data.RenderOpts
---@return string[]|nil lines
---@return string|nil err
function M.render(value, mode, opts)
  opts = opts or {}

  if mode == "pretty" or mode == "sort" then
    local indent = opts.indent
    if type(indent) ~= "number" or indent < 1 then
      indent = 2
    end
    local str, err = yaml.encode(value, { indent = indent })
    if not str then
      return nil, err
    end
    if str == "" then
      return {}, nil
    end
    return vim.split(str, "\n", { plain = true }), nil
  end

  if mode == "lines" or mode == "keys" then
    local items, err = tables.path_flatten(value, { sep = opts.sep })
    if not items then
      return nil, err
    end
    local out = {}
    if #items > 0 then
      -- Pre-size the array part: `items`'s length is already known, so
      -- there's no reason to let the fill loop below grow `out` by
      -- repeated reallocation for a large flattened document.
      out[#items] = false
    end
    for i, item in ipairs(items) do
      out[i] = (mode == "keys") and item.path or (item.path .. ": " .. display(item.value))
    end
    return out, nil
  end

  return nil,
    ("unknown YAML render mode: %s (compact is not supported -- see this module's doc comment)"):format(
      tostring(mode)
    )
end

---@type Data.Formatter
return M
