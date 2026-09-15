---@diagnostic disable: need-check-nil
-- TESTS/filter_spec.lua — :JSON/:YAML/:XML filter (pickers.refine-backed)

describe("data.filter.run", function()
  it("reports a clear error when pickers.nvim is not installed", function()
    -- Simulated absence via package.preload, not by removing the real
    -- plugin from the rtp -- this test must fail the same way whether or
    -- not pickers.nvim actually happens to be on this machine.
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      error("simulated: pickers.nvim not on rtp")
    end

    local filter = require("data.filter")
    local json_fmt = require("data.format.json")
    local got_out, got_err
    filter.run(json_fmt, { a = 1 }, {}, function(out, err)
      got_out, got_err = out, err
    end)

    package.preload["pickers.refine"] = nil
    package.loaded["pickers.refine"] = nil

    assert.is_nil(got_out)
    assert.matches("pickers.nvim", got_err)
  end)

  it("an unexpected runtime error during path_flatten is caught, not raised", function()
    -- Stub pickers.refine present regardless of whether the real plugin is
    -- on this machine's rtp -- this test targets the path_flatten failure
    -- specifically, and must not depend on pickers.nvim actually being
    -- installed to reach that code path.
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      return {}
    end

    local tables_mod = require("lib.lua.tables")
    local original_flatten = tables_mod.path_flatten
    tables_mod.path_flatten = function()
      error("boom: simulated path_flatten failure")
    end

    local filter = require("data.filter")
    local json_fmt = require("data.format.json")
    local got_out, got_err
    local ok = pcall(filter.run, json_fmt, { a = 1 }, {}, function(out, err)
      got_out, got_err = out, err
    end)

    tables_mod.path_flatten = original_flatten
    package.preload["pickers.refine"] = nil
    package.loaded["pickers.refine"] = nil

    assert.is_true(ok, "data.filter.run itself does not raise -- the error is caught")
    assert.is_nil(got_out)
    assert.matches("boom", got_err)
  end)

  it("an unexpected runtime error during render is caught, not raised", function()
    -- Same rationale as the path_flatten test above: stub pickers.refine so
    -- this test's target failure (render) is reached independent of whether
    -- pickers.nvim is actually installed.
    package.loaded["pickers.refine"] = nil
    package.preload["pickers.refine"] = function()
      return {}
    end

    local json_fmt = require("data.format.json")
    local original_render = json_fmt.render
    json_fmt.render = function()
      error("boom: simulated render failure")
    end

    local filter = require("data.filter")
    local got_out, got_err
    local ok = pcall(filter.run, json_fmt, { a = 1 }, {}, function(out, err)
      got_out, got_err = out, err
    end)

    json_fmt.render = original_render
    package.preload["pickers.refine"] = nil
    package.loaded["pickers.refine"] = nil

    assert.is_true(ok, "data.filter.run itself does not raise -- the error is caught")
    assert.is_nil(got_out)
    assert.matches("boom", got_err)
  end)
end)

describe(":JSON/:YAML/:XML filter", function()
  -- Optional soft dependency, same "sibling checkout" convention as the
  -- fenced-scope tests use for color_my_ascii (see
  -- scope_resolve_spec.lua, docs/CONTRIBUTING.md's PICKERS_DIR). Zero `it`s
  -- registered below is the correct "skipped" outcome when pickers.nvim
  -- isn't present in this test environment.
  local pickers_ok = pcall(require, "pickers.refine")
  if not pickers_ok then
    return
  end

  local bufnr
  local orig_select, orig_input

  before_each(function()
    for _, name in ipairs({ "data", "data.config", "data.bindings", "data.bindings.usrcmds" }) do
      package.loaded[name] = nil
    end
    require("data").setup()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    orig_select, orig_input = vim.ui.select, vim.ui.input
  end)

  after_each(function()
    vim.ui.select, vim.ui.input = orig_select, orig_input
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  --- Script the refine prompt for exactly one "add a <field>
  --- <contains|excludes> <term>" round, then cancel the next round (Esc)
  --- to end the loop and commit the filter -- see data.filter's own doc
  --- comment for why a change-less round is the commit signal.
  ---@param field string
  ---@param term string
  ---@param negate boolean
  local function script_one_clause(field, term, negate)
    local select_calls = 0
    vim.ui.select = function(choices, _select_opts, cb)
      select_calls = select_calls + 1
      if select_calls > 1 then
        return cb(nil)
      end
      for _, c in ipairs(choices) do
        if c.kind == "add" and c.field == field and c.negate == negate then
          return cb(c)
        end
      end
      cb(nil)
    end
    vim.ui.input = function(_input_opts, cb)
      cb(term)
    end
  end

  it(":JSON filter keeps only entries whose path matches", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"user":{"id":1,"name":"x"},"level":"error"}',
    })
    script_one_clause("path", "user", false)
    vim.cmd("JSON filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "user.id: 1", "user.name: x" }, lines)
  end)

  it(":JSON filter supports a negated (excludes) clause", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"user":{"id":1,"name":"x"},"level":"error"}',
    })
    script_one_clause("path", "user", true)
    vim.cmd("JSON filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "level: error" }, lines)
  end)

  it(":JSON filter can match on the rendered value text too", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      '{"a":{"level":"error"},"b":{"level":"info"}}',
    })
    script_one_clause("line", "error", false)
    vim.cmd("JSON filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "a.level: error" }, lines)
  end)

  it("cancelling before adding any clause leaves the scope untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    vim.ui.select = function(_choices, _select_opts, cb)
      cb(nil)
    end
    vim.cmd("JSON filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ '{"a":1}' }, lines)
  end)

  it("a filter matching nothing leaves the scope untouched", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })
    script_one_clause("path", "does-not-exist", false)
    vim.cmd("JSON filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ '{"a":1}' }, lines)
  end)

  it(":YAML filter works the same way as :JSON filter", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "user:", "  id: 1", "level: error" })
    script_one_clause("path", "user", false)
    vim.cmd("YAML filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "user.id: 1" }, lines)
  end)

  it(":XML filter works against the raw element-tree paths", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "<a><b>1</b><c>2</c></a>" })
    script_one_clause("path", ".tag", false)
    vim.cmd("XML filter")
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.same({ "children.1.tag: b", "children.2.tag: c" }, lines)
  end)

  it(
    "a buffer edit made between clause rounds still lands on the shifted scope (extmark, not a stale line pair)",
    function()
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "before",
        '{"user":{"id":1,"name":"x"},"level":"error"}',
        "after",
      })

      local select_calls = 0
      vim.ui.select = function(choices, _select_opts, cb)
        select_calls = select_calls + 1
        if select_calls == 1 then
          for _, c in ipairs(choices) do
            if c.kind == "add" and c.field == "path" and c.negate == false then
              return cb(c)
            end
          end
          return cb(nil)
        end
        -- Round 2: something else edits the buffer while the prompt is
        -- still open, shifting the scope down by one line -- before the
        -- extmark fix, the eventual write still targeted the original,
        -- now-stale line numbers.
        vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "INSERTED" })
        cb(nil)
      end
      vim.ui.input = function(_input_opts, cb)
        cb("user")
      end

      vim.cmd("2JSON filter")

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.same({ "INSERTED", "before", "user.id: 1", "user.name: x", "after" }, lines)
    end
  )

  it("does not raise when the buffer is closed before the filter finishes", function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '{"a":1}' })

    local select_calls = 0
    vim.ui.select = function(choices, _select_opts, cb)
      select_calls = select_calls + 1
      if select_calls == 1 then
        for _, c in ipairs(choices) do
          if c.kind == "add" and c.field == "path" and c.negate == false then
            return cb(c)
          end
        end
        return cb(nil)
      end
      -- Round 2: the buffer is closed while the prompt is still open.
      vim.api.nvim_buf_delete(bufnr, { force = true })
      cb(nil)
    end
    vim.ui.input = function(_input_opts, cb)
      cb("a")
    end

    local ok = pcall(vim.cmd, "JSON filter")
    assert.is_true(ok, "closing the buffer mid-filter must not raise past vim.cmd()")
  end)
end)
