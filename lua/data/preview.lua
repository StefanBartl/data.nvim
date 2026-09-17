---@module 'data.preview'
--- Before/after preview for a `filter` run that is about to replace its scope
--- in place: renders the two sides as a unified diff through
--- [diff.nvim](https://github.com/StefanBartl/diff.nvim) and asks whether to
--- apply it.
---
--- Offered on `filter` only, and that is deliberate twice over. `filter` is
--- the one action that *loses* data -- `pretty`/`compact`/`sort`/`to` all
--- render the same document a different way, and the worst a bad one costs is
--- an undo. And `filter` is already built to survive an arbitrarily long async
--- gap between "scope resolved" and "scope written" (see `data.filter` and the
--- extmark in `data.init`'s `M.filter`), which is exactly what a confirmation
--- prompt adds a second one of. Putting a preview on the synchronous actions
--- would mean giving each of them that machinery for a case none of them
--- needs.
---
--- diff.nvim is a hard requirement for this one flag, the same stance
--- `data.filter` takes towards pickers.nvim: a "preview" that silently skips
--- the preview is worse than one that says it cannot run, because the whole
--- point of the flag is to not overwrite anything unseen. Asked for and
--- missing means nothing is written.

local M = {}

---@internal
--- `diff.nvim` view values `preview.view` accepts. All five, but only since
--- diff.nvim `ff2f424`: before that, its side-by-side renderer materialized
--- only the *target* and paired it with whatever buffer the origin window
--- happened to be showing, so `vsplit`/`split`/`tab` would have put the whole
--- data buffer on the left instead of the resolved scope -- for a
--- fenced-block or Visual scope, the wrong thing entirely, while looking
--- exactly like it had worked. An older diff.nvim therefore renders those
--- three views wrongly; `:checkhealth data` cannot detect the difference, so
--- `inline` stays the default.
---@type table<string, true>
local VIEWS = { inline = true, float = true, vsplit = true, split = true, tab = true }

--- Whether a preview can be rendered at all.
---@return boolean
function M.available()
  return (pcall(require, "diff"))
end

---@internal
--- An unlisted scratch buffer holding `lines`, for diff.nvim to resolve a
--- `source=`/`target=` buffer specifier against.
---
--- The name is load-bearing, not hygiene: diff.nvim labels a buffer specifier
--- by the buffer's name, and that label is what ends up on the `---`/`+++`
--- lines of the rendered diff -- directly above a prompt asking whether to
--- destroy one of the two sides. So the name carries the side AND its line
--- count, and the header reads itself.
---@param lines string[]
---@param label string # the action, e.g. "json filter"
---@param side string  # "before" | "after"
---@return integer bufnr
local function holder(lines, label, side)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  pcall(
    vim.api.nvim_buf_set_name,
    bufnr,
    ("data://%s (%s, %d line%s)"):format(label, side, #lines, #lines == 1 and "" or "s")
  )
  return bufnr
end

---@internal
--- The windows diff.nvim opened for the preview, if it opened any.
---
--- `diff.run` returns nothing and there is no handle to ask, so this diffs
--- the window list around the call. That is deliberately the *only* thing
--- this module infers about diff.nvim's output: an earlier version sniffed
--- the focused buffer's `'filetype'` for "diff", which only ever held for
--- the unified-diff views -- the side-by-side ones leave two ordinary
--- buffers in diffmode behind. Counting new windows covers all five views,
--- needs to know nothing about what diff.nvim puts in them, and gives the
--- teardown exactly the handles it has to close again.
---
--- Zero new windows means diff.nvim rendered nothing (an internal error, or
--- two sides it considered identical), which the caller must treat as "no
--- preview" rather than as consent.
---@param before table<integer, true> # window ids that existed going in
---@return integer[]
local function opened_windows(before)
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not before[win] then
      out[#out + 1] = win
    end
  end
  return out
end

--- Show `before` vs `after` and ask whether to apply.
---
--- `on_decision(true)` means apply, `on_decision(false)` means the user said
--- no (or cancelled the prompt), and `on_decision(nil, problem)` means the
--- preview could not be shown at all -- which callers must treat as "do not
--- write", not as "write anyway": see this module's doc comment.
---@param opts Data.PreviewOpts
---@param on_decision fun(apply: boolean|nil, problem: Data.Problem|nil)
---@return nil
function M.confirm(opts, on_decision)
  local ok, diff = pcall(require, "diff")
  if not ok then
    on_decision(nil, {
      msg = "preview requires diff.nvim (not installed) -- nothing was written",
      level = "error",
    })
    return
  end

  local view = require("data.config").get("preview.view")
  if not VIEWS[view] then
    view = "inline"
  end

  local before_buf = holder(opts.before, opts.label, "before")
  local after_buf = holder(opts.after, opts.label, "after")

  local function drop_holders()
    for _, b in ipairs({ before_buf, after_buf }) do
      if vim.api.nvim_buf_is_valid(b) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end

  local wins_before = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    wins_before[win] = true
  end

  -- Everything below reaches into a third-party plugin; a failure there has
  -- to come back as a refusal to write, not as an error raised past an async
  -- callback of ours.
  local ran = pcall(
    diff.run,
    ("source=%d target=%d view=%s output=buffer"):format(before_buf, after_buf, view)
  )
  local preview_wins = ran and opened_windows(wins_before) or {}

  -- Both sides are read during `diff.run` itself (a buffer specifier resolves
  -- synchronously), so the holders have done their job by now whatever the
  -- outcome. diff.nvim copies whatever it needs into scratch buffers of its
  -- own, so deleting these does not empty the preview.
  drop_holders()

  if #preview_wins == 0 then
    on_decision(nil, {
      msg = "diff.nvim did not render a preview -- nothing was written",
      level = "error",
    })
    return
  end

  local function close_preview()
    for _, win in ipairs(preview_wins) do
      if vim.api.nvim_win_is_valid(win) then
        local bufnr = vim.api.nvim_win_get_buf(win)
        -- The last window of the last tabpage cannot be closed; pcall rather
        -- than a special case, since the preview is torn down either way and
        -- a stuck window is not worth failing the decision over.
        pcall(vim.api.nvim_win_close, win, true)
        if vim.api.nvim_buf_is_valid(bufnr) then
          pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
      end
    end
  end

  vim.ui.select({ "Apply", "Discard" }, { prompt = opts.prompt }, function(choice)
    close_preview()
    on_decision(choice == "Apply", nil)
  end)
end

return M
