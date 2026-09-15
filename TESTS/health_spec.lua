-- Test code: when something here comes back nil -- a require, a decode, a
-- format lookup -- this file must crash and name it. The nil guards LuaLS
-- asks for below would hide the very failure this spec exists to catch.
---@diagnostic disable: need-check-nil
-- TESTS/health_spec.lua — data.health (:checkhealth data)

--- Capture every vim.health.* call made during `fn()`, restoring the real
--- functions afterwards regardless of whether `fn()` errors.
---@param fn fun()
---@return {level: string, msg: string}[]
local function capture_health(fn)
  local calls = {}
  local orig = {
    start = vim.health.start,
    ok = vim.health.ok,
    warn = vim.health.warn,
    error = vim.health.error,
    info = vim.health.info,
  }

  vim.health.start = function(msg)
    calls[#calls + 1] = { level = "start", msg = msg }
  end
  vim.health.ok = function(msg)
    calls[#calls + 1] = { level = "ok", msg = msg }
  end
  vim.health.warn = function(msg)
    calls[#calls + 1] = { level = "warn", msg = msg }
  end
  vim.health.error = function(msg)
    calls[#calls + 1] = { level = "error", msg = msg }
  end
  vim.health.info = function(msg)
    calls[#calls + 1] = { level = "info", msg = msg }
  end

  local ok, err = pcall(fn)

  vim.health.start = orig.start
  vim.health.ok = orig.ok
  vim.health.warn = orig.warn
  vim.health.error = orig.error
  vim.health.info = orig.info

  if not ok then
    error(err, 0)
  end

  return calls
end

---@param calls {level: string, msg: string}[]
---@param level string
---@return string[]
local function msgs_at(calls, level)
  local out = {}
  for _, c in ipairs(calls) do
    if c.level == level then
      out[#out + 1] = c.msg
    end
  end
  return out
end

describe("data.health.check", function()
  before_each(function()
    package.loaded["data.health"] = nil
  end)

  it("starts a 'data.nvim' health section", function()
    local calls = capture_health(function()
      require("data.health").check()
    end)
    assert.equals("start", calls[1].level)
    assert.equals("data.nvim", calls[1].msg)
  end)

  it("reports lib.nvim missing as an error, not a silent skip", function()
    -- Must clear package.loaded too, not just preload -- other specs
    -- already required this real module earlier in the same nvim session,
    -- so require() would otherwise return that cached table and never
    -- reach preload at all.
    package.loaded["lib.nvim.bindings.usercmd.composer"] = nil
    package.preload["lib.nvim.bindings.usercmd.composer"] = function()
      error("simulated: lib.nvim not on rtp")
    end

    local calls = capture_health(function()
      require("data.health").check()
    end)

    package.preload["lib.nvim.bindings.usercmd.composer"] = nil
    package.loaded["lib.nvim.bindings.usercmd.composer"] = nil
    require("lib.nvim.bindings.usercmd.composer")

    local errors = msgs_at(calls, "error")
    local found = false
    for _, m in ipairs(errors) do
      if m:match("lib%.nvim not found") then
        found = true
      end
    end
    assert.is_true(found, "expected an error naming lib.nvim as missing")
  end)

  it("reports lib.lua.tables.path_flatten missing as an error", function()
    package.loaded["lib.lua.tables"] = nil
    package.preload["lib.lua.tables"] = function()
      return {}
    end

    local calls = capture_health(function()
      require("data.health").check()
    end)

    package.preload["lib.lua.tables"] = nil
    package.loaded["lib.lua.tables"] = nil

    local errors = msgs_at(calls, "error")
    local found = false
    for _, m in ipairs(errors) do
      if m:match("path_flatten not found") then
        found = true
      end
    end
    assert.is_true(found, "expected an error naming path_flatten as missing")
  end)

  it("reports color_my_ascii absent as info, not error (optional dependency)", function()
    package.loaded["color_my_ascii"] = nil
    package.preload["color_my_ascii"] = function()
      error("simulated: color_my_ascii not installed")
    end

    local calls = capture_health(function()
      require("data.health").check()
    end)

    package.preload["color_my_ascii"] = nil

    local infos = msgs_at(calls, "info")
    local found = false
    for _, m in ipairs(infos) do
      if m:match("color_my_ascii not found") then
        found = true
      end
    end
    assert.is_true(found, "expected an info line, not an error, for the optional dependency")
  end)

  it("reports pickers.nvim absent as info, not error (optional dependency)", function()
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      error("simulated: pickers.nvim not installed")
    end

    local calls = capture_health(function()
      require("data.health").check()
    end)

    package.preload["pickers.refine"] = nil

    local infos = msgs_at(calls, "info")
    local found = false
    for _, m in ipairs(infos) do
      if m:match("pickers%.nvim not found") then
        found = true
      end
    end
    assert.is_true(found, "expected an info line, not an error, for the optional dependency")
  end)

  it("reports pickers.nvim present as ok when it is on the rtp", function()
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      return {}
    end

    local calls = capture_health(function()
      require("data.health").check()
    end)

    package.preload["pickers.refine"] = nil
    package.loaded["pickers.refine"] = nil

    local oks = msgs_at(calls, "ok")
    local found = false
    for _, m in ipairs(oks) do
      if m:match("pickers%.nvim detected") then
        found = true
      end
    end
    assert.is_true(found, "expected an ok line once pickers.refine is requirable")
  end)

  it("does not raise regardless of which optional/required deps are present", function()
    local ok = pcall(capture_health, function()
      require("data.health").check()
    end)
    assert.is_true(ok)
  end)
end)
