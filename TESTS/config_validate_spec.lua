-- Test code: when something here comes back nil -- a require, a config read
-- -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/config_validate_spec.lua — the arms of data.config's validator that
-- config_spec.lua does not reach, plus `get_all`.
--
-- The validator exists because `lib.lua.config.deep_merge` accepts any key
-- and any type unconditionally -- that is its job. So a typo does not fail,
-- it becomes a real merged-in field, and the ONLY thing standing between a
-- user and a config option that silently does nothing is a warning. Each of
-- the three warning shapes therefore gets its own test, including the nested
-- and table-vs-scalar ones config_spec.lua leaves out.
--
-- Every warning is `vim.schedule`d (setup() can run during plugin load,
-- before scheduling is safe), so every test here has to pump the loop before
-- looking.

--- Run `fn()` with `vim.notify` captured, pumping the event loop afterwards so
--- the scheduled warnings have actually fired. Drains any warning still
--- pending from an earlier test first, so one test's deferred message cannot
--- be counted as the next one's.
---@param fn fun()
---@return string[]
local function warnings_from(fn)
  vim.wait(30)
  local msgs = {}
  local orig = vim.notify
  --- Test double: restored below, including when `fn()` errors.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    msgs[#msgs + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.wait(30)
  vim.notify = orig
  if not ok then
    error(err, 0)
  end
  return msgs
end

---@param msgs string[]
---@param pattern string
---@return boolean
local function matched(msgs, pattern)
  for _, m in ipairs(msgs) do
    if m:match(pattern) then
      return true
    end
  end
  return false
end

describe("data.config.setup -- the validator's three warning shapes", function()
  local config

  before_each(function()
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    config = require("data.config")
  end)

  it("warns about a nested unknown key, naming its full dot-path", function()
    local msgs = warnings_from(function()
      config.setup({ json = { indnet = 4 } })
    end)
    assert.is_true(
      matched(msgs, "unknown config key 'json%.indnet'"),
      "a bare 'indnet' would not say which section it was in"
    )
    assert.equals(2, config.get("json.indent"), "the real key is untouched by the typo")
  end)

  it("warns about a scalar where a table belongs", function()
    local msgs = warnings_from(function()
      config.setup({ json = 4 })
    end)
    assert.is_true(matched(msgs, "'json' should be a table, got number"))
  end)

  it("warns about a table where a scalar belongs", function()
    local msgs = warnings_from(function()
      config.setup({ json = { indent = { 4 } } })
    end)
    assert.is_true(matched(msgs, "'json%.indent' should be number, got table"))
  end)

  it("warns about a boolean option given a string", function()
    local msgs = warnings_from(function()
      config.setup({ fenced_scope = { enable = "false" } })
    end)
    assert.is_true(matched(msgs, "'fenced_scope%.enable' should be boolean, got string"))
  end)

  it("reports EVERY offending key, not just the first", function()
    local msgs = warnings_from(function()
      config.setup({ nope = 1, alsonope = 2, json = { indent = "x" } })
    end)
    assert.is_true(matched(msgs, "unknown config key 'nope'"))
    assert.is_true(matched(msgs, "unknown config key 'alsonope'"))
    assert.is_true(matched(msgs, "'json%.indent' should be number"))
  end)

  it("stays silent about a fully valid config", function()
    local msgs = warnings_from(function()
      config.setup({
        json = { indent = 4, sep = "/" },
        yaml = { indent = 2, sep = "." },
        xml = { indent = 8, sep = ":" },
        fenced_scope = { enable = false },
        register = { default = "z" },
        target = { split = "below" },
        preview = { filter = true, view = "float" },
        keymaps = { preset = false },
      })
    end)
    assert.equals(0, #msgs, "a correct config must not be nagged about")
  end)

  it("recurses no further than the schema does", function()
    -- `preview` has no nested tables, so a table given for one of its leaves
    -- is a type mismatch rather than something to walk into.
    local msgs = warnings_from(function()
      config.setup({ preview = { view = { "inline" } } })
    end)
    assert.is_true(matched(msgs, "'preview%.view' should be string, got table"))
    assert.is_false(matched(msgs, "unknown config key 'preview%.view%.1'"))
  end)

  it("warns but still merges, which is deep_merge's contract and not a block", function()
    warnings_from(function()
      config.setup({ jsno = { indent = 9 } })
    end)
    assert.equals(9, config.get("jsno.indent"), "the typo'd section is really there")
    assert.equals(2, config.get("json.indent"), "and the real one is unaffected")
  end)
end)

describe("data.config.get", function()
  local config

  before_each(function()
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    config = require("data.config")
    config.setup()
  end)

  it("returns nil for a path that does not exist", function()
    assert.is_nil(config.get("nope"))
    assert.is_nil(config.get("json.nope"))
    assert.is_nil(config.get("nope.nope.nope"))
  end)

  it("returns a whole section as a table", function()
    local json = config.get("json")
    assert.equals(2, json.indent)
    assert.equals(".", json.sep)
  end)

  it("deep-copies a NESTED table, not only the top level", function()
    -- The bug this guards against is a real one from a sibling plugin:
    -- `vim.tbl_deep_extend("force", {}, state)` copies only keys present on
    -- BOTH sides, so every nested table came back by reference. `vim.deepcopy`
    -- is what makes this hold.
    local first = config.get("preview")
    first.view = "MUTATED"
    first.filter = true
    assert.equals("inline", config.get("preview.view"))
    assert.is_false(config.get("preview.filter"))
  end)

  it("returns scalars by value, unchanged across reads", function()
    assert.equals(config.get("json.indent"), config.get("json.indent"))
  end)
end)

describe("data.config.get_all", function()
  local config

  before_each(function()
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    config = require("data.config")
    config.setup()
  end)

  it("returns every configured section", function()
    local all = config.get_all()
    for _, key in ipairs({
      "json",
      "yaml",
      "xml",
      "fenced_scope",
      "register",
      "target",
      "preview",
      "keymaps",
    }) do
      assert.is_not_nil(all[key], key .. " is part of the resolved config")
    end
  end)

  it("is a deep copy: mutating it cannot corrupt the session's config", function()
    local all = config.get_all()
    all.json.indent = 99
    all.preview.view = "MUTATED"
    assert.equals(2, config.get("json.indent"))
    assert.equals("inline", config.get("preview.view"))
  end)

  it("reflects a user override", function()
    config.setup({ target = { split = "left" } })
    assert.equals("left", config.get_all().target.split)
  end)

  it("hands two callers independent copies", function()
    local a, b = config.get_all(), config.get_all()
    a.json.indent = 7
    assert.equals(2, b.json.indent)
  end)
end)

describe("data.config.DEFAULTS", function()
  it("is never mutated by a setup that overrides its values", function()
    -- The file's own doc comment says "Never mutate it at runtime". `setup`
    -- merges DEFAULTS as the BASE, and `lib.lua.config.deep_merge` must not
    -- write into it -- otherwise a second `setup(nil)` would return the first
    -- call's values instead of the shipped ones.
    package.loaded["data.config"] = nil
    package.loaded["data.config.DEFAULTS"] = nil
    local config = require("data.config")

    config.setup({ json = { indent = 9 }, preview = { view = "tab" } })
    config.setup(nil)

    assert.equals(2, config.get("json.indent"), "DEFAULTS still says 2")
    assert.equals("inline", config.get("preview.view"), "DEFAULTS still says inline")

    local defaults = require("data.config.DEFAULTS")
    assert.equals(2, defaults.json.indent)
    assert.equals("inline", defaults.preview.view)
  end)

  it("declares a default for every key the plugin reads by dot-path", function()
    -- A `get()` for a path DEFAULTS does not declare returns nil, and every
    -- reader here treats nil as "not configured" -- which is how a feature
    -- ends up silently off. This pins the list both ways: the paths the
    -- source actually reads all resolve, and the validator knows them all.
    package.loaded["data.config"] = nil
    local config = require("data.config")
    config.setup()
    local read_by_source = {
      "json",
      "yaml",
      "xml",
      "fenced_scope.enable",
      "register.default",
      "target.split",
      "preview.filter",
      "preview.view",
    }
    for _, path in ipairs(read_by_source) do
      assert.is_not_nil(config.get(path), path .. " is read by lua/data and must have a default")
    end
  end)
end)
