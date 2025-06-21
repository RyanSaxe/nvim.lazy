-- snacks_dashboard.lua  ── custom git dashboard for Snacks.nvim

-- some random utilities the dahsboard needs that I'll probably not reuse

---@param max integer|nil
---@return string[]
local function recent_files_in_cwd(max)
  max = max or 10
  local cwd = vim.loop.cwd()
  local list = {}
  for _, abs in ipairs(vim.v.oldfiles) do
    if vim.startswith(abs, cwd) and vim.fn.filereadable(abs) == 1 then
      table.insert(list, vim.fn.fnamemodify(abs, ":.")) -- relative path
      if #list == max then
        break
      end
    end
  end
  return list
end

-- Normalize and format file paths for prettier display
---@param path string Path to normalize
---@param max_length? number Maximum display length (default: 40)
---@return string Normalized and formatted path
local function normalize_path(path, max_length)
  max_length = max_length or 40
  local normalized = vim.fs.normalize(path)

  if #normalized <= max_length then
    return normalized
  end

  -- Keep filename and truncate from the middle
  local parts = vim.split(normalized, "/")
  local filename = parts[#parts]

  if #filename >= max_length - 3 then
    return "..." .. filename:sub(-(max_length - 3))
  end

  -- Build path keeping filename and as much directory structure as possible
  local result = filename
  for i = #parts - 1, 1, -1 do
    local candidate = parts[i] .. "/" .. result
    if #candidate > max_length - 3 then
      return "..." .. result
    end
    result = candidate
  end

  return result
end

local git_pickers = require("custom.git.pickers")
local git_utils = require("custom.git.utils")
local Snacks = require("snacks")

local show_if_has_second_pane = function()
  -- taken from snacks.dashboard. Only enable this visual if snacks allows a second pane.
  local width = vim.o.columns
  local pane_width = 60 -- default ... make dynamic if configured
  local pane_gap = 4 -- default ... make dynamic if configured
  local max_panes = math.max(1, math.floor((width + pane_gap) / (pane_width + pane_gap)))
  return max_panes > 1
end

local create_pane = function(header, specs)
  local pane = header.pane
  header.padding = header.padding or 1
  header.indent = header.indent or 0

  local output = { header }
  for i, spec in ipairs(specs) do
    -- set padding on the spec itself
    spec.padding = (i == #specs) and 1 or 0

    -- start with defaults
    local row = {
      pane = pane,
      indent = 2,
    }
    -- copy all spec fields in
    for k, v in pairs(spec) do
      row[k] = v
    end

    table.insert(output, row)
  end

  return output -- ← you must return it!
end

local different_key_if_condition = function(condition, base_spec, git_spec, non_git_spec)
  if condition then
    return vim.tbl_deep_extend("force", {}, base_spec, git_spec)
  else
    return vim.tbl_deep_extend("force", {}, base_spec, non_git_spec)
  end
end
local search_keys = function()
  local cwd = vim.fn.getcwd()
  local project = vim.fn.fnamemodify(cwd, ":t")
  local header = { pane = 1, title = "Project", desc = " (" .. project .. ")" }

  local keys = {
    { icon = " ", key = "/", desc = "Grep Text", action = ":lua Snacks.dashboard.pick('live_grep')" },
    {
      icon = " ",
      desc = "Search Code TODOs",
      key = "x",
      action = function()
        Snacks.picker.todo_comments({ keywords = { "TODO", "FIX", "FIXME", "HACK", "BUG" } })
      end,
    },
    {
      icon = " ",
      desc = "Open TODO Notes",
      key = "t",
      action = function()
        Snacks.scratch.open({
          name = "TODO", -- this name makes it such that checkmate.nvim runs on this.
          ft = "markdown",
        })
      end,
    },
    {
      desc = "Open Code Scratchpad",
      icon = " ",
      key = "s",
      action = function()
        -- we ask the user to input the filetype and open a scratchpad for them

        vim.ui.input({
          prompt = "Enter filetype for scratchpad (default: python): ",
          default = "python",
        }, function(ft)
          if ft == nil or ft == "" then
            ft = "python"
          end
          Snacks.scratch.open({
            ft = ft,
          })
        end)
      end,
    },
  }

  local find_file_base = { icon = " ", key = "f", desc = "Find File" }
  table.insert(
    keys,
    different_key_if_condition(
      Snacks.git.get_root() ~= nil,
      find_file_base,
      { action = ":lua Snacks.dashboard.pick('git_files')" },
      { action = ":lua Snacks.dashboard.pick('files')" }
    )
  )

  return create_pane(header, keys)
end

local globalkeys = function()
  -- NOTE: consider the projects section that only shows up if not in a git repo
  local header = { pane = 1, title = "Global" }
  local keys = {
    {
      icon = " ",
      key = "p",
      desc = "Find Project",
      action = function()
        return Snacks.picker.projects({
          confirm = function(picker, item)
            picker:close()
            vim.api.nvim_set_current_dir(item.file)
            Snacks.dashboard.update()
          end,
        })
      end,
    },
    { icon = " ", key = "q", desc = "Quit", action = ":qa" },
    {
      icon = "󰒲 ",
      key = "l",
      desc = "Manage Lua Plugins",
      action = ":Lazy",
      enabled = package.loaded.lazy ~= nil,
    },
    { icon = " ", key = "r", desc = "Restore Session", section = "session" },
    {
      icon = " ",
      key = "c",
      desc = "Search Neovim Config",
      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})",
    },
  }

  return create_pane(header, keys)
end
local recent_project_toggle = function()
  local in_git = Snacks.git.get_root() ~= nil
  local has_two_panes = show_if_has_second_pane()
  -- if in git and has one pane, then we disable
  return not (in_git and not has_two_panes)
end
local get_recent_files = function()
  local out = {}
  local max_files = 5
  local recent_files = recent_files_in_cwd(max_files)
  local n_files = #recent_files
  local pane = Snacks.git.get_root() and 2 or 1
  local final_padding = pane == 2 and max_files - n_files + 1 or 1

  for i, rel in ipairs(recent_files) do
    out[#out + 1] = {
      pane = pane,
      icon = "󰈙 ",
      indent = 2,
      padding = (i == n_files) and final_padding or 0,
      desc = normalize_path(rel),
      key = tostring(i),
      action = function()
        vim.cmd("edit " .. rel)
      end,
      enabled = recent_project_toggle,
    }
  end
  if #out == 0 then
    out[1] = {
      pane = pane,
      icon = " ",
      desc = "No recent files in this directory",
      padding = pane == 2 and max_files or 1,
      enabled = recent_project_toggle,
    }
  end
  return out
end

local create_sections = function()
  local base_branch = git_utils.get_base_branch()
  local current_branch = git_utils.get_current_branch()
  local recent_files = get_recent_files()
  return {

    search_keys,
    {
      title = "Recent Project Files",
      pane = Snacks.git.get_root() and 2 or 1,
      indent = 0,
      padding = 1,
      enabled = recent_project_toggle,
    },
    recent_files,
    {
      pane = 1,
      title = "Git",
      desc = string.format(" (%s)", current_branch:gsub("\n", "")),
      indent = 0,
      padding = 1,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      desc = "Checkout Another Branch",
      key = "b",
      action = function()
        Snacks.picker.git_branches({
          all = true,
          confirm = function(picker, item)
            picker:close()
            git_utils.checkout_branch(item.branch)
            Snacks.dashboard.update()
          end,
        })
      end,
      enabled = Snacks.git.get_root() ~= nil,
      indent = 2,
    },
    {
      pane = 1,
      icon = " ",
      desc = string.format("Search Diff vs %s", base_branch),
      key = "d",
      indent = 2,
      action = function()
        git_pickers.diff_picker(base_branch)
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      indent = 2,
      desc = "Search Un-Commited Changes",
      key = "u",
      action = function()
        Snacks.picker.git_status()
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      desc = "Open LazyGit UI",
      key = "g",
      indent = 2,
      action = function()
        Snacks.lazygit({ cwd = LazyVim.root.git() })
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      indent = 2,
      -- 58 ticks is exactly the size of a line (width 60, indent = 2)
      title = "----------------------------------------------------------",
      enabled = Snacks.git.get_root() ~= nil,
    },

    {
      pane = 1,
      icon = " ",
      desc = "Search Recent Notifications",
      key = "N",
      indent = 2,
      action = function()
        vim.notify("Fetching Notifications from GitHub...")
        vim.defer_fn(git_pickers.notification_picker, 100)
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      desc = "Search Pull Requests",
      indent = 2,
      key = "P",
      action = function()
        vim.notify("Fetching open PRs from GitHub...")
        vim.defer_fn(git_pickers.pr_picker, 100)
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      desc = "Search Issues",
      key = "I",
      indent = 2,
      action = function()
        vim.notify("Fetching open issues from GitHub...")
        vim.defer_fn(git_pickers.issue_picker, 100)
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    {
      pane = 1,
      icon = " ",
      desc = "Open Repo in GitHub",
      padding = 1,
      key = "B",
      indent = 2,
      action = function()
        Snacks.gitbrowse()
      end,
      enabled = Snacks.git.get_root() ~= nil,
    },
    -- hotkeys,
    globalkeys,
    -- if snorlax is being shown and there is no git operations, then the recent files move to the
    -- first pane, and snorlax needs to be padded according to the number of lines in recent files
    {
      pane = 2,
      enabled = function()
        return show_if_has_second_pane() and Snacks.git.get_root() == nil
      end,
      padding = #recent_files / 2,
    },
    {
      pane = 2,
      section = "terminal",
      -- the commented out command below will have an animated ascii aquarium
      -- cmd = 'curl "http://asciiquarium.live?cols=$(tput cols)&rows=$(tput lines)"',
      -- NOTE: for some reason, sleep 10 makes it never flicker, but also only causes a 1 second pause
      cmd = "pokemon-colorscripts -n snorlax -s --no-title; sleep 0.01",
      ttl = math.huge, -- make the cache last forever so the 1 second pause is only the first time opening a project
      indent = 10,
      -- 21 is the exact number of lines to make right and left bar aligned
      height = 21,
      enabled = show_if_has_second_pane,
    },
  }
end
-- I like when search basically take the entire screen. Makes it much easier to see previews.
-- though I don't use this right now --- need to clean up code later
local full_layout = {
  layout = {
    box = "vertical", -- stack children top→bottom
    border = "rounded",
    height = 0.99,
    width = 0.99,
    {
      win = "input",
      height = 1,
      border = "bottom",
    },
    {
      win = "list",
      height = 0.33, -- exactly two rows tall
      border = "bottom", -- optional separator
    },
    {
      win = "preview",
      -- no height ⇒ whatever is left
    },
  },
}
return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    dependencies = { "ibhagwan/fzf-lua", "folke/todo-comments.nvim" },
    opts = {
      dashboard = {
        -- this is separated into a function so that the dashboard update can redraw it on .update()
        sections = create_sections,
        layout = { anchor = "center" },
      },
      -- picker = {
      --   layout = full_layout,
      -- },
    },
  },
}
