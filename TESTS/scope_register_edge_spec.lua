-- Test code: when something here comes back nil -- a require, a register
-- read, a name resolution -- this file must crash and name it. The nil guards
-- LuaLS asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/scope_register_edge_spec.lua — the edges of data.scope.register that
-- scope_register_spec.lua does not reach: the clipboard fallback (which needs
-- a Neovim without a provider, so it has to be simulated), every register Vim
-- itself refuses to write, and the exact asymmetry between the bare `--reg`
-- form and an explicitly named one.
--
-- The asymmetry is the load-bearing part. A bare `--reg` means "the configured
-- default", so substituting a working register for an unusable one is helpful.
-- `--reg=+` is the user naming a register themselves, and silently reading a
-- DIFFERENT one than the one they named would be worse than the error -- see
-- the module's own doc comment.

local register = require("data.scope.register")

--- Run `fn()` with `vim.fn.has("clipboard")` reporting 0, restoring the real
--- `has` afterwards regardless of how `fn()` ends. Simulated rather than
--- provoked: whether the machine running the suite has a clipboard provider is
--- not something a test may depend on.
---@generic T
---@param fn fun(): T
---@return T
local function without_clipboard(fn)
  local orig = vim.fn.has
  --- Test double: restored below.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.has = function(what)
    if what == "clipboard" then
      return 0
    end
    return orig(what)
  end
  local ok, result = pcall(fn)
  vim.fn.has = orig
  if not ok then
    error(result, 0)
  end
  return result
end

--- The other direction: force `vim.fn.has("clipboard")` to report 1. Some
--- CI Neovim builds report 0 for it even with no test double installed --
--- whether *this* machine's Neovim was built with +clipboard is just as
--- much not something a test may depend on as whether it has a provider,
--- and the "falls back to +" tests below are about the bare-flag/config
--- resolution, not about that build flag.
---@generic T
---@param fn fun(): T
---@return T
local function with_clipboard(fn)
  local orig = vim.fn.has
  --- Test double: restored below.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.has = function(what)
    if what == "clipboard" then
      return 1
    end
    return orig(what)
  end
  local ok, result = pcall(fn)
  vim.fn.has = orig
  if not ok then
    error(result, 0)
  end
  return result
end

describe("data.scope.register.name -- the bare-flag forms", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("treats an empty string like a bare flag, not like a register named ''", function()
    -- The composer parses `--reg=` (nothing after the `=`) to `""`, which is
    -- truthy in Lua and would otherwise fail the single-character check.
    -- Forced to report a clipboard build: this is about the bare-flag
    -- resolution landing on the configured default, not about the
    -- no-provider fallback the next describe block covers.
    with_clipboard(function()
      local name, err = register.name("")
      assert.is_nil(err)
      assert.equals("+", name, "the configured default")
    end)
  end)

  it("resolves false to no register, same as nil", function()
    local name, err, note = register.name(false)
    assert.is_nil(name)
    assert.is_nil(err)
    assert.is_nil(note)
  end)

  it("falls back to + when the configured default is an empty string", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "" } })
    with_clipboard(function()
      assert.equals("+", register.name(true))
    end)
  end)

  it("falls back to + when the configured default is not a string at all", function()
    -- The config validator warns about this but does not block it, so the
    -- wrong type still arrives here.
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = 5 } })
    with_clipboard(function()
      assert.equals("+", register.name(true))
    end)
  end)

  it("rejects a configured default that is not a single character", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "ab" } })
    local name, err = register.name(true)
    assert.is_nil(name)
    assert.matches("single character", err)
  end)
end)

describe("data.scope.register.name -- the clipboard fallback", function()
  before_each(function()
    package.loaded["data.config"] = nil
    require("data.config").setup()
  end)

  it("substitutes the unnamed register for a bare --reg, and SAYS it did", function()
    local got = without_clipboard(function()
      local n, e, nt = register.name(true)
      return { n, e, nt }
    end)
    assert.equals('"', got[1], "+ is permanently empty without a provider")
    assert.is_nil(got[2], "a missing provider is not the user's mistake")
    assert.matches("no clipboard provider", got[3], "a silent substitution would be worse")
    assert.matches("'\"'", got[3], "the note names what it used instead")
    assert.matches("'%+'", got[3], "and what it was configured to use")
  end)

  it("substitutes for * as well as for +", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "*" } })
    local got = without_clipboard(function()
      local n, _, nt = register.name(true)
      return { n, nt }
    end)
    assert.equals('"', got[1])
    assert.matches("no clipboard provider", got[2])
  end)

  it("leaves an explicitly named --reg=+ alone, provider or not", function()
    local got = without_clipboard(function()
      local n, e, nt = register.name("+")
      return { n, e, nt }
    end)
    assert.equals("+", got[1], "the user's own choice is honored")
    assert.is_nil(got[2])
    assert.is_nil(got[3], "and no note, because nothing was substituted")
  end)

  it("leaves an explicitly named --reg=* alone too", function()
    local got = without_clipboard(function()
      local n, _, nt = register.name("*")
      return { n, nt }
    end)
    assert.equals("*", got[1])
    assert.is_nil(got[2])
  end)

  it("does not substitute for a non-clipboard default, provider or not", function()
    package.loaded["data.config"] = nil
    require("data.config").setup({ register = { default = "z" } })
    local got = without_clipboard(function()
      local n, _, nt = register.name(true)
      return { n, nt }
    end)
    assert.equals("z", got[1], "only + and * depend on a provider")
    assert.is_nil(got[2])
  end)

  it("adds no note when a provider IS present", function()
    local _, _, note = register.name(true)
    if vim.fn.has("clipboard") == 1 then
      assert.is_nil(note)
    end
  end)
end)

describe("data.scope.register.write -- the clipboard round-trip", function()
  --- Whether "+" genuinely holds what it is set to on this machine. Probed
  --- rather than assumed, same reasoning as `without_clipboard` above: a
  --- CI runner with no provider is a real, common case, not an edge case.
  ---@return boolean
  local function real_clipboard_works()
    vim.fn.setreg("+", "")
    local set_ok = pcall(vim.fn.setreg, "+", "clipboard_probe")
    local works = false
    if set_ok then
      local get_ok, got = pcall(vim.fn.getreg, "+")
      works = get_ok and got == "clipboard_probe"
    end
    vim.fn.setreg("+", "")
    return works
  end

  it("reports failure instead of a false success when the write does not land", function()
    local works = real_clipboard_works()
    local ok, err = register.write("+", { "x", "y" })
    if works then
      assert.is_true(ok)
      assert.is_nil(err)
    else
      assert.is_false(ok)
      assert.matches("no clipboard provider", err)
    end
  end)

  it("leaves an ordinary register alone -- no round trip to verify", function()
    vim.fn.setreg("q", "", "c")
    local ok = register.write("q", { "x", "y" })
    assert.is_true(ok, "an ordinary register always holds whatever it was set to")
    assert.equals("x\ny\n", vim.fn.getreg("q"))
  end)
end)

describe("data.scope.register.writable -- every register Vim itself refuses", function()
  -- `:help registers` lists five read-only ones. Rejecting them up front with
  -- a name-the-register message beats letting `setreg` fail with a raw Vim
  -- error out of a usercmd handler.
  local names = {
    { reg = ":", what = "the last command line" },
    { reg = ".", what = "the last inserted text" },
    { reg = "%", what = "the current file name" },
    { reg = "#", what = "the alternate file name" },
    { reg = "=", what = "the expression register" },
  }

  for _, case in ipairs(names) do
    it(("refuses '%s' (%s) by name"):format(case.reg, case.what), function()
      local ok, err = register.writable(case.reg)
      assert.is_false(ok)
      assert.matches("read%-only", err)
      assert.matches(vim.pesc(case.reg), err, "the message names the register")
    end)
  end

  it("allows an ordinary named register", function()
    for _, reg in ipairs({ "a", "z", "0", "9", '"', "+", "*", "-", "/" }) do
      local ok, err = register.writable(reg)
      assert.is_true(ok, ("register '%s' should be writable"):format(reg))
      assert.is_nil(err)
    end
  end)
end)

describe("data.scope.register.read -- line splitting edges", function()
  it("drops exactly ONE trailing blank, not a run of them", function()
    -- A linewise register ends in a newline, which `vim.split` turns into one
    -- trailing empty element. A blank line the user actually yanked is
    -- content and has to survive.
    vim.fn.setreg("a", "one\n\n\n", "c")
    assert.same({ "one", "", "" }, register.read("a"))
  end)

  it("keeps a single-line register whole when it has no trailing newline", function()
    vim.fn.setreg("a", "one", "c")
    assert.same({ "one" }, register.read("a"))
  end)

  it("normalizes CRLF on every line, not just the first", function()
    vim.fn.setreg("a", "a\r\nb\r\nc\r\n", "c")
    assert.same({ "a", "b", "c" }, register.read("a"))
  end)

  it("strips a lone trailing CR with no LF after it", function()
    vim.fn.setreg("a", "a\r\nb\r", "c")
    assert.same({ "a", "b" }, register.read("a"))
  end)

  it("keeps a CR in the middle of a line, which is content", function()
    vim.fn.setreg("a", "a\rb", "c")
    assert.same({ "a\rb" }, register.read("a"))
  end)

  it("treats a register of only newlines as empty", function()
    vim.fn.setreg("a", "\n\n\n", "c")
    local lines, err = register.read("a")
    assert.is_nil(lines)
    assert.matches("empty", err)
  end)

  it("treats a register of only tabs and spaces as empty", function()
    vim.fn.setreg("a", "\t \t ", "c")
    local lines, err = register.read("a")
    assert.is_nil(lines)
    assert.matches("empty", err)
  end)

  it("reads a blockwise register as its lines", function()
    vim.fn.setreg("a", { "ab", "cd" }, "b")
    assert.same({ "ab", "cd" }, register.read("a"))
  end)
end)

describe("data.scope.register.write", function()
  it("round-trips through read for a multi-line value", function()
    vim.fn.setreg("q", "", "c")
    assert.is_true(register.write("q", { "x", "y", "z" }))
    assert.same({ "x", "y", "z" }, register.read("q"), "write then read is lossless")
  end)

  it("writes zero lines without erroring, and the register reads back as empty", function()
    -- Reachable: `data.filter` reports "no entries matched" before delivering,
    -- but a direct caller can hand an empty list straight through.
    vim.fn.setreg("q", "previous", "c")
    assert.is_true(register.write("q", {}))
    local lines, err = register.read("q")
    assert.is_nil(lines)
    assert.matches("empty", err)
  end)

  it("checks writability before touching the register at all", function()
    vim.fn.setreg("q", "keep me", "c")
    local ok = register.write("%", { "x" })
    assert.is_false(ok)
    assert.equals("keep me", vim.fn.getreg("q"), "nothing else was disturbed")
  end)
end)
