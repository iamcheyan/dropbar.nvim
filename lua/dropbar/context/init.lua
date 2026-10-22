local M = {}
local treesitter = require("dropbar.context.treesitter")
local lsp = require("dropbar.context.lsp")
local navic = require("dropbar.context.navic")
local path_util = require("dropbar.context.path")

M.config = {
  show_path = false,
  max_path_depth = 3,
  show_file = false,
  use_lsp = true,
  use_navic = true,
  use_treesitter = true,
}

M._active_menu_segment = nil
M._active_menu_win = nil

M._providers = {}
M._setup = false

local function filetype(bufnr)
  return vim.bo[bufnr or 0].filetype
end

function M.register(name, provider)
  assert(type(name) == "string", "dropbar.context provider name must be a string")
  assert(type(provider) == "table", "dropbar.context provider must be a table")
  assert(type(provider.get_info) == "function", "dropbar.context provider requires get_info")
  M._providers[name] = provider
  provider.name = provider.name or name
  provider.filetypes = provider.filetypes or {}
  return provider
end

function M.unregister(name)
  M._providers[name] = nil
end

function M.providers()
  return vim.deepcopy(M._providers)
end

local function custom_info(opts)
  local ft = filetype(opts.bufnr)
  for _, provider in pairs(M._providers) do
    if vim.tbl_contains(provider.filetypes, ft) then
      local ok, info = pcall(provider.get_info, opts)
      if ok and info then
        info.provider = provider.name
        return info
      end
    end
  end
  return nil
end

---Window whose statusline/winbar is being drawn. Heirline calls get() with no
---winid while a dropdown float may be current; g:statusline_winid is the source.
local function drawing_winid(opts)
  if opts and opts.winid and opts.winid ~= 0 and vim.api.nvim_win_is_valid(opts.winid) then
    return opts.winid
  end
  local id = tonumber(vim.g.statusline_winid)
  if id and id > 0 and vim.api.nvim_win_is_valid(id) then
    return id
  end
  return vim.api.nvim_get_current_win()
end

function M.get_info(opts)
  opts = opts or {}
  local winid = drawing_winid(opts)
  local bufnr = opts.bufnr
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_win_get_buf(winid)
  end
  opts = vim.tbl_extend("force", opts, { bufnr = bufnr, winid = winid })

  local info = nil

  -- 1. Priority: Custom registered provider (e.g. COBOL, Batch)
  info = custom_info(opts)

  -- 2. Priority: LSP (Native LSP documentSymbol cache / navic)
  if not info and M.config.use_lsp then
    local ok, lsp_info = pcall(lsp.get_info, opts)
    if ok and lsp_info and lsp_info.segments and #lsp_info.segments > 0 then
      info = lsp_info
    end
  end

  -- 3. Priority: nvim-navic (if enabled and not caught by LSP)
  if not info and M.config.use_navic then
    local ok, navic_info = pcall(navic.get_info, opts)
    if ok and navic_info and navic_info.segments and #navic_info.segments > 0 then
      info = navic_info
    end
  end

  -- 4. Priority: Tree-sitter (保底方案)
  if not info and M.config.use_treesitter then
    local ok, ts_info = pcall(treesitter.get_info, opts)
    if ok and ts_info and ts_info.segments and #ts_info.segments > 0 then
      info = ts_info
    end
  end

  -- Do not turn an ordinary file with no identifiable scope into a visible
  -- component.  The consumers use a non-nil info value as the visibility
  -- condition, so an empty fallback would leave a blank context bar behind.
  -- Path/file-only displays remain opt-in and are still allowed to create the
  -- base info below when explicitly requested.
  if not info then
    local ft = filetype(opts.bufnr)
    local show_path = opts.show_path ~= nil and opts.show_path or M.config.show_path
    local show_file = opts.show_file ~= nil and opts.show_file or M.config.show_file
    if not ft or ft == "" or (not show_path and not show_file) then
      return nil
    end
    info = {
      language = ft:upper(),
      segments = {},
      source = "file",
    }
  end

  -- Attach path and file segments
  local path_data = path_util.get_path_info({
    bufnr = opts.bufnr,
    max_path_depth = opts.max_path_depth or M.config.max_path_depth,
  })

  if path_data then
    info.path = path_data.path_segments
    info.file = path_data.file_segment
  end

  -- Assemble combined `all` segment list for rich breadcrumb rendering
  local all = {}
  local show_path = opts.show_path ~= nil and opts.show_path or M.config.show_path
  if show_path and info.path then
    for _, p in ipairs(info.path) do
      table.insert(all, p)
    end
  end

  local show_file = opts.show_file ~= nil and opts.show_file or M.config.show_file
  if show_file and info.file then
    table.insert(all, info.file)
  end

  if info.segments then
    for _, s in ipairs(info.segments) do
      table.insert(all, s)
    end
  end

  info.bufnr = opts.bufnr
  info.all = all
  return info
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M._setup then return end
  M._setup = true
  local group = vim.api.nvim_create_augroup("DropBarContext", { clear = true })
  vim.api.nvim_create_autocmd({ "LspAttach", "BufWritePost" }, {
    group = group,
    callback = function(args)
      if M.config.use_lsp then lsp.request_symbols(args.buf) end
    end,
  })
  vim.api.nvim_create_user_command("DropbarContextMenu", function()
    require("dropbar.context.menu").toggle()
  end, { desc = "Toggle code hierarchy" })
end
return M
