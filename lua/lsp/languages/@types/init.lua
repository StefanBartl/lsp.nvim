---@meta
---@module 'lsp.languages.@types'
--- Types for the language modules `lsp.languages.enable_all()` walks.
---
--- These names were referenced throughout `lsp/languages/**` and defined
--- nowhere in this repo. They resolved all the same, against a copy of an
--- older lsp.nvim that sat in a git worktree under the nvim config's
--- `.claude/` and was on every workspace's library path -- so the annotations
--- were checked against a version of themselves rather than against this one.
--- With that copy out of the index (2026-09-01) they became `undefined-doc-name`,
--- and this file is what they should have been pointing at all along.

--- The names in each category list. Literal unions rather than `string[]`,
--- because `enable_all()` builds a `require` path out of every entry: a typo
--- here is a module that silently never loads, which is exactly the failure a
--- closed set catches.
---@alias Lsp.Languages.ConfiguredLangs.Literal.App "csharp"|"java"|"dart"
---@alias Lsp.Languages.ConfiguredLangs.Literal.Doc "markdown"
---@alias Lsp.Languages.ConfiguredLangs.Literal.Scripting "lua"
---@alias Lsp.Languages.ConfiguredLangs.Literal.Systems "c"|"go"|"zig"
---@alias Lsp.Languages.ConfiguredLangs.Literal.Web "astro"|"typescript"|"html"

--- Every language module has the same surface, and `enable_all()` relies on
--- exactly that: it calls `enable()` with no arguments and ignores the rest.
--- Server *configuration* lives in `lsp.servers.*`; a language module is for
--- filetype QoL (see the note about "shell" in `lsp/languages/init.lua`).
---@class Lsp.Languages.ConfiguredLangs.Module
---@field enable fun(): nil

--- The per-language names the modules annotate themselves with. Aliases of the
--- one shape above rather than ten copies of it -- if a module ever grows a
--- second export, its alias becomes a class of its own and the others stay put.
---@alias Lsp.Languages.ConfiguredLangs.CSharp.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Dart.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Java.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Lua.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.C.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Go.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Zig.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Webdev.Astro.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Webdev.HTML.Module Lsp.Languages.ConfiguredLangs.Module
---@alias Lsp.Languages.ConfiguredLangs.Webdev.Typescript.Module Lsp.Languages.ConfiguredLangs.Module

return {}
