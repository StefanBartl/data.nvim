---@module 'data.scope.sink'
--- Where one invocation's result goes: back over the buffer scope
--- (`--inplace`), into a fresh scratch split (`--split`), or into a register
--- (`--out-reg`/`--out-reg=<name>`). The default follows the source -- a
--- buffer/selection scope replaces itself, a register source opens a split,
--- because the whole point of reading from a register is not to touch the
--- buffer you happen to be sitting in.
---
--- **Naming deviation from the concept**, which listed `--inplace`/
--- `--split`/`--reg=<name>` as the three target flags while ALSO using
--- `--reg=<name>` for the register *source* one paragraph earlier. One name
--- cannot mean both "read from here" and "write to there" on the same
--- command line, so the source keeps `--reg` (that is the reading the
--- roadmap's Phase 1 bullet spells out first and in most detail) and the
--- register *target* is `--out-reg`.
---
--- Like `data.scope.source`, this notifies nothing itself and returns a
--- `Data.Problem` instead.

local register = require("data.scope.register")

local M = {}

---@internal
--- `target.split` config values `lib.nvim.window.open_scratch_split`
--- understands. Anything else -- "auto", or a typo the config validator
--- can't catch (it checks types, not enums) -- resolves to nil, which is
--- that helper's "plain `:new`, honoring the user's own 'splitbelow'/
--- 'splitright'" behavior: the safe fallback either way.
---@type table<string, true>
local SPLIT_DIRECTIONS = {
  above = true,
  below = true,
  left = true,
  right = true,
}

---@internal
--- Monotonic counter for scratch-buffer names. `nvim_buf_set_name` fails on
--- a name another buffer already carries, and every `--split` run opens its
--- own buffer on purpose (see `open_scratch_split`'s own doc comment), so a
--- second `:JSON pretty --split` would otherwise collide with the first.
---@type integer
local scratch_seq = 0

--- Decide where `source`'s result should go.
---@param source Data.Source
---@param flags Data.IOFlags
---@return Data.Sink|nil sink
---@return Data.Problem|nil problem
function M.resolve(source, flags)
  local chosen = {}
  if flags.inplace then
    chosen[#chosen + 1] = "--inplace"
  end
  if flags.split then
    chosen[#chosen + 1] = "--split"
  end
  local wants_reg = flags.out_reg ~= nil and flags.out_reg ~= false
  if wants_reg then
    chosen[#chosen + 1] = "--out-reg"
  end
  if #chosen > 1 then
    return nil,
      {
        msg = ("%s are mutually exclusive -- pick one target"):format(table.concat(chosen, " / ")),
        level = "error",
      }
  end

  if wants_reg then
    local name, err = register.name(flags.out_reg)
    if not name then
      return nil, { msg = err or "invalid --out-reg", level = "error" }
    end
    local ok, werr = register.writable(name)
    if not ok then
      return nil, { msg = werr or "register is read-only", level = "error" }
    end
    return { kind = "register", reg = name }, nil
  end

  if flags.split then
    return { kind = "split" }, nil
  end

  if flags.inplace or source.kind == "buffer" then
    if source.s0 == nil then
      -- Only reachable for a register source with no explicit range: there
      -- is no scope to replace, and "the whole buffer" is not a sane
      -- stand-in for one (see this module's and data.scope.source's own
      -- doc comments).
      return nil,
        {
          msg = "--inplace with --reg needs an explicit range or visual selection -- refusing to replace the whole buffer with register contents",
          level = "error",
        }
    end
    return { kind = "inplace" }, nil
  end

  return { kind = "split" }, nil
end

---@internal
--- Replace `source`'s buffer span with `lines`.
---
--- Both checks are made here rather than at scope-resolution time on
--- purpose: a read-only buffer is a perfectly good *source* for
--- `--split`/`--out-reg`, and `:JSON filter` re-enters this path from an
--- async callback, arbitrarily long after the command was typed, by which
--- point the buffer may have been closed or locked meanwhile.
---@param source Data.Source
---@param lines string[]
---@return boolean ok
---@return Data.Problem|nil problem
local function write_inplace(source, lines)
  local bufnr = source.bufnr
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, { msg = "buffer is no longer valid -- discarding the result", level = "error" }
  end
  if not vim.bo[bufnr].modifiable then
    return false, { msg = "buffer is not modifiable", level = "error" }
  end
  vim.api.nvim_buf_set_lines(bufnr, source.s0, (source.e0 or 0) + 1, false, lines)
  return true, nil
end

---@internal
--- Open `lines` in a fresh scratch split.
---@param lines string[]
---@param opts Data.SinkWriteOpts
---@return boolean ok
---@return Data.Problem|nil problem
local function write_split(lines, opts)
  local ok_win, window = pcall(require, "lib.nvim.window")
  if not ok_win or type(window.open_scratch_split) ~= "function" then
    return false,
      {
        msg = "lib.nvim.window.open_scratch_split not found -- lib.nvim is outdated",
        level = "error",
      }
  end

  local direction = require("data.config").get("target.split")
  local ok, bufnr = pcall(window.open_scratch_split, lines, {
    split = SPLIT_DIRECTIONS[direction] and direction or nil,
    filetype = opts.filetype,
    -- A result split is scratch (`nofile`, wiped on hide): letting the user
    -- trim a line before yanking it back into a ticket costs nothing and
    -- saves a round trip through a real buffer.
    modifiable = true,
  })
  if not ok then
    return false,
      { msg = ("could not open result split: %s"):format(tostring(bufnr)), level = "error" }
  end

  if opts.label then
    scratch_seq = scratch_seq + 1
    pcall(vim.api.nvim_buf_set_name, bufnr, ("data://%s [%d]"):format(opts.label, scratch_seq))
  end
  return true, nil
end

--- Write `lines` to `sink`.
---@param sink Data.Sink
---@param source Data.Source
---@param lines string[]
---@param opts? Data.SinkWriteOpts
---@return boolean ok
---@return Data.Problem|nil problem
---@return string|nil note # what happened, when nothing visible did (register target)
function M.write(sink, source, lines, opts)
  opts = opts or {}

  if sink.kind == "inplace" then
    local ok, problem = write_inplace(source, lines)
    return ok, problem, nil
  end

  if sink.kind == "register" then
    local ok, err = register.write(sink.reg, lines)
    if not ok then
      return false, { msg = err or "register write failed", level = "error" }
    end
    return true, nil, ("wrote %d line(s) to register '%s'"):format(#lines, sink.reg)
  end

  local ok, problem = write_split(lines, opts)
  return ok, problem, nil
end

return M
