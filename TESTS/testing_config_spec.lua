---@diagnostic disable: need-check-nil
-- TESTS/testing_config_spec.lua -- the project's own testing.nvim configuration (.testing.lua)
-- must keep the gates that make a green run mean something.
--
-- The file once carried `assertions = "warn"`, a waiver for one case that asserted nothing on a
-- runner without a clipboard provider. That case was fixed, the waiver stayed, and from then on any
-- case that lost its assertions passed with a mere warning. This spec pins the strict settings so
-- relaxing one of them is a visible, deliberate edit to this file as well.

--- Load `.testing.lua` from the repository root (the table it returns).
---@return table
local function load_config()
  local src = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(src, ":p")))
  local chunk, err = loadfile(root .. "/.testing.lua")
  assert(chunk, err)
  local cfg = chunk()
  assert(type(cfg) == "table", ".testing.lua must return a table")
  return cfg
end

describe(".testing.lua", function()
  local cfg = load_config()

  it("does not waive the no-assertion check", function()
    -- nil is the testing.nvim default, which is "error".
    assert.is_true(
      cfg.assertions == nil or cfg.assertions == "error",
      'a case without an assertion must fail, not warn (assertions = "'
        .. tostring(cfg.assertions)
        .. '")'
    )
  end)

  it("keeps every guard but `state` in mode error", function()
    local guards = cfg.guards or {}
    for _, name in ipairs({ "fs", "scheduled_error", "prompt", "deprecation", "process_net" }) do
      assert.equals("error", guards[name], "guard '" .. name .. "' must stay in mode error")
    end
  end)

  it("keeps each spec file in its own nvim process", function()
    assert.equals("file", cfg.isolated, "specs replace package.loaded entries and must not leak")
  end)
end)
