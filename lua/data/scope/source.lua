---@module 'data.scope.source'
--- Where one `:JSON`/`:YAML`/`:XML`/`:Data` invocation reads its input
--- from: a register (`--reg`/`--reg=<name>`) or, as before, the resolved
--- buffer scope (explicit range, enclosing fenced block, or whole buffer --
--- see `data.scope.resolve`).
---
--- A register source still records the buffer span an explicit range picked
--- out, because `--reg --inplace` is a legitimate combination ("format what
--- I copied and put it over this selection"). It is only ever recorded when
--- a range was actually given: without one, "in place" would mean the whole
--- buffer, and replacing an entire file with clipboard contents is not
--- something a formatting command should be able to do by accident -- see
--- `data.scope.sink`, which is where that refusal lives.
---
--- Deliberately notifies nothing itself: it returns a `Data.Problem` and
--- lets `data`'s own deferred notifier decide (see that module's `notify`
--- for why notifying straight from a usercmd handler is the wrong place).

local register = require("data.scope.register")
local resolve = require("data.scope.resolve")

local M = {}

--- Resolve the input for one invocation.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@param fmt? string # "json"|"yaml"|"xml" -- enables the fenced-block fallback for a buffer source
---@param flags? Data.IOFlags
---@return Data.Source|nil source
---@return Data.Problem|nil problem
function M.resolve(bufnr, cmd, fmt, flags)
  flags = flags or {}

  local reg, rerr, note = register.name(flags.reg)
  if rerr then
    return nil, { msg = rerr, level = "error" }
  end

  if reg then
    local lines, lerr = register.read(reg)
    if not lines then
      return nil, { msg = lerr or "register read failed", level = "error" }
    end
    local s0, e0
    if cmd.range and cmd.range > 0 then
      s0, e0 = cmd.line1 - 1, cmd.line2 - 1
    end
    return {
      kind = "register",
      lines = lines,
      bufnr = bufnr,
      reg = reg,
      note = note,
      s0 = s0,
      e0 = e0,
    },
      nil
  end

  local s0, e0 = resolve.lines(bufnr, cmd, fmt)
  local lines = vim.api.nvim_buf_get_lines(bufnr, s0, e0 + 1, false)
  if #lines == 0 then
    return nil, { msg = "nothing to process (empty range)", level = "warn" }
  end

  return { kind = "buffer", lines = lines, bufnr = bufnr, s0 = s0, e0 = e0 }, nil
end

return M
