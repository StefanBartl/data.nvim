---@module 'data.filter'
--- Interactive path/value filtering behind `:JSON filter`/`:YAML filter`/
--- `:XML filter`: build a `pickers.refine` clause stack against the same
--- flattened `{path, value}` entries `lines`/`keys` already render (see
--- `lib.lua.tables.path_flatten`), then hand the surviving entries' `lines`-
--- style text back to the caller.
---
--- `pickers.nvim` is a hard requirement for this one action -- there is no
--- "everything passes" degraded mode that would still deserve the name
--- "filter". Every other data.nvim command works with pickers.nvim absent;
--- this is the one exception, and it fails through `on_done`'s `err` with
--- one clear message instead of silently doing nothing.

local M = {}

--- Call `fn(a, b, c)` guarded by `pcall`, collapsing an unexpected runtime
--- error into the same `nil, err` shape `path_flatten`/`formatter.render`
--- already use for an ordinary failure. Shared with `data.init` -- see
--- `data.util.safe_call`'s own doc comment for why this isn't
--- `lib.nvim.safe_api.safe_call` instead.
local safe_call = require("data.util.safe_call")

---@internal
--- One `pickers.refine` item per flattened leaf: `path` for path-only
--- clauses, `line` for the pre-rendered "path: value" text (exactly what
--- `<Verb> lines` would have shown for the same leaf), so a clause can also
--- match a leaf's own display text.
---@param items {path: string, value: any}[]
---@param rendered_lines string[] # same order/length as `items` -- both come from the same `path_flatten` traversal order
---@return {path: string, line: string}[]
local function to_refine_items(items, rendered_lines)
  local out = {}
  for i, item in ipairs(items) do
    out[i] = { path = item.path, line = rendered_lines[i] }
  end
  return out
end

--- Interactively build a filter over `formatter`'s flattened rendering of
--- `value`, then call `on_done(out_lines, err)` once the user stops editing
--- the clause stack.
---
--- `pickers.refine.Handle:prompt`'s own contract is what shapes the loop
--- below: `on_done` fires on every round (commit or cancel), `on_change`
--- only when the stack actually changed. Cancelling a round is therefore
--- ambiguous by itself -- it means "stop adding clauses, apply what I have"
--- once at least one clause exists, and "abort, I want no filter at all"
--- when the stack is still empty -- so the loop re-opens the prompt after
--- every change and only treats a change-less round as the stop signal.
---
--- `on_done(nil, nil)` -- cancelled before any clause was ever added:
--- nothing to do, not an error.
--- `on_done(nil, err)` -- pickers.nvim missing, or `path_flatten`/`render`
--- failed on `value` itself.
--- `on_done(lines, nil)` -- the clause stack was applied; `lines` may be an
--- empty table when nothing matched (the caller decides how to report
--- that, this module only says what happened).
---@param formatter Data.Formatter
---@param value any
---@param opts Data.RenderOpts
---@param on_done fun(out_lines: string[]|nil, err: string|nil)
---@return nil
function M.run(formatter, value, opts, on_done)
  local ok, refine = pcall(require, "pickers.refine")
  if not ok then
    on_done(nil, "requires pickers.nvim (pickers.refine) -- not installed")
    return
  end

  -- Flattened twice over (once here for the filterable items, once inside
  -- `render("lines", ...)` for their display text) rather than threading a
  -- shared intermediate through both -- data.nvim's format modules are
  -- deliberately thin adapters with no shared-state contract between
  -- `decode`/`render`, and a large-enough document to make one extra
  -- `path_flatten` pass matter is already well past what an interactive,
  -- human-driven filter prompt is comfortable to use on.
  local tables = require("lib.lua.tables")
  local items, ferr = safe_call(tables.path_flatten, value, { sep = opts.sep })
  if not items then
    on_done(nil, ferr)
    return
  end

  local rendered, rerr = safe_call(formatter.render, value, "lines", opts)
  if not rendered then
    on_done(nil, rerr)
    return
  end

  local refine_items = to_refine_items(items, rendered)

  -- Everything past this point calls into pickers.refine's own API
  -- (`Handle:prompt`/`:is_active`/`:apply`), a third-party plugin this
  -- module doesn't control -- a bug or version mismatch there must still
  -- reach the caller through `on_done`'s `err`, not raise past an async
  -- UI callback.
  local ok_new, h_or_err = pcall(refine.new, {
    fields = {
      path = function(it)
        return it.path
      end,
      line = function(it)
        return it.line
      end,
    },
  })
  if not ok_new then
    on_done(nil, tostring(h_or_err))
    return
  end
  local h = h_or_err

  local function loop()
    local changed = false
    local ok_prompt, prompt_err = pcall(h.prompt, h, function()
      changed = true
    end, function()
      if changed then
        loop()
        return
      end
      local ok_apply, result = pcall(function()
        if not h:is_active() then
          return nil
        end
        local kept = h:apply(refine_items)
        local out = {}
        for i, it in ipairs(kept) do
          out[i] = it.line
        end
        return out
      end)
      if not ok_apply then
        on_done(nil, tostring(result))
        return
      end
      on_done(result, nil)
    end)
    if not ok_prompt then
      on_done(nil, tostring(prompt_err))
    end
  end

  loop()
end

return M
