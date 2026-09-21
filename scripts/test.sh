#!/usr/bin/env bash
#
# Runs the busted/plenary spec suite headlessly. Wraps
# scripts/minimal_init.lua -- see that file for what it does and why.
#
#   scripts/test.sh                    every spec under TESTS/
#   scripts/test.sh path/to_spec.lua   a single spec file
#
# Env vars (all optional -- see scripts/minimal_init.lua's own fallbacks):
#   LIB_NVIM_DIR      path to a lib.nvim checkout
#   PLENARY_DIR       path to a plenary.nvim checkout

set -euo pipefail

cd "$(dirname "$0")/.."

command -v nvim >/dev/null 2>&1 || {
  printf '\033[31m%s\033[0m\n' "nvim is not on PATH." >&2
  exit 1
}

target="${1:-TESTS/}"

if [[ "$target" == *.lua ]]; then
  # Deliberately NOT :PlenaryBustedFile. That maps to plenary's
  # `test_harness.test_file`, which takes no options and therefore spawns its
  # child nvim with no `-u` at all -- the child then has only the cwd and
  # plenary on its 'runtimepath', so every optional soft dependency
  # (color_my_ascii, pickers.nvim, diff.nvim) looks absent and every spec
  # gated on one silently registers zero tests. A single-file run reported
  # "Success" while quietly skipping exactly the tests it was invoked for.
  # `plenary.busted.run` is what that child would have called anyway; running
  # it in THIS process keeps the `-u scripts/minimal_init.lua` below, which is
  # where those dependencies come from.
  cmd="lua require('plenary.busted').run('$target')"
else
  cmd="PlenaryBustedDirectory $target { minimal_init = 'scripts/minimal_init.lua', sequential = true }"
fi

exec nvim -n --clean --headless -u scripts/minimal_init.lua -c "$cmd"
