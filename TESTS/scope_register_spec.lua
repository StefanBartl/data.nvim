-- Test code: when something here comes back nil -- a require, a register
-- read, a name resolution -- this file must crash and name it. The nil
-- guards LuaLS asks for below would hide the very failure this spec exists
-- to catch.
---@diagnostic disable: need-check-nil
-- Every `disable-next-line: undefined-field` below suppresses assert.* --
-- luassert's augmentation of the global `assert` table (workspace.check-
-- ThirdParty is off, so no busted/luassert stub is injected) -- not a real gap.
-- TESTS/scope_register_spec.lua — data.scope.register

local register = require("data.scope.register")

describe("data.scope.register.name", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("resolves an absent flag to no register at all", function()
    local name, err = register.name(nil)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(name)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(err, "an absent --reg is not an error, just 'no register involved'")
  end)

  it("resolves an explicit name verbatim", function()
    local name = register.name("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("a", name)
  end)

  it("resolves a bare --reg to the configured default", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "z" } })
    local name = register.name(true)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("z", name)
  end)

  it("rejects a multi-character name", function()
    local name, err = register.name("clipboard")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(name)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(err:find("single character", 1, true))
  end)

  it("never rewrites an explicitly named clipboard register", function()
    -- The bare-flag clipboard fallback is deliberately asymmetric: an
    -- explicit --reg=+ is the user's own choice and must be honored even
    -- with no provider, so it fails later with "register is empty" rather
    -- than silently reading a different register (see the module's own doc
    -- comment).
    local name, _, note = register.name("+")
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("+", name)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(note)
  end)
end)

describe("data.scope.register.read", function()
  it("splits a linewise register into lines without a trailing blank", function()
    vim.fn.setreg("a", { "one", "two" }, "l")
    local lines, err = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(err)
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "one", "two" }, lines)
  end)

  it("normalizes CRLF, which is how clipboard text arrives on Windows", function()
    vim.fn.setreg("a", '{\r\n  "x": 1\r\n}', "c")
    local lines = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "{", '  "x": 1', "}" }, lines, "no stray CR survives the read")
  end)

  it("keeps a CR that is not terminating a line", function()
    -- Only the line-ending artifact goes; a CR inside a line is content.
    vim.fn.setreg("a", "a\rb\r\nc", "c")
    local lines = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ "a\rb", "c" }, lines)
  end)

  it("refuses the expression register, which would evaluate rather than read", function()
    -- getreg("=") runs the stored expression. Every other register read here
    -- is side-effect free, and `--reg` reads like one -- so this is a named
    -- refusal, not a silent evaluation.
    vim.g.data_nvim_expr_probe = 0
    vim.fn.setreg("=", 'luaeval("(function() vim.g.data_nvim_expr_probe = 1; return 42 end)()")')
    local lines, err = register.read("=")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(err:find("expression register", 1, true))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(0, vim.g.data_nvim_expr_probe, "refused before anything was evaluated")
  end)

  it("reads a charwise register as a single line", function()
    vim.fn.setreg("a", '{"a":1}', "c")
    local lines = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.same({ '{"a":1}' }, lines)
  end)

  it("reports an empty register instead of returning empty lines", function()
    vim.fn.setreg("a", "", "c")
    local lines, err = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(err:find("empty", 1, true))
  end)

  it("treats a whitespace-only register as empty", function()
    vim.fn.setreg("a", "   \n  ", "c")
    local lines = register.read("a")
    ---@diagnostic disable-next-line: undefined-field
    assert.is_nil(lines, "there is nothing to decode in whitespace")
  end)
end)

describe("data.scope.register.write", function()
  it("writes lines linewise", function()
    vim.fn.setreg("a", "", "c")
    local ok = register.write("a", { "x", "y" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(ok)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals("x\ny\n", vim.fn.getreg("a"))
  end)

  it("refuses a read-only register by name", function()
    local ok, err = register.write("%", { "x" })
    ---@diagnostic disable-next-line: undefined-field
    assert.is_false(ok)
    ---@diagnostic disable-next-line: undefined-field
    assert.is_truthy(err:find("read-only", 1, true))
  end)
end)
