-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/bindings_spec.lua — data.bindings orchestration + the reserved
-- (currently no-op) autocmds/keymaps modules, see NEW-08 in their doc
-- comments for why they exist ahead of any actual default binding.

describe("data.bindings.autocmds.setup", function()
  it("does not error and defines no autocmds (reserved for future use)", function()
    package.loaded["data.bindings.autocmds"] = nil
    local autocmds = require("data.bindings.autocmds")
    local before = #vim.api.nvim_get_autocmds({})

    local ok = pcall(autocmds.setup, { keymaps = { preset = false } })

    assert.is_true(ok)
    assert.equals(before, #vim.api.nvim_get_autocmds({}))
  end)
end)

describe("data.bindings.keymaps.setup", function()
  it("does not error and sets no keymaps (reserved for future use)", function()
    package.loaded["data.bindings.keymaps"] = nil
    local keymaps = require("data.bindings.keymaps")
    local before = #vim.api.nvim_get_keymap("n")

    local ok = pcall(keymaps.setup, { keymaps = { preset = false } })

    assert.is_true(ok)
    assert.equals(before, #vim.api.nvim_get_keymap("n"))
  end)
end)

describe("data.bindings.setup", function()
  before_each(function()
    for _, name in ipairs({
      "data.bindings",
      "data.bindings.usrcmds",
      "data.bindings.keymaps",
      "data.bindings.autocmds",
      "data.config",
    }) do
      package.loaded[name] = nil
    end
    require("data.config").setup(nil)
  end)

  it("wires up usrcmds, keymaps and autocmds without error", function()
    local ok = pcall(function()
      require("data.bindings").setup()
    end)
    assert.is_true(ok)
  end)

  it("registers the :JSON/:YAML/:XML/:Data user commands", function()
    require("data.bindings").setup()
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds["JSON"])
    assert.is_not_nil(cmds["YAML"])
    assert.is_not_nil(cmds["XML"])
    assert.is_not_nil(cmds["Data"])
  end)
end)
