local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
  error('This plugins requires nvim-telescope/telescope.nvim')
end

local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require("telescope.config").values
local previewers = require "telescope.previewers"
local from_entry = require "telescope.from_entry"
local utils = require "telescope.utils"
local putils = require "telescope.previewers.utils"
local git_command = utils.__git_command

-- Custom previewer to show git diff against a target branch
previewers.git_branch_diff = previewers.new_termopen_previewer {
  get_command = function(entry)
    local target_branch = entry.target_branch or "origin/main"
    local filepath = entry.value or entry.path or entry.filename
    if not filepath then
      return { "echo", "No file selected" }
    end
    return { "git", "diff", target_branch, "--", filepath }
  end
}

local function defaulter(f, default_opts)
  default_opts = default_opts or {}
  return {
    new = function(opts)
      if conf.preview == false and not opts.preview then
        return false
      end
      opts.preview = type(opts.preview) ~= "table" and {} or opts.preview
      if type(conf.preview) == "table" then
        for k, v in pairs(conf.preview) do
          opts.preview[k] = vim.F.if_nil(opts.preview[k], v)
        end
      end
      return f(opts)
    end,
    __call = function()
      local ok, err = pcall(f(default_opts))
      if not ok then
        error(debug.traceback(err))
      end
    end,
  }
end

previewers.git_file_branch_diff = defaulter(function(opts)
  return previewers.new_buffer_previewer {
    title = "Git File Diff Preview",
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,

    define_preview = function(self, entry)
      if entry.status and (entry.status == "??" or entry.status == "A ") then
        local p = from_entry.path(entry, true, false)
        if p == nil or p == "" then
          return
        end
        conf.buffer_previewer_maker(p, self.state.bufnr, {
          bufname = self.state.bufname,
          winid = self.state.winid,
          preview = opts.preview,
          file_encoding = opts.file_encoding,
        })
      else
        local cmd = git_command({ "--no-pager", "diff", opts.diff_against, "--", entry.value }, opts)
        putils.job_maker(cmd, self.state.bufnr, {
          value = entry.value,
          bufname = self.state.bufname,
          cwd = opts.cwd,
          callback = function(bufnr)
            if vim.api.nvim_buf_is_valid(bufnr) then
              putils.highlighter(bufnr, "diff", opts)
            end
          end,
        })
      end
    end,
  }
end, {})

local git_diff = function(opts)
  opts = opts or {}

  local diff_against = opts.diff_against or "main"

  local cmd = { "git", "diff", "--name-only", diff_against }

  pickers.new(opts, {
    prompt_title = string.format("Git diff %s", diff_against),
    finder = finders.new_oneshot_job(cmd, opts),
    previewer = previewers.git_file_branch_diff.new(opts),
    sorter = conf.file_sorter(opts),
  }):find()
end

return telescope.register_extension {
  exports = { git_diff = git_diff },
}
