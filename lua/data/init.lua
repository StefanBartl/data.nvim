---@module 'data'
--- Public facade for data.nvim: `setup()` plus the range-aware `run()`/
--- `convert()` actions every `:JSON`/`:YAML`/`:XML` route calls into.

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
--- `lib.nvim.bindings.usercmd.composer`'s `make_deferred_notify`). `M.run`/
--- `M.convert` are reached the same way (a route handler calling straight
--- through), so they need the same deferral.
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

---@internal
--- Resolve a per-invocation option against its configured default. Falls
--- back on `nil` OR an empty string: the composer's `--sep=` flag (no value
--- after the `=`) parses to `""`, which is truthy in Lua and would
--- otherwise silently win over the configured separator instead of falling
--- back to it.
---@param v any
---@param default any
---@return any
local function opt_or_default(v, default)
  if v == nil or v == "" then
    return default
  end
  return v
end

---@internal
--- Call `fn(a, b, c)` guarded by `pcall`, collapsing an unexpected runtime
--- error into the same `nil, err` shape `formatter.decode`/`formatter.render`
--- already use. Neither `lib.lua.xml`/`lib.lua.yaml`'s decoders/encoders nor
--- `lib.nvim.json`'s null-normalization throw under normal use, but each has
--- (or had) a recursion-depth guard as its only defense against a
--- pathologically deep document -- this is the belt to that suspenders, so a
--- gap in one of those guards surfaces here as a clean notification instead
--- of a raw Vim error escaping past the caller's `vim.cmd()`.
---@param fn function
---@param a any
---@param b any
---@param c any
---@return any result_or_nil
---@return string|nil err
local function safe_call(fn, a, b, c)
  local ok, r1, r2 = pcall(fn, a, b, c)
  if not ok then
    return nil, tostring(r1)
  end
  return r1, r2
end

---@internal
--- Shared prelude for `run`/`convert`: modifiable check, scope resolution,
--- non-empty check. Already notifies on failure, so callers only need to
--- check for a nil `s0`.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@param fmt string
---@return integer|nil s0, integer|nil e0, string[]|nil src
local function resolve_scope(bufnr, cmd, fmt)
  if not vim.bo[bufnr].modifiable then
    notify.error("buffer is not modifiable")
    return nil, nil, nil
  end
  local s0, e0 = scope.lines(bufnr, cmd, fmt)
  local src = vim.api.nvim_buf_get_lines(bufnr, s0, e0 + 1, false)
  if #src == 0 then
    notify.warn("nothing to process (empty range)")
    return nil, nil, nil
  end
  return s0, e0, src
end

---@internal
--- `:JSON ndjson`: treat each non-blank line of the scope as its own JSON
--- object (rather than the whole scope as one document) and pretty-print it
--- in place. A line that fails to decode is left completely unchanged --
--- one bad line in a log dump shouldn't block reformatting the rest -- and
--- the total skipped is reported once as a single warning afterwards.
---@param formatter Data.Formatter
---@param fmt string
---@param bufnr integer
---@param s0 integer
---@param e0 integer
---@param src string[]
---@param opts Data.RenderOpts
---@return nil
local function run_ndjson(formatter, fmt, bufnr, s0, e0, src, opts)
  local out, skipped = {}, 0
  for _, line in ipairs(src) do
    if line:find("%S") then
      local value, derr = safe_call(formatter.decode, line)
      local rendered, rerr
      if not derr then
        rendered, rerr = safe_call(formatter.render, value, "pretty", opts)
      end
      if rendered and not rerr then
        for _, rl in ipairs(rendered) do
          out[#out + 1] = rl
        end
      else
        skipped = skipped + 1
        out[#out + 1] = line
      end
    else
      out[#out + 1] = line
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, s0, e0 + 1, false, out)
  if skipped > 0 then
    notify.warn(
      ("%s ndjson: %d line(s) could not be decoded and were left unchanged"):format(
        fmt:upper(),
        skipped
      )
    )
  end
end

--- Format/filter the resolved scope (range, fenced block, or whole buffer)
--- of the current buffer in place.
---@param fmt string              # "json"|"yaml"|"xml"
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
  opts = {
    indent = opt_or_default(opts.indent, defaults.indent),
    sep = opt_or_default(opts.sep, defaults.sep),
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local s0, e0, src = resolve_scope(bufnr, cmd, fmt)
  if not s0 then
    return
  end
  ---@cast e0 integer
  ---@cast src string[]

  if mode == "ndjson" then
    run_ndjson(formatter, fmt, bufnr, s0, e0, src, opts)
    return
  end

  local value, derr = safe_call(formatter.decode, table.concat(src, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(fmt:upper(), derr))
    return
  end

  local out, rerr = safe_call(formatter.render, value, mode, opts)
  if not out then
    notify.error(("%s render failed: %s"):format(fmt:upper(), rerr))
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, s0, e0 + 1, false, out)
end

--- Convert the resolved scope from `src_fmt` to `dst_fmt`, replacing it with
--- the pretty-printed result in the target format (`:JSON to yaml`,
--- `:YAML to json`). XML is deliberately not wired into this: its decoded
--- element tree has no unambiguous mapping to or from a plain JSON/YAML
--- value without a schema -- see docs/architecture.md.
---@param src_fmt string
---@param dst_fmt string
---@param cmd Lib.UserCommand.Args
---@param opts? Data.RenderOpts
---@return nil
function M.convert(src_fmt, dst_fmt, cmd, opts)
  local src_formatter = formats.get(src_fmt)
  local dst_formatter = formats.get(dst_fmt)
  if not (src_formatter and dst_formatter) then
    notify.error(("unknown format '%s'"):format(tostring(not src_formatter and src_fmt or dst_fmt)))
    return
  end

  opts = opts or {}
  local defaults = config.get(dst_fmt) or {}
  opts = {
    indent = opt_or_default(opts.indent, defaults.indent),
    sep = opt_or_default(opts.sep, defaults.sep),
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local s0, e0, src = resolve_scope(bufnr, cmd, src_fmt)
  if not s0 then
    return
  end
  ---@cast e0 integer
  ---@cast src string[]

  local value, derr = safe_call(src_formatter.decode, table.concat(src, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(src_fmt:upper(), derr))
    return
  end

  local out, rerr = safe_call(dst_formatter.render, value, "pretty", opts)
  if not out then
    notify.error(("%s -> %s conversion failed: %s"):format(src_fmt:upper(), dst_fmt:upper(), rerr))
    return
  end

  vim.api.nvim_buf_set_lines(bufnr, s0, e0 + 1, false, out)
end

--- Interactively filter the resolved scope down to the flattened path/value
--- entries matching a user-built `pickers.refine` clause stack (`:JSON
--- filter`/`:YAML filter`/`:XML filter`), replacing the scope with the
--- survivors' `lines`-style text. See `data.filter` for the actual clause
--- loop; this only resolves scope/decode and writes the result back, same
--- shape as `run`/`convert`, except the write happens later, from
--- `data.filter`'s `on_done` callback, once the interactive part is over.
---@param fmt string              # "json"|"yaml"|"xml"
---@param cmd Lib.UserCommand.Args
---@param opts? Data.RenderOpts
---@return nil
function M.filter(fmt, cmd, opts)
  local formatter = formats.get(fmt)
  if not formatter then
    notify.error(("unknown format '%s'"):format(tostring(fmt)))
    return
  end

  opts = opts or {}
  local defaults = config.get(fmt) or {}
  opts = {
    indent = opt_or_default(opts.indent, defaults.indent),
    sep = opt_or_default(opts.sep, defaults.sep),
  }

  local bufnr = vim.api.nvim_get_current_buf()
  local s0, e0, src = resolve_scope(bufnr, cmd, fmt)
  if not s0 then
    return
  end
  ---@cast e0 integer
  ---@cast src string[]

  local value, derr = safe_call(formatter.decode, table.concat(src, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(fmt:upper(), derr))
    return
  end

  require("data.filter").run(formatter, value, opts, function(out, ferr)
    if ferr then
      notify.error(("%s filter: %s"):format(fmt:upper(), ferr))
      return
    end
    if not out then
      -- Cancelled before any clause was added -- nothing to do, silently.
      return
    end
    if #out == 0 then
      notify.warn(("%s filter: no entries matched -- scope left unchanged"):format(fmt:upper()))
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, s0, e0 + 1, false, out)
  end)
end

--- Auto-detect the format for a `:Data <action>` invocation (an enclosing
--- fenced code block's language when the cursor sits inside one and no
--- explicit range was given, otherwise the buffer's own filetype -- see
--- `data.detect`) and dispatch to `run`/`filter` accordingly. `:JSON`/
--- `:YAML`/`:XML` never need this: the verb itself already says the format.
---@param action string # "pretty"|"lines"|"keys"|"sort"|"filter" -- the format-agnostic subset every formatter supports the same way
---@param cmd Lib.UserCommand.Args
---@param opts? Data.RenderOpts
---@return nil
function M.run_auto(action, cmd, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local fmt, derr = require("data.detect").format(bufnr, cmd)
  if not fmt then
    notify.error(derr)
    return
  end

  if action == "filter" then
    M.filter(fmt, cmd, opts)
  else
    M.run(fmt, action, cmd, opts)
  end
end

--- Configure data.nvim and wire up its user commands.
---@param opts? DataConfig
---@return nil
function M.setup(opts)
  config.setup(opts)
  require("data.bindings").setup()
end

return M
