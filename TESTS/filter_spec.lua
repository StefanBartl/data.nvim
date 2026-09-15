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
    vim.api.nvim_buf_delete(bufnr, { force = true })
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
end)
