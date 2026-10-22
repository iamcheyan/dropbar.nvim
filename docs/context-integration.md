# Integrated context source

This fork incorporates the parser and hierarchy menu from iamcheyan/contextline.nvim
(MIT, copyright 2026 iamcheyan; see LICENSE.context). It includes the source checkout's
menu and Tree-sitter improvements. No contextline runtime or plugin is required.
The COBOL layout was migrated from iamcheyan/cobol.nvim (MIT, same author).

Use `require('dropbar.sources.context')` as a bar source. Call its `setup()` after
requiring dropbar, then pass `should_attach` as `bar.enable`, `{ source }` as
`bar.sources` and `render` as `bar.render`. The optional renderer returns nil to
use the standard dropbar rendering. COBOL uses a bracketed AST chain with
right-aligned waiting closures through the same dropbar lifecycle and winbar.
COBOL and Batch modules are discovered on demand, in either plugin load order.

`require('dropbar.context').register(name, {filetypes = {...}, get_info = fn})`
registers additional language providers. The hierarchy command is
`:DropbarContextMenu`. All migrated modules live under `dropbar.context`.

The upstream default source and menu APIs remain available. The custom source
is enabled explicitly by the consuming configuration.

Parser and menu regressions are in tests/context/. Run with Neovim 0.12+,
this checkout on runtimepath, and the required parsers installed. The consuming
Neovim configuration's tests/context_bar_spec.lua covers the unified bar,
clicks, diagnostics, COBOL waiting closures, and absence of contextline.
