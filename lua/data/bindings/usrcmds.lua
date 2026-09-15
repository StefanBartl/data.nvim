---@module 'data.bindings.usrcmds'
--- The `:JSON <action> [opts]` compound command (range-aware: no range =
--- whole buffer, a range or visual selection = only those lines), built via
--- lib.nvim's composer (`:Verb sub …` + `<Tab>` completion + Markdown
--- docgen).
---
--- Thin command wrappers over `data.run()`: every action route enables
--- `range` and reads `ctx.raw` (the untouched nvim callback args) for the
--- actual line span. `:YAML`/`:XML` are planned (Phase 2/3 in the project
--- concept) but not registered yet -- there is no YAML encoder or XML module
--- in lib.nvim to back them.

local composer = require("lib.nvim.bindings.usercmd.composer")

local M = {}

---@internal
--- Shared indent arg for `pretty`/`sort`.
---@type Lib.UserCmd.Composer.ArgSpec[]
local INDENT_ARG = { { name = "indent", type = "INT", optional = true } }

---@internal
--- Shared path-separator flag for `lines`/`keys`.
---@type Lib.UserCmd.Composer.FlagSpec[]
local SEP_FLAG = { { name = "sep", type = "STRING" } }

--- Create the `:JSON` verb (range-aware; normal + visual).
---@return nil
function M.setup()
  local data = require("data")

  composer.verb("JSON", {
    desc = "JSON format/filter (range-aware; no range = whole buffer)",
    default = function(ctx)
      data.run("json", "pretty", ctx.raw, {})
    end,
    routes = {
      {
        path = { "pretty" },
        range = true,
        args = INDENT_ARG,
        desc = "Pretty-print (default 2-space indent; :JSON pretty 4 for 4)",
        run = function(ctx)
          data.run("json", "pretty", ctx.raw, { indent = ctx.args.indent })
        end,
      },
      {
        path = { "compact" },
        range = true,
        desc = "Collapse onto one line",
        run = function(ctx)
          data.run("json", "compact", ctx.raw, {})
        end,
      },
      {
        path = { "lines" },
        range = true,
        flags = SEP_FLAG,
        desc = "One 'path: value' per line, nested keys dotted (--sep to override)",
        run = function(ctx)
          data.run("json", "lines", ctx.raw, { sep = ctx.flags.sep })
        end,
      },
      {
        path = { "keys" },
        range = true,
        flags = SEP_FLAG,
        desc = "List only the (dotted) key paths, no values",
        run = function(ctx)
          data.run("json", "keys", ctx.raw, { sep = ctx.flags.sep })
        end,
      },
      {
        path = { "sort" },
        range = true,
        args = INDENT_ARG,
        desc = "Pretty-print with object keys sorted (see data.format.json for why this equals 'pretty' today)",
        run = function(ctx)
          data.run("json", "sort", ctx.raw, { indent = ctx.args.indent })
        end,
      },
    },
  })
end

return M
