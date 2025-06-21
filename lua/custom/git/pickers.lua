local M = {}

local fns = require("custom.git.picker_fns")
local utils = require("custom.git.utils")

local wide_layout_with_wrap = {
  layout = {
    box = "vertical", -- stack children top→bottom
    border = "rounded",
    height = 0.8,
    width = 0.8,
    {
      win = "input",
      height = 1,
      border = "bottom",
    },
    {
      win = "list",
      height = 0.4, -- exactly two rows tall
      border = "bottom", -- optional separator
    },
    {
      on_win = function(win)
        vim.api.nvim_set_option_value("wrap", true, { scope = "local", win = win.win })
        -- TODO: figure out why this does not work
        vim.api.nvim_set_option_value("number", false, { scope = "local", win = win.win })
        vim.api.nvim_set_option_value("relativenumber", false, { scope = "local", win = win.win })
      end,
      win = "preview",
      -- no height ⇒ whatever is left
    },
  },
}

M.issue_picker = function()
  Snacks.picker({
    finder = fns.fetch_issues,
    format = fns.format_issue_row,
    preview = fns.preview_issue,
    confirm = function(picker, item)
      picker:close()
      -- open the browser for the selected issue using gh cli
      vim.fn.jobstart({ "gh", "issue", "view", item.number, "--web" })
    end,
    layout = wide_layout_with_wrap,
  })
end

M.notification_picker = function()
  Snacks.picker({
    finder = fns.fetch_notifications,
    format = fns.format_notification_row,
    layout = {
      layout = {
        box = "vertical", -- stack children top→bottom
        border = "rounded",
        height = 0.8,
        width = 0.8,
        {
          win = "input",
          height = 1,
          border = "bottom",
        },
        {
          win = "list",
        },
      },
    },
    confirm = function(picker, item)
      picker:close()
      local url = vim.fn.system({
        "gh",
        "api",
        item.api_url,
        "--jq",
        ".html_url",
      })
      url = vim.trim(url) -- remove trailing newline
      if url == "" then
        vim.notify("Failed to fetch URL for notification: " .. item.title, vim.log.levels.ERROR)
        return
      end
      vim.ui.open(url)
    end,
  })
end

-- TODO: <S-CR> should open in browser
M.pr_picker = function()
  Snacks.picker({
    layout = wide_layout_with_wrap,
    win = {
      input = {
        keys = {
          ["<S-CR>"] = { "browse", desc = "Open PR in browser", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["<S-CR>"] = { "browse", desc = "Open PR in browser", mode = { "n", "i" } },
        },
      },
    },
    actions = {
      browse = function(picker, pr)
        picker:close()
        -- open the browser for the selected PR using gh cli
        vim.fn.jobstart({ "gh", "pr", "view", pr.number, "--web" })
      end,
    },
    finder = fns.fetch_prs,
    format = fns.format_pr_row,
    preview = fns.preview_pr,
    confirm = function(picker, pr)
      picker:close()
      vim.notify("Checking out PR #" .. pr.number .. " and opening in DiffView.")
      utils.confirm_stash_uncommitted_changes_before_op("Checking out PR #" .. pr.number .. ".", function()
        -- 4) Use `gh pr checkout <N> --force`
        vim.fn.jobstart({ "gh", "pr", "checkout", pr.number, "--force" }, {
          on_exit = function()
            vim.schedule(function()
              vim.notify("Checked out PR #" .. pr.number)
              require("custom.git.diff").fetch_and_diff(pr.baseRefName)
            end)
          end,
        })
      end)
    end,
  })
end

M.diff_picker = function(base_branch, head)
  Snacks.picker({
    finder = fns.custom_diff,
    format = "file",
    preview = "diff",
    base = base_branch,
    head = head,
  })
end

return M
