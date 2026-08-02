-- ============================================================
-- Markdown -> PDF live preview (pandoc + auto-reloading PDF viewer)
-- ============================================================
--
-- Workflow:
--   1. Open and save a .md file.
--   2. `:MarkdownPdf` (or `<leader>mp`) -- renders it to a PDF next to the
--      source and opens your PDF viewer.
--   3. Every `:w` re-renders. The viewer notices the file changed and reloads,
--      so the preview tracks what you type as fast as you save.
--   4. `:MarkdownPdfStop` (or `<leader>ms`) stops watching.
--
-- Why not a browser-based previewer? You asked for a PDF, and pandoc's LaTeX
-- output is the same pipeline that renders the .tex files above -- so a
-- markdown doc and a LaTeX doc come out looking consistent.
--
-- Requires: pandoc + a LaTeX engine (xelatex) + a PDF viewer.
-- Tunables (set in init.lua before this loads, or with :lua):
--   vim.g.markdown_pdf_engine   -- default 'xelatex'
--   vim.g.markdown_pdf_args     -- table of extra pandoc args, replaces the defaults
--   vim.g.markdown_pdf_viewer   -- default: first of zathura / okular / xdg-open

local M = {}

--- Per-buffer preview state, keyed by bufnr.
--- @type table<integer, { source: string, pdf: string, tmp: string, viewer: vim.SystemObj?, running: boolean, pending: boolean }>
local sessions = {}

local augroup = vim.api.nvim_create_augroup('custom-markdown-pdf', { clear = true })

local function notify(msg, level) vim.notify('[markdown-pdf] ' .. msg, level or vim.log.levels.INFO) end

--- Pick a PDF viewer that reloads when the file on disk changes.
--- zathura and okular both watch the file; xdg-open delegates to whatever is
--- registered for application/pdf and may not reload.
local function find_viewer()
  if vim.g.markdown_pdf_viewer then return vim.g.markdown_pdf_viewer end
  for _, candidate in ipairs { 'zathura', 'okular' } do
    if vim.fn.executable(candidate) == 1 then return candidate end
  end
  return 'xdg-open'
end

local function pandoc_args(source, target)
  local extra = vim.g.markdown_pdf_args
    or {
      '--pdf-engine=' .. (vim.g.markdown_pdf_engine or 'xelatex'),
      '--from=markdown+yaml_metadata_block+tex_math_dollars+pipe_tables+task_lists',
      '--highlight-style=tango', -- syntax highlighting for fenced code blocks
      '--toc-depth=3',
      '-V',
      'geometry:margin=1in',
      '-V',
      'linkcolor=blue',
      '-V',
      'colorlinks=true',
    }
  local args = { 'pandoc', source, '-o', target, '--standalone' }
  vim.list_extend(args, extra)
  return args
end

--- Render `session.source` to a temp file, then atomically move it into place.
--- Rendering straight to the final path would let the viewer pick up a
--- half-written PDF and flash an error; rename(2) on the same filesystem is atomic.
local function render(bufnr, on_first_success)
  local session = sessions[bufnr]
  if not session then return end

  if session.running then
    session.pending = true -- coalesce writes that land mid-build
    return
  end
  session.running = true

  vim.system(pandoc_args(session.source, session.tmp), { text = true, cwd = vim.fs.dirname(session.source) }, function(result)
    vim.schedule(function()
      session.running = false

      if result.code ~= 0 then
        vim.fn.delete(session.tmp)
        local err = vim.trim((result.stderr or '') ~= '' and result.stderr or (result.stdout or 'pandoc failed'))
        notify('render failed:\n' .. err, vim.log.levels.ERROR)
        return
      end

      local ok, rename_err = vim.uv.fs_rename(session.tmp, session.pdf)
      if not ok then
        notify('could not replace ' .. session.pdf .. ': ' .. tostring(rename_err), vim.log.levels.ERROR)
        return
      end

      if on_first_success then on_first_success() end

      if session.pending then
        session.pending = false
        render(bufnr) -- a save arrived while we were building; rebuild once
      end
    end)
  end)
end

local function open_viewer(bufnr)
  local session = sessions[bufnr]
  if not session or session.viewer then return end

  local viewer = find_viewer()
  session.viewer = vim.system({ viewer, session.pdf }, { detach = true }, function()
    vim.schedule(function()
      if sessions[bufnr] then sessions[bufnr].viewer = nil end
    end)
  end)
  notify('previewing in ' .. viewer .. ': ' .. vim.fn.fnamemodify(session.pdf, ':~'))
end

function M.start(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local source = vim.api.nvim_buf_get_name(bufnr)
  if source == '' then return notify('save the buffer to a file first', vim.log.levels.WARN) end
  if vim.fn.executable 'pandoc' == 0 then return notify('pandoc is not installed (see DECISIONS-NVIM.md)', vim.log.levels.ERROR) end

  if sessions[bufnr] then
    render(bufnr, function() open_viewer(bufnr) end) -- already watching: just refresh
    return
  end

  local dir, name = vim.fs.dirname(source), vim.fn.fnamemodify(source, ':t:r')
  sessions[bufnr] = {
    source = source,
    pdf = vim.fs.joinpath(dir, name .. '.pdf'),
    -- Hidden, and still ends in .pdf so pandoc can infer the output format.
    tmp = vim.fs.joinpath(dir, '.' .. name .. '.md-preview.pdf'),
    running = false,
    pending = false,
  }

  vim.api.nvim_create_autocmd('BufWritePost', {
    group = augroup,
    buffer = bufnr,
    desc = 'Re-render the markdown PDF preview',
    callback = function() render(bufnr) end,
  })

  -- Writing the buffer is what the viewer reacts to, so a preview of an
  -- unsaved buffer would immediately look stale. Flush it first.
  if vim.bo[bufnr].modified then vim.cmd 'silent write' end

  notify 'rendering...'
  render(bufnr, function() open_viewer(bufnr) end)
end

function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = sessions[bufnr]
  if not session then return notify 'no preview running for this buffer' end

  vim.api.nvim_clear_autocmds { group = augroup, buffer = bufnr }
  vim.fn.delete(session.tmp)
  -- The viewer window is left open on purpose: the PDF is a real artifact you
  -- may still want to read or send to someone.
  sessions[bufnr] = nil
  notify 'preview stopped (PDF kept)'
end

vim.api.nvim_create_user_command('MarkdownPdf', function() M.start() end, { desc = 'Live-preview this markdown buffer as a PDF' })
vim.api.nvim_create_user_command('MarkdownPdfStop', function() M.stop() end, { desc = 'Stop the markdown PDF live preview' })

vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'markdown', 'markdown.mdx' },
  group = augroup,
  callback = function(event)
    -- Prose settings, matching the LaTeX ones.
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.spell = true
    vim.keymap.set({ 'n', 'x' }, 'j', "v:count == 0 ? 'gj' : 'j'", { buffer = event.buf, expr = true })
    vim.keymap.set({ 'n', 'x' }, 'k', "v:count == 0 ? 'gk' : 'k'", { buffer = event.buf, expr = true })

    vim.keymap.set('n', '<leader>mp', function() M.start(event.buf) end, { buffer = event.buf, desc = '[M]arkdown: start PDF [P]review' })
    vim.keymap.set('n', '<leader>ms', function() M.stop(event.buf) end, { buffer = event.buf, desc = '[M]arkdown: [S]top PDF preview' })

    pcall(function() require('which-key').add { { '<leader>m', group = '[M]arkdown', buffer = event.buf } } end)
  end,
})

-- Don't leave orphaned state (or a stray temp file) when the buffer goes away.
vim.api.nvim_create_autocmd({ 'BufDelete', 'VimLeavePre' }, {
  group = augroup,
  callback = function(event)
    local session = sessions[event.buf]
    if session then
      vim.fn.delete(session.tmp)
      sessions[event.buf] = nil
    end
  end,
})

return M
