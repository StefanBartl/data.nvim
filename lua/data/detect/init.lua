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
---
--- A register source (`:Data ... --reg=+`) skips both: neither signal says
--- anything about text that never came from this buffer. It sniffs the
--- register's own first non-blank line instead -- see `M.from_text`.

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

--- Guess a data.nvim format from the text itself, for input that has no
--- buffer behind it to ask about (a register).
---
--- Deliberately a shallow first-characters heuristic, not a parse: `{`/`[`
--- is JSON, `<` is XML, and a leading `---` document marker, a `- ` sequence
--- item or a `key:` mapping line is YAML. Anything else is `nil` -- a wrong
--- guess here would hand the text to the wrong decoder and report a decode
--- error about a format the user never meant, which reads as a bug in the
--- data rather than a missed guess. `:JSON`/`:YAML`/`:XML` name the format
--- outright and never come through here.
---@param text string
---@return string|nil fmt
function M.from_text(text)
  local first = text:match("[^\r\n]*%S[^\r\n]*")
  if not first then
    return nil
  end
  first = first:gsub("^%s+", "")

  local head = first:sub(1, 1)
  if head == "{" or head == "[" then
    return "json"
  end
  if head == "<" then
    return "xml"
  end
  if first:match("^%-%-%-") or first:match("^%-%s") or first:match("^[%w_%-%.\"']+%s*:%s*") then
    return "yaml"
  end
  return nil
end

---@internal
--- The format of the register a `--reg` flag names, for `:Data --reg=...`.
---@param flags Data.IOFlags
---@return string|nil fmt
---@return string|nil err
local function register_format(flags)
  local register = require("data.scope.register")
  local name, nerr = register.name(flags.reg)
  if not name then
    return nil, nerr or "invalid --reg"
  end
  local lines, rerr = register.read(name)
  if not lines then
    return nil, rerr
  end
  local fmt = M.from_text(table.concat(lines, "\n"))
  if fmt then
    return fmt, nil
  end
  return nil,
    ("could not determine a format from register '%s' -- use :JSON/:YAML/:XML directly"):format(
      name
    )
end

--- Guess `bufnr`'s data.nvim format for a `:Data` invocation.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@param flags? Data.IOFlags
---@return string|nil fmt
---@return string|nil err
function M.format(bufnr, cmd, flags)
  if flags and flags.reg ~= nil and flags.reg ~= false then
    return register_format(flags)
  end

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
