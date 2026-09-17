-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- Every `disable-next-line: undefined-field` below suppresses assert.* --
-- luassert's augmentation of the global `assert` table (workspace.check-
-- ThirdParty is off, so no busted/luassert stub is injected) -- not a real gap.
-- TESTS/oneline_spec.lua — data.util.oneline and the `lines` contract

local oneline = require("data.util.oneline")

--- A literal backslash, built rather than written. Whether a `\` in this file
--- survives to mean a backslash depends on every layer that touched it, and
--- getting that wrong here produces a test that passes for the wrong reason:
--- an earlier draft put a REAL newline inside a JSON string literal, which is
--- invalid JSON that the decoder happened to tolerate.
local BS = string.char(92)

describe("data.util.oneline.escape", function()
  it("leaves an ordinary value untouched", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("hello world", oneline.escape("hello world"))
  end)

  it("escapes the control characters that would break a line", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(BS .. "n", oneline.escape("\n"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(BS .. "r", oneline.escape("\r"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(BS .. "t", oneline.escape("\t"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("x" .. BS .. "ny", oneline.escape("x\ny"))
  end)

  it("escapes any other C0 control character by byte", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("a" .. BS .. "x00b", oneline.escape("a" .. string.char(0) .. "b"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("a" .. BS .. "x1Bb", oneline.escape("a" .. string.char(27) .. "b"))
  end)

  it("leaves backslashes alone, so a Windows path stays readable", function()
    -- Documented trade-off: a literal `\n` in the source and a real newline
    -- render the same. `lines` is a human-readable summary, not JSON to parse
    -- back, so readability wins -- see the module's own doc comment.
    local path = "C:" .. BS .. "Users" .. BS .. "me"
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(path, oneline.escape(path))
  end)
end)

describe("the `lines` contract: one line per leaf", function()
  -- Regression: a decoded value holding a real newline -- the `message` or
  -- `stack` field of a support log, which is this plugin's headline input --
  -- produced a rendered item containing that newline. `nvim_buf_set_lines`
  -- rejects such an item, so the action failed with an internal-looking error
  -- naming a data.nvim source file and line; `--out-reg` accepted it silently
  -- instead, turning two leaves into three register lines.

  --- JSON source text whose `a` value carries an escaped newline.
  local JSON = '{"a":"x' .. BS .. 'ny","b":1}'

  it("json renders a multi-line value as a single line", function()
    local formatter = require("data.format").get("json")
    local rendered = formatter.render(formatter.decode(JSON), "lines", { sep = "." })
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: x" .. BS .. "ny", "b: 1" }, rendered)
  end)

  it("yaml renders a multi-line value as a single line", function()
    local formatter = require("data.format").get("yaml")
    local rendered = formatter.render({ a = "x\ny", b = 1 }, "lines", { sep = "." })
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: x" .. BS .. "ny", "b: 1" }, rendered)
  end)

  it("no rendered line ever contains a newline", function()
    local formatter = require("data.format").get("json")
    local rendered = formatter.render(formatter.decode(JSON), "lines", { sep = "." })
    for _, line in ipairs(rendered) do
      ---@diagnostic disable-next-line: undefined-field
      assert.is_nil(line:find("\n", 1, true))
    end
  end)

  it("writes such a document to the buffer instead of failing", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { JSON })
    vim.cmd("JSON lines")

    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a: x" .. BS .. "ny", "b: 1" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("keeps the register line count honest for --out-reg", function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { JSON })
    vim.fn.setreg("q", "", "c")
    vim.cmd("JSON lines --out-reg=q")

    local got = vim.split(vim.fn.getreg("q"), "\n", { plain = true })
    if got[#got] == "" then
      got[#got] = nil
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, #got, "two leaves must arrive as two register lines, not three")
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
