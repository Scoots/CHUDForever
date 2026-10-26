-- A small popup menu for edit mode, opened at the cursor.
-- Items: { text, isTitle, separator, checked (true/false shows a check box),
--          icon, disabled, func, submenu (function returning items) }.
local _, ns = ...

local Menu = {}
ns.Menu = Menu

local WIDTH, ROW_HEIGHT, PADDING = 240, 18, 5
local frame, catcher
local rows = {}
local stack = {} -- earlier item lists, for Back

local function Create()
  -- Clicking anywhere outside the menu closes it.
  catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", function() Menu.Close() end)
  catcher:Hide()

  frame = CreateFrame("Frame", "CombatHUDMenu", UIParent)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetFrameLevel(catcher:GetFrameLevel() + 10)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetWidth(WIDTH)
  local border = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetColorTexture(0.35, 0.35, 0.4, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.96)
  bg:SetAllPoints()
  frame:SetScript("OnHide", function() catcher:Hide() end)
  frame:Hide()
  table.insert(UISpecialFrames, "CombatHUDMenu") -- Escape closes it
end

local function Row(index)
  if rows[index] then return rows[index] end
  local row = CreateFrame("Button", nil, frame)
  row:SetHeight(ROW_HEIGHT)
  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetColorTexture(1, 1, 1, 0.12)
  row.highlight:SetAllPoints()
  row.box = row:CreateTexture(nil, "ARTWORK")
  row.box:SetSize(10, 10)
  row.box:SetPoint("LEFT", 6, 0)
  row.mark = row:CreateTexture(nil, "OVERLAY")
  row.mark:SetSize(6, 6)
  row.mark:SetPoint("CENTER", row.box)
  row.mark:SetColorTexture(1, 0.82, 0.2, 1)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(14, 14)
  row.icon:SetPoint("LEFT", 20, 0)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetJustifyH("LEFT")
  row.text:SetPoint("RIGHT", -16, 0)
  row.arrow = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.arrow:SetPoint("RIGHT", -6, 0)
  row.arrow:SetText(">")
  row.line = row:CreateTexture(nil, "ARTWORK")
  row.line:SetColorTexture(0.35, 0.35, 0.4, 1)
  row.line:SetHeight(1)
  row.line:SetPoint("LEFT", 6, 0)
  row.line:SetPoint("RIGHT", -6, 0)
  row:SetScript("OnEnter", function(self)
    if self.item and self.item.tooltip then self.item.tooltip(self) end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    local item = self.item
    if not item or item.disabled or item.isTitle or item.separator then return end
    if item.submenu then
      table.insert(stack, self.items)
      Menu.Show(item.submenu(), true)
    elseif item.back then
      Menu.Show(table.remove(stack), true)
    else
      Menu.Close()
      if item.func then item.func() end
    end
  end)
  rows[index] = row
  return row
end

-- Fills the menu with items, keeping its position (submenus and Back).
function Menu.Show(items, keepPosition)
  if not frame then Create() end
  local list = items
  if #stack > 0 then
    list = { { text = "< Back", back = true } }
    for _, item in ipairs(items) do list[#list + 1] = item end
  end

  local y = -PADDING
  for index, item in ipairs(list) do
    local row = Row(index)
    row.item, row.items = item, items
    local height = item.separator and 7 or ROW_HEIGHT
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", PADDING, y)
    row:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    y = y - height

    row.line:SetShown(item.separator == true)
    row.box:SetShown(item.checked ~= nil)
    row.box:SetColorTexture(0.25, 0.25, 0.3, 1)
    row.mark:SetShown(item.checked == true)
    row.icon:SetShown(item.icon ~= nil)
    if item.icon then row.icon:SetTexture(item.icon) end
    row.arrow:SetShown(item.submenu ~= nil)
    local left = item.icon and 38 or (item.checked ~= nil and 22 or 8)
    row.text:SetPoint("LEFT", left, 0)
    row.text:SetText(item.separator and "" or (item.text or ""))
    if item.isTitle then
      row.text:SetTextColor(1, 0.82, 0.2)
    elseif item.disabled then
      row.text:SetTextColor(0.5, 0.5, 0.5)
    else
      row.text:SetTextColor(1, 1, 1)
    end
    row:EnableMouse(not (item.isTitle or item.separator or item.disabled))
    row:Show()
  end
  for index = #list + 1, #rows do rows[index]:Hide() end
  frame:SetHeight(-y + PADDING)

  if not keepPosition then
    local scale = UIParent:GetEffectiveScale()
    local x, cursorY = GetCursorPosition()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 4, cursorY / scale - 4)
  end
  catcher:Show()
  frame:Show()
end

function Menu.Open(items)
  wipe(stack)
  Menu.Show(items, false)
end

function Menu.Close()
  if frame then frame:Hide() end
  wipe(stack)
end
