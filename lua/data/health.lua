---@module 'data.health'
--- `:checkhealth data` diagnostics.
---
--- Reports Neovim version, `lib.nvim` availability (required -- the command
--- layer is built on `lib.nvim.bindings.usercmd.composer`), and whether the
--- installed `lib.nvim` has `tables.path_flatten` (`lines`/`keys`, every
--- format), `lib.lua.yaml.encode` (`:YAML`), and `lib.lua.xml` (`:XML`) --
--- each only present from the version data.nvim shipped alongside the
--- feature that needs it. Read-only: never mutates state.

local M = {}

--- Run the health check.
---@return nil
function M.check()
  local health = vim.health or require("health")
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local warn = health.warn or health.report_warn
  local err = health.error or health.report_error
  local info = health.info or health.report_info

  start("data.nvim")

  if vim.fn.has("nvim-0.9") == 1 then
    ok("Neovim " .. tostring(vim.version()))
  else
    warn("data.nvim targets Neovim 0.9+", { "Upgrade Neovim to 0.9+" })
  end

  if pcall(require, "lib.nvim.bindings.usercmd.composer") then
    ok("lib.nvim detected (:JSON command layer)")
  else
    err("lib.nvim not found -- :JSON will fail to load", { 'Install "StefanBartl/lib.nvim"' })
  end

  local tables_ok, tables_mod = pcall(require, "lib.lua.tables")
  if tables_ok and type(tables_mod.path_flatten) == "function" then
    ok("lib.lua.tables.path_flatten available (:JSON/:YAML/:XML lines/keys)")
  else
    err(
      "lib.lua.tables.path_flatten not found -- lib.nvim is outdated",
      { "Update StefanBartl/lib.nvim to a version that ships tables.path_flatten" }
    )
  end

  local yaml_ok, yaml_mod = pcall(require, "lib.lua.yaml")
  if yaml_ok and type(yaml_mod.encode) == "function" then
    ok("lib.lua.yaml.encode available (:YAML pretty/lines/keys/sort)")
  else
    err(
      "lib.lua.yaml.encode not found -- lib.nvim is outdated",
      { "Update StefanBartl/lib.nvim to a version that ships yaml.encode" }
    )
  end

  local xml_ok, xml_mod = pcall(require, "lib.lua.xml")
  if xml_ok and type(xml_mod.decode) == "function" and type(xml_mod.encode) == "function" then
    ok("lib.lua.xml available (:XML pretty/compact/lines/keys/sort)")
  else
    err(
      "lib.lua.xml not found -- lib.nvim is outdated",
      { "Update StefanBartl/lib.nvim to a version that ships lib.lua.xml" }
    )
  end

  info(
    "yaml/xml are deliberately minimal subsets (no anchors/flow-style/DTDs/namespaces) -- see docs/scope.md"
  )
end

return M
