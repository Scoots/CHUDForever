-- Swing timer for auto-attacks: a row each for the main hand, off hand and
-- ranged weapon. Auto (the default) shows what you have equipped: the main
-- hand, the off hand while you dual wield, and for hunters the ranged weapon.
-- Otherwise config.hands picks any of them.
--
-- The game has its own swing timer (SwingTimerMainHandFrame, ...Off..., ...Ranged...),
-- which knows every swing, pauses while you can't swing (out of range,
-- stunned) and follows haste (Flurry, Bloodlust). When it's there, each of
-- our rows follows it: the game's bar is made see-through and its value is
-- handed to an invisible bar on our row, whose fill our lit texture is
-- clipped to. Handing on a value works even when it's secret; the time text
-- is only worked out when it isn't.
--
-- Without it: the combat log is closed to addons on this client
-- (registering for it is a blocked action), so single swings can't be seen,
-- and the timer is an estimate:
-- it starts when you start auto-attacking (PLAYER_ENTER_COMBAT), repeats at
-- your weapon speed, and resyncs when an on-next-swing ability lands (Heroic
-- Strike, Cleave, Maul, Raptor Strike) or Slam. Attack speed can be secret in
-- combat; the last readable speed is kept.
local _, ns = ...
local issecret = ns.issecret

local Swing = {}
ns.Swing = Swing

local frame
local config
local visualRowHeight = 14
local visualGap = 1

local WHITE = ns.WHITE
local COLORS = {
  main = { 0.95, 0.72, 0.2 },
  off = { 0.35, 0.75, 1 },
  ranged = { 0.45, 0.85, 0.35 },
}
local HANDS = { "main", "off", "ranged" } -- the rows, top to bottom
local LABELS = { main = "MH", off = "OH", ranged = "RNG" }

local BG_COLORS = {
  dark = { 0.08, 0.08, 0.1 },
  slate = { 0.12, 0.14, 0.18 },
  blue = { 0.08, 0.14, 0.24 },
  green = { 0.08, 0.18, 0.12 },
  red = { 0.22, 0.08, 0.08 },
}

-- on: that hand is attacking (melee auto-attack, or Auto Shot / Shoot repeating).
local swings = {
  main = { speed = 0, last = 0, on = false },
  off = { speed = 0, last = 0, on = false },
  ranged = { speed = 0, last = 0, on = false },
}
local attacking = false -- melee auto-attack on

local function ReadSpeed(value)
  if issecret(value) or type(value) ~= "number" or value <= 0 then return nil end
  return value
end

local function EnsureLast(state)
  if not state.last or state.last <= 0 then state.last = GetTime() end
end

local function IsActive(state)
  return state ~= nil and state.on and state.speed ~= nil and state.speed > 0
end

-- The weapon speeds. A secret reading (in combat) keeps the last one; an
-- off hand that reads as none (no weapon there) is none.
local function RefreshSpeeds()
  local ok, main, off = pcall(UnitAttackSpeed, "player")
  if not ok then return end
  if not issecret(main) then
    swings.main.speed = ReadSpeed(main) or 0
    if swings.main.speed > 0 then EnsureLast(swings.main) end
  end
  if not issecret(off) then
    swings.off.speed = ReadSpeed(off) or 0
    if swings.off.speed > 0 then EnsureLast(swings.off) end
  end
  if UnitRangedDamage then
    local okRanged, speed = pcall(UnitRangedDamage, "player")
    if okRanged and not issecret(speed) then swings.ranged.speed = ReadSpeed(speed) or 0 end
  end
end

local function NewHand(parent, key, label)
  local row = CreateFrame("StatusBar", nil, parent)
  row:SetStatusBarTexture(WHITE)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetTexture(WHITE)
  row.text = row:CreateFontString(nil, "OVERLAY")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetShadowColor(0, 0, 0, 1)
  row.text:SetShadowOffset(1, -1)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("RIGHT", -4, 0)
  row.label:SetText(label)

  local r, g, b = COLORS[key][1], COLORS[key][2], COLORS[key][3]
  row:SetStatusBarColor(r, g, b)
  row.bg:SetVertexColor(r * 0.18, g * 0.18, b * 0.18, 0.9)

  row:SetMinMaxValues(0, 1)
  row:SetValue(0)

  -- Following the game's bar: an invisible copy of it, and our fill clipped
  -- to the edge of the copy's fill.
  row.mirror = CreateFrame("StatusBar", nil, row)
  row.mirror:SetAllPoints(row)
  row.mirror:SetStatusBarTexture(WHITE)
  row.mirror:GetStatusBarTexture():SetAlpha(0)
  row.mirror:SetMinMaxValues(0, 1)
  row.mirror:SetValue(0)
  row.clip = CreateFrame("Frame", nil, row, "DisableUntrustedLayoutScriptsTemplate")
  row.clip:SetClipsChildren(true)
  row.lit = row.clip:CreateTexture(nil, "ARTWORK")
  row.lit:SetAllPoints(row)
  row.lit:SetTexture(WHITE)
  row.lit:SetVertexColor(r, g, b)
  row.clip:Hide()
  row.key = key
  return row
end

-- The game's swing bars ---------------------------------------------------------------

local NATIVE = { main = "SwingTimerMainHandFrame", off = "SwingTimerOffHandFrame", ranged = "SwingTimerRangedFrame" }

local function IsType(object, kind)
  return type(object) == "table" and object.IsObjectType ~= nil and object:IsObjectType(kind)
end

-- The status bar of one of the game's swing frames: the frame itself, or a child.
local function NativeBar(native)
  if not native then return end
  if IsType(native, "StatusBar") then return native end
  for _, key in ipairs({ "Bar", "StatusBar", "SwingBar", "bar", "statusBar" }) do
    if IsType(native[key], "StatusBar") then return native[key] end
  end
  for _, child in ipairs({ native:GetChildren() }) do
    if IsType(child, "StatusBar") then return child end
  end
end

local function NativeText(native, bar)
  for _, holder in ipairs({ bar, native }) do
    for _, key in ipairs({ "Text", "TimeText", "Time", "text" }) do
      if IsType(holder[key], "FontString") then return holder[key] end
    end
  end
end

-- Makes every part of the game's swing frame see-through (it keeps working).
local function Unseen(native, bar)
  for _, holder in ipairs({ native, bar }) do
    for _, region in ipairs({ holder:GetRegions() }) do region:SetAlpha(0) end
  end
  local fill = bar:GetStatusBarTexture()
  if fill then fill:SetAlpha(0) end
end

-- Our fill: the copy's fill, or the other side of it. The game's bar either
-- fills as the swing comes or empties; row.rising says which once it's been
-- seen moving (until then it's taken to empty).
local function AnchorClip(row)
  local fill = row.mirror:GetStatusBarTexture()
  local reverse = row.mirror:GetReverseFill()
  local other = (config and config.fill == "up") ~= (row.rising == true)
  row.clip:ClearAllPoints()
  if other then
    if reverse then
      row.clip:SetPoint("TOPLEFT", row, "TOPLEFT")
      row.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT")
    else
      row.clip:SetPoint("TOPRIGHT", row, "TOPRIGHT")
      row.clip:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
    end
  elseif reverse then
    row.clip:SetPoint("TOPRIGHT", row, "TOPRIGHT")
    row.clip:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT")
  else
    row.clip:SetPoint("TOPLEFT", row, "TOPLEFT")
    row.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
  end
end

-- Our row follows the game's bar for its hand. Returns false when there's none.
local function Follow(row)
  local native = _G[NATIVE[row.key]]
  local bar = NativeBar(native)
  if not bar then return false end
  row.native, row.nativeBar = native, bar
  if not row.hooked then
    row.hooked = true
    -- Its time, copied if it has one (it may be secret; it's only handed on).
    local text = NativeText(native, bar)
    if text then
      row.copiesText = true
      hooksecurefunc(text, "SetText", function(_, value)
        if row.following then row.text:SetText(value) end
      end)
    end
  end
  row.following = true
  Unseen(native, bar)
  local reverse = bar.GetReverseFill and bar:GetReverseFill()
  row.mirror:SetReverseFill(not issecret(reverse) and reverse == true)
  AnchorClip(row)
  row:SetValue(0) -- our own fill stays empty; the clipped one shows
  row.text:SetText("")
  return true
end

-- Hands the game's bar on to our row, each frame.
local function Mirror(row, state)
  local native, bar = row.native, row.nativeBar
  local shown = native:IsShown()
  if row.clip:IsShown() ~= shown then row.clip:SetShown(shown) end
  if not shown then
    if not row.copiesText then row.text:SetText("") end
    return
  end
  local low, high = bar:GetMinMaxValues()
  local value = bar:GetValue()
  row.mirror:SetMinMaxValues(low, high)
  row.mirror:SetValue(value)
  if issecret(value) or issecret(low) or issecret(high) or high <= low then return end
  local fraction = (value - low) / (high - low)
  -- Which way it goes, from how it moves (a swing jumps it back).
  if row.lastFraction then
    local delta = fraction - row.lastFraction
    local rising
    if delta > 0 and delta < 0.5 then rising = true elseif delta < 0 and delta > -0.5 then rising = false end
    if rising ~= nil and rising ~= row.rising then
      row.rising = rising
      AnchorClip(row)
    end
  end
  row.lastFraction = fraction
  if row.copiesText then return end
  local speed = state.speed
  if not speed or speed <= 0 then
    row.text:SetText("")
    return
  end
  local done = row.rising and fraction or (1 - fraction) -- how much of the swing has passed
  if (config and config.fill) == "up" then
    ns.SetNumberText(row.text, "%.1f", done * speed)
  else
    ns.SetNumberText(row.text, "%.1f", (1 - done) * speed)
  end
end

-- /chud debug swing: what the game's swing frames are, for working out problems.
function Swing.Probe()
  local function Show(value)
    if issecret(value) then return "secret" end
    return tostring(value)
  end
  for key, name in pairs(NATIVE) do
    local native = _G[name]
    if not native then
      ns.Print(name .. ": not on this client.")
    else
      local children = {}
      for _, child in ipairs({ native:GetChildren() }) do children[#children + 1] = child:GetObjectType() end
      ns.Print(("%s (%s): shown %s, protected %s, %d regions, children: %s."):format(name, native:GetObjectType(),
        tostring(native:IsShown()), tostring(native:IsProtected()), select("#", native:GetRegions()),
        #children > 0 and table.concat(children, ", ") or "none"))
      local bar = NativeBar(native)
      if bar then
        local low, high = bar:GetMinMaxValues()
        local row = frame and frame[key]
        ns.Print(("  bar: value %s of %s-%s, reverse fill %s, text %s, the HUD follows it: %s."):format(
          Show(bar:GetValue()), Show(low), Show(high), tostring(bar.GetReverseFill and bar:GetReverseFill()),
          NativeText(native, bar) and "found" or "none", tostring(row ~= nil and row.following == true)))
      else
        ns.Print("  no status bar found in it.")
      end
    end
  end
end

local function Create()
  frame = CreateFrame("Frame", nil, UIParent)

  local border = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetColorTexture(0, 0, 0, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetTexture(WHITE)

  for _, key in ipairs(HANDS) do frame[key] = NewHand(frame, key, LABELS[key]) end

  ns.AttachMover(frame, function() return config end, function() return "CENTER" end, {
    onGear = function(gear) ns.EditMenu.GearForMeter("swing", "Swing timer", config, gear) end,
  })
  frame.mover.SetLabel("Swing")
end

-- What's equipped. Works in combat.
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

local function WeaponIn(slot)
  local id = GetInventoryItemID("player", slot)
  if not id or issecret(id) then return false end
  local ok, _, _, _, _, _, classID = pcall(GetItemInfoInstant, id)
  return ok and not issecret(classID) and classID == 2 -- Weapon (not a shield or a held item)
end

local _, playerClass = UnitClass("player")

-- The rows to show, in order. Auto: the main hand, the off hand while you
-- dual wield, the ranged weapon for hunters (others can tick Ranged).
local function ShownHands()
  local shown = {}
  if not config then return shown end
  local hands = config.hands or {}
  for _, key in ipairs(HANDS) do
    local on
    if config.mode == "pick" then
      on = hands[key] == true
    elseif key == "main" then
      on = true
    elseif key == "off" then
      on = WeaponIn(17)
    else
      on = playerClass == "HUNTER" and WeaponIn(18)
    end
    if on then shown[#shown + 1] = key end
  end
  return shown
end

local shownKey = "" -- the rows last laid out, to notice gear changes
local shownRows = {}

local function Layout(shown)
  if not frame or not config then return end
  local rowHeight = math.max(4, math.floor(visualRowHeight or config.height or 14))
  local gap = math.max(0, math.floor(visualGap or 0))
  local fontSize = math.max(8, math.floor(math.min(rowHeight, 22) * 0.62))
  local wanted = {}
  for index, key in ipairs(shown) do
    wanted[key] = true
    local row = frame[key]
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(index - 1) * (rowHeight + gap))
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * (rowHeight + gap))
    row:SetHeight(rowHeight)
    row.text:SetFont(ns.Font(), fontSize, "OUTLINE")
    row:Show()
  end
  for _, key in ipairs(HANDS) do
    if not wanted[key] then
      frame[key]:Hide()
      frame[key].following = false
      frame[key].clip:Hide()
    end
  end
end

local function ApplyStyle()
  if not frame or not config then return end
  local bg = BG_COLORS[config.bgColor or "dark"] or BG_COLORS.dark
  local containerAlpha = math.max(0, math.min(1, config.containerAlpha or 0.8))
  frame.bg:SetVertexColor(0, 0, 0, 0)
  for _, key in ipairs(HANDS) do frame[key].bg:SetVertexColor(bg[1], bg[2], bg[3], containerAlpha) end
end

local function UpdateHand(row, state)
  if row.following then return Mirror(row, state) end
  local speed = state.speed
  if not speed or speed <= 0 then
    row:SetValue(0)
    row.text:SetText("")
    return
  end
  local now = GetTime()
  if not IsActive(state) then
    row:SetValue(0)
    row.text:SetText("")
    return
  end
  if not state.last or state.last <= 0 then state.last = now end
  local elapsed = now - state.last
  if elapsed < 0 then
    state.last = now
    elapsed = 0
  end
  if elapsed >= speed then
    local loops = math.floor(elapsed / speed)
    state.last = state.last + loops * speed
    elapsed = now - state.last
  end
  local remain = math.max(0, speed - elapsed)
  local fill = config and config.fill or "down"
  if fill == "up" then
    local progress = math.max(0, math.min(1, elapsed / speed))
    row:SetValue(progress)
    ns.SetNumberText(row.text, "%.1f", elapsed)
  else
    row:SetValue(remain / speed)
    ns.SetNumberText(row.text, "%.1f", remain)
  end
end

function Swing.Update()
  if not frame or not frame:IsShown() or not config then return end
  for _, key in ipairs(shownRows) do UpdateHand(frame[key], swings[key]) end
end

-- Old settings: "main" / "both" became picked hands; "auto" stays.
local function Migrate()
  if config.modeVersion == 2 then return end
  if config.mode == "both" then
    config.mode, config.hands = "pick", { main = true, off = true }
  elseif config.mode == "main" then
    config.mode, config.hands = "pick", { main = true }
  elseif config.mode ~= "pick" and config.mode ~= "none" then
    config.mode = "auto"
  end
  config.modeVersion = 2
end

function Swing.Apply(newConfig)
  config = newConfig
  Swing.config = newConfig
  if config then Migrate() end
  local shown = ShownHands()
  shownKey, shownRows = table.concat(shown, ","), shown
  if not config or not config.enabled or config.mode == "none" or #shown == 0 then
    if frame then
      frame:Hide()
      for _, key in ipairs(HANDS) do frame[key].following = false end
    end
    return
  end

  if not frame then
    Create()
    frame:SetScript("OnUpdate", Swing.Update)
  end

  local scale = ns.profile and ns.profile.scale or 1
  local width = math.floor((config.width or 250) * scale + 0.5)
  local rowHeight = math.max(4, math.floor((config.height or 14) * scale + 0.5))
  local gap = math.max(0, math.floor((config.gap or 1) * scale + 0.5))
  frame:SetSize(width, rowHeight * #shown + gap * (#shown - 1))
  visualRowHeight, visualGap = rowHeight, gap

  for _, key in ipairs(HANDS) do
    frame[key]:SetStatusBarTexture(ns.BarTexture())
    frame[key].label:SetText(LABELS[key])
  end
  ApplyStyle()

  ns.PlaceFrame(frame, config, "CENTER")
  frame.mover:SetShown(ns.editMode)

  RefreshSpeeds()
  Layout(shown)
  frame:Show()
  -- Follow the game's own swing bars where they're there.
  for _, key in ipairs(shown) do
    if not Follow(frame[key]) then frame[key].following = false end
  end
  Swing.Update()
end

function Swing.SetMoverShown(shown)
  if frame and frame:IsShown() then frame.mover:SetShown(shown) end
end

function Swing.Frame()
  return frame
end

-- A swing just happened (auto-attack starting, or an on-next-swing ability landing).
local function Swung(both)
  local now = GetTime()
  swings.main.last = now
  if both then swings.off.last = now end
  Swing.Update()
end

-- Abilities that land on a swing (or, Slam, restart it).
local ON_SWING = { 78, 845, 6807, 2973, 1464 } -- Heroic Strike, Cleave, Maul, Raptor Strike, Slam
-- Ranged auto-attacks: each one is a shot.
local SHOTS = { 75, 5019, 3018, 2764 } -- Auto Shot, Shoot (wand), Shoot (bow), Throw
local function OnSwingName(name)
  return ns.NameSet(ON_SWING)[name] == true
end

local function ShotName(name)
  return ns.NameSet(SHOTS)[name] == true
end

local function AttackSpeedChanged()
  RefreshSpeeds()
  Swing.Update()
end

local function SetAttacking(on)
  attacking = on
  swings.main.on, swings.off.on = on, on
end

ns.On("PLAYER_ENTERING_WORLD", function()
  RefreshSpeeds()
  ns.Schedule(Swing.Update)
end)
ns.OnUnit("UNIT_ATTACK_SPEED", "player", function()
  ns.Schedule(AttackSpeedChanged)
end)
ns.OnUnit("UNIT_RANGEDDAMAGE", "player", function()
  ns.Schedule(AttackSpeedChanged)
end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function()
  ns.Schedule(AttackSpeedChanged)
  -- A weapon on or off (in combat too): Auto's rows come or go.
  ns.Schedule(function()
    if config and config.enabled and table.concat(ShownHands(), ",") ~= shownKey then Swing.Apply(config) end
  end)
end)
-- Auto-attack starting and stopping.
ns.On("PLAYER_ENTER_COMBAT", function()
  RefreshSpeeds()
  SetAttacking(true)
  Swung(true)
end)
ns.On("PLAYER_LEAVE_COMBAT", function()
  SetAttacking(false)
  Swing.Update()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  SetAttacking(false)
  ns.Schedule(Swing.Update)
end)
-- Auto Shot / Shoot repeating.
ns.On("START_AUTOREPEAT_SPELL", function()
  RefreshSpeeds()
  swings.ranged.on = true
  Swing.Update()
end)
ns.On("STOP_AUTOREPEAT_SPELL", function()
  swings.ranged.on = false
  Swing.Update()
end)
ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID then return end
  local name = C_Spell.GetSpellName(spellID)
  if not name or issecret(name) then return end
  if ShotName(name) then
    swings.ranged.last = GetTime()
    Swing.Update()
  elseif attacking and OnSwingName(name) then
    Swung(false)
  end
end)
