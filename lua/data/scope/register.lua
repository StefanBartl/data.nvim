---@module 'data.scope.register'
--- Register access shared by the `--reg=<name>` source scope and the
--- `--out-reg=<name>` target: resolving a flag value to a register name
--- (including the configured default behind a bare `--reg`), reading, and
--- writing.
---
--- Kept in its own module rather than inlined into `data.scope.source`
--- because `data.detect` needs the same name resolution and the same read
--- to sniff a format out of register contents for `:Data --reg=...`, well
--- before any source/sink is built.

local M = {}

---@internal
--- Registers Vim itself refuses to write to (`:help registers`): the last
--- command line, the last inserted text, the current file name, the
--- alternate file name, and the expression register. Rejected up front with
--- a name-the-register message rather than letting `setreg` fail with a raw
--- Vim error out of a usercmd handler.
---@type table<string, true>
local READ_ONLY = {
  [":"] = true,
  ["."] = true,
  ["%"] = true,
  ["#"] = true,
  ["="] = true,
}

---@internal
--- The expression register is refused as a SOURCE too. That is a separate
--- rule from the write ban above, and it does not follow from it.
---
--- `getreg("=")` *evaluates* the stored expression rather than returning
--- stored text -- verified, not assumed: a `=` register holding a
--- `luaeval(...)` call runs that call and hands back its result. Every other
--- register read here is a plain text read with no side effects, and `--reg`
--- reads like one. A formatting command that executes whatever expression
--- happens to be sitting in `=` is a surprise nobody asked for, so this is a
--- named refusal rather than a silent evaluation.
---@type table<string, true>
local UNREADABLE = { ["="] = true }

--- Resolve a `--reg`/`--out-reg` flag value to a register name.
---
--- `nil`/`false` (flag absent) resolves to `nil, nil` -- not an error, just
--- "no register involved". A bare `--reg` (the composer binds `true` for an
--- `optional_value` flag given without `=value`) resolves to the configured
--- `register.default`; `--reg=x` to `x` verbatim.
---
--- The clipboard fallback applies to the bare form only: the default is `+`,
--- and on a Neovim without a clipboard provider `+` is permanently empty, so
--- an implicit default would fail for a reason the user never chose. An
--- explicitly typed `--reg=+` is left alone and fails with the ordinary
--- "register is empty" message instead -- that one WAS the user's choice,
--- and silently reading a different register than the one they named would
--- be worse than the error.
---@param flag string|boolean|nil
---@return string|nil name
---@return string|nil err
---@return string|nil note # non-fatal remark the caller should surface
function M.name(flag)
  if flag == nil or flag == false then
    return nil, nil, nil
  end

  local implicit = (flag == true or flag == "")
  local name
  if implicit then
    name = require("data.config").get("register.default")
    if type(name) ~= "string" or name == "" then
      name = "+"
    end
  else
    name = tostring(flag)
  end

  if #name ~= 1 then
    return nil, ("invalid register name %q -- a register name is a single character"):format(name)
  end

  local note
  if implicit and (name == "+" or name == "*") and vim.fn.has("clipboard") == 0 then
    note = ("no clipboard provider -- using register '\"' instead of the configured default '%s'"):format(
      name
    )
    name = '"'
  end

  return name, nil, note
end

--- Whether `name` can be written to, with the reason when it cannot.
---@param name string
---@return boolean ok
---@return string|nil err
function M.writable(name)
  if READ_ONLY[name] then
    return false, ("register '%s' is read-only -- pick a writable one"):format(name)
  end
  return true, nil
end

--- Read `name`'s contents as lines.
---
--- A linewise register ends in a trailing newline, which `vim.split` turns
--- into a trailing empty element -- dropped here so the caller gets the
--- lines that were yanked and not one blank extra, which would otherwise
--- show up as a stray empty line in every scratch split.
---
--- CRLF is normalized away for the same reason that trailing blank is: it is
--- an artifact of where the text came from, not content. The register scope
--- exists for "I copied this out of a ticket tool", and on Windows that text
--- arrives CRLF-terminated far more often than not. All three decoders
--- tolerate the stray CR (it is whitespace to each of them), but anything
--- that passes a line through verbatim does not -- `:JSON ndjson` re-emits a
--- line it could not decode exactly as it found it, which put a literal `^M`
--- into the result. Only a LINE-TERMINATING CR is dropped; one in the middle
--- of a line is content and stays.
---@param name string
---@return string[]|nil lines
---@return string|nil err
function M.read(name)
  if UNREADABLE[name] then
    return nil,
      ("register '%s' is the expression register -- reading it would evaluate its contents"):format(
        name
      )
  end
  local ok, text = pcall(vim.fn.getreg, name)
  if not ok then
    return nil, ("could not read register '%s': %s"):format(name, tostring(text))
  end
  if type(text) ~= "string" then
    -- A register holding a NUL byte comes back as a Blob, not a string, and
    -- `tostring` on one raises E976 -- which used to escape this module as a
    -- raw Vim error from inside a usercmd handler. There is nothing sensible
    -- to decode in binary anyway, so it is named and refused.
    return nil, ("register '%s' holds binary data, not text -- nothing to decode"):format(name)
  end
  if not text:find("%S") then
    return nil, ("register '%s' is empty"):format(name)
  end

  local lines = vim.split(text, "\n", { plain = true })
  for i = 1, #lines do
    local line = lines[i]
    if line:sub(-1) == "\r" then
      lines[i] = line:sub(1, -2)
    end
  end
  if #lines > 1 and lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines, nil
end

--- Write `lines` into `name` as a linewise register.
---@param name string
---@param lines string[]
---@return boolean ok
---@return string|nil err
function M.write(name, lines)
  local writable, werr = M.writable(name)
  if not writable then
    return false, werr
  end
  local ok, err = pcall(vim.fn.setreg, name, lines, "l")
  if not ok then
    return false, ("could not write register '%s': %s"):format(name, tostring(err))
  end
  return true, nil
end

return M
