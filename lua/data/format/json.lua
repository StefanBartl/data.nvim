---@module 'data.format.json'
--- Thin adapter over `lib.nvim.json` + `lib.lua.json.encode` +
--- `lib.lua.tables.path_flatten` for data.nvim's JSON render modes. No
--- parsing/encoding logic of its own -- see lib.nvim's json/tables modules
--- for the actual implementation.

local json = require("lib.nvim.json")
local json_encode = require("lib.lua.json.encode")
local tables = require("lib.lua.tables")

local M = {}

---@internal
--- Render a leaf value for `lines`/`keys` display: bare text for strings (no
--- quotes -- this is a human-readable summary, not valid JSON), Lua's own
--- tostring for numbers/booleans, "null" for `vim.json.decode`'s NULL
--- sentinel, and a compact JSON fragment for a table leaf (an empty `{}`/
--- `[]` survives `path_flatten` as its own leaf -- see
--- `lib.lua.tables.paths`).
---@param v any
---@return string
local function display(v)
  if v == vim.NIL then
    return "null"
  end
  local t = type(v)
  if t == "string" then
    return v
  end
  if t == "table" then
    return (json_encode(v)) or vim.inspect(v)
  end
  return tostring(v)
end

--- Decode a JSON string into a Lua value.
---@param text string
---@return any decoded
---@return string|nil err
function M.decode(text)
  return json.decode(text)
end

--- Render a decoded value in one of data.nvim's JSON modes.
---
--- `pretty` and `sort` are currently identical: `vim.json.decode` returns a
--- plain Lua table with no preserved source key order, and
--- `lib.lua.json.encode` sorts object keys by default -- there is no "as
--- read" order left to preserve once a value has round-tripped through Lua.
--- `sort` stays its own route for discoverability and forward-compatibility
--- (an order-preserving decoder would give it real meaning), not because it
--- currently behaves differently from `pretty`.
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
    local str, err = json_encode.pretty(value, { indent = indent })
    if not str then
      return nil, err
    end
    return vim.split(str, "\n", { plain = true }), nil
  end

  if mode == "compact" then
    local str, err = json_encode(value)
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
    for i, item in ipairs(items) do
      out[i] = (mode == "keys") and item.path or (item.path .. ": " .. display(item.value))
    end
    return out, nil
  end

  return nil, "unknown JSON render mode: " .. tostring(mode)
end

---@type Data.Formatter
return M
