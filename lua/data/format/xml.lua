---@module 'data.format.xml'
--- Thin adapter over `lib.lua.xml` + `lib.lua.tables.path_flatten` for
--- data.nvim's XML render modes. Pure Lua underneath, same as
--- `format/yaml.lua` -- neither format's decode/encode touches `vim.json`.
---
--- `lines`/`keys` flatten the RAW decoded element tree
--- (`{tag, attrs, children}` -- see `lib.lua.xml`'s own doc comment), not a
--- JSON-like objectification of the XML document. A path therefore looks
--- like `children.1.attrs.id`, not `user.id` -- mechanical, but faithful to
--- the actual decoded shape, and consistent with this repo's stance of not
--- guessing a schema-dependent mapping (see docs/architecture.md).

local xml = require("lib.lua.xml")
local tables = require("lib.lua.tables")

local M = {}

---@internal
--- Render a leaf value for `lines`/`keys` display. Unlike JSON/YAML, an XML
--- leaf is never a "generic value" in the JSON-value sense -- it's either a
--- plain string (a tag name, an attribute value, a text node) or an empty
--- `attrs`/`children` table, which has no XML representation of its own
--- (`lib.lua.xml.encode` only knows how to encode a whole `{tag, ...}`
--- element, not an arbitrary bare table).
---@param v any
---@return string
local function display(v)
  if type(v) == "string" then
    return v
  end
  if type(v) == "table" then
    return vim.inspect(v)
  end
  return tostring(v)
end

--- Decode an XML string into an element tree.
---@param text string
---@return any decoded
---@return string|nil err
function M.decode(text)
  return xml.decode(text)
end

--- Render a decoded element tree in one of data.nvim's XML modes.
---
--- `pretty` and `sort` are identical: `lib.lua.xml.encode` already sorts
--- attribute names on every call, and element order is a property of the
--- source document `path_flatten`/this encoder never reorders -- there is
--- nothing left for a dedicated "sort" pass to change.
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
    local str, err = xml.encode.pretty(value, { indent = indent })
    if not str then
      return nil, err
    end
    return vim.split(str, "\n", { plain = true }), nil
  end

  if mode == "compact" then
    local str, err = xml.encode(value)
    if not str then
      return nil, err
    end
    return { str }, nil
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

  return nil, "unknown XML render mode: " .. tostring(mode)
end

---@type Data.Formatter
return M
