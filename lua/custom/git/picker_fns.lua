local M = {}

function M.fetch_prs()
  local fields = table.concat({
    "number",
    "title",
    "author",
    "headRefName",
    "baseRefName",
    "isDraft",
    "labels",
    "files",
    "body",
    -- uncomment below and figure out how to determine if a PR has serious issues
    -- "mergeable",
    -- "statusCheckRollup",
  }, ",")

  local json_lines = vim.fn.systemlist({
    "gh",
    "pr",
    "list",
    "--state",
    "open",
    "--json",
    fields,
    "--jq",
    ".[] | @json",
  })

  local prs = {}
  for _, line in ipairs(json_lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if ok then
      -- copy only what we need (keep path + counts)
      local files = {}
      for _, f in ipairs(obj.files or {}) do
        files[#files + 1] = {
          path = f.path,
          additions = f.additions or 0,
          deletions = f.deletions or 0,
        }
      end

      prs[#prs + 1] = {
        number = obj.number,
        title = obj.title,
        author = obj.author and obj.author.login or "",
        head = obj.headRefName,
        base = obj.baseRefName,
        draft = obj.isDraft,
        labels = vim.tbl_map(function(l)
          return l.name
        end, obj.labels or {}),
        files = files,
        body = obj.body or "",
        file = "~/.config/nvim/init.lua",
        text = obj.body or "",  -- will be set in formatter
      }
    end
  end
  return prs
end


---@param item   table   -- the PR item your finder produced
---@param picker table   -- Snacks passes the current picker object
---@return snacks.picker.Highlight[]
function M.format_pr_row(item, picker)
  local a = Snacks.picker.util.align
  local ret = {} ---@type snacks.picker.Highlight[]
  -- green means open PR, dimmed means draft PR
  ret[#ret + 1] = {
    a("#" .. tostring(item.number or 0), 6, { truncate = true }),
    item.draft and "SnacksIndent" or "SnacksIndent3",
  }

  ret[#ret + 1] = {
    a(item.author or "<unknown>", 15, { truncate = true }),
    "SnacksIndent5",
  }

  local branch = (item.head and item.base) and (item.head .. "→" .. item.base) or ""
  ret[#ret + 1] = {
    a(branch, 20, { truncate = true }),
    "SnacksPickerIdx",
  }

  ret[#ret + 1] = { " " }
  ret[#ret + 1] = {
    item.title or "<no title>",
    "SnacksIndent4",
  }

  if item.labels and #item.labels > 0 then
    ret[#ret + 1] = { " [" .. table.concat(item.labels, ", ") .. "]", "SnacksIndent8" }
  end

  if item.files and #item.files > 0 then
    local paths = vim.tbl_map(function(f)
      if type(f) == "table" then
        return f.path
      end
      return tostring(f)
    end, item.files)
    ret[#ret + 1] = {
      " (" .. table.concat(paths, ", ") .. ")",
      "SnacksIndent1",
    }
  end

  -- Make the row fuzzy-searchable -- this is why we add the files from the diff
  item.text = table.concat(
    vim.tbl_map(function(seg)
      return seg[1]
    end, ret),
    ""
  )

  return ret
end

-- TODO: figure out how to have this preview window have text wrap
---@param ctx snacks.picker.preview.ctx
function M.preview_pr(ctx)
  local pr = ctx.item or {}
  pr.files = pr.files or {}
  pr.labels = pr.labels or {}

  local lines = {}

  -- Title
  lines[#lines + 1] = "# PR #" .. (pr.number or 0) .. ": " .. (pr.title or "")
  lines[#lines + 1] = ""

  -- Metadata
  lines[#lines + 1] = "## Metadata"
  local function meta(label, value)
    if value and value ~= "" then
      lines[#lines + 1] = "- **" .. label .. "**: " .. value
    end
  end

  meta("Author", pr.author)
  if pr.head and pr.base then
    meta("Branch", pr.head .. " → " .. pr.base)
  end
  if #pr.labels > 0 then
    meta("Labels", table.concat(pr.labels, ", "))
  end
  if pr.draft then
    meta("Draft", "Yes")
  end

  -- Description
  lines[#lines + 1] = ""
  lines[#lines + 1] = "## Description"
  lines[#lines + 1] = (pr.body and pr.body ~= "" and pr.body) or "_No description provided_"

  -- Files changed
  if #pr.files > 0 then
    local add_sum, del_sum = 0, 0
    for _, f in ipairs(pr.files) do
      add_sum = add_sum + (f.additions or 0)
      del_sum = del_sum + (f.deletions or 0)
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(
      "## Files changed: %d file%s | +%d −%d",
      #pr.files,
      (#pr.files == 1 and "" or "s"),
      add_sum,
      del_sum
    )
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```diff"

    for _, f in ipairs(pr.files) do
      -- Decide prefix so diff coloring shows additions, deletions, or mixed
      local prefix = (f.additions or 0) > 0 and (f.deletions or 0) == 0 and "+"
        or (f.deletions or 0) > 0 and (f.additions or 0) == 0 and "-"
        or " "
      lines[#lines + 1] = string.format("%s %s | +%d −%d", prefix, f.path, f.additions or 0, f.deletions or 0)
    end

    lines[#lines + 1] = "```"
  end

  -- Render into the preview buffer with Markdown + diff coloring
  ctx.preview:set_lines(lines)
  ctx.preview:highlight({ ft = "markdown" })
end
-- GitHub Issues picker ----------------------------------
-- Add these functions below your existing PR picker code, before the final `return M`

--- Fetch open issues from GitHub using the `gh` CLI
function M.fetch_issues()
  local fields = table.concat({
    "number",
    "title",
    "author",
    "state",
    "labels",
    "body",
  }, ",")

  local json_lines = vim.fn.systemlist({
    "gh",
    "issue",
    "list",
    "--state",
    "open",
    "--json",
    fields,
    "--jq",
    ".[] | @json",
  })

  local issues = {}
  for _, line in ipairs(json_lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if not ok then goto continue end

    -- Simplify labels
    local labels = vim.tbl_map(function(l)
      return l.name
    end, obj.labels or {})

    issues[#issues + 1] = {
      number = obj.number,
      title  = obj.title,
      author = obj.author and obj.author.login or "",
      state  = obj.state,
      labels = labels,
      body   = obj.body or "",
      text   = obj.body or "",  -- will be set in formatter
    }
    ::continue::
  end

  return issues
end


--- Format one issue row for the picker
---@param item   table   -- the Issue item
---@param picker table   -- Snacks.picker instance
---@return snacks.picker.Highlight[]
function M.format_issue_row(item, picker)
  local a = Snacks.picker.util.align
  local ret = {} ---@type snacks.picker.Highlight[]

  -- Issue number
  ret[#ret + 1] = { a("#" .. tostring(item.number), 6, { truncate = true }), "SnacksIndent3" }

  -- Author
  ret[#ret + 1] = { a(item.author or "<unknown>", 15, { truncate = true }), "SnacksIndent5" }

  -- Title
  ret[#ret + 1] = { " ", "" }
  ret[#ret + 1] = { item.title or "<no title>", "SnacksIndent4" }

  -- Labels
  if item.labels and #item.labels > 0 then
    ret[#ret + 1] = { " [" .. table.concat(item.labels, ", ") .. "]", "SnacksIndent8" }
  end

  -- Make fuzzy searchable
  item.text = table.concat(vim.tbl_map(function(seg) return seg[1] end, ret), "")
  return ret
end

--- Preview the selected issue in Markdown
---@param ctx snacks.picker.preview.ctx
function M.preview_issue(ctx)
  local issue = ctx.item or {}
  issue.labels = issue.labels or {}

  local lines = {}
  table.insert(lines, "# Issue #" .. issue.number .. ": " .. (issue.title or ""))
  table.insert(lines, "")

  -- Metadata
  table.insert(lines, "## Metadata")
  local function meta(label, value)
    if value and value ~= "" then
      table.insert(lines, "- **" .. label .. "**: " .. value)
    end
  end
  meta("Author", issue.author)
  if #issue.labels > 0 then
    meta("Labels", table.concat(issue.labels, ", "))
  end
  meta("State", issue.state)

  -- Description
  table.insert(lines, "")
  table.insert(lines, "## Description")
  table.insert(lines, (issue.body ~= "" and issue.body) or "_No description provided_")

  -- Render
  ctx.preview:set_lines(lines)
  ctx.preview:highlight({ ft = "markdown" })
end

-- below is a slight modification of snacks picker for git diffs to let us pass reference commits

---@param ... (string|string[]|nil)
local function git_args(...)
  local ret = { "-c", "core.quotepath=false" } ---@type string[]
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    vim.list_extend(ret, type(arg) == "table" and arg or { arg })
  end
  return ret
end

-- I add two custom fields to the snacks.picker.git.Config so I can pass base and head refs
---@class ExpandedGitConfig : snacks.picker.git.Config
---@field base  string?   # optional “base” ref
---@field head  string?   # optional “head” ref

---@param opts ExpandedGitConfig
---@type snacks.picker.finder
M.custom_diff = function(opts, ctx)
  -- build your git-diff args exactly as before
  local ARGS
  if not opts.base and not opts.head then
    ARGS = git_args(opts.args, "--no-pager", "diff", "--no-color", "--no-ext-diff")
  elseif not opts.head then
    ARGS = git_args(opts.args, "--no-pager", "diff", opts.base, "--no-color", "--no-ext-diff")
  elseif not opts.base then
    error("base is required when head is provided")
  else
    ARGS = git_args(opts.args, "--no-pager", "diff", "--no-color", "--no-ext-diff",
                    opts.base .. "..." .. opts.head)
  end

  local proc_finder = require("snacks.picker.source.proc").proc({
    opts,
    { cmd = "git", args = ARGS },
  }, ctx)

  return function(cb)
    local state = {
      file    = nil,
      header  = {},
      hunk    = {},
      in_hunk = false,
      new_ln  = nil,
    }

    local function flush_hunk()
      if state.file and #state.hunk > 0 then
        local diff_text = table.concat(state.header, "\n")
                            .. "\n" .. table.concat(state.hunk, "\n")
        cb({
          text    = state.file .. ":" .. state.new_ln,
          diff    = diff_text,
          file    = state.file,
          pos     = { state.new_ln, 0 },
          preview = { text = diff_text, ft = "diff", loc = false },
        })
      end
    end
    -- this fixes current bugs in snacks git diff finder where it misses nuances of stuff like file renames
    proc_finder(function(item)
      local line = item.text

      if line:match("^diff ") then
        -- new file diff; emit any pending hunk
        flush_hunk()
        state.header  = { line }
        state.hunk    = {}
        state.in_hunk = false
        state.file    = line:match(" a/(.-) b/")  -- capture filename
      elseif line:match("^@@") then
        -- start of a new hunk: first flush previous, then init
        flush_hunk()
        state.in_hunk = true
        state.hunk    = { line }
        state.new_ln  = tonumber(line:match("^@@ [^+]*%+([0-9]+)")) or 1
      elseif state.in_hunk then
        -- body of the current hunk
        table.insert(state.hunk, line)
      else
        -- still in header (covers index…, deps:, mode changes, etc.)
        table.insert(state.header, line)
      end
    end)

    -- final hunk at EOF
    flush_hunk()
  end
end


local align = function(txt, width, opts)
  return require("snacks.picker.util").align(txt, width, opts)
end

-- Very light-weight parsing for the common “git@” and “https://” remotes
local function current_repo()
  local remote = (vim.fn.systemlist({ "git", "remote", "get-url", "origin" })[1] or ""):gsub("%.git$", "")
  local owner, repo = remote:match("github%.com[:/](.-)/(.-)$")
  return owner or "", repo or ""
end

local function iso_to_relative(iso)
  local ok, t = pcall(function()
    return vim.fn.strptime("%Y-%m-%dT%H:%M:%SZ", iso)
  end)
  if not ok or not t then return "?" end
  local delta = os.time() - t
  if delta < 60   then return delta .. " s ago"
  elseif delta < 3600 then return math.floor(delta/60) .. " m ago"
  elseif delta < 86400 then return math.floor(delta/3600) .. " h ago"
  else return math.floor(delta/86400) .. " d ago" end
end

-- ─────────────────────────────────────────────────────────────
-- Fetch
-- ─────────────────────────────────────────────────────────────
function M.fetch_notifications()
  local owner, repo = current_repo()
  if owner == "" or repo == "" then return {} end

  local endpoint = string.format("/repos/%s/%s/notifications", owner, repo)
  local cmd = {
    "gh",
    "api",
    string.format("%s?participating=true&per_page=100&all=true", endpoint),
    "--jq",
    ".[] | @json",
  }

  local json_lines = vim.fn.systemlist(cmd)
  local notes = {}

  for _, line in ipairs(json_lines) do
    local ok, obj = pcall(vim.json.decode, line)
    if ok then
      local subj = obj.subject or {}
      notes[#notes + 1] = {
        id         = obj.id,
        unread     = obj.unread,
        reason     = obj.reason,             -- e.g. "mention", "author", …
        updated_at = obj.updated_at,
        repo       = owner .. "/" .. repo,
        title      = subj.title or "",
        type       = subj.type or "",        -- "PullRequest", "Issue", …
        api_url    = subj.url    or "",
        html_url   = subj.latest_comment_url -- fallback, fixed in preview
                    and subj.latest_comment_url:gsub("api%.github%.com/repos/", "github.com/"):gsub("/pulls/", "/pull/")
                    or "",
      text   = subj.title or "",  -- will be set in formatter
      }

    end
  end
    return notes
end

-- ─────────────────────────────────────────────────────────────
-- Row formatter
-- ─────────────────────────────────────────────────────────────
---@param item   table
---@param picker table
function M.format_notification_row(item, picker)
  local ret = {}
  ret[#ret+1] = { align(item.type or "", 12), item.unread and "SnacksPickerIdx" or "SnacksIndent" }
  ret[#ret+1] = { align(item.reason or "?", 12), item.unread and "SnacksIndent2" or "SnacksIndent" }
  ret[#ret+1] = { " " .. iso_to_relative(item.updated_at), item.unread and "SnacksIndent1" or "SnacksIndent" }
  ret[#ret+1] = { " " .. (item.title ~= "" and item.title or "<no title>"), item.unread and "SnacksIndent4" or "SnacksIndent" }
 -- Make fuzzy searchable
  item.text = table.concat(vim.tbl_map(function(seg) return seg[1] end, ret), "")

  return ret
end



return M
