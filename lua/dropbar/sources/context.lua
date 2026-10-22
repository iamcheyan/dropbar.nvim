-- Unified context source: language providers, hierarchy menus and COBOL layout.
local M = {}

local DROPBAR_WINBAR = "%{%v:lua.dropbar()%}"


local HIDDEN = {
  ["neo-tree"] = true,
  ["NvimTree"] = true,
  ["aerial"] = true,
  ["help"] = true,
  ["lazy"] = true,
  ["mason"] = true,
  ["Trouble"] = true,
  ["snacks_layout_box"] = true,
  ["qf"] = true,
  ["csv"] = true,
  ["tsv"] = true,
  ["text"] = true,
  ["txt"] = true,
  ["plaintex"] = true,
  ["log"] = true,
  ["gitcommit"] = true,
  ["gitrebase"] = true,
  ["diff"] = true,
  ["checkhealth"] = true,
  ["man"] = true,
  ["dropbar_context_menu"] = true,
  ["dropbar_menu"] = true,
}

function M.is_cobol(ft)
  return ft == "cobol" or ft == "cbl" or ft == "cob"
end

function M.ensure_highlights()
  local set = vim.api.nvim_set_hl
  -- Links follow a later WinBar change. Copying the RGB values leaves the
  -- previous palette on the breadcrumb.
  set(0, "DropBarContextText", { link = "WinBar" })
  set(0, "DropBarContextActiveMenu", { link = "WinBar" })
  set(0, "DropBarIconUISeparator", { link = "DropBarContextText" })
  local warning = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false })
  if not warning.fg then
    warning = vim.api.nvim_get_hl(0, { name = "WarningMsg", link = false })
  end
  set(0, "DropBarContextAlert", { fg = warning.fg, bold = true })
  set(0, "DropBarContextErrorBadge", { fg = "#ffffff", bg = "#b3261e", bold = true })
  set(0, "DropBarContextWarningBadge", { fg = "#ffffff", bg = "#8a5a00", bold = true })
end

local function context()
  local cl = require("dropbar.context")
  if not cl._setup then
    cl.setup({
      separator = "  ",
      show_path = false,
      show_file = false,
      show_icons = true,
      use_lsp = true,
      use_navic = true,
      use_treesitter = true,
    })
  end
  return cl
end

-- cobol.nvim and batch.nvim register themselves only when dropbar.context is
-- already loaded. Register again here so either startup order works.
local function ensure_provider(ft)
  local cl = context()
  if M.is_cobol(ft) then
    local ok, ctx = pcall(require, "cobol.context")
    if ok then
      cl.register("cobol", {
        filetypes = { "cobol", "cbl", "cob" },
        get_info = ctx.get_info,
      })
    end
  elseif ft == "dosbatch" or ft == "batch" then
    local ok, ctx = pcall(require, "batch.context")
    if ok then
      cl.register("batch", {
        filetypes = { "dosbatch", "batch" },
        get_info = ctx.get_info,
      })
    end
  end
end

local function info_for(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local ft = vim.bo[buf].filetype
  local bt = vim.bo[buf].buftype
  if bt ~= "" or ft == "" or HIDDEN[ft] then
    return nil
  end
  ensure_provider(ft)
  local ok, info = pcall(context().get_info, { bufnr = buf, winid = win })
  if not ok or not info or not info.segments or #info.segments == 0 then
    return nil
  end
  return info
end

function M.should_attach(buf, win)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if vim.fn.win_gettype(win) ~= "" then
    return false
  end
  return info_for(buf, win) ~= nil
end

local function symbol_col(symbol)
  local bar = symbol.bar
  if not bar then
    return 0
  end
  local col = bar.padding.left or 0
  for _, component in ipairs(bar.components) do
    if component.bar_idx == symbol.bar_idx then
      return col
    end
    col = col + component:displaywidth()
    if bar.separator then
      col = col + bar.separator:displaywidth()
    end
  end
  return col
end

local function open_menu(symbol)
  local bar = symbol.bar
  local win = bar and bar.win or vim.api.nvim_get_current_win()
  local buf = bar and bar.buf or vim.api.nvim_get_current_buf()
  require("dropbar.context.menu").open({
    winid = win,
    bufnr = buf,
    segment_index = symbol.segment_index,
    col = symbol_col(symbol),
  })
end

local function open_diagnostic_list(buf, severity)
  local diagnostics = vim.diagnostic.get(buf, { severity = severity })
  if #diagnostics == 0 then
    vim.notify("No matching diagnostics in this buffer", vim.log.levels.INFO)
    return
  end
  local title = severity == vim.diagnostic.severity.ERROR and "Errors in current buffer"
    or "Warnings in current buffer"
  vim.fn.setqflist({}, "r", {
    title = title,
    items = vim.diagnostic.toqflist(diagnostics),
  })
  vim.cmd("copen")
end

function M.get_symbols(buf, win, _)
  M.ensure_highlights()
  local info = info_for(buf, win)
  if not info then
    return {}
  end
  local bar_api = require("dropbar.bar")
  local cl = context()
  local syms = {}
  local total = #info.segments
  for i, seg in ipairs(info.segments) do
    local text = seg.text or ""
    if text ~= "" then
      local icon = (seg.icon and seg.icon ~= "") and (seg.icon .. " ") or ""
      if i == total and seg.type == "symbol" and seg.lines and seg.lines > 1 then
        text = text .. string.format(" (%dL)", seg.lines)
      end
      local active = cl._active_menu_segment == i and (not cl._active_menu_win or cl._active_menu_win == win)
      local hl = active and "DropBarContextActiveMenu" or "DropBarContextText"
      syms[#syms + 1] = bar_api.dropbar_symbol_t:new({
        buf = buf,
        win = win,
        icon = " " .. icon,
        name = text .. " ",
        icon_hl = hl,
        name_hl = hl,
        segment_index = i,
        on_click = function(self, _, _, button)
          if button and button ~= "l" then
            return
          end
          open_menu(self)
        end,
      })
    end
  end

  local counts = vim.diagnostic.count(buf)
  local errors = counts[vim.diagnostic.severity.ERROR] or 0
  local warnings = counts[vim.diagnostic.severity.WARN] or 0
  if errors > 0 then
    syms[#syms + 1] = bar_api.dropbar_symbol_t:new({
      buf = buf,
      win = win,
      icon = "",
      name = "  " .. errors .. " ",
      name_hl = "DropBarContextErrorBadge",
      on_click = function(_, _, _, button)
        if button and button ~= "l" then
          return
        end
        open_diagnostic_list(buf, vim.diagnostic.severity.ERROR)
      end,
    })
  end
  if warnings > 0 then
    syms[#syms + 1] = bar_api.dropbar_symbol_t:new({
      buf = buf,
      win = win,
      icon = "",
      name = "  " .. warnings .. " ",
      name_hl = "DropBarContextWarningBadge",
      on_click = function(_, _, _, button)
        if button and button ~= "l" then
          return
        end
        open_diagnostic_list(buf, vim.diagnostic.severity.WARN)
      end,
    })
  end
  return syms
end

function M.cobol_click(_, _, button)
  if button and button ~= "l" then
    return
  end
  local mouse = vim.fn.getmousepos()
  local win = mouse.winid and mouse.winid > 0 and mouse.winid or vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or vim.api.nvim_get_current_buf()
  require("dropbar.context.menu").open({
    winid = win,
    bufnr = buf,
    segment_index = 1,
    col = math.max(0, (mouse.wincol or 1) - 1),
  })
end



function M.cobol(buf, win, plain)
  local text = require("dropbar.context.cobol").render(buf, win)
  if plain then
    return vim.api.nvim_eval_statusline(text, { winid = win, use_winbar = true }).str
  end
  return "%@v:lua.dropbar.context_cobol_click@" .. text .. "%X"
end

function M.render(bar, plain)
  if M.is_cobol(vim.bo[bar.buf].filetype) then
    return M.cobol(bar.buf, bar.win, plain)
  end
end

local function ours(winbar)
  return winbar == DROPBAR_WINBAR
end

function M.sync(buf, win)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  win = win == 0 and vim.api.nvim_get_current_win() or win
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return
  end
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  local ft = vim.bo[buf].filetype
  local bt = vim.bo[buf].buftype
  if bt ~= "" or ft == "" or HIDDEN[ft] then
    if ours(vim.wo[win].winbar) then
      vim.wo[win].winbar = ""
    end
    return
  end
  if M.should_attach(buf, win) then
    local current = vim.wo[win].winbar
    if current == "" then
      vim.wo[win].winbar = DROPBAR_WINBAR
    end
    return
  end
  if ours(vim.wo[win].winbar) then
    vim.wo[win].winbar = ""
  end
end

function M.setup()
  M.ensure_highlights()
  _G.dropbar.context_cobol_click = M.cobol_click
  context()
  local group = vim.api.nvim_create_augroup("DropBarContextBar", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      vim.schedule(M.ensure_highlights)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "FileType", "DiagnosticChanged" }, {
    group = group,
    callback = function(args)
      local function apply()
        if not vim.api.nvim_buf_is_valid(args.buf) then
          return
        end
        for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
          M.sync(args.buf, win)
        end
      end
      apply()
      vim.schedule(apply)
    end,
  })
  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = group,
    callback = function(args)
      pcall(function()
        require("dropbar.utils.bar").exec("update", { buf = args.buf })
      end)
    end,
  })
end

return M
