> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# data.nvim

```
██████╗  █████╗ ████████╗ █████╗
██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗
██║  ██║███████║   ██║   ███████║
██║  ██║██╔══██║   ██║   ██╔══██║
██████╔╝██║  ██║   ██║   ██║  ██║
╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
                                               .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)

Format and filter structured data (JSON, YAML, XML) in place, in the buffer or a
visual selection — `pretty`, `compact` (JSON/XML), `lines` to flatten nested keys
onto one `path: value` per line, `keys` for just the paths.

---

## Documentation

Start at [docs/README.md](docs/README.md) — what's where, and which question each page
answers.

**The Basics**

- [Requirements](docs/requirements.md) — Neovim version and required plugins.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the handful of things that matter on day one.
- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)

**Integrations**

- [Optional integrations](docs/integrations.md) — fenced-block scope via color_my_ascii.nvim.

**The Rest**

- [What it does and what not](docs/scope.md) — JSON, YAML, and XML today; what's still planned.
- [Why it does it that way](docs/architecture.md)
- [Health check](docs/health.md) — what `:checkhealth data` reports, line by line.
- [Contributing](docs/CONTRIBUTING.md)
- [Feedback](https://github.com/StefanBartl/data.nvim/issues)

`:help data` is the same reference inside the editor.

---

## License

data.nvim is released under the [MIT License](https://opensource.org/licenses/MIT) — see [LICENSE](LICENSE).
