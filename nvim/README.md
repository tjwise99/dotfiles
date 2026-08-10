# nvim

Vendored from <https://github.com/jsmith212/dotfiles>, `nvim/` at commit `fe34989`. An
[NvChad](https://nvchad.com) v2.5 config; upstream carries no licence file, so this copy is here by
the author's say-so rather than by a grant.

Not a submodule, because the upstream directory is not its own repository — pulling a change means
diffing that path and applying it by hand.

## Changed from upstream

The AI stack is removed: `zbirenbaum/copilot.lua` and `olimorris/codecompanion.nvim`, their
`configs/` files, `configs/fidget-spinner.lua` (used only by CodeCompanion's `init`) and
`configs/vectorcode.lua`, plus the `codecompanion` source and provider in `configs/blink.lua`. All
of it authenticates against a GitHub Copilot subscription this account does not have. Their three
entries are dropped from `lazy-lock.json` as well.

`lua/configs/.gitignore` is deleted. It listed `local_lspconfig.lua`, which upstream tracks anyway —
but `tools/sync.sh` commits with `git add -A`, so keeping the ignore here would mean the file exists
on this machine and on no other, while `lspconfig.lua` requires it unconditionally.

`configs/rust-tools.lua` is dead upstream too — nothing requires it, and `rustaceanvim` is what
actually configures Rust. Kept, so the diff against upstream stays small.

## Depends on

Neovim 0.11+, and a `python3` that can build a venv before mason will install its Python tools. Both
come from `asdf/tool-versions` and `asdf/uv-python.sh`; the repo README's Neovim section has the
version-pin reasoning and the two first-launch commands.
