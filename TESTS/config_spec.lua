-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/config_spec.lua — data.config

describe("data.config", function()
  local config

  before_each(function()
    -- Fresh module instance: `options` is a module-level singleton, and a
    -- stale merge from a previous test would mask the bug this spec exists
    -- to catch.
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    config = require("data.config")
  end)

  it("starts with the shipped defaults before setup() is ever called", function()
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("json.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("json.sep"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("yaml.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("yaml.sep"))
    ---@diagnostic disable-next-line: undefined-field
    assert.is_false(config.get("keymaps.preset"))
  end)

  it("deep-merges a partial override, leaving untouched defaults in place", function()
    config.setup({ json = { indent = 4 } })
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(4, config.get("json.indent"))
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(".", config.get("json.sep"), "sep survives an override that only touches indent")
  end)

  it("tolerates setup(nil) / setup() with no argument", function()
    config.setup(nil)
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("json.indent"))
  end)

  it("warns about an unknown top-level key instead of silently accepting it", function()
    local calls = {}
    local orig = vim.notify
    --- Test double: reassigning `vim.notify` a second time in this file
    --- (see the next `it` below) is intentional -- each capture is
    --- restored before the test ends, they never run concurrently.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      calls[#calls + 1] = msg
    end
    config.setup({ jsno = { indent = 4 } })
    vim.wait(20)
    vim.notify = orig

    local found = false
    for _, m in ipairs(calls) do
      if m:match("unknown config key 'jsno'") then
        found = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(found, "expected a warning naming the unknown key")
    -- The typo'd key still merges in as-is (deep_merge's own contract) --
    -- this only makes the mistake visible, it doesn't block it.
    ---@diagnostic disable-next-line: undefined-field
    assert.equals(2, config.get("json.indent"), "the real json.indent is untouched by the typo")
  end)

  it("warns about a wrong-typed leaf value instead of silently accepting it", function()
    local calls = {}
    local orig = vim.notify
    --- Test double: same rationale as the previous `it`'s reassignment.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg)
      calls[#calls + 1] = msg
    end
    config.setup({ json = { indent = "four" } })
    vim.wait(20)
    vim.notify = orig

    local found = false
    for _, m in ipairs(calls) do
      if m:match("'json%.indent' should be number, got string") then
        found = true
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(found, "expected a warning naming the type mismatch")
  end)

  it("get() returns a deep copy, not a live reference into the stored config", function()
    config.setup(nil)
    ---@diagnostic disable-next-line: undefined-field
    local fenced = config.get("fenced_scope")
    fenced.enable = false
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(
      config.get("fenced_scope").enable,
      "mutating a get() result must not affect the stored config"
    )
  end)
end)
