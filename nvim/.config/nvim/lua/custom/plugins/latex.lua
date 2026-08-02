-- ============================================================
-- LaTeX: VimTeX + latexmk continuous compilation + live PDF viewer
-- ============================================================
--
-- Workflow:
--   1. Open a .tex file.
--   2. `<localleader>ll` (with maplocalleader = <space>, that is `<space>ll`)
--      -- or `:VimtexCompile` -- starts `latexmk -pvc` in the background.
--   3. `<localleader>lv` / `:VimtexView` opens the PDF viewer.
--   4. From then on every `:w` triggers a rebuild and the viewer reloads itself.
--
-- Requires (system packages, see DECISIONS-NVIM.md):
--   texlive-scheme-basic, latexmk, texlive-collection-latexrecommended,
--   texlive-collection-fontsrecommended, texlive-xetex, and a PDF viewer.

-- NOTE: all `vim.g.vimtex_*` settings must be assigned BEFORE the plugin is
-- sourced, which `vim.pack.add` does synchronously. Order matters here.

-- ---------- Viewer ----------
-- Preference order:
--   zathura -- VimTeX's best-supported viewer, reloads instantly, full SyncTeX
--              (forward search jumps the PDF to your cursor, backward search
--              jumps Neovim to a spot you clicked in the PDF).
--   okular  -- ships with KDE, auto-reloads, forward SyncTeX only.
--   xdg-open -- last resort: opens the PDF, no SyncTeX, reload depends on the app.
if vim.fn.executable 'zathura' == 1 then
  vim.g.vimtex_view_method = 'zathura'
elseif vim.fn.executable 'okular' == 1 then
  vim.g.vimtex_view_method = 'general'
  vim.g.vimtex_view_general_viewer = 'okular'
  vim.g.vimtex_view_general_options = '--noraise --unique file:@pdf\\#src:@line@tex'
else
  vim.g.vimtex_view_method = 'general'
  vim.g.vimtex_view_general_viewer = 'xdg-open'
  vim.g.vimtex_view_general_options = '@pdf'
end

-- ---------- Compiler ----------
-- latexmk is what makes this "hot reload": `-pvc` (preview continuously) keeps
-- watching the source files and rebuilds on every write, and it runs LaTeX as
-- many times as needed to settle references/citations/TOC.
vim.g.vimtex_compiler_method = 'latexmk'
vim.g.vimtex_compiler_latexmk = {
  continuous = 1, -- the `-pvc` watch loop (this is what you want; it is also the default)
  aux_dir = '.aux', -- keep .aux/.fls/.fdb_latexmk clutter out of the way...
  out_dir = '', -- ...but leave the PDF next to the .tex so it's easy to find
  options = {
    '-verbose',
    '-file-line-error', -- error format VimTeX can parse into the quickfix list
    '-synctex=1', -- required for jumping between editor and PDF
    '-interaction=nonstopmode', -- never block waiting for input on an error
  },
}

-- Open the viewer automatically after the first successful compile. This is
-- VimTeX's own mechanism (it hooks `User VimtexEventCompileSuccess`), and it is
-- the only reliable way to sequence "compile, then view": the PDF does not
-- exist until latexmk finishes, and a first cold build can take many seconds.
vim.g.vimtex_view_automatic = 1

-- ---------- Diagnostics / quickfix ----------
-- 0 = build the quickfix list but never steal focus by popping it open.
-- Real diagnostics come from texlab (configured in init.lua's `servers` table)
-- and show up inline like any other LSP; use `<leader>q` for the full list.
vim.g.vimtex_quickfix_mode = 0
-- Hide the noisiest LaTeX warnings that are almost never actionable.
vim.g.vimtex_quickfix_ignore_filters = {
  'Underfull \\\\hbox',
  'Overfull \\\\hbox',
  'LaTeX Warning: .\\+ float specifier changed to',
  'Package hyperref Warning: Token not allowed in a PDF string',
}

-- ---------- Editing ----------
vim.g.vimtex_indent_enabled = 1
vim.g.vimtex_syntax_conceal_disable = 0 -- conceal $\alpha$ as α etc. in insert-normal
vim.g.tex_flavor = 'latex' -- treat ambiguous .tex files as LaTeX, not plain TeX

vim.pack.add { { src = 'https://github.com/lervag/vimtex' } }

-- ---------- Convenience ----------
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'tex', 'plaintex' },
  group = vim.api.nvim_create_augroup('custom-vimtex', { clear = true }),
  callback = function(event)
    -- Prose settings: wrap at the window edge and move by screen line.
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.keymap.set({ 'n', 'x' }, 'j', "v:count == 0 ? 'gj' : 'j'", { buffer = event.buf, expr = true })
    vim.keymap.set({ 'n', 'x' }, 'k', "v:count == 0 ? 'gk' : 'k'", { buffer = event.buf, expr = true })

    -- One key to "start the live preview": compile continuously, then show the PDF.
    -- `lp` is unused by VimTeX's own <localleader>l… mappings, so this slots in
    -- alongside them rather than shadowing one.
    --
    -- Do NOT try to sequence this with a timer. `:VimtexView` refuses to run
    -- until the PDF is readable ("Viewer cannot read PDF file!"), and a cold
    -- first build routinely takes longer than any delay you'd care to hardcode.
    -- Instead: if the PDF is already there, show it now; otherwise start the
    -- compiler and let `vimtex_view_automatic` open the viewer when the build
    -- actually lands.
    vim.keymap.set('n', '<localleader>lp', function()
      local state = vim.b.vimtex
      if not state then
        vim.notify('VimTeX has not initialised for this buffer', vim.log.levels.WARN)
        return
      end

      -- VimTeX identifies the "main" document by looking for `\documentclass`.
      -- If it finds none anywhere it falls back to the current file and the
      -- compile then dies with "failed mainfile detection", which reads like a
      -- multi-file project problem and isn't. Say what's actually wrong.
      if state.main_parser == 'fallback current file' then
        vim.notify(
          'No \\documentclass found — this is a LaTeX fragment, not a document.\n'
            .. 'Wrap it in \\documentclass{article} … \\begin{document} … \\end{document}.',
          vim.log.levels.WARN
        )
        return
      end

      local ok, out = pcall(vim.fn.eval, 'b:vimtex.compiler.get_file("pdf")')
      local pdf = (ok and out) or ''

      -- `:VimtexCompile` is a toggle, so only start it when it isn't running.
      local running = select(2, pcall(vim.fn.eval, 'b:vimtex.compiler.is_running()'))
      if running ~= 1 then
        vim.cmd 'VimtexCompile'
      end

      if pdf ~= '' and vim.fn.filereadable(pdf) == 1 then
        vim.cmd 'VimtexView'
      end
    end, { buffer = event.buf, desc = 'LaTeX: start live [P]review (compile + view)' })

    -- One-time health check: Fedora's texlive packages don't always run
    -- `updmap-sys`, and without `pdftex.map` every build silently falls back to
    -- generating bitmap (pk) fonts -- slow first compiles and fuzzy PDFs.
    if vim.g._custom_texmap_checked == nil then
      vim.g._custom_texmap_checked = true
      vim.system({ 'kpsewhich', 'pdftex.map' }, { text = true }, function(res)
        if res.code ~= 0 then
          vim.schedule(function()
            vim.notify('LaTeX font maps are missing (no pdftex.map).\nRun: sudo updmap-sys', vim.log.levels.WARN)
          end)
        end
      end)
    end

    -- Label the VimTeX mapping prefix in which-key so `<space>l` is discoverable.
    pcall(function() require('which-key').add { { '<localleader>l', group = '[L]aTeX (VimTeX)', buffer = event.buf } } end)
  end,
})
