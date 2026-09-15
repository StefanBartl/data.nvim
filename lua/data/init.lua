---@module 'data'
--- Public facade for data.nvim: `setup()` plus the range-aware `run()` action
--- every `:JSON`/`:YAML`/`:XML` route calls into.

local config = require("data.config")
local formats = require("data.format")
local scope = require("data.scope.resolve")
local raw_notify = require("lib.nvim.notify").create("[data]")

local M = {}

---@internal
--- `vim.notify` at ERROR level ultimately reaches `nvim_err_writeln`; called
--- synchronously from inside a usercmd handler invoked via `vim.cmd()` (a
--- script, a macro, a test), that surfaces as a raw "Vim:..." error from the
--- *caller's* `vim.cmd()` instead of a clean notification -- the exact
--- failure mode lib.nvim's own composer defers past with `vim.schedule` (see
--- `lib.nvim.bindings.usercmd.composer`'s `make_deferred_notify`). `M.run` is
--- reached the same way (a route handler calling straight through), so it
--- needs the same deferral.
local notify = {
  error = function(msg)
    vim.schedule(function()
      raw_notify.error(msg)
    end)
  end,
  warn = function(msg)
    vim.schedule(function()
      raw_notify.warn(msg)
    end)
  end,
}

--- Format/filter the resolved scope (range, or whole buffer) of the current
--- buffer in place.
---@param fmt string              # "json"|"yaml"
---@param mode Data.RenderMode
---@param cmd Lib.UserCommand.Args # the raw nvim user-command args (range info)
---@param opts? Data.RenderOpts    # per-invocation override; falls back to config.<fmt>.indent/sep when a field is nil
---@return nil
function M.run(fmt, mode, cmd, opts)
  local formatter = formats.get(fmt)
  if not formatter then
    notify.error(("unknown format '%s'"):format(tostring(fmt)))
    return
  end

  -- Per-invocation args/flags win when given (":JSON pretty 4"); otherwise
  -- fall back to the resolved config.<fmt>.indent/sep -- previously these
  -- config values were merged/typed but never actually read anywhere, so a
  -- user-set json.indent silently had no effect.
  opts = opts or {}
  local defaults = config.get(fmt) or {}
  opts = { indent = opts.indent or defaults.indent, sep = opts.sep or defaults.sep }

  local bufnr = vim.api.nvim_get_current_buf()
  if not vim.bo[bufnr].modifiable then
    notify.error("buffer is not modifiable")
    return
  end

  local s0, e0 = scope.lines(bufnr, cmd)
  local src = vim.api.nvim_buf_get_lines(bufnr, s0, e0 + 1, false)
  if #src == 0 then
    notify.warn("nothing to format (empty range)")
    return
  end

  local value, derr = formatter.decode(table.concat(src, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(fmt:upper(), derr))
    return
  end

  local out, rerr = formatter.render(value, mode, opts)
  if not out then
    notify.error(("%s render failed: %s"):format(fmt:upper(), rerr))
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, s0, e0 + 1, false, out)
end

--- Configure data.nvim and wire up its user commands.
---@param opts? DataConfig
---@return nil
function M.setup(opts)
  config.setup(opts)
  require("data.bindings").setup()
end

return M
