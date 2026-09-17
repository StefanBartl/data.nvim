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
--- `diff.nvim` view values this can use. `vsplit`/`split`/`tab` are NOT
--- offered, and the reason is a real constraint rather than a preference:
--- diff.nvim's side-by-side renderer materializes only the *target* into a
--- scratch buffer and pairs it with whatever buffer the origin window is
--- showing (`diff.core.render.side_by_side`), so the left-hand side would be
--- the whole data buffer rather than the resolved scope -- for a fenced-block
--- or Visual scope, the wrong thing entirely. `inline`/`float` render a
--- unified diff from both resolved sides, which is what this needs.
---@type table<string, true>
local VIEWS = { inline = true, float = true }

--- Whether a preview can be rendered at all.
---@return boolean
function M.available()
  return (pcall(require, "diff"))
end

---@internal
--- An unlisted scratch buffer holding `lines`, for diff.nvim to resolve a
--- `source=`/`target=` buffer specifier against. Named only for hygiene while
--- it briefly exists; diff.nvim labels a buffer specifier by its number, not
--- its name.
---@param lines string[]
---@param name string
---@return integer bufnr
local function holder(lines, name)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  pcall(vim.api.nvim_buf_set_name, bufnr, name)
  return bufnr
end

---@internal
--- Replace the `--- <label>` / `+++ <label>` pair diff.nvim writes at the top
--- of a unified-diff buffer with something a person can act on.
---
--- Cosmetic only, and guarded so it can never damage the preview: diff.nvim
--- labels a buffer specifier by its buffer *number*, so the header reads
--- `--- 7` / `+++ 8` -- two numbers that say nothing about which side is
--- which, in front of a prompt asking whether to destroy one of them. There
--- is no label option in diff.nvim's `key=value` grammar to pass instead. If
--- the first two lines don't look like that header (a future diff.nvim
--- changes its shape), they are left exactly as they are and the preview is
--- still perfectly usable, just labelled by number.
---@param bufnr integer
---@param before_label string
---@param after_label string
---@return nil
local function relabel(bufnr, before_label, after_label)
  local head = vim.api.nvim_buf_get_lines(bufnr, 0, 2, false)
  if #head < 2 or not head[1]:match("^%-%-%- ") or not head[2]:match("^%+%+%+ ") then
    return
  end
  local modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  pcall(vim.api.nvim_buf_set_lines, bufnr, 0, 2, false, {
    "--- " .. before_label,
    "+++ " .. after_label,
  })
  vim.bo[bufnr].modifiable = modifiable
end

---@internal
--- The buffer diff.nvim just rendered the preview into, if it did.
---
--- `diff.run` returns nothing and there is no handle to ask, so this reads
--- the window it leaves focused -- `inline` and `float` both end by entering
--- the new diff buffer. Every condition below has to hold for that to be what
--- we're looking at, so a diff.nvim that rendered nothing (an internal error,
--- or a version that stops focusing the result) is detected as "no preview"
--- rather than mistaken for one.
---@param exclude table<integer, true> # buffers that were ours going in
---@return integer|nil
local function rendered_buffer(exclude)
  local bufnr = vim.api.nvim_get_current_buf()
  if exclude[bufnr] or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  if vim.bo[bufnr].filetype ~= "diff" then
    return nil
  end
  return bufnr
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

  local before_buf = holder(opts.before, ("data://%s (before)"):format(opts.label))
  local after_buf = holder(opts.after, ("data://%s (after)"):format(opts.label))

  local function drop_holders()
    for _, b in ipairs({ before_buf, after_buf }) do
      if vim.api.nvim_buf_is_valid(b) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end

  -- Everything below reaches into a third-party plugin; a failure there has
  -- to come back as a refusal to write, not as an error raised past an async
  -- callback of ours.
  local ran = pcall(
    diff.run,
    ("source=%d target=%d view=%s output=buffer"):format(before_buf, after_buf, view)
  )
  local preview_buf = ran and rendered_buffer({ [before_buf] = true, [after_buf] = true }) or nil

  -- Both sides are read during `diff.run` itself (a buffer specifier resolves
  -- synchronously), so the holders have done their job by now whatever the
  -- outcome.
  drop_holders()

  if not preview_buf then
    on_decision(nil, {
      msg = "diff.nvim did not render a preview -- nothing was written",
      level = "error",
    })
    return
  end

  relabel(preview_buf, opts.before_label, opts.after_label)
  local preview_win = vim.api.nvim_get_current_win()

  local function close_preview()
    if vim.api.nvim_win_is_valid(preview_win) then
      pcall(vim.api.nvim_win_close, preview_win, true)
    end
    if vim.api.nvim_buf_is_valid(preview_buf) then
      pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
    end
  end

  vim.ui.select({ "Apply", "Discard" }, { prompt = opts.prompt }, function(choice)
    close_preview()
    on_decision(choice == "Apply", nil)
  end)
end

return M
