---@module 'data'
--- Public facade for data.nvim: `setup()` plus the range-aware `run()`/
--- `convert()` actions every `:JSON`/`:YAML`/`:XML` route calls into.
---
--- Every action takes the same two decisions before it does any work:
--- *where does the input come from* (`data.scope.source`: the buffer scope,
--- or a register via `--reg`) and *where does the result go*
--- (`data.scope.sink`: `--inplace`, `--split`, `--out-reg`, defaulting to
--- whichever matches the source). Decode/render in between is unchanged and
--- knows about neither.

local config = require("data.config")
local formats = require("data.format")
local source_scope = require("data.scope.source")
local sink_scope = require("data.scope.sink")
local raw_notify = require("lib.nvim.notify").create("[data]")

local M = {}

---@internal
--- Namespace for the extmark `M.filter` anchors its scope to across the
--- interactive `pickers.refine` prompt -- see that function's own comment
--- for why a plain `s0`/`e0` line pair isn't enough there.
local FILTER_NS = vim.api.nvim_create_namespace("data.nvim/filter")

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
  info = function(msg)
    vim.schedule(function()
      raw_notify.info(msg)
    end)
  end,
}

---@internal
--- Surface a `Data.Problem` from `data.scope.source`/`data.scope.sink`,
--- which report failures rather than notifying themselves (see those
--- modules' doc comments). `prefix` names the action when the message alone
--- wouldn't ("JSON filter: ...").
---@param problem Data.Problem|nil
---@param prefix? string
---@return nil
local function report(problem, prefix)
  if not problem then
    return
  end
  local msg = (prefix or "") .. problem.msg
  if problem.level == "warn" then
    notify.warn(msg)
  else
    notify.error(msg)
  end
end

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
--- Resolve `opts.indent` the same way `opt_or_default` does, but also warn
--- distinctly when a value WAS given and is invalid (not a positive
--- number), rather than silently falling back to `default` the same way an
--- omitted indent already does -- `format/{json,xml,yaml}.lua`'s own
--- `render` clamps an invalid indent to 2 too, but has no notify channel of
--- its own to tell "you typed something wrong" apart from "you typed
--- nothing", so that distinction has to happen here, before `render` ever
--- sees it.
---@param v any
---@param default integer
---@return integer
local function resolve_indent(v, default)
  if v == nil or v == "" then
    return default
  end
  if type(v) ~= "number" or v < 1 then
    notify.warn(("invalid indent %s -- using %d instead"):format(vim.inspect(v), default))
    return default
  end
  return v
end

--- Call `fn(a, b, c)` guarded by `pcall`, collapsing an unexpected runtime
--- error into the same `nil, err` shape `formatter.decode`/`formatter.render`
--- already use. Neither `lib.lua.xml`/`lib.lua.yaml`'s decoders/encoders nor
--- `lib.nvim.json`'s null-normalization throw under normal use, but each has
--- (or had) a recursion-depth guard as its only defense against a
--- pathologically deep document -- this is the belt to that suspenders, so a
--- gap in one of those guards surfaces here as a clean notification instead
--- of a raw Vim error escaping past the caller's `vim.cmd()`. Shared with
--- `data.filter` (see `data.util.safe_call`'s own doc comment for why this
--- isn't `lib.nvim.safe_api.safe_call` instead).
local safe_call = require("data.util.safe_call")

---@internal
--- Shared prelude for `run`/`convert`/`filter`: resolve where the input
--- comes from and where the result goes, in that order (the target's
--- default depends on the source). Already notifies on failure, so callers
--- only need to check for a nil source.
---
--- Note what is NOT checked here any more: `modifiable`. It used to gate
--- every invocation, which was wrong the moment a result could go somewhere
--- other than the buffer -- a read-only buffer is a perfectly good source
--- for `--split`/`--out-reg`. The check moved into the in-place write in
--- `data.scope.sink`, which is the only place it actually applies.
---@param bufnr integer
---@param cmd Lib.UserCommand.Args
---@param fmt string|nil
---@param flags Data.IOFlags|nil
---@return Data.Source|nil source
---@return Data.Sink|nil sink
local function resolve_io(bufnr, cmd, fmt, flags)
  local source, sproblem = source_scope.resolve(bufnr, cmd, fmt, flags)
  if not source then
    report(sproblem)
    return nil, nil
  end
  if source.note then
    notify.warn(source.note)
  end

  local sink, kproblem = sink_scope.resolve(source, flags or {})
  if not sink then
    report(kproblem)
    return nil, nil
  end

  return source, sink
end

---@internal
--- Render modes whose output is flattened `path: value` text rather than a
--- document in the source format -- a `--split` result buffer must not
--- claim `'filetype'` json/yaml/xml for those.
---@type table<string, true>
local TEXT_MODES = { lines = true, keys = true, filter = true }

---@internal
--- Hand `lines` to the resolved target and report whatever came back.
---@param sink Data.Sink
---@param source Data.Source
---@param lines string[]
---@param fmt string
---@param mode string
---@param prefix? string # passed through to `report`
---@return nil
local function deliver(sink, source, lines, fmt, mode, prefix)
  local ok, problem, note = sink_scope.write(sink, source, lines, {
    filetype = (not TEXT_MODES[mode]) and fmt or nil,
    label = ("%s %s%s"):format(fmt, mode, source.reg and (" (" .. source.reg .. ")") or ""),
  })
  if not ok then
    report(problem, prefix)
    return
  end
  if note then
    -- A register target writes nothing visible; say what happened, or the
    -- command looks like it silently did nothing at all.
    notify.info((prefix or "") .. note)
  end
end

---@internal
--- Whether this invocation should preview before writing. `--preview` and
--- `--no-preview` win over the configured default, in that order of
--- explicitness; giving both is a contradiction rather than a ranking.
---@param flags Data.IOFlags
---@return boolean|nil wanted
---@return Data.Problem|nil problem
local function preview_wanted(flags)
  if flags.preview and flags.no_preview then
    return nil, { msg = "--preview / --no-preview are mutually exclusive", level = "error" }
  end
  if flags.no_preview then
    return false, nil
  end
  if flags.preview then
    return true, nil
  end
  return config.get("preview.filter") == true, nil
end

---@internal
--- `:JSON ndjson`: treat each non-blank line of the input as its own JSON
--- object (rather than the whole input as one document) and pretty-print
--- it. A line that fails to decode is left completely unchanged -- one bad
--- line in a log dump shouldn't block reformatting the rest -- and the
--- total skipped is reported once as a single warning afterwards.
---@param formatter Data.Formatter
---@param fmt string
---@param src string[]
---@param opts Data.RenderOpts
---@return string[] out
local function run_ndjson(formatter, fmt, src, opts)
  -- Hoisted out of the loop below -- this is the one loop in the plugin
  -- whose iteration count scales with user input (ndjson line count), so a
  -- per-line table-field lookup is worth avoiding here specifically.
  local decode, render = formatter.decode, formatter.render

  local out, skipped = {}, 0
  for _, line in ipairs(src) do
    if line:find("%S") then
      local value, derr = safe_call(decode, line)
      local rendered, rerr
      if not derr then
        rendered, rerr = safe_call(render, value, "pretty", opts)
      end
      if rendered and not rerr then
        table.move(rendered, 1, #rendered, #out + 1, out)
      else
        skipped = skipped + 1
        out[#out + 1] = line
      end
    else
      out[#out + 1] = line
    end
  end

  if skipped > 0 then
    -- A high skip ratio usually means the scope isn't actually ndjson at
    -- all (wrong command, wrong range) rather than "a few bad lines in an
    -- otherwise good log dump" -- the message should say so instead of
    -- reading identically at 1-of-500 and 450-of-500.
    local total = #src
    if total > 0 and (skipped / total) >= 0.5 then
      notify.warn(
        ("%s ndjson: %d/%d line(s) (%d%%) could not be decoded -- this scope may not actually be ndjson"):format(
          fmt:upper(),
          skipped,
          total,
          math.floor((skipped / total) * 100)
        )
      )
    else
      notify.warn(
        ("%s ndjson: %d line(s) could not be decoded and were left unchanged"):format(
          fmt:upper(),
          skipped
        )
      )
    end
  end

  return out
end

---@internal
--- Per-invocation args/flags win when given (":JSON pretty 4"); otherwise
--- fall back to the resolved config.<fmt>.indent/sep -- before these were
--- read here, the config values were merged/typed but never actually read
--- anywhere, so a user-set json.indent silently had no effect.
---@param fmt string
---@param opts Data.RenderOpts|nil
---@return Data.RenderOpts
local function resolve_render_opts(fmt, opts)
  opts = opts or {}
  local defaults = config.get(fmt) or {}
  return {
    indent = resolve_indent(opts.indent, defaults.indent),
    sep = opt_or_default(opts.sep, defaults.sep),
  }
end

--- Format the resolved input -- the buffer scope (range, fenced block, or
--- whole buffer) or a register (`--reg`) -- and deliver the result to the
--- resolved target (in place, a scratch split, or a register).
---@param fmt string              # "json"|"yaml"|"xml"
---@param mode Data.RenderMode
---@param cmd Lib.UserCommand.Args # the raw nvim user-command args (range info)
---@param opts? Data.RenderOpts    # per-invocation override; falls back to config.<fmt>.indent/sep when a field is nil
---@param flags? Data.IOFlags      # --reg / --inplace / --split / --out-reg
---@return nil
function M.run(fmt, mode, cmd, opts, flags)
  local formatter = formats.get(fmt)
  if not formatter then
    notify.error(("unknown format '%s'"):format(tostring(fmt)))
    return
  end

  opts = resolve_render_opts(fmt, opts)

  local bufnr = vim.api.nvim_get_current_buf()
  local source, sink = resolve_io(bufnr, cmd, fmt, flags)
  if not source then
    return
  end
  ---@cast sink Data.Sink

  if mode == "ndjson" then
    deliver(sink, source, run_ndjson(formatter, fmt, source.lines, opts), fmt, mode)
    return
  end

  local value, derr = safe_call(formatter.decode, table.concat(source.lines, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(fmt:upper(), derr))
    return
  end

  local out, rerr = safe_call(formatter.render, value, mode, opts)
  if not out then
    notify.error(("%s render failed: %s"):format(fmt:upper(), rerr))
    return
  end
  deliver(sink, source, out, fmt, mode)
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
---@param flags? Data.IOFlags
---@return nil
function M.convert(src_fmt, dst_fmt, cmd, opts, flags)
  local src_formatter = formats.get(src_fmt)
  local dst_formatter = formats.get(dst_fmt)
  if not (src_formatter and dst_formatter) then
    notify.error(("unknown format '%s'"):format(tostring(not src_formatter and src_fmt or dst_fmt)))
    return
  end

  opts = resolve_render_opts(dst_fmt, opts)

  local bufnr = vim.api.nvim_get_current_buf()
  local source, sink = resolve_io(bufnr, cmd, src_fmt, flags)
  if not source then
    return
  end
  ---@cast sink Data.Sink

  local value, derr = safe_call(src_formatter.decode, table.concat(source.lines, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(src_fmt:upper(), derr))
    return
  end

  local out, rerr = safe_call(dst_formatter.render, value, "pretty", opts)
  if not out then
    notify.error(("%s -> %s conversion failed: %s"):format(src_fmt:upper(), dst_fmt:upper(), rerr))
    return
  end

  -- The result is a `dst_fmt` document, so that is what a `--split` result
  -- buffer's 'filetype' has to say -- not the format it was read from.
  deliver(sink, source, out, dst_fmt, "pretty")
end

--- Interactively filter the resolved input down to the flattened path/value
--- entries matching a user-built `pickers.refine` clause stack (`:JSON
--- filter`/`:YAML filter`/`:XML filter`), then deliver the survivors'
--- `lines`-style text to the resolved target. See `data.filter` for the
--- actual clause loop; this only resolves source/target and decode, same
--- shape as `run`/`convert`, except the write happens later, from
--- `data.filter`'s `on_done` callback, once the interactive part is over.
---
--- That gap is exactly why an in-place target here cannot reuse
--- `run`/`convert`'s plain `s0`/`e0` line pair unchanged: the clause-building
--- prompt can take an arbitrary amount of time (however long a person takes
--- to pick fields and type terms), and nothing stops the buffer from being
--- edited elsewhere, made unmodifiable, or closed outright in that window --
--- a plain line pair captured before the prompt opened would then either
--- write over the wrong lines or throw a raw "invalid buffer" error out of
--- an async callback. An extmark tracks the scope's actual position across
--- whatever happens meanwhile (shrinking/growing with edits inside it the
--- same way any other extmark does), and buffer validity/`modifiable` are
--- checked again right before the write (in `data.scope.sink`), not just
--- once up front. A `--split`/`--out-reg` target needs none of that: it
--- writes somewhere that did not exist yet when the prompt opened.
---
--- `--preview` (or `preview.filter = true`) adds a second such gap: the
--- result is shown as a diff.nvim before/after diff and only written once
--- the user says so -- see `data.preview`. The extmark therefore stays alive
--- until after that decision, and the live span is re-read from it on both
--- sides of the preview.
---@param fmt string              # "json"|"yaml"|"xml"
---@param cmd Lib.UserCommand.Args
---@param opts? Data.RenderOpts
---@param flags? Data.IOFlags
---@return nil
function M.filter(fmt, cmd, opts, flags)
  local formatter = formats.get(fmt)
  if not formatter then
    notify.error(("unknown format '%s'"):format(tostring(fmt)))
    return
  end

  opts = resolve_render_opts(fmt, opts)

  local bufnr = vim.api.nvim_get_current_buf()
  local source, sink = resolve_io(bufnr, cmd, fmt, flags)
  if not source then
    return
  end
  ---@cast sink Data.Sink

  local value, derr = safe_call(formatter.decode, table.concat(source.lines, "\n"))
  if derr then
    notify.error(("%s decode failed: %s"):format(fmt:upper(), derr))
    return
  end

  local prefix = ("%s filter: "):format(fmt:upper())

  local preview, pproblem = preview_wanted(flags or {})
  if preview == nil then
    report(pproblem, prefix)
    return
  end
  if preview and sink.kind ~= "inplace" then
    -- Nothing to preview against: `--split`/`--out-reg` leave the scope
    -- exactly where it is, so the "before" is still on screen afterwards.
    notify.warn(prefix .. "--preview only applies to an in-place result -- ignored")
    preview = false
  end

  local mark_id, del_mark
  if sink.kind == "inplace" then
    mark_id = vim.api.nvim_buf_set_extmark(bufnr, FILTER_NS, source.s0, 0, {
      end_row = (source.e0 or 0) + 1,
      end_col = 0,
    })
    del_mark = function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_del_extmark, bufnr, FILTER_NS, mark_id)
      end
    end
  else
    del_mark = function() end
  end

  require("data.filter").run(formatter, value, opts, function(out, ferr)
    if ferr then
      notify.error(prefix .. ferr)
      del_mark()
      return
    end
    if not out then
      -- Cancelled before any clause was added -- nothing to do, silently.
      del_mark()
      return
    end
    if #out == 0 then
      notify.warn(prefix .. "no entries matched -- nothing written")
      del_mark()
      return
    end

    -- Re-read the live scope BEFORE anything else: the extmark has been
    -- tracking it across the whole clause-building prompt, and both the write
    -- span and the preview's "before" side have to come from where the scope
    -- actually is now, not from where it was when the command was typed.
    local before = source.lines
    if mark_id then
      if not vim.api.nvim_buf_is_valid(bufnr) then
        notify.error(
          prefix .. "buffer was closed before the filter finished -- discarding the result"
        )
        return
      end
      local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, FILTER_NS, mark_id, { details = true })
      source.s0 = mark[1]
      source.e0 = (mark[3] and mark[3].end_row) and (mark[3].end_row - 1) or source.e0
      before = vim.api.nvim_buf_get_lines(bufnr, source.s0, (source.e0 or 0) + 1, false)
    end

    if not preview or vim.deep_equal(before, out) then
      -- Identical sides have nothing to show and nothing to decide: diff.nvim
      -- would report "No differences found" and open no window, leaving a
      -- prompt with no preview behind it.
      del_mark()
      deliver(sink, source, out, fmt, "filter", prefix)
      return
    end

    require("data.preview").confirm({
      before = before,
      after = out,
      label = ("%s filter"):format(fmt),
      prompt = ("%s filter: replace %d line(s) with %d?"):format(fmt:upper(), #before, #out),
    }, function(apply, problem)
      if problem then
        report(problem, prefix)
        del_mark()
        return
      end
      if not apply then
        notify.info(prefix .. "discarded -- scope left unchanged")
        del_mark()
        return
      end

      -- The prompt is another arbitrarily long gap, so the span is re-read
      -- from the extmark once more rather than trusting the one taken before
      -- the preview opened.
      if mark_id then
        if not vim.api.nvim_buf_is_valid(bufnr) then
          notify.error(prefix .. "buffer was closed during the preview -- discarding the result")
          return
        end
        local mark =
          vim.api.nvim_buf_get_extmark_by_id(bufnr, FILTER_NS, mark_id, { details = true })
        source.s0 = mark[1]
        source.e0 = (mark[3] and mark[3].end_row) and (mark[3].end_row - 1) or source.e0
      end
      del_mark()

      deliver(sink, source, out, fmt, "filter", prefix)
    end)
  end)
end

--- Auto-detect the format for a `:Data <action>` invocation (an enclosing
--- fenced code block's language when the cursor sits inside one and no
--- explicit range was given, the register's own first non-blank line under
--- `--reg`, otherwise the buffer's own filetype -- see `data.detect`) and
--- dispatch to `run`/`filter` accordingly. `:JSON`/`:YAML`/`:XML` never
--- need this: the verb itself already says the format.
---@param action string # "pretty"|"lines"|"keys"|"sort"|"filter" -- the format-agnostic subset every formatter supports the same way
---@param cmd Lib.UserCommand.Args
---@param opts? Data.RenderOpts
---@param flags? Data.IOFlags
---@return nil
function M.run_auto(action, cmd, opts, flags)
  local bufnr = vim.api.nvim_get_current_buf()
  -- A register named here is read twice: once for the format sniff, once
  -- for the source itself further down. Reading a register has no side
  -- effects and no cost worth threading a pre-resolved source through two
  -- public functions to avoid.
  local fmt, derr = require("data.detect").format(bufnr, cmd, flags)
  if not fmt then
    notify.error(derr)
    return
  end

  if action == "filter" then
    M.filter(fmt, cmd, opts, flags)
  else
    M.run(fmt, action, cmd, opts, flags)
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
