-- Shared cooldowns: one button for several spells or items that share a
-- cooldown (the shocks, a hunter's fire or frost traps, Fire and Frost Ward,
-- potions). The entry
-- lists the others in entry.group: spell IDs on a spell's button, item IDs on
-- an item's. The button tracks its own spell if you know it, else the first
-- member you know (an item button: the first one you carry). Its icon is the
-- member you used last, or always its own (entry.groupIcon = "first"). With
-- Target debuff on, it watches every member's debuff on the target.
local _, ns = ...
local issecret = ns.issecret

local Groups = {}
ns.Groups = Groups

-- Shared cooldowns the game has, offered as a quick way to fill a group.
-- ranks: more spell IDs whose debuffs count (the lower ranks).
Groups.FAMILIES = {
  { name = "Shocks", members = { 8042, 8050, 8056 }, -- Earth, Flame, Frost Shock
    ranks = { 8042, 8044, 8045, 8046, 10412, 10413, 10414, 8050, 8052, 8053, 10447, 10448, 29228,
      8056, 8058, 10472, 10473 } },
  -- Traps: every rank, and the debuffs they leave ("Immolation Trap Effect"...).
  { name = "Fire traps", members = { 13795, 13813 }, -- Immolation, Explosive Trap
    ranks = { 13795, 14302, 14303, 14304, 14305, 13797, 14298, 14299, 14300, 14301,
      13813, 14316, 14317, 13812, 14314, 14315 } },
  { name = "Frost traps", members = { 1499, 13809 }, -- Freezing, Frost Trap
    ranks = { 1499, 14310, 14311, 3355, 14308, 14309, 13809, 13810 } },
  -- Curses: only one of yours on a target at a time (Bane of Doom has its own
  -- button, but its debuff counts here too). Forever calls Agony and Doom
  -- "Bane of", has new IDs for the Elements, and no Curse of Shadow.
  { name = "Curses", members = { 980, 702, 704, 1714, 1311676, 18223 }, -- Agony, Weakness, Recklessness,
    ranks = { 980, 1014, 6217, 11711, 11712, 11713, 702, 1108, 6205, 7646, 11707, 11708, -- Tongues, the Elements,
      704, 7658, 7659, 11717, 1714, 11719, 1311676, 1311677, 1311680, 440892, 18223, 603 } }, -- Exhaustion
  -- Stings: no shared cooldown, but only one of yours on a target at a time.
  { name = "Stings", members = { 1978, 3034, 3043 }, -- Serpent, Viper, Scorpid Sting
    ranks = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 3034, 14279, 14280,
      3043 } },
  { name = "Fire and Frost Ward", members = { 543, 6143 } },
}

local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local SpellName = ns.SpellName

function Groups.IsGroup(entry)
  return type(entry.group) == "table" and #entry.group > 0
end

-- Every member, the entry's own spells (or item) first, each once.
function Groups.Members(entry)
  local list, seen = {}, {}
  local function Add(id)
    if type(id) == "number" and not seen[id] then
      seen[id] = true
      list[#list + 1] = id
    end
  end
  local own = entry.item or entry.spell
  if type(own) == "table" then
    for _, id in ipairs(own) do Add(id) end
  else
    Add(own)
  end
  for _, id in ipairs(entry.group or {}) do Add(id) end
  return list
end

-- The spell a spell's button tracks: its own if known, else the first member
-- known. Same returns as ns.ResolveSpell.
function Groups.ResolveSpell(entry)
  -- entry.bySpec: spec key -> the spell for that spec (a mage's filler), when known.
  local mine = entry.bySpec and ns.specKey and entry.bySpec[ns.specKey]
  if mine then
    local spellID, name = ns.ResolveSpell(mine)
    if spellID then return spellID, name end
  end
  local spellID, name = ns.ResolveSpell(entry.spell)
  if spellID or not Groups.IsGroup(entry) then return spellID, name end
  return ns.ResolveSpell(entry.group)
end

-- The item an item's button tracks: its own if you carry it, else the first
-- member you carry, else its own.
function Groups.ResolveItem(entry)
  if not Groups.IsGroup(entry) or not GetItemCount then return entry.item end
  for _, id in ipairs(Groups.Members(entry)) do
    local ok, count = pcall(GetItemCount, id)
    if ok and not issecret(count) and type(count) == "number" and count > 0 then return id end
  end
  return entry.item
end

-- Each member's name (for an item, the spell it casts when used) and icon,
-- for telling which one you just used.
function Groups.Names(entry)
  local names = {}
  for _, id in ipairs(Groups.Members(entry)) do
    if entry.item then
      local ok, name = pcall(GetItemSpell, id)
      local icon = ns.Button.ItemIcon(id)
      if ok and not issecret(name) and name and icon then names[name] = icon end
    else
      local name = SpellName(id)
      if name then names[name] = C_Spell.GetSpellTexture(id) end
    end
  end
  return names
end

-- The known shared cooldown a spell belongs to (any rank), if any.
function Groups.FamilyOf(spellID)
  local name = type(spellID) == "number" and SpellName(spellID)
  if not name then return end
  for _, family in ipairs(Groups.FAMILIES) do
    for _, id in ipairs(family.members) do
      if SpellName(id) == name then return family end
    end
  end
end

-- What Target debuff watches on the target: the spell's debuff, or with a
-- group, every member's (any rank, for the known families).
function Groups.DebuffIDs(entry, spellID)
  if not Groups.IsGroup(entry) then return ns.Aura.SpellIDs({ spell = spellID }) end
  local members = Groups.Members(entry)
  local ids = ns.Aura.SpellIDs({ spell = spellID, aura = members })
  for _, id in ipairs(members) do
    local family = Groups.FamilyOf(id)
    for _, rank in ipairs(family and family.ranks or {}) do ids[rank] = true end
  end
  return ids
end

-- Adds a dropped spell or item to a button's group: spells go with spells,
-- items with items. Returns the added ID, or nil when it can't go there.
function Groups.Add(entry, dropped)
  local id
  if entry.spell then id = dropped.spell elseif entry.item then id = dropped.item end
  if type(id) ~= "number" then return end
  for _, have in ipairs(Groups.Members(entry)) do
    if have == id then return id end
  end
  entry.group = entry.group or {}
  table.insert(entry.group, id)
  return id
end

function Groups.Remove(entry, id)
  for index, have in ipairs(entry.group or {}) do
    if have == id then
      table.remove(entry.group, index)
      break
    end
  end
  if not Groups.IsGroup(entry) then entry.group, entry.groupIcon = nil, nil end
end

-- The first spell button in a list (other than skip) of the same known family
-- as a spell: where a dropped spell stacks. nil when there's none.
function Groups.FamilyButton(entries, spellID, skip)
  local family = Groups.FamilyOf(spellID)
  if not family then return end
  for _, entry in ipairs(entries) do
    if entry ~= skip and entry.spell and not entry.aura then
      for _, id in ipairs(Groups.Members(entry)) do
        if Groups.FamilyOf(id) == family then return entry end
      end
    end
  end
end

-- How many buttons Collapse would fold in, changing nothing.
function Groups.Collapsible(entries)
  local count = 0
  for index, entry in ipairs(entries) do
    local first = type(entry.spell) == "table" and entry.spell[1] or entry.spell
    local into = not entry.aura and first and Groups.FamilyButton(entries, first, entry)
    for other = 1, index - 1 do
      if entries[other] == into then
        count = count + 1
        break
      end
    end
  end
  return count
end

-- Stacks a list's spell buttons of the same known family (three shock
-- buttons become one shocks button). Returns how many buttons it folded in.
function Groups.Collapse(entries)
  local folded, index = 0, 1
  while index <= #entries do
    local entry = entries[index]
    local first = type(entry.spell) == "table" and entry.spell[1] or entry.spell
    local into = not entry.aura and first and Groups.FamilyButton(entries, first, entry)
    -- Only into a button earlier in the list, so the first one keeps its place.
    local earlier = false
    for other = 1, index - 1 do
      if entries[other] == into then earlier = true end
    end
    if into and earlier then
      for _, id in ipairs(Groups.Members(entry)) do Groups.Add(into, { spell = id }) end
      table.remove(entries, index)
      folded = folded + 1
    else
      index = index + 1
    end
  end
  return folded
end

-- The members of a known family a button doesn't have yet.
function Groups.Missing(entry, family)
  local have, missing = {}, {}
  for _, id in ipairs(Groups.Members(entry)) do
    local name = SpellName(id)
    if name then have[name] = true end
  end
  for _, id in ipairs(family.members) do
    local name = SpellName(id)
    if name and not have[name] then missing[#missing + 1] = id end
  end
  return missing
end

-- Before shared cooldowns, a shock with Target debuff on stood for every
-- shock by itself. Such buttons get the shocks as their group, once, so they
-- keep working the same way.
local SHOCK_RANKS = {}
for _, id in ipairs(Groups.FAMILIES[1].ranks) do SHOCK_RANKS[id] = true end

function Groups.MigrateProfile(profile)
  for _, bar in ipairs(profile.bars or {}) do
    for _, entry in ipairs(bar.buttons or {}) do
      local first = type(entry.spell) == "table" and entry.spell[1] or entry.spell
      local targetDebuff = entry.targetDebuff
      if targetDebuff == nil then targetDebuff = (bar.buttonDefaults or {}).targetDebuff end
      if targetDebuff and not entry.group and not entry.aura and SHOCK_RANKS[first] then
        entry.group = { 8042, 8050, 8056 }
      end
    end
  end
end

function Groups.Migrate(db)
  if db.groupsVersion == 1 then return end
  db.groupsVersion = 1
  for _, profile in pairs(db.profiles or {}) do Groups.MigrateProfile(profile) end
end
