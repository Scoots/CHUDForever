-- Saved settings, building the HUD, event wiring and slash commands.
--
-- Each character uses one profile (CombatHUDDB.chars[Name-Realm].profile),
-- whatever its talents: on WoW Forever trees are filled freely, so there's no
-- single spec to go by. A new character's profile has the whole class's
-- spells, and the ones it doesn't know stay hidden. The spec is still
-- detected, but only for /chud debug info and /chud debug spec.
local _, ns = ...
local issecret = ns.issecret

ns.editMode = false

local function DeepCopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, inner in pairs(value) do copy[key] = DeepCopy(inner) end
  return copy
end

-- A fresh profile: the default layout for your class, every tree's spells
-- (Defaults.lua). "Rebuild from my action bars" builds one from your bars instead.
local function NewProfile()
  local _, class = UnitClass("player")
  return ns.DefaultProfile(class)
end

local CharacterKey = ns.CharacterKey

-- This character's saved settings: the profile it uses (profile). Older
-- versions kept one per spec (profiles: spec key -> name), read once by
-- SelectProfile.
function ns.CharSettings()
  local key = CharacterKey()
  if not key or not CombatHUDDB then return end
  local chars = CombatHUDDB.chars
  chars[key] = chars[key] or {}
  return chars[key]
end

-- Specs -------------------------------------------------------------------------

local function SpecsForClass(class)
  local list = {}
  for _, spec in ipairs(ns.SPECS) do
    if spec.class == class then list[#list + 1] = spec end
  end
  return list
end

-- Points spent in one talent tree. Older clients return name, icon, points;
-- newer ones id, name, description, icon, points.
local function TreePoints(tab)
  local results = { pcall(GetTalentTabInfo, tab) }
  if not results[1] or issecret(results[2]) then return end
  local points
  if type(results[2]) == "number" then points = results[6] else points = results[4] end
  if not issecret(points) and type(points) == "number" then return points end
end

-- The spec whose tree has the most points. ns.SPECS lists each class's specs
-- in talent tree order.
local function SpecFromTalentPoints(specs)
  if not (GetNumTalentTabs and GetTalentTabInfo) then return end
  local ok, trees = pcall(GetNumTalentTabs)
  if not ok or issecret(trees) or type(trees) ~= "number" then return end
  local best, bestPoints = nil, 0
  for tab = 1, math.min(trees, #specs) do
    local points = TreePoints(tab)
    if points and points > bestPoints then best, bestPoints = specs[tab], points end
  end
  return best
end

-- The current spec key (e.g. "SHAMAN_ENHANCEMENT"), its ns.SPECS entry, and
-- how it was found. Falls back to the class token. For information only.
function ns.GetSpec()
  local _, class = UnitClass("player")
  if issecret(class) or not class then return end

  local specs = SpecsForClass(class)
  for _, spec in ipairs(specs) do
    for _, spellID in ipairs(spec.spells) do
      if ns.IsSpellKnown(spellID) then return spec.key, spec, "final talent" end
    end
  end
  local spec = SpecFromTalentPoints(specs)
  if spec then return spec.key, spec, "talent points" end
  return class, nil, "not detected"
end

local function UniqueName(base)
  local profiles = CombatHUDDB.profiles
  if not profiles[base] then return base end
  local number = 2
  while profiles[("%s (%d)"):format(base, number)] do number = number + 1 end
  return ("%s (%d)"):format(base, number)
end

-- A new profile's name: the character's.
local function CharacterProfileName()
  local name = UnitName("player")
  if issecret(name) or not name then name = "My profile" end
  return UniqueName(name)
end

-- From the old one-profile-per-spec settings: the profile of the spec
-- detected now (else the first one there), and the others' names.
local function FromSpecProfiles(settings, specKey)
  local profiles, names = CombatHUDDB.profiles, {}
  for _, name in pairs(settings.profiles or {}) do
    if profiles[name] and not tContains(names, name) then names[#names + 1] = name end
  end
  table.sort(names)
  local current = settings.profiles and settings.profiles[specKey]
  local keep = profiles[current or ""] and current or names[1]
  local others = {}
  for _, name in ipairs(names) do
    if name ~= keep then others[#others + 1] = name end
  end
  return keep, others
end

-- Picks this character's profile, creating it from the defaults the first time.
local function SelectProfile()
  local settings = ns.CharSettings()
  if not settings then return false end
  local db = CombatHUDDB
  local specKey, _, source = ns.GetSpec()
  local name = settings.profile
  local brandNew = next(settings) == nil -- a character CombatHUD hasn't seen before
  if not name or not db.profiles[name] then
    local others
    name, others = FromSpecProfiles(settings, specKey)
    if name and #others > 0 then
      ns.Print(("One profile per character now: this one uses %s. Your other spec profiles (%s) are still in the list (/chud); pick one with Use This Profile."):format(
        name, table.concat(others, ", ")))
    end
    if not name then
      name = CharacterProfileName()
      db.profiles[name] = NewProfile()
      if brandNew then settings.quickSetup = true end -- QuickSetup.lua shows it after login
    end
    settings.profile, settings.profiles, settings.spec = name, nil, nil
  end
  ns.specKey, ns.specSource, ns.profileName, ns.profile = specKey, source, name, db.profiles[name]
  return true
end

-- What the HUD is currently built from: the spec, which rank of each spell
-- you know, and which items are equipped. Rebuilds are skipped when it
-- hasn't changed.
local function Signature()
  local parts = { ns.specKey, ns.profileName }
  for _, bar in ipairs(ns.profile.bars or {}) do
    if bar.type == "weapons" then parts[#parts + 1] = "weapons:" .. ns.Weapons.Signature() end
    for _, entry in ipairs(bar.buttons or {}) do
      if entry.slot then
        parts[#parts + 1] = "slot:" .. tostring(GetInventoryItemID("player", entry.slot))
      elseif entry.item then
        parts[#parts + 1] = "item:" .. tostring(ns.Groups.ResolveItem(entry)) -- a group: the one you carry
      elseif entry.aura then
        parts[#parts + 1] = "aura:" .. tostring(type(entry.aura) == "table" and entry.aura[1] or entry.aura)
      else
        parts[#parts + 1] = tostring((ns.Groups.ResolveSpell(entry)))
      end
    end
  end
  return table.concat(parts, ",")
end

-- Refreshing ----------------------------------------------------------------------

function ns.RefreshCooldowns()
  local gcd = ns.GCDCooldown()
  for _, btn in ipairs(ns.activeButtons) do
    ns.Button.RefreshCooldown(btn)
    ns.Button.RefreshGCD(btn, gcd)
    ns.Button.RefreshReactive(btn)
  end
end

function ns.RefreshTints()
  for _, btn in ipairs(ns.activeButtons) do
    ns.Button.RefreshTint(btn)
    ns.Button.RefreshReactive(btn)
  end
end

-- Execute and the like change with the target's health.
function ns.RefreshReactives()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.reactive then ns.Button.RefreshReactive(btn) end
  end
end

function ns.RefreshCosts()
  for _, btn in ipairs(ns.activeButtons) do ns.Button.RefreshCost(btn) end
end

-- Building ------------------------------------------------------------------------

local lastSignature
local pending -- nil, "changed" or "force": a rebuild waiting for combat to end

-- Rebuilds the HUD. Without force, only when the spec, spells or gear changed.
-- Waits until combat ends.
function ns.Rebuild(force)
  if InCombatLockdown() then
    if force or pending ~= "force" then pending = force and "force" or "changed" end
    return
  end
  pending = nil
  if not SelectProfile() then return end

  local ok, signature = pcall(Signature)
  if not ok then signature = nil end
  if not force and signature and signature == lastSignature then return end
  lastSignature = signature

  ns.Learn.Prepare(ns.profile)
  ns.Bar.BuildAll(ns.profile)
  ns.Power.Apply(ns.profile.power)
  ns.Health.Apply(ns.profile.health)
  ns.Cast.Apply(ns.profile.cast)
  ns.Swing.Apply(ns.profile.swing)
  ns.Range.Scan()
  ns.RefreshCooldowns()
  ns.Sounds.Apply(ns.profile)
  ns.Visibility.Update()
end

local function RebuildIfChanged() ns.Rebuild(false) end
local function RebuildNow() ns.Rebuild(true) end

-- Profiles ---------------------------------------------------------------------------
-- A profile is a whole layout (bars, buttons, power bar). Each character picks
-- one per spec; profiles are shared, so two characters or specs can use the
-- same one.

function ns.ProfileNames()
  local names = {}
  for name in pairs(CombatHUDDB and CombatHUDDB.profiles or {}) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- Uses a profile on this character.
function ns.UseProfile(name)
  local settings = ns.CharSettings()
  if not settings or not CombatHUDDB.profiles[name] then return end
  settings.profile = name
  RebuildNow()
end

-- A new profile, copied from this one or from the class's defaults, and used.
-- copyFrom: the name of a profile to copy, or nil for the defaults.
function ns.CreateProfile(copyFrom)
  if not ns.profile then return end
  local name
  if copyFrom and CombatHUDDB.profiles[copyFrom] then
    name = UniqueName(copyFrom .. " copy")
    CombatHUDDB.profiles[name] = DeepCopy(CombatHUDDB.profiles[copyFrom])
  else
    name = CharacterProfileName()
    CombatHUDDB.profiles[name] = NewProfile()
  end
  ns.UseProfile(name)
  ns.Print("Now using the profile " .. name .. ".")
  return name
end

-- A copy of a profile under a new name, without switching to it.
function ns.DuplicateProfile(name)
  if not CombatHUDDB.profiles[name] then return end
  local copy = UniqueName(name .. " copy")
  CombatHUDDB.profiles[copy] = DeepCopy(CombatHUDDB.profiles[name])
  return copy
end

function ns.RenameProfile(old, newName)
  local profiles = CombatHUDDB.profiles
  if not old or not profiles[old] or newName == old then return end
  if profiles[newName] then
    ns.Print("There's already a profile called " .. newName .. ".")
    return
  end
  profiles[newName], profiles[old] = profiles[old], nil
  for _, settings in pairs(CombatHUDDB.chars) do
    if settings.profile == old then settings.profile = newName end
    -- Not yet moved to one profile per character.
    for specKey, name in pairs(settings.profiles or {}) do
      if name == old then settings.profiles[specKey] = newName end
    end
  end
  RebuildNow()
end

-- Adds a profile (an imported one, say) under a free name based on base, and uses it.
function ns.AddProfile(base, profile)
  local name = UniqueName(base)
  CombatHUDDB.profiles[name] = profile
  ns.UseProfile(name)
  return name
end

-- Replaces the current profile with one built from your action bars.
-- name: which profile (the one in use if left out).
function ns.RebuildFromActionBars(name)
  name = name or ns.profileName
  if not name or InCombatLockdown() then return end
  local built = ns.Starter.Build()
  CombatHUDDB.profiles[name] = built
  RebuildNow()
  ns.Print("Built " .. name .. " from your action bars: " .. ns.Starter.Describe(built) .. ".")
end

-- Deletes a profile. Characters using it get a fresh one from the defaults.
-- The last profile can't be deleted.
function ns.DeleteProfile(name)
  local profiles = CombatHUDDB.profiles
  if #ns.ProfileNames() <= 1 then
    ns.Print("That's your only profile, so it stays.")
    return
  end
  profiles[name] = nil
  for _, settings in pairs(CombatHUDDB.chars) do
    if settings.profile == name then settings.profile = nil end
    for specKey, used in pairs(settings.profiles or {}) do
      if used == name then settings.profiles[specKey] = nil end
    end
  end
  RebuildNow()
  ns.Print("Deleted the profile " .. name .. ".")
end

-- Edit mode -------------------------------------------------------------------------

-- On screen while editing: a Done button. Escape leaves edit mode too; every
-- other key goes on to the game as usual.
local editBar

local function EditBar()
  if editBar then return editBar end
  editBar = CreateFrame("Frame", "CombatHUDEditBar", UIParent)
  editBar:SetSize(250, 28)
  editBar:SetPoint("TOP", 0, -60)
  editBar:SetFrameStrata("DIALOG")
  editBar:EnableMouse(true)
  local edge = editBar:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.2, 0.6, 1, 0.8)
  local bg = editBar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.95)
  local text = editBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("LEFT", 10, 0)
  text:SetText("CombatHUD edit mode")

  local done = CreateFrame("Button", nil, editBar)
  done:SetSize(84, 20)
  done:SetPoint("RIGHT", -4, 0)
  local doneBg = done:CreateTexture(nil, "BACKGROUND")
  doneBg:SetAllPoints()
  doneBg:SetColorTexture(0.2, 0.45, 0.8, 0.9)
  local highlight = done:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.15)
  local label = done:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER")
  label:SetText("Done (Esc)")
  done:SetScript("OnClick", function() ns.SetEditMode(false) end)

  editBar:EnableKeyboard(true)
  editBar:SetScript("OnKeyDown", function(self, key)
    if InCombatLockdown() then return end
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      ns.SetEditMode(false)
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
  editBar:Hide()
  return editBar
end

-- Edit mode rebuilds the HUD: hidden buttons show, aura buttons show stand-in
-- icons, and dynamic bars show one icon per aura to work with.
function ns.SetEditMode(on)
  if on and InCombatLockdown() then
    ns.Print("Can't edit the HUD in combat.")
    return
  end
  ns.editMode = on
  if not on then
    ns.Menu.Close()
    ns.Popover.Close()
  end
  -- The movers, grid and Done bar first, so that a problem in the rebuild
  -- can't leave you stuck in edit mode (the error still shows).
  EditBar():SetShown(on)
  ns.Bar.ShowGrid(on)
  ns.Bar.SetProfileMoverShown(on)
  local ok, err = pcall(RebuildNow)
  if not ok then geterrorhandler()(err) end
  ns.Power.SetMoverShown(on)
  ns.Health.SetMoverShown(on)
  ns.Cast.SetMoverShown(on)
  ns.Swing.SetMoverShown(on)
  ns.Options.Refresh()
end

-- Called by the bars when something is dropped on them or right-clicked.
function ns.InsertButton(barConfig, configIndex, entry)
  table.insert(barConfig.buttons, configIndex, entry)
  RebuildNow()
  ns.Options.Refresh()
end

function ns.RemoveButton(barConfig, configIndex)
  table.remove(barConfig.buttons, configIndex)
  RebuildNow()
  ns.Options.Refresh()
end

-- bars: a profile's bar list (the one in use if left out).
local function FindBar(name, bars)
  for index, bar in ipairs(bars or ns.profile.bars or {}) do
    if (bar.name or ""):lower() == name:lower() then return index, bar end
  end
end

-- A bar name not used yet on a profile's bars: the name, or "name 2", "name 3"...
function ns.UniqueBarName(bars, name)
  name = name or "Bar"
  if not FindBar(name, bars) then return name end
  local number = 2
  while FindBar(name .. " " .. number, bars) do number = number + 1 end
  return name .. " " .. number
end

-- Adds a whole bar (a copy, an import, one moved from another profile) to the
-- end of a profile's bars, under a name it doesn't have yet.
function ns.AddBarConfig(bar, profile)
  profile.bars = profile.bars or {}
  bar.name = ns.UniqueBarName(profile.bars, bar.name)
  bar.buttons = type(bar.buttons) == "table" and bar.buttons or {}
  table.insert(profile.bars, bar)
  if profile == ns.profile then RebuildNow() end
  return bar
end

-- A copy of a bar, right after it and a little lower on screen.
function ns.DuplicateBar(bar, profile)
  profile = profile or ns.profile
  local copy = DeepCopy(bar)
  copy.name = ns.UniqueBarName(profile.bars, (bar.name or "Bar") .. " copy")
  copy.y = (bar.y or 0) - (bar.size or 36) - 12
  local index = #profile.bars + 1
  for i, other in ipairs(profile.bars) do
    if other == bar then index = i + 1 end
  end
  table.insert(profile.bars, index, copy)
  if profile == ns.profile then RebuildNow() end
  return copy
end

-- profile: which profile gets the bar (the one in use if left out). Only
-- the one in use goes into edit mode, to place it.
function ns.AddBar(name, profile)
  profile = profile or ns.profile
  profile.bars = profile.bars or {}
  local bars = profile.bars
  local lowest = 0
  for _, bar in ipairs(bars) do lowest = math.min(lowest, (bar.y or 0) - (bar.size or 40)) end
  if name == "" then name = "Bar " .. (#bars + 1) end
  if FindBar(name, bars) then
    ns.Print("There's already a bar called " .. name .. ".")
    return
  end
  table.insert(bars, {
    name = name,
    orientation = "HORIZONTAL", grow = "CENTER",
    size = 36, spacing = 4, scale = 1,
    x = 0, y = lowest - 12,
    buttons = {},
  })
  if profile == ns.profile then
    ns.SetEditMode(true)
    ns.Print("Added " .. name .. ". Drag it into place and drop spells on it.")
  end
  return bars[#bars]
end

-- bar: a bar's config table, or its name. profile: whose (the one in use if left out).
function ns.DeleteBar(bar, profile)
  local bars = (profile or ns.profile).bars or {}
  local index
  if type(bar) == "table" then
    for i, config in ipairs(bars) do
      if config == bar then index = i end
    end
  else
    index, bar = FindBar(bar, bars)
  end
  if not index then
    ns.Print("No bar by that name.")
    return
  end
  table.remove(bars, index)
  RebuildNow()
  ns.Print("Deleted " .. (bar.name or "the bar") .. ".")
end

-- Events ------------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, addon)
  if addon ~= ns.name then return end
  CombatHUDDB = CombatHUDDB or {}
  local db = CombatHUDDB
  db.profiles = db.profiles or {}
  db.chars = db.chars or {}
  -- Version 1 kept spec -> profile pairs directly in each character's table.
  for _, settings in pairs((db.version or 1) < 2 and db.chars or {}) do
    if not settings.profiles then
      local profiles = {}
      for key, value in pairs(settings) do
        if type(value) == "string" then profiles[key] = value end
      end
      for key in pairs(profiles) do settings[key] = nil end
      settings.profiles = profiles
    end
  end
  db.version = 2

  -- Version 3: old default "My Active Buffs" bars (picked burst list) become
  -- the consolidated auto self-buff bar.
  if (db.defaultsVersion or 0) < 3 then
    db.defaultsVersion = 3
    for _, profile in pairs(db.profiles) do
      for _, bar in ipairs(profile.bars or {}) do
        local name = (bar.name or ""):lower()
        if name == "active buffs" and ns.Bar.Type(bar) == "buffs" then
          bar.type = "allbuffs"
          bar.dynamic, bar.unit, bar.mine = true, "player", true
          bar.maxIcons = bar.maxIcons or 8
          bar.maxDuration = 60
          bar.filter = nil
          bar.buttons = {}
        end
      end
    end
  end

  -- "In combat or with a target" is gone: it's "In combat" now.
  if (db.visibilityVersion or 0) < 1 then
    db.visibilityVersion = 1
    local function Fix(config)
      if type(config) == "table" and config.show == "combatOrTarget" then config.show = "combat" end
    end
    for _, profile in pairs(db.profiles) do
      Fix(profile.visibilityDefaults)
      for _, key in ipairs({ "power", "health", "cast", "swing" }) do Fix(profile[key]) end
      for _, bar in ipairs(profile.bars or {}) do Fix(bar) end
    end
  end

  ns.Groups.Migrate(db)
  if db.alertsVersion ~= 1 then
    db.alertsVersion = 1
    for _, profile in pairs(db.profiles) do ns.Alerts.MigrateProfile(profile) end
  end
end)

-- The game only draws cooldown numbers when its own "Show cooldown numbers"
-- setting is on. Point that out rather than changing the setting.
local function CheckCountdownSetting()
  local getBool = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
  if not getBool or getBool("countdownForCooldowns") then return end
  for _, btn in ipairs(ns.activeButtons) do
    if btn.opts.numbers then
      ns.Print("Cooldown numbers need the game's \"Show cooldown numbers\" option (Options > Action Bars).")
      return
    end
  end
end

ns.On("PLAYER_LOGIN", function()
  RebuildNow()
  CheckCountdownSetting()
end)
-- Learning a spell: checked at once and again a moment later, in case the
-- spellbook catches up after the event.
local recheckQueued
local function SpellsChanged()
  ns.Schedule(RebuildIfChanged)
  if recheckQueued then return end
  recheckQueued = true
  C_Timer.After(1.5, function()
    recheckQueued = nil
    RebuildIfChanged()
  end)
end
ns.On("SPELLS_CHANGED", SpellsChanged)
ns.On("LEARNED_SPELL_IN_TAB", SpellsChanged)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", SpellsChanged)
ns.On("CHARACTER_POINTS_CHANGED", function() ns.Schedule(RebuildIfChanged) end)
-- Running out of a potion moves its shared cooldown's button to another you carry.
ns.On("BAG_UPDATE_DELAYED", function() ns.Schedule(RebuildIfChanged) end)
ns.On("PLAYER_TALENT_UPDATE", function() ns.Schedule(RebuildIfChanged) end)
-- A different pet: its abilities (a warlock's pet ability button).
ns.OnUnit("UNIT_PET", "player", function() ns.Schedule(RebuildIfChanged) end)
ns.On("PET_BAR_UPDATE", function() ns.Schedule(RebuildIfChanged) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Schedule(RebuildIfChanged) end)

ns.On("SPELL_UPDATE_COOLDOWN", function() ns.Schedule(ns.RefreshCooldowns) end)
ns.On("BAG_UPDATE_COOLDOWN", function() ns.Schedule(ns.RefreshCooldowns) end)
ns.On("SPELL_UPDATE_USABLE", function() ns.Schedule(ns.RefreshTints) end)
ns.On("PLAYER_TARGET_CHANGED", function() ns.Schedule(ns.RefreshTints) end)
ns.OnUnit("UNIT_HEALTH", "target", function() ns.Schedule(ns.RefreshReactives) end)

ns.On("PLAYER_REGEN_DISABLED", function()
  ns.Menu.Close()
  ns.Options.Close()
  if ns.editMode then
    ns.SetEditMode(false)
    ns.Print("Edit mode turned off for combat.")
  end
end)

ns.On("PLAYER_REGEN_ENABLED", function()
  if pending then ns.Rebuild(pending == "force") end
  ns.Bar.FlushLayouts()
  ns.RefreshCosts()
end)

-- Slash commands ------------------------------------------------------------------------

local function SpellLabel(spellID)
  local name = spellID and C_Spell.GetSpellName(spellID)
  if name and not issecret(name) then return name end
  return tostring(spellID)
end

local function Describe(entry)
  if entry.slot then return "slot " .. entry.slot end
  if entry.item then return "item " .. entry.item end
  if entry.aura then
    local first = type(entry.aura) == "table" and entry.aura[1] or entry.aura
    return SpellLabel(first) .. " (" .. (entry.show or "up") .. " on " .. (entry.unit or "player") .. ")"
  end
  return SpellLabel(type(entry.spell) == "table" and entry.spell[1] or entry.spell)
end

function ns.PrintInfo()
  ns.Print(("Profile: %s. Spec (for information): %s (%s)."):format(tostring(ns.profileName), tostring(ns.specKey),
    tostring(ns.specSource)))
  if not ns.profile then return end
  for _, bar in ipairs(ns.profile.bars or {}) do
    local shown, skipped = {}, {}
    for _, entry in ipairs(bar.buttons or {}) do
      local spellID, name
      if entry.spell and not entry.aura and not bar.dynamic then
        spellID, name = ns.Groups.ResolveSpell(entry)
      end
      if entry.aura or bar.dynamic then
        shown[#shown + 1] = "aura: " .. Describe(entry)
      elseif spellID then
        shown[#shown + 1] = ("%s (%d)"):format(name or "?", spellID)
      elseif entry.slot and GetInventoryItemID("player", entry.slot) then
        shown[#shown + 1] = Describe(entry)
      elseif entry.item then
        shown[#shown + 1] = Describe(entry)
      else
        skipped[#skipped + 1] = Describe(entry)
      end
    end
    local line = (bar.name or "Bar") .. ": " .. (#shown > 0 and table.concat(shown, ", ") or "nothing")
    if #skipped > 0 then line = line .. ". Left out: " .. table.concat(skipped, ", ") end
    ns.Print(line)
  end
  ns.Print("Global cooldown reference spell: " .. (ns.GCDCooldown() and "found" or "not found"))
end

-- Everything spec detection looks at, for troubleshooting.
function ns.PrintDiag()
  local _, class = UnitClass("player")
  if issecret(class) then class = "?" end
  ns.Print(("Class: %s. Spec: %s (%s)."):format(tostring(class), tostring(ns.specKey), tostring(ns.specSource)))
  for _, spec in ipairs(SpecsForClass(class)) do
    for _, spellID in ipairs(spec.spells) do
      ns.Print(("%s, %s (%d): %s"):format(spec.name, SpellLabel(spellID), spellID, ns.DescribeSpellKnown(spellID)))
    end
  end
  if GetNumTalentTabs and GetTalentTabInfo then
    local ok, trees = pcall(GetNumTalentTabs)
    if ok and not issecret(trees) and type(trees) == "number" then
      for tab = 1, trees do ns.Print(("Talent tree %d: %s points"):format(tab, tostring(TreePoints(tab)))) end
    end
  else
    ns.Print("No talent tree functions on this client.")
  end
  ns.Print(("Stormstrike (17364): %s"):format(ns.DescribeSpellKnown(17364)))
end

-- /chud perf: memory and CPU of CombatHUD next to ForeverAuras, to compare.
-- CPU is only counted while the game's script profiling is on (it slows
-- the game a little, so it's off by default).
local COMPARE = { "CombatHUD", "ForeverAuras", "ForeverAurasOptions", "WeakAuras", "WeakAurasOptions" }
local perfSince

local function PrintPerf(argument)
  local addons = C_AddOns or {}
  local isLoaded = addons.IsAddOnLoaded or IsAddOnLoaded
  local getCVar = (C_CVar and C_CVar.GetCVarBool) or GetCVarBool
  local profiling = getCVar and getCVar("scriptProfile")
  if argument == "reset" then
    if profiling and ResetCPUUsage then ResetCPUUsage() end
    perfSince = GetTime()
    ns.Print("CPU counters reset. Play a while (a fight or two), then type /chud perf.")
    return
  end
  if UpdateAddOnMemoryUsage then UpdateAddOnMemoryUsage() end
  if profiling and UpdateAddOnCPUUsage then UpdateAddOnCPUUsage() end
  local seconds = GetTime() - (perfSince or 0)
  for _, name in ipairs(COMPARE) do
    if isLoaded and isLoaded(name) then
      local line = name .. ":"
      if GetAddOnMemoryUsage then line = line .. (" %.0f KB memory"):format(GetAddOnMemoryUsage(name)) end
      if profiling and GetAddOnCPUUsage then
        local ms = GetAddOnCPUUsage(name)
        line = line .. (", %.0f ms CPU"):format(ms)
        if perfSince and seconds > 0 then line = line .. (" (%.2f ms per second)"):format(ms / seconds) end
      end
      ns.Print(line)
    end
  end
  if not profiling then
    ns.Print("For CPU too: /console scriptProfile 1, /reload, then /chud perf reset and play a while."
      .. " Turn it off afterwards with /console scriptProfile 0 (it slows the game a little).")
  elseif not perfSince then
    ns.Print("CPU is counted since login. /chud perf reset starts a fresh count.")
  end
end

-- The everyday commands are in /chud help; the troubleshooting ones are
-- under /chud debug (and still work without "debug", as they used to).
local HELP = {
  "/chud - open the settings",
  "/chud edit - move bars and drop spells or items on them (also /chud lock, /chud unlock)",
  "/chud reset - reset this character's profile to the defaults (asks first)",
  "/chud report - everything a bug report needs, ready to copy",
  "/chud version - which version of CombatHUD this is",
  "/chud debug - commands for troubleshooting",
}

local DEBUG = {
  { name = "info", help = "the profile, the detected spec and the spells on each bar",
    run = function() ns.PrintInfo() end },
  { name = "spec", aliases = { "diag" }, help = "what spec detection sees (for information; it doesn't pick the profile)",
    run = function() ns.PrintDiag() end },
  { name = "auras", help = "your buffs, what each aura bar watches, and whether its aura widget is running",
    run = function() ns.Aura.PrintDiag() end },
  { name = "totems", help = "what the totem bar knows about each slot",
    run = function() ns.Totem.PrintDiag() end },
  { name = "weapons", help = "each hand's temporary enchant as the game reports it (try in and out of combat)",
    run = function() ns.Weapons.PrintDiag() end },
  { name = "shield", help = "your shield's absorb amount as the game reports it (try in and out of combat)",
    run = function() ns.Absorb.PrintDiag() end },
  { name = "swing", aliases = { "swingprobe" }, help = "the game's own swing timer bars, and whether the HUD follows them",
    run = function() ns.Swing.Probe() end },
  { name = "range", aliases = { "rangeprobe" }, help = "item and trinket buttons: their action bar slot and what the game reports about range",
    run = function() ns.Range.Probe() end },
  { name = "links", help = "which buff each spell was learned to give (links clear: forget them)",
    run = function(argument)
      if argument == "clear" then
        ns.Learn.Clear()
        RebuildNow()
      else
        ns.Learn.Print()
      end
    end },
  { name = "perf", help = "memory (and CPU, with script profiling on) next to other aura addons (perf reset: start counting)",
    run = function(argument) PrintPerf(argument) end },
  { name = "sound", help = "play an alert sound: blip, drop, bell, heartbeat, siren, raid, custom",
    run = function(argument) ns.Sounds.Preview(argument) end },
}

local function FindDebug(word)
  for _, topic in ipairs(DEBUG) do
    if topic.name == word or tContains(topic.aliases or {}, word) then return topic end
  end
end

local function DebugHelp()
  ns.Print("Troubleshooting (/chud debug name):")
  for _, topic in ipairs(DEBUG) do ns.Print(("/chud debug %s - %s"):format(topic.name, topic.help)) end
end

-- /chud reset asks first; /chud reset confirm does it.
local function Reset(argument)
  if InCombatLockdown() then
    ns.Print("Can't change the HUD in combat.")
  elseif not ns.profile then
    ns.Print("The HUD isn't loaded yet.")
  elseif argument ~= "confirm" then
    ns.Print(("This replaces the profile %s with the default layout for your class (other characters using it change too). To go ahead: /chud reset confirm"):format(
      ns.profileName))
  else
    CombatHUDDB.profiles[ns.profileName] = NewProfile()
    RebuildNow()
    ns.Print("Reset " .. ns.profileName .. " to the defaults.")
  end
end

SLASH_COMBATHUD1 = "/chud"
SLASH_COMBATHUD2 = "/combathud"
SlashCmdList.COMBATHUD = function(message)
  local command, argument = strtrim(message or ""):match("^(%S*)%s*(.-)$")
  command, argument = command:lower(), argument:lower()

  if command == "" or command == "config" or command == "options" then
    ns.Options.Toggle()
  elseif command == "edit" or command == "move" or command == "unlock" or command == "lock" then
    local on = not ns.editMode
    if command == "unlock" then on = true elseif command == "lock" then on = false end
    ns.SetEditMode(on)
    if ns.editMode then
      ns.Print("Edit mode on. Drag bars to move them, drop spells or items on them, right-click a button or bar for options. Type /chud edit again to stop.")
    else
      ns.Print("Edit mode off.")
    end
  elseif command == "reset" then
    Reset(argument)
  elseif command == "report" then
    ns.Report.Show()
  elseif command == "version" then
    ns.Print("Version " .. ns.Version() .. ".")
  elseif command == "debug" then
    local word, rest = argument:match("^(%S*)%s*(.-)$")
    local topic = FindDebug(word)
    if topic then topic.run(rest) else DebugHelp() end
  elseif FindDebug(command) then
    FindDebug(command).run(argument)
  else
    for _, line in ipairs(HELP) do ns.Print(line) end
  end
end
