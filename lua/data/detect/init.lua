---@module 'data.detect'
--- Guess which of "json"/"yaml"/"xml" a `:Data` invocation should act as --
--- see `data.bindings.usrcmds`'s `:Data` verb. `:JSON`/`:YAML`/`:XML` never
--- need this: the verb itself already says the format. Two signals, tried
--- in this order:
---
---   1. The enclosing fenced code block's language tag, when the cursor
---      sits inside one, no explicit range was given, and
---      `fenced_scope.enable` isn't `false` -- the same
---      `color_my_ascii.fences` API `data.scope.resolve`'s own fenced-block
---      fallback already calls, just without a fixed `lang` filter this
---      time (see that module's fence API doc).
---   2. The buffer's own 'filetype' otherwise (color_my_ascii absent, no
---      fence under the cursor, or an explicit range was given) -- a
---      compound filetype like `yaml.docker-compose` is read by its first
---      dotted component.
---
--- Neither found: `nil, err` -- there is no third guess to fall back to.

local M = {}

---@internal
--- Fence language tag -> data.nvim format name. Mirrors
--- `data.scope.resolve`'s FENCE_LANGS table, inverted.
---@type table<string, string>
local FORMAT_BY_FENCE_LANG = {
  json = "json",
  jsonc = "json",
  yaml = "yaml",
  yml = "yaml",
  xml = "xml",
}

---@internal
--- 'filetype' (or its first dotted component) -> data.nvim format name.
---@type table<string, string>
local FORMAT_BY_FILETYPE = {
  json = "json",
  jsonc = "json",
  yaml = "yaml",
  xml = "xml",
}

---@internal
--- The enclosing fenced block's data.nvim format, or nil. Only consulted
--- for the *current* window's buffer, same guard as
--- `data.scope.resolve`'s fenced-block fallback and for the same reason:
--- the cursor read below only means anything when `bufnr` is what that
--- window actually shows.
---@param bufnr integer
---@return string|nil
local function fenced_block_format(bufnr)
  if vim.api.nvim_win_get_buf(0) ~= bufnr then
    return nil
  end
  local ok, cma = pcall(require, "color_my_ascii")
  if not ok or type(cma.fences) ~= "table" then
    return nil
  end
  local row0 = vim.api.nvim_win_get_cursor(0)[1] - 1
  local block = cma.fences.block_at(bufnr, row0, {})
  if not block or not block.lang then
    return nil
  end
  return FORMAT_BY_FENCE_LANG[block.lang]
end

--- Guess `bufnr`'s data.nvim format for a `:Data` invocation.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@return string|nil fmt
---@return string|nil err
function M.format(bufnr, cmd)
  if
    not (cmd.range and cmd.range > 0)
    and require("data.config").get("fenced_scope.enable") ~= false
  then
    local fmt = fenced_block_format(bufnr)
    if fmt then
      return fmt, nil
    end
  end

  local ft = vim.bo[bufnr].filetype or ""
  local head = ft:match("^[^.]+") or ft
  local fmt = FORMAT_BY_FILETYPE[head]
  if fmt then
    return fmt, nil
  end

  return nil,
    ("could not determine a format (not inside a json/yaml/xml fenced block, and filetype %q doesn't map to one) -- use :JSON/:YAML/:XML directly"):format(
      ft ~= "" and ft or "<empty>"
    )
end

return M
