-- Test code: when something here comes back nil -- a require, a health call
-- -- this file must crash and name it. The nil guards LuaLS asks for below
-- would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/health_deps_spec.lua — the dependency arms of `:checkhealth data`
-- that health_spec.lua does not reach, plus two structural properties of the
-- check itself.
--
-- health_spec.lua covers the section header, lib.nvim, path_flatten,
-- color_my_ascii and pickers.nvim. Left over were the yaml/window/xml arms,
-- diff.nvim, the Neovim-version warning, and -- the reason this file exists
-- -- whether the report is actually TRUE on a machine where everything works.
-- It is not: see the last describe block.

--- Capture every `vim.health.*` call made during `fn()`, restoring the real
--- functions afterwards regardless of whether `fn()` errors. Same shape as
--- health_spec.lua's own helper; duplicated rather than shared because
--- `PlenaryBustedDirectory` gives each spec file its own nvim process and
--- TESTS/ is not on 'runtimepath' as a module root.
---@param fn fun()
---@return {level: string, msg: string}[]
local function capture_health(fn)
  local calls = {}
  local orig = {}
  for _, k in ipairs({ "start", "ok", "warn", "error", "info" }) do
    orig[k] = vim.health[k]
    vim.health[k] = function(msg)
      calls[#calls + 1] = { level = k, msg = tostring(msg) }
    end
  end

  local ok, err = pcall(fn)

  for _, k in ipairs({ "start", "ok", "warn", "error", "info" }) do
    vim.health[k] = orig[k]
  end

  if not ok then
    error(err, 0)
  end
  return calls
end

--- Run `:checkhealth data`'s check with `mod` simulated as absent (when
--- `replacement` is nil) or replaced by `replacement`, then restore it.
---
--- `package.loaded` has to be cleared as well as `package.preload` set:
--- earlier tests in this same nvim process have already required the real
--- module, so `require` would return the cached table and never consult
--- preload at all.
---@param mod string
---@param replacement? table
---@param fn fun()
local function with_module_missing(mod, replacement, fn)
  local had = package.loaded[mod]
  package.loaded[mod] = nil
  package.preload[mod] = function()
    if replacement ~= nil then
      return replacement
    end
    error("simulated: " .. mod .. " is not installed")
  end

  local ok, err = pcall(fn)

  package.preload[mod] = nil
  package.loaded[mod] = had or nil
  if not had then
    -- Restore the real module for the tests that come after this one, rather
    -- than leaving a hole another spec in this file would then trip over.
    pcall(require, mod)
  end
  if not ok then
    error(err, 0)
  end
end

---@param calls {level: string, msg: string}[]
---@param level string
---@param needle string
---@return boolean
local function reported(calls, level, needle)
  for _, c in ipairs(calls) do
    if c.level == level and c.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("data.health.check -- the remaining lib.nvim arms", function()
  before_each(function()
    package.loaded["data.health"] = nil
  end)

  local arms = {
    {
      mod = "lib.lua.yaml",
      needle = "lib.lua.yaml.encode not found",
      what = "yaml.encode",
    },
    {
      mod = "lib.nvim.window",
      needle = "lib.nvim.window.open_scratch_split not found",
      what = "window.open_scratch_split",
    },
    {
      mod = "lib.lua.xml",
      needle = "lib.lua.xml not found",
      what = "lib.lua.xml",
    },
  }

  for _, arm in ipairs(arms) do
    it(("reports a %s-less lib.nvim as an error naming the update"):format(arm.what), function()
      -- Present but empty, which is the realistic shape of the failure this
      -- arm is for: an older lib.nvim that has the module but not the member.
      local calls
      with_module_missing(arm.mod, {}, function()
        calls = capture_health(function()
          require("data.health").check()
        end)
      end)
      assert.is_true(reported(calls, "error", arm.needle))
      assert.is_true(reported(calls, "error", "outdated"), "says what to do about it")
    end)

    it(("survives %s failing to load outright"):format(arm.mod), function()
      local calls
      with_module_missing(arm.mod, nil, function()
        calls = capture_health(function()
          require("data.health").check()
        end)
      end)
      assert.is_true(reported(calls, "error", arm.needle), "a throwing require is still an error")
      assert.is_true(reported(calls, "start", "data.nvim"), "and the section still completes")
    end)
  end
end)

describe("data.health.check -- diff.nvim, the third optional dependency", function()
  before_each(function()
    package.loaded["data.health"] = nil
  end)

  it("reports it absent as info, never as an error", function()
    local calls
    with_module_missing("diff", nil, function()
      calls = capture_health(function()
        require("data.health").check()
      end)
    end)
    assert.is_true(reported(calls, "info", "diff.nvim not found (optional)"))
    assert.is_false(reported(calls, "error", "diff.nvim"), "optional means optional")
  end)

  it("reports it present as ok", function()
    local calls
    with_module_missing("diff", { run = function() end }, function()
      calls = capture_health(function()
        require("data.health").check()
      end)
    end)
    assert.is_true(reported(calls, "ok", "diff.nvim detected"))
  end)

  it("reports color_my_ascii present as ok", function()
    local calls
    with_module_missing("color_my_ascii", { fences = {} }, function()
      calls = capture_health(function()
        require("data.health").check()
      end)
    end)
    assert.is_true(reported(calls, "ok", "color_my_ascii detected"))
  end)
end)

describe("data.health.check -- the Neovim version gate", function()
  before_each(function()
    package.loaded["data.health"] = nil
  end)

  it("warns rather than errors on a Neovim the plugin does not target", function()
    local orig_has = vim.fn.has
    --- Test double: restored immediately below.
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.has = function(what)
      if what == "nvim-0.9" then
        return 0
      end
      return orig_has(what)
    end

    local ok, calls = pcall(capture_health, function()
      require("data.health").check()
    end)
    vim.fn.has = orig_has

    assert.is_true(ok)
    assert.is_true(reported(calls, "warn", "targets Neovim 0.9+"))
    assert.is_false(reported(calls, "error", "Neovim"), "an old Neovim is a warning, not an error")
  end)
end)

describe("data.health.check -- structural properties of the check itself", function()
  before_each(function()
    package.loaded["data.health"] = nil
  end)

  it("no 'dependency missing' arm then calls into the missing dependency", function()
    -- The recurring defect this campaign has now found in three sibling
    -- repos: a health check reports a dependency as absent and then reaches
    -- into it unconditionally on the very next line, so `:checkhealth`
    -- crashes exactly on the machine the check was written for. Driven here
    -- by making EVERY dependency data.health touches unavailable at once --
    -- if any arm reaches past its own guard, this raises.
    local mods = {
      "lib.nvim.bindings.usercmd.composer",
      "lib.lua.tables",
      "lib.lua.yaml",
      "lib.nvim.window",
      "lib.lua.xml",
      "color_my_ascii",
      "pickers.refine",
      "diff",
    }
    local had = {}
    for _, m in ipairs(mods) do
      had[m] = package.loaded[m]
      package.loaded[m] = nil
      package.preload[m] = function()
        error("simulated: " .. m .. " is not installed")
      end
    end

    local ok, calls = pcall(capture_health, function()
      require("data.health").check()
    end)

    for _, m in ipairs(mods) do
      package.preload[m] = nil
      package.loaded[m] = had[m] or nil
      if not had[m] then
        pcall(require, m)
      end
    end

    assert.is_true(ok, "the check must complete on a machine with nothing installed")
    assert.is_true(reported(calls, "start", "data.nvim"))
    assert.is_true(reported(calls, "error", "lib.nvim not found"))
    assert.is_true(reported(calls, "info", "color_my_ascii not found"))
    assert.is_true(reported(calls, "info", "pickers.nvim not found"))
    assert.is_true(reported(calls, "info", "diff.nvim not found"))
  end)

  it("mutates nothing -- it is a report, and says so", function()
    local before_bufs = #vim.api.nvim_list_bufs()
    local before_wins = #vim.api.nvim_list_wins()
    local before_cmds = vim.tbl_count(vim.api.nvim_get_commands({}))

    capture_health(function()
      require("data.health").check()
    end)

    assert.equals(before_bufs, #vim.api.nvim_list_bufs())
    assert.equals(before_wins, #vim.api.nvim_list_wins())
    assert.equals(before_cmds, vim.tbl_count(vim.api.nvim_get_commands({})))
  end)
end)

describe("BUG: :checkhealth data reports two errors on a fully working install", function()
  -- Found by simply running the check with every dependency present and
  -- reading what it said. `lib.lua.yaml.encode` and `lib.lua.xml.encode` are
  -- both CALLABLE TABLES (a `__call` metamethod plus members like
  -- `encode.pretty`, which `data.format.xml` calls by name), not bare
  -- functions. `data.health` gates both on `type(...) == "function"`, which is
  -- false for a table however callable it is -- so the check reports
  --
  --   error: lib.lua.yaml.encode not found -- lib.nvim is outdated
  --   error: lib.lua.xml not found -- lib.nvim is outdated
  --
  -- at the highest severity, telling the user to update a dependency that is
  -- fine, while `:YAML` and `:XML` work perfectly -- as the rest of this
  -- suite demonstrates in the same process. Same root cause as the
  -- buffer-ctx.nvim finding from earlier in this campaign: a lib.nvim
  -- `require` hands back a `__call`-able table, not a function.
  --
  -- Not fixed here (that is a one-line change to a user-visible report, and a
  -- separate decision): pinned, so the fix has something to flip.

  before_each(function()
    package.loaded["data.health"] = nil
  end)

  it("lib.lua.yaml.encode is callable, but is a table and not a function", function()
    local yaml = require("lib.lua.yaml")
    assert.equals("table", type(yaml.encode), "BUG: this is what the check rejects")
    assert.equals("function", type(getmetatable(yaml.encode).__call), "and it IS callable")
    assert.is_not_nil(yaml.encode({ a = 1 }), "and calling it works")
  end)

  it("lib.lua.xml.encode is the same shape, with a .pretty member besides", function()
    local xml = require("lib.lua.xml")
    assert.equals("table", type(xml.encode), "BUG: this is what the check rejects")
    assert.equals("function", type(xml.encode.pretty), "data.format.xml calls this by name")
  end)

  it("BUG: so the check errors about yaml.encode although :YAML works", function()
    local calls = capture_health(function()
      require("data.health").check()
    end)
    assert.is_true(
      reported(calls, "error", "lib.lua.yaml.encode not found"),
      "BUG: a false error on a healthy install"
    )
    assert.same(
      { "a: 1" },
      require("data.format.yaml").render({ a = 1 }, "pretty"),
      ":YAML works in this very process, which is what makes the report false"
    )
  end)

  it("BUG: and errors about lib.lua.xml although :XML works", function()
    local calls = capture_health(function()
      require("data.health").check()
    end)
    assert.is_true(
      reported(calls, "error", "lib.lua.xml not found"),
      "BUG: a false error on a healthy install"
    )
    assert.same(
      { "<a/>" },
      require("data.format.xml").render({ tag = "a", attrs = {}, children = {} }, "compact"),
      ":XML works in this very process too"
    )
  end)

  it("BUG: exactly two of the errors on a healthy install are false ones", function()
    -- Pins the count as well as the identities: a fix should take this to
    -- zero, and any NEW false error should fail here rather than hide behind
    -- the two already known.
    local calls = capture_health(function()
      require("data.health").check()
    end)
    local errors = {}
    for _, c in ipairs(calls) do
      if c.level == "error" then
        errors[#errors + 1] = c.msg
      end
    end
    assert.equals(2, #errors, "BUG: a healthy install should report none")
  end)
end)
