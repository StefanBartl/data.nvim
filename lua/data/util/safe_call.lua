---@module 'data.util.safe_call'
--- Shared `pcall` wrapper used by both `data.init` and `data.filter`.
---
--- Deliberately not `lib.nvim.safe_api.safe_call`: that one normalizes to
--- `(ok, result, err)` and only keeps `fn`'s *first* return value in
--- `result`, discarding a second one -- every caller here wraps a
--- `decode`/`render`-shaped function that returns its own `(value, err)` on
--- an ordinary (non-throwing) failure, and that second value must survive
--- the wrap. This keeps the plain `(result_or_nil, err)` shape both call
--- sites already expect.
---@param fn function
---@param a any
---@param b any
---@param c any
---@return any result_or_nil
---@return string|nil err
return function(fn, a, b, c)
  local ok, r1, r2 = pcall(fn, a, b, c)
  if not ok then
    return nil, tostring(r1)
  end
  return r1, r2
end
