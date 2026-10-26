-- A small panel beside an edit-mode gear, for the quick settings of a bar
-- (or the power, health, cast or swing bar). Its rows change the setting as
-- you drag or click, and the HUD redraws right away.
--
-- rows, in order, each one of:
--   { slider = label, min, max, step, get = function() -> number, set = function(value) }
--   { choice = label, choices = { { value, label }, ... }, get, set }
--   { button = text, func }
local _, ns = ...

local Popover = {}
ns.Popover = Popover

local WIDTH = 260
local panel
local pools = { slider = {}, choice = {}, button = {} }
local used = {}

local function Redraw()
  if not InCombatLockdown() then ns.Rebuild(true) end
end

local function NewButton(parent, width, height)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, height)
  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(0.18, 0.18, 0.22, 1)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.1)
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.text:SetPoint("LEFT", 3, 0)
  button.text:SetPoint("RIGHT", -3, 0)
  button.text:SetWordWrap(false)
  return button
end

local function Create()
  panel = CreateFrame("Frame", "CombatHUDPopover", UIParent)
  panel:SetWidth(WIDTH)
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  -- Dragged by its title or any empty part, once open.
  panel:SetMovable(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  local edge = panel:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.2, 0.6, 1, 0.8)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.97)
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", 10, -8)
  panel.title:SetPoint("RIGHT", -28, 0)
  panel.title:SetJustifyH("LEFT")
  local close = NewButton(panel, 18, 18)
  close.text:SetText("x")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() Popover.Close() end)
  table.insert(UISpecialFrames, "CombatHUDPopover") -- Escape closes it
  panel:Hide()
end

-- Rows ---------------------------------------------------------------------------------

local function NewSlider()
  local row = CreateFrame("Frame", nil, panel)
  row:SetSize(WIDTH - 20, 34)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("TOPLEFT")
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.value:SetPoint("TOPRIGHT")
  local slider = CreateFrame("Slider", nil, row)
  slider:SetOrientation("HORIZONTAL")
  slider:SetHeight(16)
  slider:SetPoint("TOPLEFT", 0, -14)
  slider:SetPoint("TOPRIGHT", 0, -14)
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetColorTexture(0.2, 0.2, 0.25, 1)
  track:SetHeight(4)
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
  slider:EnableMouseWheel(true)
  slider:SetScript("OnMouseWheel", function(self, delta)
    self:SetValue(self:GetValue() + delta * (row.step or 1))
  end)
  slider:SetScript("OnValueChanged", function(_, value)
    if row.filling or not row.data then return end
    local step = row.step or 1
    value = math.floor(value / step + 0.5) * step
    row.value:SetText(value)
    if value ~= row.data.get() then
      row.data.set(value)
      ns.Schedule(Redraw)
    end
  end)
  row.slider = slider
  return row
end

local function FillSlider(row, data)
  row.data, row.step = data, data.step or 1
  row.label:SetText(data.slider)
  row.filling = true
  row.slider:SetMinMaxValues(data.min, data.max)
  row.slider:SetValueStep(row.step)
  local value = math.max(data.min, math.min(data.max, data.get() or data.min))
  row.slider:SetValue(value)
  row.filling = false
  row.value:SetText(value)
end

local function NewChoice()
  local row = CreateFrame("Frame", nil, panel)
  row:SetSize(WIDTH - 20, 38)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("TOPLEFT")
  row.buttons = {}
  return row
end

local function FillChoice(row, data)
  row.label:SetText(data.choice)
  local count = #data.choices
  local width = math.floor((WIDTH - 20 - (count - 1) * 4) / count)
  local current = data.get()
  for index, choice in ipairs(data.choices) do
    local button = row.buttons[index] or NewButton(row, width, 20)
    row.buttons[index] = button
    button:SetWidth(width)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", (index - 1) * (width + 4), -15)
    button.text:SetText(choice[2])
    local on = current == choice[1]
    button.bg:SetColorTexture(on and 0.85 or 0.18, on and 0.6 or 0.18, on and 0.15 or 0.22, 1)
    button.text:SetTextColor(on and 0 or 1, on and 0 or 1, on and 0 or 1)
    button:SetScript("OnClick", function()
      data.set(choice[1])
      FillChoice(row, data)
      ns.Schedule(Redraw)
    end)
    button:Show()
  end
  for index = count + 1, #row.buttons do row.buttons[index]:Hide() end
end

local function NewAction()
  local button = NewButton(panel, WIDTH - 20, 22)
  return button
end

local function FillAction(button, data)
  button.text:SetText(data.button)
  button:SetScript("OnClick", function()
    Popover.Close()
    data.func()
  end)
end

local KINDS = {
  slider = { new = NewSlider, fill = FillSlider, height = 38 },
  choice = { new = NewChoice, fill = FillChoice, height = 42 },
  button = { new = NewAction, fill = FillAction, height = 26 },
}

local function KindOf(data)
  if data.slider then return "slider" end
  if data.choice then return "choice" end
  return "button"
end

local function ReleaseRows()
  for _, item in ipairs(used) do
    item.row:Hide()
    table.insert(pools[item.kind], item.row)
  end
  wipe(used)
end

-- Opens the panel beside anchor (the gear that was clicked).
function Popover.Open(anchor, title, rows)
  if InCombatLockdown() then return end
  if not panel then Create() end
  ns.Menu.Close()
  ReleaseRows()
  panel.title:SetText(title)
  local y = -32
  for _, data in ipairs(rows) do
    local kind = KindOf(data)
    local row = table.remove(pools[kind]) or KINDS[kind].new()
    KINDS[kind].fill(row, data)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 10, y)
    row:Show()
    used[#used + 1] = { kind = kind, row = row }
    y = y - KINDS[kind].height
  end
  panel:SetHeight(-y + 6)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 8, 0)
  panel:Show()
end

function Popover.Close()
  if panel then panel:Hide() end
end

ns.On("PLAYER_REGEN_DISABLED", Popover.Close)
