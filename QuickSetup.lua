-- Quick setup: a few choices for a new character's HUD, shown once after its
-- first login (Profile.lua marks the character), and again from the profile
-- page or the game's Options > AddOns entry. Every choice applies at once, so
-- the HUD changes behind the window as you pick; Done just closes it.
--
--   Size:      compact, normal or large (the HUD scale, with the gaps between
--              bars scaled to match)
--   Position:  lower or middle of the screen (every bar moved together)
--   Also show: health bar, cast bar, swing timer; and hiding the game's cast bar
local _, ns = ...

local QuickSetup = {}
ns.QuickSetup = QuickSetup

local SIZES = { { "compact", "Compact", 0.85 }, { "normal", "Normal", 1 }, { "large", "Large", 1.2 } }
local POSITIONS = { { "low", "Lower", 0 }, { "mid", "Middle", 90 } } -- pixels up from the default layout

local window
local profile -- the one being set up

local function Find(list, key)
  for _, item in ipairs(list) do
    if item[1] == key then return item end
  end
  return list[1]
end

local function Round(value) return math.floor(value + 0.5) end

-- Everything placed on screen: the bars and the four meters.
local Meter

local function Placed()
  Meter("cast")
  local list = {}
  for _, bar in ipairs(profile.bars or {}) do list[#list + 1] = bar end
  for _, key in ipairs({ "power", "health", "cast", "swing" }) do
    if profile[key] then list[#list + 1] = profile[key] end
  end
  return list
end

local function CurrentSize()
  local scale, best, gap = profile.scale or 1, SIZES[2], math.huge
  for _, size in ipairs(SIZES) do
    if math.abs(size[3] - scale) < gap then best, gap = size, math.abs(size[3] - scale) end
  end
  return best[1]
end

-- A new size: the scale, and every position spread or drawn in to match
-- (around the HUD's middle line, so nothing ends up overlapping).
local function SetSize(key)
  local old, new = profile.scale or 1, Find(SIZES, key)[3]
  if math.abs(new - old) < 0.001 then return end
  local ratio, middle = new / old, Find(POSITIONS, profile.hudPosition)[3]
  for _, config in ipairs(Placed()) do
    config.x = Round((config.x or 0) * ratio)
    config.y = Round(middle + ((config.y or 0) - middle) * ratio)
  end
  profile.scale = new
end

local function SetPosition(key)
  local shift = Find(POSITIONS, key)[3] - Find(POSITIONS, profile.hudPosition)[3]
  profile.hudPosition = key ~= "low" and key or nil
  for _, config in ipairs(Placed()) do config.y = (config.y or 0) + shift end
end

-- A meter's settings; an older profile without them gets the default spot.
local SPOTS = {
  health = { width = 250, height = 14, x = 0, y = -134 },
  cast = { width = 250, height = 16, x = 0, y = -170 },
  swing = { width = 250, height = 14, x = 0, y = -190 },
}

function Meter(key)
  if not profile[key] then
    profile[key] = {}
    for field, value in pairs(SPOTS[key] or {}) do profile[key][field] = value end
  end
  return profile[key]
end

-- The window ----------------------------------------------------------------------------

local function NewButton(parent, width, height, text)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, height)
  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(0.18, 0.18, 0.22, 1)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.1)
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  button.text:SetPoint("CENTER")
  button.text:SetText(text or "")
  return button
end

local function Label(parent, text, y)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 16, y)
  label:SetText(text)
  return label
end

-- A row of buttons, one of them picked.
local function Choices(parent, y, list, get, set)
  local buttons = {}
  for index, item in ipairs(list) do
    local button = NewButton(parent, 104, 24, item[2])
    button:SetPoint("TOPLEFT", 110 + (index - 1) * 110, y + 4)
    button:SetScript("OnClick", function()
      set(item[1])
      QuickSetup.Refresh()
    end)
    buttons[#buttons + 1] = { button = button, key = item[1] }
  end
  return function()
    local current = get()
    for _, entry in ipairs(buttons) do
      local on = entry.key == current
      entry.button.bg:SetColorTexture(on and 0.85 or 0.18, on and 0.6 or 0.18, on and 0.15 or 0.22, 1)
      entry.button.text:SetTextColor(on and 0 or 1, on and 0 or 1, on and 0 or 1)
    end
  end
end

-- A check box with its label.
local function Check(parent, x, y, text, get, toggle)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(150, 20)
  button:SetPoint("TOPLEFT", x, y + 2)
  local box = button:CreateTexture(nil, "ARTWORK")
  box:SetSize(14, 14)
  box:SetPoint("LEFT")
  box:SetColorTexture(0.2, 0.2, 0.25, 1)
  local mark = button:CreateTexture(nil, "OVERLAY")
  mark:SetSize(8, 8)
  mark:SetPoint("CENTER", box)
  mark:SetColorTexture(1, 0.82, 0.2, 1)
  local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("LEFT", box, "RIGHT", 6, 0)
  label:SetText(text)
  button:SetScript("OnClick", function()
    toggle()
    QuickSetup.Refresh()
  end)
  return function(enabled)
    mark:SetShown(get())
    button:SetEnabled(enabled ~= false)
    label:SetTextColor(enabled ~= false and 1 or 0.5, enabled ~= false and 1 or 0.5, enabled ~= false and 1 or 0.5)
  end
end

local refreshers = {}

local function Create()
  window = CreateFrame("Frame", "CombatHUDQuickSetup", UIParent)
  window:SetSize(460, 300)
  window:SetPoint("TOP", 0, -90)
  window:SetFrameStrata("DIALOG")
  window:EnableMouse(true)
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  local edge = window:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.2, 0.6, 1, 0.8)
  local bg = window:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.97)

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -14)
  title:SetText("Set up CombatHUD")
  local intro = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  intro:SetWidth(428)
  intro:SetJustifyH("LEFT")
  intro:SetText("Your HUD is ready for your class. A few choices to start; they show on screen as you pick. Everything else can be changed later.")

  Label(window, "Size", -76)
  refreshers[#refreshers + 1] = Choices(window, -76, SIZES, CurrentSize, SetSize)
  Label(window, "Position", -112)
  refreshers[#refreshers + 1] = Choices(window, -112, POSITIONS,
    function() return profile.hudPosition or "low" end, SetPosition)

  Label(window, "Also show", -150)
  local function Toggle(key)
    return function() return Meter(key).enabled == true end,
      function() Meter(key).enabled = not Meter(key).enabled end
  end
  local healthGet, healthToggle = Toggle("health")
  local castGet, castToggle = Toggle("cast")
  local swingGet, swingToggle = Toggle("swing")
  local health = Check(window, 110, -150, "Health bar", healthGet, healthToggle)
  local cast = Check(window, 220, -150, "Cast bar", castGet, castToggle)
  local swing = Check(window, 330, -150, "Swing timer", swingGet, swingToggle)
  local hideGame = Check(window, 220, -176, "Hide the game's cast bar",
    function() return Meter("cast").hideGame ~= false end,
    function() Meter("cast").hideGame = Meter("cast").hideGame == false end)
  refreshers[#refreshers + 1] = function()
    health()
    cast()
    swing()
    hideGame(castGet())
  end

  local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 50)
  hint:SetWidth(428)
  hint:SetJustifyH("LEFT")
  hint:SetText("Later: /chud edit (or right-click the minimap button) to move bars, resize them with the gear on their name, and drop spells on them. /chud for every setting. This window: Quick Setup on your profile's page.")

  local done = NewButton(window, 120, 26, "Done")
  done:SetPoint("BOTTOMRIGHT", -16, 14)
  done:SetScript("OnClick", function() window:Hide() end)

  -- However it closes (Done, Escape), this character has seen it.
  window:SetScript("OnHide", function()
    local settings = ns.CharSettings()
    if settings then settings.quickSetup = nil end
  end)
  table.insert(UISpecialFrames, "CombatHUDQuickSetup") -- Escape closes it
  window:Hide()
end

-- Redraws the choices, and the HUD (when it's the profile in use).
function QuickSetup.Refresh()
  if not window or not profile then return end
  for _, refresh in ipairs(refreshers) do refresh() end
  if profile == ns.profile and not InCombatLockdown() then ns.Rebuild(true) end
  if ns.Options.Refresh then ns.Options.Refresh() end
end

-- target: the profile to set up (the one in use if left out).
function QuickSetup.Show(target)
  if InCombatLockdown() then
    ns.Print("Quick setup can't be used in combat.")
    return
  end
  profile = target or ns.profile
  if not profile then return end
  if not window then Create() end
  window:Show()
  QuickSetup.Refresh()
end

-- After a new character's first login, once out of combat.
local waiting
local function ShowIfNew()
  local settings = ns.CharSettings()
  if not (settings and settings.quickSetup and ns.profile) then return end
  if InCombatLockdown() then
    waiting = true
    return
  end
  QuickSetup.Show()
end

ns.On("PLAYER_LOGIN", function() C_Timer.After(2, ShowIfNew) end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if waiting then
    waiting = nil
    ShowIfNew()
  end
end)
