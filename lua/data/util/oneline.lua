---@module 'data.util.oneline'
--- Make a rendered leaf value safe to be one line of a `lines` result.
---
--- `lines`/`keys` promise exactly one `path: value` per leaf. A decoded value
--- can hold anything a string can hold, including newlines -- and in this
--- plugin's own headline use case it usually does: the `message`, `error` or
--- `stack` field of a support log is multi-line far more often than not. That
--- breaks the promise three different ways depending on where the result
--- goes, and every one of them looked like something other than what it was:
---
---   * in place / `--split`: `nvim_buf_set_lines` rejects an item containing
---     a newline, so the action failed with an internal-looking error naming
---     a data.nvim source file and line;
---   * `--out-reg`: `setreg` accepts it happily and the embedded newline
---     silently becomes a line break, so a two-leaf document arrived as three
---     lines with no indication anything had happened.
---
--- Control characters are therefore escaped here, at the point where a value
--- becomes display text, rather than being papered over at each of the three
--- write sites.
---
--- **Backslashes are deliberately NOT escaped.** That makes a literal `\n` in
--- the source value and a real newline render identically, which is a real
--- (if small) ambiguity -- accepted on purpose, because the alternative
--- renders every Windows path as `C:\\Users\\...`. `lines` is documented as a
--- human-readable summary, not as valid JSON to be parsed back (see
--- `data.format.json`'s own `display`), and for a summary readability wins.

local M = {}

---@internal
--- The escapes worth spelling out; everything else in C0 falls through to the
--- `\xNN` form below.
---@type table<string, string>
local NAMED = {
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

--- Escape control characters in `s` so it cannot span lines.
---@param s string
---@return string
function M.escape(s)
  if not s:find("%c") then
    -- The overwhelmingly common case: no scan-and-rebuild for a value that
    -- was already one line.
    return s
  end
  return (s:gsub("%c", function(c)
    return NAMED[c] or ("\\x%02X"):format(c:byte())
  end))
end

return M
