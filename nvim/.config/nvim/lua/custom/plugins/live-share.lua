-- ============================================================
-- live-share.nvim: real-time collaborative editing (pair programming)
-- ============================================================
--
-- IMPORTANT -- read this before telling anyone to "join my Live Share":
--
-- This is NOT Microsoft's Visual Studio Live Share. That protocol is closed,
-- tied to a Microsoft/GitHub account, and has no Neovim client -- you cannot
-- join a `prod.liveshare.vsengsaas.visualstudio.com/join?...` link from here.
--
-- What this *is*: an open, editor-independent collaboration protocol. A VS Code
-- user can join a session hosted from this Neovim, but they must install the
-- "Open Pair" extension (publisher: darkerthanblack2000), NOT the Microsoft
-- Live Share extension:
--
--     ext install darkerthanblack2000.open-pair
--
-- Both directions are supported: Neovim host + VS Code guest, and VS Code host
-- + Neovim guest.
--
-- Workflow (hosting):
--   1. `<leader>cs` or `:LiveShareHostStart` -- opens an SSH reverse tunnel and
--      copies the share URL to your clipboard.
--   2. Paste that URL to the other person. They run Open Pair's join command
--      (VS Code) or `:LiveShareJoin <url>` (Neovim).
--   3. You get a `vim.ui.select` prompt to approve or reject each guest.
--   4. `<leader>cq` or `:LiveShareStop` when you're done.
--
-- Requires (all already present on this machine):
--   ssh       -- builds the reverse tunnel to the relay
--   openssl   -- libcrypto.so.3, for the end-to-end encryption
--   wl-copy   -- so the share URL lands in the Wayland clipboard

vim.pack.add { { src = 'https://github.com/azratul/live-share.nvim' } }

require('live-share').setup {
  -- Shown to other participants next to your cursor. Change this to whatever
  -- you want people to see; $USER is just a safe default.
  username = vim.env.USER or 'nvim',

  -- Transport. Two choices:
  --   'ws'    -- WebSocket over TCP through a public relay. Works everywhere,
  --             including behind corporate NAT/firewalls. This is the default
  --             and what you want unless you have a reason otherwise.
  --   'punch' -- direct peer-to-peer UDP with NAT hole-punching. Lower latency,
  --             no third party in the path, but it needs the `punch` luarocks
  --             library (>= 0.3.2, luarocks is NOT installed here) and is only
  --             tested on Linux -- so it would break a Windows guest.
  transport = 'ws',

  -- The relay that gives you a public URL. 'nokey@localhost.run' is the one
  -- default that needs no account and no SSH key registration -- it accepts an
  -- anonymous connection, which is why it's the sane starting point.
  -- Alternatives: 'serveo.net', 'localhost.run', 'ngrok' (ngrok is not
  -- installed here and would need an authtoken).
  service = 'nokey@localhost.run',

  -- Local port the collaboration server binds to. Only ever reached through
  -- the tunnel, so this is just "some free port on loopback".
  port_internal = 9876,

  -- Port on the *public* URL side. 80 is what localhost.run hands out.
  port = 80,

  -- How long to wait for the tunnel to come up, in ~250ms ticks. Bump this if
  -- you're on a slow link and hosting times out before the URL appears.
  max_attempts = 40,

  -- Root of the shared file tree. nil = Neovim's cwd at the moment you start
  -- hosting, which is almost always the project you're in. Set it explicitly
  -- only if you habitually launch nvim from $HOME -- see the warning below.
  workspace_root = nil,

  -- Where the plugin stashes the generated URL. Leave as-is.
  service_url = '/tmp/service.url',

  -- nil = autodetect libcrypto. Fedora keeps it at /usr/lib64/libcrypto.so.3,
  -- which autodetect finds. If you ever see an "openssl library not found"
  -- error after a system upgrade, hardcode the path here.
  openssl_lib = nil,

  -- Flip to true and check `:messages` if a session won't establish.
  debug = false,
}

-- ---------- Keymaps ----------
-- `<leader>c` for [C]ollab. It was the only unused single letter in this config
-- (s/t/h/f/m/q are taken), so nothing here shadows an existing mapping.
local map = function(lhs, rhs, desc) vim.keymap.set('n', lhs, rhs, { desc = desc }) end

map('<leader>cs', '<cmd>LiveShareHostStart<cr>', 'Collab: [S]tart hosting (URL to clipboard)')
map('<leader>cq', '<cmd>LiveShareStop<cr>', 'Collab: [Q]uit session')
map('<leader>cp', '<cmd>LiveSharePeers<cr>', 'Collab: list [P]eers')
map('<leader>ct', '<cmd>LiveShareTerminal<cr>', 'Collab: shared [T]erminal')

-- Joining takes a URL argument, so prompt for it rather than pretending a
-- bare `<cmd>LiveShareJoin<cr>` would work.
map('<leader>cj', function()
  vim.ui.input({ prompt = 'Live Share URL: ' }, function(url)
    if url and url ~= '' then vim.cmd('LiveShareJoin ' .. vim.trim(url)) end
  end)
end, 'Collab: [J]oin a session by URL')

pcall(function() require('which-key').add { { '<leader>c', group = '[C]ollab (live-share)' } } end)

-- ---------- Safety note ----------
-- Anyone holding the share URL can request to join; the *only* gate is you
-- approving the prompt. There is no password and no account check. So:
--   * Don't paste the URL anywhere public.
--   * Start hosting from the project directory, not from $HOME -- with
--     `workspace_root = nil` the guest sees your cwd tree, and hosting from
--     $HOME would offer up ~/.ssh and every dotfile you own.
--   * `:LiveShareStop` when you're finished; the tunnel stays open otherwise.
--
-- Known rough edges (upstream, not fixable here): simultaneous edits to the
-- same line resolve last-write-wins and one edit is silently lost; syncing a
-- very large workspace is slow because the full file list is sent up front;
-- a guest reconnecting resets shared-terminal state.
