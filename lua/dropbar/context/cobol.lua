local M = {}
local function winbar_text(text)
  return (text:gsub("%%", "%%%%"))
end

local function clip_parts(parts, budget)
  local full = table.concat(parts, " > ")
  if vim.api.nvim_strwidth(full) <= budget then
    return full
  end
  budget = budget - 4 -- room for the leading "… > "
  local kept = {}
  local width = 0
  for i = #parts, 1, -1 do
    local part = parts[i]
    local cost = vim.api.nvim_strwidth(part) + (#kept > 0 and 3 or 0)
    if width + cost > budget and #kept > 0 then
      break
    end
    table.insert(kept, 1, part)
    width = width + cost
  end
  return "… > " .. table.concat(kept, " > ")
end

local function breadcrumb_highlight(parts)
  if not parts[1] then
    return "CobolBreadcrumbProc"
  end
  local division = parts[1]
  if division:find("DATA", 1, true) then
    return "CobolBreadcrumbData"
  elseif division:find("ENVIRONMENT", 1, true) then
    return "CobolBreadcrumbEnv"
  elseif division:find("IDENTIFICATION", 1, true) then
    return "CobolBreadcrumbId"
  end
  return "CobolBreadcrumbProc"
end

-- Waiting closures for the winbar's right edge, innermost first.
local function waiting_closure_parts(win_id, bufnr, budget)
  if not require("cobol").config.show_waiting_closures then
    return {}
  end
  local pos = vim.api.nvim_win_get_cursor(win_id)
  local stack = require("cobol.ast").closure_stack(bufnr, pos[1] - 1, pos[2])
  local kept = {}
  local width = 0
  for _, entry in ipairs(stack) do
    local cost = vim.api.nvim_strwidth(entry) + (#kept > 0 and 3 or 0)
    if width + cost > budget and #kept > 0 then
      break
    end
    kept[#kept + 1] = entry
    width = width + cost
  end
  if #kept < #stack then
    kept[#kept + 1] = "…"
  end
  return kept
end

function M.render(bufnr, win_id)
  local cobol = require("cobol")
  if not cobol.state.enabled then return "" end
  local ok, wininfo = pcall(vim.fn.getwininfo, win_id)
  local textoff = 0
  if ok and wininfo and wininfo[1] then
    textoff = wininfo[1].textoff or 0
  end

  local width = vim.api.nvim_win_get_width(win_id)
  local avail = math.max(20, width - textoff - 2)

  local crumb_parts = {}
  local hl_group = "CobolBreadcrumbProc"
  if require("cobol").config.show_breadcrumbs then
    local pos = vim.api.nvim_win_get_cursor(win_id)
    local ok_chain, parts = pcall(require("cobol.ast").chain, bufnr, pos[1] - 1, pos[2])
    if ok_chain and parts and #parts > 0 then
      crumb_parts = parts
      hl_group = breadcrumb_highlight(parts)
    end
  end

  if #crumb_parts == 0 then
    return ""
  end

  -- The breadcrumb is the primary signal: give it the space it needs and keep
  -- waiting closures only in what is left over, dropping them when there is no
  -- room instead of squeezing the chain down to its last part.
  local crumb_need = vim.api.nvim_strwidth(table.concat(crumb_parts, " > ")) + 4
  local waiting_budget = avail - crumb_need - 6
  local waiting_text = ""
  if waiting_budget >= 16 then
    local waiting = waiting_closure_parts(win_id, bufnr, waiting_budget)
    local candidate = waiting[1] and table.concat(waiting, "  ") or ""
    if candidate ~= "" and vim.api.nvim_strwidth(candidate) + 4 <= waiting_budget then
      waiting_text = candidate
    end
  end
  local crumb_budget = avail
    - (waiting_text ~= "" and (vim.api.nvim_strwidth(waiting_text) + 4) or 0)
    - 4

  local pad = string.rep(" ", textoff)
  local winbar = pad
    .. "%#"
    .. hl_group
    .. "#[ "
    .. winbar_text(clip_parts(crumb_parts, math.max(12, crumb_budget)))
    .. " ]%*"
  if waiting_text ~= "" then
    winbar = winbar .. "%=" .. "%#CobolWaitingClosure#⌫ " .. winbar_text(waiting_text) .. " "
  end
  return winbar
end


return M
