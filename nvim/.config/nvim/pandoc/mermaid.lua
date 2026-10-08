--[[
  Pandoc Lua filter: render ```mermaid fences to vector PDF via mermaid-cli.

  Why a filter and not `mermaid-filter` from npm:
    * mermaid-filter shells out to a fresh headless Chromium for EVERY diagram on
      EVERY run. With a preview that re-renders on each :w that is 2-5s of lag per
      save. This filter content-hashes each diagram and only re-renders the ones
      that actually changed, so an unchanged doc costs zero Chromium launches.
    * It writes its temp files into the current directory; this one keeps them in
      the XDG cache.

  Failure behaviour is deliberate: if mmdc is missing or errors, the original code
  block is left untouched and a warning goes to stderr. A broken diagram degrades
  to visible source text -- it never fails the whole PDF build.

  Env vars (set by the markdown-pdf plugin, all optional):
    MERMAID_MMDC        path to mmdc            (default: 'mmdc' on PATH)
    MERMAID_THEME       mermaid theme           (default: 'neutral')
    MERMAID_BACKGROUND  diagram background      (default: 'white')
    MERMAID_CACHE       cache directory         (default: $XDG_CACHE_HOME/...)
--]]

-- Bump to invalidate every cached diagram after changing render settings below.
local CACHE_VERSION = '1'

local function env(name, fallback)
  local v = os.getenv(name)
  if v == nil or v == '' then return fallback end
  return v
end

local HOME = env('HOME', '')
local CONFIG_DIR = HOME .. '/.config/nvim/pandoc'

local MMDC = env('MERMAID_MMDC', 'mmdc')
local THEME = env('MERMAID_THEME', 'neutral')
local BACKGROUND = env('MERMAID_BACKGROUND', 'white')
local CACHE = env('MERMAID_CACHE', env('XDG_CACHE_HOME', HOME .. '/.cache') .. '/nvim-markdown-pdf/mermaid')

local MERMAID_CONFIG = CONFIG_DIR .. '/mermaid-config.json'
local PUPPETEER_CONFIG = CONFIG_DIR .. '/mermaid-puppeteer.json'

local function exists(path)
  local fh = io.open(path, 'r')
  if fh then fh:close() return true end
  return false
end

local warned = false
local function warn(msg)
  io.stderr:write('[mermaid.lua] ' .. msg .. '\n')
end

--- Render `code` to `out` (a .pdf path). Returns true on success.
local function render(code, out)
  local mmd = out:gsub('%.pdf$', '.mmd')
  local fh, err = io.open(mmd, 'w')
  if not fh then
    warn('cannot write ' .. mmd .. ': ' .. tostring(err))
    return false
  end
  fh:write(code, '\n')
  fh:close()

  local args = {
    '--input', mmd,
    '--output', out,
    '--theme', THEME,
    '--backgroundColor', BACKGROUND,
    -- Crop the PDF page to the drawing instead of emitting a full A4 sheet with
    -- the diagram marooned in the top-left corner.
    '--pdfFit',
    '--quiet',
  }
  if exists(MERMAID_CONFIG) then
    table.insert(args, '--configFile')
    table.insert(args, MERMAID_CONFIG)
  end
  if exists(PUPPETEER_CONFIG) then
    table.insert(args, '--puppeteerConfigFile')
    table.insert(args, PUPPETEER_CONFIG)
  end

  -- pandoc.pipe execs directly (no shell), so nothing here needs quoting.
  local ok, perr = pcall(pandoc.pipe, MMDC, args, '')
  if not ok then
    warn('mmdc failed: ' .. tostring(perr))
    os.remove(mmd)
    return false
  end
  if not exists(out) then
    warn('mmdc reported success but produced no file: ' .. out)
    return false
  end
  os.remove(mmd)
  return true
end

function CodeBlock(block)
  if not block.classes:includes('mermaid') then return nil end

  if not warned and not exists(CACHE) then
    pandoc.system.make_directory(CACHE, true)
  end

  local key = pandoc.utils.sha1(table.concat({ CACHE_VERSION, THEME, BACKGROUND, block.text }, '\0'))
  local out = CACHE .. '/' .. key .. '.pdf'

  if not exists(out) then
    if not render(block.text, out) then
      warned = true
      return nil -- leave the fence as literal text; the document still builds
    end
  end

  local caption = block.attributes['caption']

  if FORMAT:match('latex') then
    -- adjustbox's `max size` caps BOTH dimensions without upscaling a small
    -- diagram. Width alone is not enough: a tall graph scaled to \linewidth
    -- can exceed \textheight and overflow the page bottom.
    local tex = '\\begin{center}\n\\includegraphics[max size={\\linewidth}{0.75\\textheight}]{'
      .. out .. '}\n\\end{center}'
    if caption then
      return pandoc.Div({
        pandoc.RawBlock('latex', tex),
        pandoc.Para(pandoc.Emph(pandoc.Str(caption))),
      })
    end
    return pandoc.RawBlock('latex', tex)
  end

  local img = pandoc.Image(caption and pandoc.Str(caption) or {}, out)
  return pandoc.Para({ img })
end
