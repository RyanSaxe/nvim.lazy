-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- local opts = { noremap = true, silent = true }

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "move lines down in visual selection" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "move lines up in visual selection" })
-- make escape go to normal mode when in a terminal
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { silent = true, desc = "Terminal: go to Normal mode" })

-- TODO: set up full different set of git toggles
-------------------------------------------------------------------------------
-- 1) <leader>tg: “Toggle Diffview (fetch & diff against remote default HEAD)”
--    When no arguments are given, we treat head_refName = "HEAD".
-------------------------------------------------------------------------------
local diff = require("custom.git.diff")
vim.keymap.set("n", "<leader>tg", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    -- pass base_refName = nil (so it falls back to origin/<default>),
    diff.toggle_diffview(nil)
  end
end, {
  desc = "Toggle Diffview (fetch & diff against remote HEAD)",
})

-------------------------------------------------------------------------------
-- 2) <leader>tG: prompt for a base branch name, then toggle Diffview.
--    Again, head_refName = "HEAD".
-------------------------------------------------------------------------------
vim.keymap.set("n", "<leader>tG", function()
  if diff.is_diffview_open() then
    vim.cmd("DiffviewClose")
  else
    vim.ui.input({ prompt = "Base branch (empty for default): " }, function(input)
      -- `input` may be nil or "" if <Esc> or blank
      --
      -- Treat any non-empty string as the “base_refName” and
      -- always use head_refName = "HEAD" here.
      local base = (input ~= nil and input ~= "") and input or nil
      diff.toggle_diffview(base)
    end)
  end
end, {
  desc = "Toggle Diffview (fetch & diff against a specified branch)",
})

-- LSP related toggles
-- NOTE: consider extending this to other LSP servers as needed
-- NOTE: consider extensind to other types of analysis settings like type checking strictness
-- TODO: look into seeing if sonarlint can also be executed workspace wide
local function toggle_pyright_diagnostic_mode()
  local clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf(), name = "basedpyright" })
  if vim.tbl_isempty(clients) then
    vim.notify("basedpyright isn’t attached here", vim.log.levels.WARN)
    return
  end

  for _, client in ipairs(clients) do
    local cfg = client.config.settings or {}

    if type(cfg.basedpyright) ~= "table" then
      cfg.basedpyright = {}
    end
    if type(cfg.basedpyright.analysis) ~= "table" then
      cfg.basedpyright.analysis = {}
    end

    local current = cfg.basedpyright.analysis.diagnosticMode or "openFilesOnly"
    local next_mode = (current == "openFilesOnly") and "workspace" or "openFilesOnly"

    cfg.basedpyright.analysis.diagnosticMode = next_mode

    client.config.settings = cfg

    client.notify("workspace/didChangeConfiguration", { settings = nil })
    -- vim.cmd("LspRestart basedpyright")

    vim.notify(("basedpyright diagnosticMode → %s"):format(next_mode), vim.log.levels.INFO)
  end
end

vim.keymap.set("n", "<leader>tp", toggle_pyright_diagnostic_mode, { desc = "Toggle basedpyright diagnosticMode" })

-- some code that I might use for searching python packages -- but since go to def is so good I probably don't need it
-- local get_python_package_dir = function()
--   local venv_path = os.getenv("VIRTUAL_ENV")
--   if not venv_path then
--     vim.notify("Could not determine Python VIRTUAL_ENV.", vim.log.levels.WARN)
--     return nil
--   end
-- local site_packages_path = venv_path .. "/lib/python" .. vim.fn.matchstr(vim.fn.system("python -c 'import sys; print(sys.version_info.major)'"), "%d") .. "/site-packages"
--   return site_packages_path
-- end
--
-- local get_all_available_python_packages = function()
--   local site_packages_path = get_python_package_dir()
--   if not site_packages_path then
--     return {}
--   end
--
--   local packages = {}
--   for _, dir in ipairs(vim.fn.readdir(site_packages_path)) do
--     if vim.fn.isdirectory(site_packages_path .. "/" .. dir) == 1 then
--       table.insert(packages, dir)
--     end
--   end
--   return packages
-- end
