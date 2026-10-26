-- Ways in besides /chud: an entry in the game's Options > AddOns list, a
-- minimap button, and the addon compartment (the minimap's addon menu, on
-- clients that have one; set up in the .toc). Left-click opens the settings,
-- right-click edits the HUD.
--
-- Settings (CombatHUDDB.minimap, for every character): hide, angle (degrees
-- around the minimap).
local _, ns = ...

local Launcher = {}
ns.Launcher = Launcher

local ICON = "Interface\\AddOns\\CombatHUD\\Media\\Icon"

local function CloseGameOptions()
  if InCombatLockdown() then return end
  for _, frame in ipairs({ SettingsPanel, InterfaceOptionsFrame }) do
    if frame and frame:IsShown() then pcall(HideUIPanel, frame) end
  end
end

function Launcher.OpenSettings()
  CloseGameOptions()
  ns.Options.Toggle()
end

function Launcher.ToggleEdit()
  CloseGameOptions()
  ns.SetEditMode(not ns.editMode)
end

local function Tooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText("CombatHUD " .. ns.Version())
  GameTooltip:AddLine("Left-click: settings", 1, 1, 1)
  GameTooltip:AddLine("Right-click: move bars and add spells", 1, 1, 1)
  GameTooltip:Show()
end

-- Minimap button ------------------------------------------------------------------------

local button

local function Saved()
  CombatHUDDB.minimap = CombatHUDDB.minimap or { angle = 200 }
  return CombatHUDDB.minimap
end

local function Place()
  local angle = math.rad(Saved().angle or 200)
  local radius = Minimap:GetWidth() / 2 + 10
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateButton()
  button = CreateFrame("Button", "CombatHUDMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)
  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, mouse)
    if mouse == "RightButton" then Launcher.ToggleEdit() else Launcher.OpenSettings() end
  end)
  button:SetScript("OnEnter", Tooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Dragged around the edge of the minimap.
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local x, y = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local centerX, centerY = Minimap:GetCenter()
      Saved().angle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX))
      Place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function Launcher.SetMinimapShown(shown)
  Saved().hide = not shown or nil
  if shown and not button then CreateButton() end
  if button then
    button:SetShown(shown)
    if shown then Place() end
  end
end

-- The game's Options > AddOns entry ---------------------------------------------------

local function NewButton(parent, text, onClick)
  local widget = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  widget:SetSize(220, 24)
  widget:SetText(text)
  widget:SetScript("OnClick", onClick)
  return widget
end

local function RegisterOptionsPanel()
  local panel = CreateFrame("Frame")
  panel.name = "CombatHUD"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("CombatHUD")
  local version = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  version:SetPoint("LEFT", title, "RIGHT", 8, -1)
  version:SetText(ns.Version())
  local about = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  about:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  about:SetWidth(560)
  about:SetJustifyH("LEFT")
  about:SetText("CombatHUD has its own settings window, with every bar and its buttons. "
    .. "To move bars or add spells, edit the HUD: drag bars, drop spells or items on them, and right-click for options.")

  local open = NewButton(panel, "Open CombatHUD Settings", Launcher.OpenSettings)
  open:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 0, -16)
  local edit = NewButton(panel, "Move Bars and Add Spells", Launcher.ToggleEdit)
  edit:SetPoint("LEFT", open, "RIGHT", 12, 0)
  local quick = NewButton(panel, "Quick Setup", function()
    CloseGameOptions()
    ns.QuickSetup.Show()
  end)
  quick:SetPoint("LEFT", edit, "RIGHT", 12, 0)

  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -14)
  local label = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  label:SetText("Show the minimap button")
  check:SetScript("OnShow", function(self) self:SetChecked(not Saved().hide) end)
  check:SetScript("OnClick", function(self) Launcher.SetMinimapShown(self:GetChecked() == true) end)

  local commands = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  commands:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -12)
  commands:SetText("Also: /chud for the settings, /chud edit to move bars, /chud report for a bug report.")

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

-- The addon compartment (named in the .toc) --------------------------------------------

function CombatHUD_OnAddonCompartmentClick(_, mouse)
  if mouse == "RightButton" then Launcher.ToggleEdit() else Launcher.OpenSettings() end
end

function CombatHUD_OnAddonCompartmentEnter(_, frame)
  Tooltip(frame)
end

function CombatHUD_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end

ns.On("PLAYER_LOGIN", function()
  ns.Try("options entry", RegisterOptionsPanel)
  Launcher.SetMinimapShown(not Saved().hide)
end)
