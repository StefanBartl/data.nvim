-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "data",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "color_my_ascii.nvim", "diff.nvim", "lib.nvim", "pickers.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- "error" = a case without a single assertion fails (the default; kept explicit so nobody
  -- relaxes it to "warn" again). Every case asserts on every platform, with or without a
  -- clipboard provider.
  assertions = "error",
  -- Safety nets. The suite passes every guard below cleanly in mode "error" (no file written
  -- outside the temp dirs, no process or network started by a spec, no blocking prompt, no
  -- unseen scheduled error, no deprecated API), so no `guard_allow` entry is needed.
  guards = {
    fs = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
    -- Off on purpose: every case calls `setup()`, which leaves the :Data/:JSON/:YAML/:XML commands
    -- (the process is thrown away with the file, `isolated = "file"`), and loading a json/yaml
    -- filetype adds the runtime's syntax highlight groups (about 340 warnings, 42 failing cases
    -- in mode "error", none of them a leak of the plugin).
    state = "off",
  },
}
