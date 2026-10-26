-- Learning which buff a spell gives.
--
-- An ability often applies a buff with a different spell ID from its own
-- (Shamanistic Rage, Elemental Mastery...), and the aura widget matches by
-- ID, so dropping the ability on an aura bar would track the wrong ID. Out of
-- combat, buff data is readable, so the buff's ID is remembered for that
-- spell (CombatHUDDB.auraLinks, by spell name, so every rank shares it):
--   - after you cast a spell that's on an aura bar, from the buffs of yours
--     that appeared right then (same name or icon first; otherwise the only
--     new one, since out of combat nothing else is likely to land then)
--   - when the HUD is built, from buffs already up with the same name or icon
local _, ns = ...
local issecret = ns.issecret

local Learn = {}
ns.Learn = Learn

-- Spells on aura bars: name -> { icon = fileID, ids = set of IDs already tracked }.
local wanted = {}

-- Buff IDs learned for a spell name, or nil.
function Learn.Linked(name)
  local links = CombatHUDDB and CombatHUDDB.auraLinks
  if not links or not name or issecret(name) then return end
  return links[name]
end

local function Remember(spellName, auraID, auraName)
  CombatHUDDB.auraLinks = CombatHUDDB.auraLinks or {}
  local list = CombatHUDDB.auraLinks[spellName] or {}
  CombatHUDDB.auraLinks[spellName] = list
  for _, id in ipairs(list) do
    if id == auraID then return false end
  end
  table.insert(list, auraID)
  ns.Print(("Learned that %s gives the buff %s (%d)."):format(spellName, auraName, auraID))
  return true
end

-- Looks through your current buffs for ones matching wanted spells (all of
-- them, or only onlyName). Returns true if anything new was learned.
local function ScanBuffs(onlyName)
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not getAura or InCombatLockdown() or not next(wanted) then return false end
  local learned = false
  for index = 1, 40 do
    local ok, aura = pcall(getAura, "player", index, "HELPFUL|PLAYER")
    if not ok or not aura then break end
    local id, name, icon = aura.spellId, aura.name, aura.icon
    if issecret(id) or issecret(name) or issecret(icon) then break end
    for spellName, spell in pairs(wanted) do
      local matches = name == spellName or (icon ~= nil and icon == spell.icon)
      if (not onlyName or spellName == onlyName) and matches and not spell.ids[id] then
        if Remember(spellName, id, name) then
          spell.ids[id] = true
          learned = true
        end
      end
    end
  end
  return learned
end

-- quiet: don't report casts that taught nothing (totems: many have no buff).
local function AddWanted(spell, ids, quiet)
  if type(spell) == "table" then
    for _, id in ipairs(spell) do AddWanted(id, ids, quiet) end
    return
  end
  if type(spell) ~= "number" then return end
  local name = C_Spell.GetSpellName(spell)
  if not name or issecret(name) then return end
  local entry = wanted[name] or { icon = C_Spell.GetSpellTexture(spell), ids = {}, quiet = quiet }
  wanted[name] = entry
  for id in pairs(ids) do entry.ids[id] = true end
end

-- Called before each build (out of combat): notes which spells sit on aura
-- bars and learns from buffs that are already up.
function Learn.Prepare(profile)
  wipe(wanted)
  for _, bar in ipairs(profile.bars or {}) do
    local kind = ns.Bar.Type(bar)
    -- Totems' buffs, for the totem bar's range check.
    if kind == "totems" then
      for _, spellID in ipairs(ns.Totem.KnownSpells()) do AddWanted(spellID, ns.Totem.BuffSet(spellID), true) end
    end
    for _, entry in ipairs(bar.buttons or {}) do
      -- Buffs on you only; debuffs on the target are left alone.
      local aura = kind == "buffs" or kind == "alerts" or kind == "charges"
        or (kind == "cooldowns" and (entry.aura or entry.watchAura == true))
      if aura and entry.unit ~= "target" and not entry.slot and not entry.item then
        local ids = ns.Aura.SpellIDs(entry)
        AddWanted(entry.spell, ids)
        AddWanted(entry.aura, ids)
      end
    end
  end
  ScanBuffs(nil)
end

-- Buffs of yours added in the last few seconds: { id, name, icon, time }.
local recent = {}

local Readable = ns.AllReadable

-- Every buff of yours seen, per class, by name, so every rank of a potion is
-- one entry (CombatHUDDB.buffBook): class -> name -> { ids = { [spell ID] =
-- true }, icon, duration (seconds, 0 for none, nil if never readable), seen =
-- time() }. For the every-buff bar's list, hiding buffs from it, and "A buff
-- I've had". Only your own buffs (yours or your pet's) are kept, and ones not
-- seen for FORGET_AFTER are dropped at login.
local FORGET_AFTER = 60 * 24 * 3600
local _, playerClass = UnitClass("player")

local function Book()
  if not CombatHUDDB then return {} end
  CombatHUDDB.buffBook = CombatHUDDB.buffBook or {}
  local class = playerClass or "?"
  local book = CombatHUDDB.buffBook[class]
  if not book then
    book = {}
    CombatHUDDB.buffBook[class] = book
    -- Older versions kept one list for every character: it goes to the first class to log in.
    for id, info in pairs(CombatHUDDB.seenBuffs or {}) do
      if info.name then
        local entry = book[info.name] or { ids = {}, icon = info.icon, seen = info.seen or 0 }
        entry.ids[id] = true
        book[info.name] = entry
      end
    end
    CombatHUDDB.seenBuffs = nil
  end
  return book
end

-- Whether a buff is hidden on any bar of the profile in use.
local function HiddenAnywhere(name)
  for _, bar in ipairs(ns.profile and ns.profile.bars or {}) do
    if bar.hide and bar.hide[name] then return true end
  end
  return false
end

local function RememberSeen(id, name, icon, duration)
  if not CombatHUDDB then return end
  local book = Book()
  local entry = book[name]
  if not entry then
    entry = { ids = {} }
    book[name] = entry
  end
  local newRank = not entry.ids[id]
  entry.ids[id] = true
  entry.icon, entry.seen = icon or entry.icon, time()
  if not issecret(duration) and type(duration) == "number" then entry.duration, entry.guessed = duration, nil end
  -- A new rank of a hidden buff is hidden too, from the next build.
  if newRank and HiddenAnywhere(name) then ns.Rebuild(true) end
end

-- A buff's length from its spell's description ("... for 20 sec."), for
-- buffs whose duration the game never let us read. nil when it doesn't say.
local function DescribedDuration(ids)
  if not C_Spell.GetSpellDescription then return end
  for id in pairs(ids) do
    local ok, text = pcall(C_Spell.GetSpellDescription, id)
    if ok and not issecret(text) and type(text) == "string" then
      text = text:lower()
      for _, unit in ipairs({ { "sec", 1 }, { "min", 60 }, { "hour", 3600 } }) do
        for _, lead in ipairs({ "for ", "lasts ", "over " }) do
          local number = text:match(lead .. "(%d+%.?%d*) " .. unit[1])
          if number then return tonumber(number) * unit[2] end
        end
      end
    end
  end
end

-- This class's buffs, most recently seen first: { name, icon, duration,
-- guessed (the duration is from its description), seen, ids }.
function Learn.Buffs()
  local list = {}
  for name, entry in pairs(Book()) do
    if entry.duration == nil and not entry.noDescription then
      entry.duration = DescribedDuration(entry.ids)
      if entry.duration then entry.guessed = true else entry.noDescription = true end
    end
    list[#list + 1] = { name = name, icon = entry.icon, duration = entry.duration, guessed = entry.guessed,
      seen = entry.seen or 0, ids = entry.ids }
  end
  table.sort(list, function(a, b)
    if a.seen ~= b.seen then return a.seen > b.seen end
    return a.name < b.name
  end)
  return list
end

local function Ago(seen)
  local days = math.floor((time() - (seen or 0)) / 86400)
  if days <= 0 then return "today" end
  if days == 1 then return "yesterday" end
  return days .. " days ago"
end

-- The game's tooltip for a buff (its spell's), with when you last had it.
-- buff: an entry of Learn.Buffs(), or { ids = { [id] = true } } / spellID.
function Learn.ShowTooltip(owner, buff)
  if type(buff) == "number" then buff = { ids = { [buff] = true } } end
  local id = buff and next(buff.ids or {})
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if not (id and pcall(GameTooltip.SetSpellByID, GameTooltip, id)) then
    GameTooltip:SetText(buff and buff.name or "?")
  end
  if buff and buff.seen then
    local ranks = 0
    for _ in pairs(buff.ids) do ranks = ranks + 1 end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Last had: %s%s"):format(Ago(buff.seen), ranks > 1 and (", " .. ranks .. " ranks seen") or ""), 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

-- For "A buff I've had": each buff with one of its spell IDs.
function Learn.Seen()
  local list = {}
  for _, buff in ipairs(Learn.Buffs()) do
    local id = next(buff.ids)
    if id then list[#list + 1] = { id = id, name = buff.name, icon = buff.icon, seen = buff.seen } end
  end
  return list
end

-- The spell IDs of a bar's hidden buffs, every rank (the game's aura frame
-- filters by ID). config.exclude: IDs from older versions whose name wasn't known.
function Learn.HiddenIDs(config)
  local ids, book = {}, Book()
  for name in pairs(config.hide or {}) do
    for id in pairs(book[name] and book[name].ids or {}) do ids[id] = true end
  end
  for id in pairs(config.exclude or {}) do ids[id] = true end
  return ids
end

-- Hides a buff (by name) on a bar, or shows it again.
function Learn.SetHidden(config, name, hidden)
  config.hide = config.hide or {}
  config.hide[name] = hidden or nil
  if not next(config.hide) then config.hide = nil end
end

-- Hidden buffs used to be kept by spell ID (config.exclude): now by name.
local function MigrateExcludes()
  for _, profile in pairs(CombatHUDDB.profiles or {}) do
    for _, bar in ipairs(profile.bars or {}) do
      for id in pairs(bar.exclude or {}) do
        local name = ns.SpellName(id)
        if name then
          bar.hide = bar.hide or {}
          bar.hide[name] = true
          local book = Book()
          local entry = book[name] or { ids = {}, icon = C_Spell.GetSpellTexture(id), seen = time() }
          entry.ids[id] = true
          book[name] = entry
          bar.exclude[id] = nil
        end
      end
      if bar.exclude and not next(bar.exclude) then bar.exclude = nil end
    end
  end
end

-- Forgets buffs not seen for a long while, unless a bar hides them.
local function Prune()
  local hidden = {}
  for _, profile in pairs(CombatHUDDB.profiles or {}) do
    for _, bar in ipairs(profile.bars or {}) do
      for name in pairs(bar.hide or {}) do hidden[name] = true end
    end
  end
  local cutoff = time() - FORGET_AFTER
  for _, book in pairs(CombatHUDDB.buffBook or {}) do
    for name, entry in pairs(book) do
      if (entry.seen or 0) < cutoff and not hidden[name] then book[name] = nil end
    end
  end
end

-- Before the HUD is built (Profile.lua builds it at login too, after this).
ns.On("PLAYER_LOGIN", function()
  if not CombatHUDDB then return end
  MigrateExcludes()
  Prune()
end)

ns.OnUnit("UNIT_AURA", "player", function(_, _, info)
  if issecret(info) or not info or issecret(info.addedAuras) or not info.addedAuras then return end
  local now = GetTime()
  local learning = not InCombatLockdown() and next(wanted)
  for _, aura in ipairs(info.addedAuras) do
    local id, name, icon = aura.spellId, aura.name, aura.icon
    local helpful, mine = aura.isHelpful, aura.isFromPlayerOrPlayerPet
    if Readable(id, name, icon, helpful, mine) and helpful ~= false and mine ~= false and id then
      RememberSeen(id, name, icon, aura.duration)
      if learning then table.insert(recent, { id = id, name = name, icon = icon, time = now }) end
    end
  end
  while recent[1] and now - recent[1].time > 3 do table.remove(recent, 1) end
end)

-- Buffs still up when combat ends are readable again.
local function ScanBuffs()
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not getAura or InCombatLockdown() then return end
  for index = 1, 40 do
    local ok, aura = pcall(getAura, "player", index, "HELPFUL|PLAYER")
    if not ok or not aura or not Readable(aura.spellId, aura.name, aura.icon) then break end
    RememberSeen(aura.spellId, aura.name, aura.icon, aura.duration)
  end
end
ns.On("PLAYER_REGEN_ENABLED", ScanBuffs)
-- At login too, for the durations of buffs you already have.
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, ScanBuffs) end)

-- Picks the buff a cast gave from the buffs that appeared around it.
local function LearnFromCast(spellName, castTime)
  local spell = wanted[spellName]
  if not spell or InCombatLockdown() then return end
  local candidates, matching = {}, {}
  for _, aura in ipairs(recent) do
    if aura.time >= castTime - 0.5 and aura.time <= castTime + 0.6 then
      table.insert(candidates, aura)
      if aura.name == spellName or (spell.icon ~= nil and aura.icon == spell.icon) then table.insert(matching, aura) end
    end
  end
  local chosen = matching
  if #chosen == 0 and #candidates == 1 then chosen = candidates end

  local learned, tracked = false, false
  for _, aura in ipairs(chosen) do
    if spell.ids[aura.id] then
      tracked = true
    elseif Remember(spellName, aura.id, aura.name) then
      spell.ids[aura.id] = true
      learned = true
    end
  end
  if learned then
    ns.Rebuild(true)
  elseif not tracked and #chosen == 0 then
    -- Also covers buffs already up before the cast (a refresh adds nothing new).
    if not ScanBuffs(spellName) then
      if spell.quiet then
        -- Nothing to say.
      elseif #candidates == 0 then
        ns.Print(("Cast %s, but no new buff of yours appeared, so there was nothing to learn."):format(spellName))
      else
        ns.Print(("Cast %s and %d buffs appeared at once; couldn't tell which is its own. Right-click the bar in edit mode and use \"Add a buff I have now\"."):format(spellName, #candidates))
      end
    else
      ns.Rebuild(true)
    end
  end
end

-- After you cast a spell that's on an aura bar, look for its buff.
ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID or InCombatLockdown() then return end
  local name = C_Spell.GetSpellName(spellID)
  if not name or issecret(name) or not wanted[name] then return end
  local castTime = GetTime()
  C_Timer.After(0.6, function() LearnFromCast(name, castTime) end)
end)

function Learn.Print()
  local links = CombatHUDDB and CombatHUDDB.auraLinks
  if not links or not next(links) then
    ns.Print("No buffs learned yet.")
    return
  end
  for spellName, ids in pairs(links) do
    local parts = {}
    for _, id in ipairs(ids) do
      local name = C_Spell.GetSpellName(id)
      parts[#parts + 1] = ("%s (%d)"):format(name and not issecret(name) and name or "?", id)
    end
    ns.Print(spellName .. " -> " .. table.concat(parts, ", "))
  end
end

function Learn.Clear()
  if CombatHUDDB then CombatHUDDB.auraLinks = {} end
  ns.Print("Forgot all learned buffs.")
end
