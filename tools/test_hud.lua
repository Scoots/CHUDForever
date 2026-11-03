-- Loads the whole addon in plain Lua 5.1 against a stand-in for the game, and
-- builds every class's starting HUD for every race it can be.
-- Run from the addon folder:  lua tools/test_hud.lua
--
-- The stand-in only remembers what the addon sets (points, sizes, alpha); any
-- other widget method does nothing. So this finds crashes and wrong layouts, not
-- how the game really draws them.

local failures, passed = 0, 0

local function check(condition, message)
  if condition then
    passed = passed + 1
  else
    failures = failures + 1
    print("FAIL: " .. message)
  end
end

local function equal(actual, expected, message)
  check(actual == expected, ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

-- The game's widgets ---------------------------------------------------------------------------

local objects, registered, errors, delayed
local Widget = {}
local WidgetMeta = {
  __index = function(_, key)
    local method = Widget[key]
    if method then return method end
    -- Any other widget method does nothing.
    if type(key) == "string" and key:match("^[A-Z]") then return function() end end
  end,
}

local function NewWidget(kind, parent)
  local widget = setmetatable({ widgetType = kind, parentWidget = parent, scripts = {}, shownFlag = true, alphaValue = 1,
    widthValue = 0, heightValue = 0, pointList = {} }, WidgetMeta)
  objects[#objects + 1] = widget
  return widget
end

function Widget:SetPoint(...) self.pointList[#self.pointList + 1] = { ... } end
function Widget:ClearAllPoints() self.pointList = {} end
function Widget:GetNumPoints() return #self.pointList end
function Widget:GetPoint(index)
  local point = self.pointList[index or 1]
  if point then return unpack(point) end
end
function Widget:SetSize(width, height) self.widthValue, self.heightValue = width, height end
function Widget:SetWidth(width) self.widthValue = width end
function Widget:SetHeight(height) self.heightValue = height end
function Widget:GetWidth() return self.widthValue end
function Widget:GetHeight() return self.heightValue end
function Widget:GetSize() return self.widthValue, self.heightValue end
function Widget:Show() self.shownFlag = true end
function Widget:Hide() self.shownFlag = false end
function Widget:SetShown(shown) self.shownFlag = shown and true or false end
function Widget:IsShown() return self.shownFlag end
function Widget:IsVisible() return self.shownFlag end
function Widget:SetAlpha(alpha) self.alphaValue = alpha end
function Widget:GetAlpha() return self.alphaValue end
function Widget:SetScript(name, fn) self.scripts[name] = fn end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:HookScript() end
function Widget:HasScript() return true end
function Widget:RegisterEvent(event) registered[event] = registered[event] or {}; table.insert(registered[event], self) end
function Widget:RegisterUnitEvent(event) self:RegisterEvent(event) end
function Widget:IsEventRegistered() return false end
function Widget:CreateTexture() return NewWidget("Texture", self) end
function Widget:CreateFontString() return NewWidget("FontString", self) end
function Widget:CreateMaskTexture() return NewWidget("Texture", self) end
function Widget:CreateLine() return NewWidget("Line", self) end
function Widget:CreateAnimationGroup() return NewWidget("AnimationGroup", self) end
function Widget:CreateAnimation() return NewWidget("Animation", self) end
function Widget:SetParent(parent) self.parentWidget = parent end
function Widget:GetParent() return self.parentWidget end
function Widget:GetFrameLevel() return self.levelValue or 1 end
function Widget:SetFrameLevel(level) self.levelValue = level end
function Widget:GetFrameStrata() return "MEDIUM" end
function Widget:GetCenter() return 960, 540 end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self.widthValue end
function Widget:GetTop() return self.heightValue end
function Widget:GetBottom() return 0 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetScale() return 1 end
function Widget:IsProtected() return false end
function Widget:IsForbidden() return false end
function Widget:GetObjectType() return self.widgetType end
function Widget:IsObjectType(kind) return self.widgetType == kind end
function Widget:SetText(text) self.textValue = text end
function Widget:GetText() return self.textValue end
function Widget:GetStringWidth() return 40 end
function Widget:GetStringHeight() return 12 end
function Widget:GetLineHeight() return 12 end
function Widget:GetFont() return "font", 12, "" end
function Widget:SetTexture(texture) self.textureValue = texture end
function Widget:GetTexture() return self.textureValue end
function Widget:SetDesaturation(gray) self.grayValue = gray end
function Widget:GetStatusBarTexture() self.fill = self.fill or NewWidget("Texture", self); return self.fill end
function Widget:GetValue() return self.valueNumber or 0 end
function Widget:SetValue(value) self.valueNumber = value end
function Widget:GetMinMaxValues() return 0, 1 end
function Widget:GetCountdownFontString() self.count = self.count or NewWidget("FontString", self); return self.count end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:GetCursorPosition() return 0 end
function Widget:GetNumber() return 0 end
function Widget:GetNumRegions() return 0 end
function Widget:GetNumChildren() return 0 end
function Widget:GetDuration() return 0 end
function Widget:IsPlaying() return false end
function Widget:IsMouseOver() return false end
function Widget:IsMovable() return true end
-- The aura widget builds its buttons when it's given a group or a slot.
function Widget:AddAuraGroup(_, _, options) if options.initializeFrame then options.initializeFrame(NewWidget("Button", self)) end end
function Widget:AddAuraSlot(_, _, options) if options.initializeFrame then options.initializeFrame(NewWidget("Button", self)) end end

local function Fire(event, ...)
  for _, widget in ipairs(registered[event] or {}) do
    local handler = widget.scripts.OnEvent
    if handler then handler(widget, event, ...) end
  end
end

-- One frame's worth of OnUpdate scripts, which run scheduled work.
local function Tick()
  for index = 1, #objects do
    local widget = objects[index]
    local handler = widget.scripts.OnUpdate
    if handler and widget.shownFlag then handler(widget, 0.05) end
  end
end

-- The game's functions --------------------------------------------------------------------------

local scenario
local RACE_IDS = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Tauren = 6, Gnome = 7, Troll = 8, Skyborne = 95 }

-- Helpers of the game's that only hand back something to pass to a widget.
local anything
anything = setmetatable({}, { __index = function() return anything end, __call = function() return NewWidget("Helper") end })

local function SetUpGame()
  objects, registered, errors, delayed = {}, {}, {}, {}
  CombatHUDDB = nil
  UISpecialFrames = {}
  SlashCmdList = {}
  UIParent = NewWidget("Frame")
  UIParent:SetSize(1920, 1080)
  GameTooltip = NewWidget("GameTooltip")
  WorldFrame = NewWidget("Frame")
  Minimap = NewWidget("Minimap")
  Minimap:SetSize(140, 140)
  CreateFrame = function(kind, name, parent)
    local widget = NewWidget(kind, parent)
    if name then _G[name] = widget end
    return widget
  end
  wipe = function(list) for key in pairs(list) do list[key] = nil end return list end
  tinsert, tremove = table.insert, table.remove
  strtrim = function(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
  strsplit = function(separator, text)
    local parts = {}
    for part in (text .. separator):gmatch("(.-)" .. separator) do parts[#parts + 1] = part end
    return unpack(parts)
  end
  securecallfunction = function(fn, ...)
    local args, count = { ... }, select("#", ...)
    xpcall(function() fn(unpack(args, 1, count)) end, function(message) errors[#errors + 1] = debug.traceback(message, 2) end)
  end
  geterrorhandler = function() return function(message) errors[#errors + 1] = tostring(message) end end
  hooksecurefunc = function() end
  time, date = os.time, os.date
  debugstack = function() return "" end
  AnchorUtil, GridLayoutUtil = anything, anything
  InCombatLockdown = function() return scenario.combat == true end
  GetTime = function() return 1000 end
  GetScreenHeight, GetScreenWidth = function() return 1080 end, function() return 1920 end
  GetCursorPosition = function() return 0, 0 end
  IsShiftKeyDown, IsAltKeyDown, IsControlKeyDown = function() return false end, function() return false end, function() return false end
  GetCursorInfo = function() end
  ClearCursor = function() end
  UnitName = function() return "Tester" end
  GetRealmName = function() return "Realm" end
  UnitClass = function() return scenario.class, scenario.class end
  UnitRace = function() return scenario.race, scenario.race, RACE_IDS[scenario.race] end
  UnitLevel = function() return 60 end
  UnitExists = function(unit) return unit == "player" end
  UnitGUID = function(unit) return "guid-" .. tostring(unit) end
  UnitPower, UnitPowerMax = function() return 50 end, function() return 100 end
  UnitPowerType = function() return 0, "MANA" end
  UnitHealth, UnitHealthMax = function() return 50 end, function() return 100 end
  UnitAffectingCombat = function() return scenario.combat == true end
  UnitGetTotalAbsorbs = function() return 0 end
  UnitIsDeadOrGhost = function() return false end
  UnitIsFriend = function() return true end
  UnitCanAttack = function() return false end
  UnitAttackSpeed = function() return 2, 0 end
  UnitRangedDamage = function() return 2 end
  IsMounted = function() return false end
  IsResting = function() return false end
  IsInInstance = function() return false end
  GetShapeshiftFormID = function() return scenario.form end
  IsStealthed = function() return scenario.stealthed == true end
  GetSpellBaseCooldown = function(id) return (scenario.cooldowns[id] or 0) * 1000, 1500 end
  local function Knows(id) return type(id) == "number" and not (scenario.unknown and scenario.unknown[id]) end
  IsPlayerSpell = Knows
  GetInventoryItemID = function(_, slot) return (slot == 16 or slot == 17) and 19019 or nil end
  GetInventoryItemTexture = function() return "icon" end
  GetActionInfo = function() end
  GetTalentTabInfo, GetNumTalentTabs = function() end, function() return 3 end
  GetPlayerFacing = function() return 0 end
  Enum = {
    ItemClass = { Weapon = 2 }, WeaponSlot = { MainHand = 0, OffHand = 1 }, ItemEnchantType = { None = 0, Permanent = 1, Temporary = 2, Imbue = 3 },
    PowerType = { Mana = 0, Rage = 1, Energy = 3 }, ItemSlotFilterType = {},
  }
  CustomAuraContainerAuraProcessingPolicy = { None = 0 }
  C_AddOns = { GetAddOnMetadata = function() return "test" end, IsAddOnLoaded = function() return true end, LoadAddOn = function() end }
  C_Timer = {
    After = function(_, fn) delayed[#delayed + 1] = fn end,
    NewTicker = function() return NewWidget("Ticker") end,
    NewTimer = function() return NewWidget("Ticker") end,
  }
  C_CurveUtil = {
    CreateCurve = function() return NewWidget("Curve") end, CreateColorCurve = function() return NewWidget("Curve") end,
    EvaluateColorValueFromBoolean = function(value, yes, no) if value then return yes end return no end,
  }
  C_Spell = {
    GetSpellName = function(id) return type(id) == "number" and ("Spell" .. id) or nil end,
    GetSpellTexture = function(id) return "icon" .. tostring(id) end,
    GetSpellInfo = function(name)
      local id = tonumber(tostring(name):match("^Spell(%d+)$"))
      return id and { spellID = id, name = name, iconID = id } or nil
    end,
    GetSpellDescription = function(id) return scenario.slows and scenario.slows[id] and "Slows the target for 9 sec." or "" end,
    IsSpellHarmful = function(id) return scenario.slows ~= nil and scenario.slows[id] == true end,
    GetSpellCooldown = function() return { startTime = 0, duration = 0, isEnabled = true, isActive = false } end,
    GetSpellCharges = function() end,
    GetSpellPowerCost = function() return {} end,
    IsSpellUsable = function() return true, false end,
    IsCurrentSpell = function() return false end,
  }
  C_SpellBook = { IsSpellKnown = Knows }
  C_SpecializationInfo = {
    GetSpecializationInfo = function(tab) return tab, "Tree", "", "icon", nil, nil, (scenario.points or {})[tab] or 0 end,
  }
  if scenario.noSpecInfo then C_SpecializationInfo = nil end
  C_Item = {
    GetItemCount = function() return 0 end, GetItemSpell = function() end, GetItemIconByID = function() return "icon" end,
    GetItemNameByID = function() return "Item" end, GetItemCooldown = function() return 0, 0, 1 end,
    GetItemInfoInstant = function() return 19019, nil, nil, nil, "icon", 2 end, GetWeaponEnchantInfo = function() return {} end,
  }
  C_UnitAuras = { GetAuraDataByIndex = function() end, GetPlayerAuraBySpellID = function() end, GetAuraDataBySpellName = function() end }
  C_Spell.GetSpellCooldownDuration = function() return NewWidget("Duration") end
  C_SpellBook.IsSpellInSpellBook = C_SpellBook.IsSpellKnown
  C_SpellBook.GetSpellBookItemInfo = function() end
  C_ActionBar = { EnableActionRangeCheck = function() end, HasRangeRequirements = function() return false end, IsActionInRange = function() end }
  C_CVar = { GetCVarBool = function() return true end }
  C_SpellActivationOverlay = { IsSpellOverlayed = function() return false end }
  C_StringUtil = { CreateNumericRuleFormatter = function() return NewWidget("Formatter") end }
  C_UnitAuras.AddAuraSound, C_UnitAuras.RemoveAuraSound = function() end, function() end
  AuraContainerSortMethod, AuraContainerSortDirection = { ExpirationOnly = 1 }, { Normal = 0 }
  PowerBarColor = {}
  CreateColor = function() return NewWidget("Color") end
  GetBuildInfo = function() return "1.60.1", "70707", "Nov 2 2026", 16001 end
  GetInventoryItemCooldown = function() return 0, 0, 1 end
  GetItemIcon = function() return "icon" end
  PlaySoundFile = function() end
  UnitCastingInfo, UnitChannelInfo = function() end, function() end
  UnitIsDead = function() return false end
  UnitPowerPercent = function() return 50 end
  UnitPosition = function() return 0, 0, 0, 0 end
  GetTotemInfo = function() return false end
  GetTotemDuration = function() return NewWidget("Duration") end
  InterfaceOptions_AddCategory = function() end
  Settings = anything
end

-- Loading the addon ------------------------------------------------------------------------------

local function TocFiles()
  local files = {}
  for line in io.lines("CHUDForever.toc") do
    local file = line:match("^([%w_]+%.lua)%s*$")
    if file then files[#files + 1] = file end
  end
  return files
end
local FILES = TocFiles()

local function Boot(class, race, form, stealthed, options)
  scenario = { class = class, race = race, form = form, stealthed = stealthed, cooldowns = {
    [11113] = 45, [18562] = 15, [408120] = 6, [1322605] = 8, [407995] = 6, [12294] = 6, [23881] = 6, [23922] = 6, [1680] = 10, [7384] = 5, [6572] = 5, [2565] = 5,
  } }
  for key, value in pairs(options or {}) do scenario[key] = value end
  SetUpGame()
  local ns = {}
  for _, file in ipairs(FILES) do assert(loadfile(file))("CHUDForever", ns) end
  Fire("ADDON_LOADED", "CHUDForever")
  Fire("PLAYER_LOGIN")
  Fire("PLAYER_ENTERING_WORLD", true, false)
  Tick()
  Tick()
  return ns
end

local function Bars(ns)
  local byName = {}
  for _, frame in ipairs(ns.Bar.Frames()) do
    if frame.config then byName[frame.config.name] = frame end
  end
  return byName
end

local function NoErrors(ns, what)
  for _, message in ipairs(errors) do check(false, what .. ": " .. tostring(message)) end
  for _, message in ipairs(ns.problems or {}) do check(false, what .. ": " .. tostring(message)) end
  check(#errors == 0 and #(ns.problems or {}) == 0, what .. " has no errors")
end

-- The middles of a bar's showing buttons, measured from the bar's middle.
local function ShownMiddles(frame)
  local list = {}
  for _, btn in ipairs(frame.buttons) do
    if btn.alphaValue ~= 0 then
      local place = btn.place
      local across = frame.vertical and -place.y or place.x
      list[#list + 1] = across + (frame.vertical and frame.itemHeight or frame.itemWidth) / 2
        - (frame.vertical and frame.heightValue or frame.widthValue) / 2
    end
  end
  return list
end

local function Mean(list)
  local total = 0
  for _, value in ipairs(list) do total = total + value end
  return #list > 0 and total / #list or 0
end

local function SetForm(ns, form, stealthed)
  scenario.form, scenario.stealthed = form, stealthed
  Fire("UPDATE_SHAPESHIFT_FORM")
  Fire("UPDATE_STEALTH")
  Tick()
  Tick()
end

-- Every class and race ---------------------------------------------------------------------------

local RACES = {
  WARRIOR = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll", "Skyborne" },
  PALADIN = { "Human", "Dwarf", "Skyborne" },
  HUNTER = { "Dwarf", "NightElf", "Orc", "Tauren", "Troll", "Skyborne" },
  ROGUE = { "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Troll" },
  PRIEST = { "Human", "Dwarf", "NightElf", "Gnome", "Scourge", "Troll", "Skyborne" },
  SHAMAN = { "Orc", "Tauren", "Troll", "Skyborne" },
  MAGE = { "Human", "Gnome", "Scourge", "Troll" },
  WARLOCK = { "Human", "Gnome", "Orc", "Scourge" },
  DRUID = { "NightElf", "Tauren" },
}

for class, races in pairs(RACES) do
  for _, race in ipairs(races) do
    local what = class .. " " .. race
    local ok, ns = pcall(Boot, class, race)
    check(ok, what .. " loads: " .. tostring(not ok and ns or ""))
    if ok then
      NoErrors(ns, what)
      local bars = Bars(ns)
      local name = ns.profileName
      check(name ~= nil, what .. " has a profile")
      for _, bar in ipairs({ "My Active Buffs", "Rotation", "Cooldowns", "Items", "Absorb" }) do
        check(bars[bar] ~= nil, what .. " has " .. bar)
      end
      local profile = ns.profile
      if bars.Rotation and bars.Cooldowns then
        check(bars["My Active Buffs"].config.y > bars.Rotation.config.y, what .. ": buffs above Rotation")
        check(bars.Rotation.config.y > profile.power.y, what .. ": Rotation above power")
        check(bars.Cooldowns.config.y < profile.power.y, what .. ": Cooldowns below power")
        equal(bars.Target, nil, what .. " has no Target bar")
        -- A button that comes and goes would push the row off center.
        for _, bar in ipairs({ "Rotation", "Cooldowns", "Utility" }) do
          for _, entry in ipairs(bars[bar] and bars[bar].config.buttons or {}) do
            if entry.aura then equal(entry.show, "always", what .. ": an aura button on " .. bar .. " holds its place") end
          end
        end
      end
      -- Rebuild From Bars keeps the class's own bars and adds no Target bar.
      local rebuilt, problem = pcall(ns.RebuildFromActionBars)
      check(rebuilt, what .. " rebuilds from bars: " .. tostring(problem))
      Tick()
      local after = Bars(ns)
      check(after.Absorb ~= nil and after.Target == nil, what .. ": Rebuild From Bars has Absorb and no Target")
      NoErrors(ns, what .. " after Rebuild From Bars")
    end
  end
end

-- Druid forms ------------------------------------------------------------------------------------

do
  local ns = Boot("DRUID", "Tauren", 5, false)
  NoErrors(ns, "druid in Bear Form")
  local rotation = Bars(ns).Rotation
  local shown = ShownMiddles(rotation)
  equal(#shown, 4, "Bear Form shows Maul, Swipe, Demoralizing Roar and Primal Bite")
  check(math.abs(Mean(shown)) < 0.51, "Bear Form's buttons are centered (off by " .. Mean(shown) .. ")")

  -- Forms change in combat, when aura widgets can't move: nothing may need to.
  local places = {}
  for index, btn in ipairs(rotation.buttons) do places[index] = btn.place.x end
  scenario.combat = true
  for _, state in ipairs({ { 1, false, 6, "Cat Form" }, { 1, true, 8, "Prowl" }, { nil, false, 4, "no form" }, { 31, false, 4, "Moonkin Form" }, { 3, false, 0, "Travel Form" }, { 5, false, 4, "Bear Form" } }) do
    SetForm(ns, state[1], state[2])
    local list = ShownMiddles(rotation)
    equal(#list, state[3], state[4] .. ": buttons showing")
    if #list > 0 then check(math.abs(Mean(list)) < 0.51, state[4] .. " is centered (off by " .. Mean(list) .. ")") end
  end
  for index, btn in ipairs(rotation.buttons) do equal(btn.place.x, places[index], "a button stays put when forms change") end
  scenario.combat = false
  NoErrors(ns, "changing forms")

  -- Swiftmend's long cooldown puts it on Cooldowns, where it hides in a form too.
  local cooldowns = Bars(ns).Cooldowns
  SetForm(ns, 5, false)
  check(cooldowns.collapse == true, "Cooldowns can close gaps: none of its spells leaves a debuff")
  check(math.abs(Mean(ShownMiddles(cooldowns))) < 0.51, "Cooldowns is centered in Bear Form")

  local utility = Bars(ns).Utility
  SetForm(ns, 1, false)
  check(math.abs(Mean(ShownMiddles(utility))) <= utility.step / 2, "Utility in Cat Form is within half a button of center")
end

-- Rogue stealth ----------------------------------------------------------------------------------

do
  local ns = Boot("ROGUE", "Human", nil, false)
  NoErrors(ns, "rogue")
  local rotation = Bars(ns).Rotation
  local out = ShownMiddles(rotation)
  check(math.abs(Mean(out)) < 0.51, "Rogue's Rotation is centered out of stealth (off by " .. Mean(out) .. ")")
  SetForm(ns, nil, true)
  local stealthed = ShownMiddles(rotation)
  equal(#stealthed, #out + 3, "Stealth adds Ambush, Cheap Shot and Garrote")
  check(math.abs(Mean(stealthed)) <= rotation.step / 2, "Stealth's row is within half a button of center")
  -- In the middle, nothing moved: the openers go outside the row.
  local seen = {}
  for _, middle in ipairs(stealthed) do
    check(not seen[middle], "no two showing buttons share a spot")
    seen[middle] = true
  end
end

-- Mage: the filler follows the spec --------------------------------------------------------------

do
  local TALENTS = { 12042, 12043, 400574, 11129, 11113, 11366, 11426, 13031, 13032, 13033, 11958, 12472, 1312002 }
  local function Unknown(...)
    local unknown = {}
    for _, id in ipairs(TALENTS) do unknown[id] = true end
    for _, id in ipairs({ ... }) do unknown[id] = nil end
    return unknown
  end
  local function Filler(ns) return Bars(ns).Rotation.buttons[1].spellID end

  for _, case in ipairs({ { { 21, 0, 0 }, 5143, "MAGE_ARCANE" }, { { 0, 21, 0 }, 133, "MAGE_FIRE" }, { { 0, 0, 21 }, 116, "MAGE_FROST" } }) do
    local ns = Boot("MAGE", "Human", nil, false, { points = case[1], unknown = Unknown() })
    equal(ns.specKey, case[3], "talent points pick the spec")
    equal(Filler(ns), case[2], case[3] .. "'s filler")
    NoErrors(ns, case[3])
  end

  -- No points to read: the talent spells you know say.
  for _, case in ipairs({ { 12043, 5143, "MAGE_ARCANE" }, { 11366, 133, "MAGE_FIRE" }, { 11958, 116, "MAGE_FROST" } }) do
    local ns = Boot("MAGE", "Human", nil, false, { noSpecInfo = true, unknown = Unknown(case[1]) })
    equal(ns.specKey, case[3], "talent spells pick the spec")
    equal(Filler(ns), case[2], case[3] .. "'s filler, from its talent spells")
    equal(ns.specSource, "talent spells", "and it says so")
  end

  -- Nothing to go on: still a filler, and no error.
  local unsure = Boot("MAGE", "Human", nil, false, { noSpecInfo = true, unknown = Unknown() })
  equal(unsure.specSource, "not detected", "a mage with no talents has no spec")
  equal(Filler(unsure), 116, "and gets Frostbolt")
  NoErrors(unsure, "a mage with no talents")

  -- A filler isn't a debuff to keep up: it stays in color, slow or burn or not.
  local slows = {}
  for _, id in ipairs({ 116, 133, 5143, 11366, 15407, 585, 120, 8921 }) do slows[id] = true end
  local frost = Boot("MAGE", "Human", nil, false, { points = { 0, 0, 21 }, unknown = Unknown(11366), slows = slows })
  local byID = {}
  for _, btn in ipairs(Bars(frost).Rotation.buttons) do byID[btn.spellID] = btn end
  check(byID[116].icon.grayValue ~= 1, "Frostbolt is in color")
  check(byID[11366].icon.grayValue ~= 1, "Pyroblast is in color")
  local priest = Bars(Boot("PRIEST", "Human", nil, false, { slows = slows })).Rotation
  for _, btn in ipairs(priest.buttons) do
    if btn.spellID == 15407 then check(btn.icon.grayValue ~= 1, "Mind Flay is in color") end
  end
  local dots = Bars(Boot("DRUID", "Tauren", nil, false, { slows = slows })).Rotation
  for _, btn in ipairs(dots.buttons) do
    if btn.spellID == 8921 then equal(btn.icon.grayValue, 1, "a damage over time spell like Moonfire still grays until it's on") end
  end

  -- Everything on Rotation, on buttons of their own.
  local all = Bars(Boot("MAGE", "Human", nil, false, { points = { 0, 0, 21 }, unknown = Unknown(11366, 1312002, 11113) }))
  local ids = {}
  for _, btn in ipairs(all.Rotation.buttons) do ids[#ids + 1] = btn.spellID end
  equal(table.concat(ids, ","), "116,2136,11366,1312002,120,1326079,11113", "a mage's Rotation, in order")
  for _, entry in ipairs(all.Cooldowns.config.buttons) do
    check(entry.spell ~= 11113, "Blast Wave isn't on Cooldowns")
  end

  -- A respec changes it at once.
  local ns = Boot("MAGE", "Human", nil, false, { points = { 21, 0, 0 }, unknown = Unknown() })
  equal(Filler(ns), 5143, "Arcane before the respec")
  scenario.points = { 0, 0, 21 }
  Fire("PLAYER_TALENT_UPDATE")
  Tick()
  equal(Filler(ns), 116, "Frost after it")
  NoErrors(ns, "a respec")
end

-- Class specifics --------------------------------------------------------------------------------

do
  local bars = Bars(Boot("WARRIOR", "Orc"))
  local names = {}
  for _, entry in ipairs(bars.Debuffs.config.buttons) do names[#names + 1] = entry.spell end
  equal(table.concat(names, ","), "772,7386,1715,6343", "Warrior's Debuffs bar")
  check(bars.Debuffs.config.y > bars.Rotation.config.y and bars.Debuffs.config.y < bars["My Active Buffs"].config.y, "Debuffs is between buffs and Rotation")
  for _, entry in ipairs(bars.Rotation.config.buttons) do
    check(entry.spell ~= 772 and entry.spell ~= 7386 and entry.spell ~= 1715 and entry.spell ~= 6343, "Rotation has no debuff spells")
  end

  local warrior = {}
  for _, entry in ipairs(bars.Cooldowns.config.buttons) do warrior[entry.spell] = true end
  check(warrior[1329555], "Warrior's Cooldowns has Reckless Swings")

  local rogue = {}
  for _, btn in ipairs(Bars(Boot("ROGUE", "Human")).Rotation.buttons) do rogue[btn.spellID or 0] = true end
  check(rogue[1329283], "Rogue's Rotation has Shank")

  local hunter = Bars(Boot("HUNTER", "Orc"))
  equal(#hunter.Traps.config.buttons, 1, "Hunter has one trap button")

  local troll = Boot("PRIEST", "Troll")
  check(Bars(troll)["Buff With Charges"] ~= nil, "a troll priest has a charge bar")
  local human = Boot("PRIEST", "Human")
  equal(Bars(human)["Buff With Charges"], nil, "a human priest has no charge bar")
  local spells = {}
  for _, entry in ipairs(Bars(human).Cooldowns.config.buttons) do spells[entry.spell] = true end
  check(spells[13896] and spells[20600], "a human priest has Feedback and Perception")
  check(not spells[10797] and not spells[20580] and not spells[9035], "a human priest has no other race's spells")

  -- Each race's priest spells, on the bar for what they do, and no other race's.
  local PRIEST_SPELLS = {
    Human = { [13896] = "Cooldowns", [1277370] = "Cooldowns" },
    Dwarf = { [13908] = "Cooldowns", [1277331] = "Utility" },
    NightElf = { [10797] = "Cooldowns", [2651] = "Cooldowns" },
    Gnome = { [1277462] = "Cooldowns", [1277455] = "Utility" },
    Scourge = { [2652] = "Cooldowns", [1277324] = "Cooldowns" },
    Troll = { [9035] = "Cooldowns" },
    Skyborne = {},
  }
  local everyRacial = {}
  for _, spells in pairs(PRIEST_SPELLS) do
    for id in pairs(spells) do everyRacial[id] = true end
  end
  for race, spells in pairs(PRIEST_SPELLS) do
    local byBar, where = Bars(Boot("PRIEST", race)), {}
    for _, bar in ipairs({ "Cooldowns", "Utility" }) do
      for _, entry in ipairs(byBar[bar].config.buttons) do where[entry.spell] = bar end
    end
    for id in pairs(everyRacial) do
      equal(where[id], spells[id], ("a %s priest, spell %d"):format(race, id))
    end
    equal(where[6346], "Utility", "every priest has Fear Ward")
  end

  local shaman = Boot("SHAMAN", "Orc")
  local charges = Bars(shaman)["Buff With Charges"]
  check(charges and charges.config.x == Bars(shaman).Weapons.config.x, "Charges is centered over the left column")
end

-- Charge bars: picking a buff --------------------------------------------------------------------

do
  local ns = Boot("SHAMAN", "Orc")
  local bar = ns.NewBarConfig("Picked", "charges", 0, 30, { width = 120 })
  ns.AddBarConfig(bar, ns.profile)
  Tick()
  local choices = ns.EditMenu.ChargeChoices(bar)
  equal(choices[1].text, "Spell324", "Lightning Shield is the first choice")
  choices[1].func()
  equal(#bar.buttons, 1, "picking a buff adds it")
  equal(bar.buttonDefaults.pips, 3, "and how many charges it holds")
  ns.EditMenu.ChargeChoices(bar)[2].func()
  equal(#bar.buttons, 1, "picking another replaces it")
  equal(bar.buttons[1].aura[1], 408510, "with Water Shield")
  NoErrors(ns, "picking a charge buff")

  local human = Boot("PRIEST", "Human")
  for _, item in ipairs(human.EditMenu.ChargeChoices({ buttons = {} })) do
    check(item.text ~= "Spell18137", "a human priest isn't offered Shadowguard")
  end
end

-- The windows: each opens and draws every bar's page -------------------------------------------

for _, class in ipairs({ "SHAMAN", "PRIEST", "WARRIOR", "DRUID", "ROGUE", "PALADIN", "HUNTER" }) do
  local ns = Boot(class, RACES[class][1])
  local ok, problem = pcall(ns.SetEditMode, true)
  check(ok, class .. " edit mode opens: " .. tostring(problem))
  Tick()
  ok, problem = pcall(ns.Options.Open)
  check(ok, class .. " settings open: " .. tostring(problem))
  for _, bar in ipairs(ns.profile.bars) do
    ok, problem = pcall(ns.Options.Open, bar)
    check(ok, class .. " " .. tostring(bar.name) .. " page opens: " .. tostring(problem))
  end
  ok, problem = pcall(ns.QuickSetup.Show)
  check(ok, class .. " quick setup opens: " .. tostring(problem))
  ok, problem = pcall(ns.Pulse.Test)
  check(ok, class .. " pulse test: " .. tostring(problem))
  ok, problem = pcall(ns.SetEditMode, false)
  check(ok, class .. " edit mode closes: " .. tostring(problem))
  Tick()
  NoErrors(ns, class .. " windows")
end

print(("%d passed, %d failed"):format(passed, failures))
