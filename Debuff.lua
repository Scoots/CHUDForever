-- A cooldown button can also show your debuff from that spell on the target.
-- While it's up, the button shows the debuff's own icon in full color with
-- its time left as a big number in the middle, red for the last few seconds,
-- and its stacks in the corner.
-- The spell's cooldown keeps its clock swipe on top, its number moved to the
-- corner (Button.lua). The debuff is drawn by the game's aura widget (secret
-- in combat), in a part laid between the button's icon and its swipes. Parts
-- are pooled apart from the buttons, so a button without one never carries
-- an aura widget around.
--
-- A shared cooldown's button watches every member's debuff (Groups.lua): a
-- shocks button shows Flame Shock's damage over time or Frost Shock's slow,
-- and with both up, the one ending first (the game sorts them by time left).
--
-- "Auto" (targetDebuff = "auto", the default on generated rotation bars)
-- works out for each spell whether it leaves a debuff, and sets the button up:
--   a debuff and no cooldown (Corruption): gray until it's on the target, then
--     the debuff's icon in color with its time left;
--   a debuff and a cooldown (Flame Shock, Stormstrike): always in color, the
--     cooldown as a clock spinner, the debuff's time left as a big number.
local _, ns = ...

local Debuff = {}
ns.Debuff = Debuff

local SLOT = "Debuff"
local LOW = 5 -- seconds left when the number turns red

-- Spells that leave a debuff ----------------------------------------------------------------
-- What you've been seen casting comes first (CombatHUDDB.debuffSpells, by
-- name), then lists of well-known ones, then the spell's description for a
-- harmful spell ("over 12 sec", "for 8 sec", "Lasts 30 sec").

local KNOWN = {
  589, 15286, 14914,                        -- Shadow Word: Pain, Vampiric Embrace, Holy Fire
  172, 980, 348, 18265, 702, 1490, 17862, 704, 1714, -- Corruption, Agony, Immolate, Siphon Life, curses
  8921, 5570, 770, 16857, 1822, 1079,        -- Moonfire, Insect Swarm, Faerie Fire (both), Rake, Rip
  772, 7386, 1715, 1160, 6343, 12294,        -- Rend, Sunder Armor, Hamstring, Demoralizing Shout, Thunder Clap, Mortal Strike
  1978, 1130, 3043, 3034, 5116, 2974,        -- Serpent, Hunter's Mark, Scorpid, Viper, Concussive Shot, Wing Clip
  1943, 703, 8647,                           -- Rupture, Garrote, Expose Armor
  17364, 8050, 8056,                         -- Stormstrike, Flame Shock, Frost Shock
}
-- Ones whose description reads like a debuff but that leave none to track.
local NOT = { 8042, 1766, 6552, 72, 2139, 2120 } -- Earth Shock, Kick, Pummel, Shield Bash, Counterspell, Flamestrike

local SpellName, Names, Harmful = ns.SpellName, ns.NameSet, ns.IsHarmful

local function Learned()
  if not CombatHUDDB then return {} end
  CombatHUDDB.debuffSpells = CombatHUDDB.debuffSpells or {}
  return CombatHUDDB.debuffSpells
end

local function Describes(spellID)
  if not C_Spell.GetSpellDescription then return false end
  local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
  if not ok or ns.issecret(text) or type(text) ~= "string" then return false end
  text = text:lower()
  return (text:find("over %d+ sec") or text:find("for %d+ sec") or text:find("lasts %d+ sec")
    or text:find("for %d+ min")) ~= nil
end

function Debuff.LeavesDebuff(spellID)
  local name = SpellName(spellID)
  if not name then return false end
  local learned = Learned()[name]
  if learned ~= nil then return learned end
  if Names(KNOWN)[name] then return true end
  if Names(NOT)[name] then return false end
  return Harmful(spellID) and Describes(spellID)
end

-- A cooldown of its own, longer than the global cooldown.
function Debuff.HasCooldown(spellID)
  local cooldown = ns.BaseCooldown(spellID)
  return cooldown ~= nil and cooldown > 1.5
end

-- Whether an entry's spell (any member of a shared cooldown) leaves a debuff.
function Debuff.EntryLeavesDebuff(entry)
  for _, id in ipairs(ns.Groups.Members(entry)) do
    if Debuff.LeavesDebuff(id) then return true end
  end
  return false
end

-- For "auto": settles a spell button's options (its own merged copy).
function Debuff.ApplyAuto(opts, entry, spellID)
  if opts.targetDebuff ~= "auto" then return end
  if not Debuff.EntryLeavesDebuff(entry) then
    opts.targetDebuff = false
    return
  end
  opts.targetDebuff = true
  if Debuff.HasCooldown(spellID) then
    opts.desaturate, opts.numbers = false, false -- colored; the cooldown as a spinner, the debuff's time as the number
  else
    opts.debuffGray = true -- gray until it's on the target
  end
end

-- Learning from your casts, out of combat: a harmful spell whose debuff then
-- shows on the target leaves one; one that twice doesn't, doesn't.
local misses = {}

local function Check(name)
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not getAura then return end
  local found = false
  for index = 1, 40 do
    local ok, aura = pcall(getAura, "target", index, "HARMFUL|PLAYER")
    if not ok or ns.issecret(aura) then return end
    if not aura then break end
    if ns.issecret(aura.name) then return end
    if aura.name == name then
      found = true
      break
    end
  end
  local store = Learned()
  local before = store[name]
  if found then
    store[name], misses[name] = true, nil
  else
    misses[name] = (misses[name] or 0) + 1
    if misses[name] >= 2 then store[name] = false end
  end
  if store[name] ~= before then ns.Rebuild(true) end
end

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if ns.issecret(spellID) or not spellID or InCombatLockdown() then return end
  local name = SpellName(spellID)
  if not name or not Harmful(spellID) then return end
  local exists = UnitExists("target")
  if ns.issecret(exists) or not exists then return end
  C_Timer.After(0.7, function() Check(name) end)
end)

-- The game's order for a debuff group: the one ending first, if it can sort.
local function SortOrder()
  if AuraContainerSortMethod and AuraContainerSortDirection and AuraContainerSortMethod.ExpirationOnly then
    return AuraContainerSortMethod.ExpirationOnly, AuraContainerSortDirection.Normal
  end
end

local retired = CreateFrame("Frame")
retired:Hide()
local pool


local function BuildNative(button, part)
  button:EnableMouse(false)
  -- The debuff's own icon (Flame or Frost Shock, say), set by the game.
  part.icon = button:CreateTexture(nil, "ARTWORK")
  part.icon:SetAllPoints()
  part.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ns.Try("debuff icon", button.SetIcon, button, part.icon)
  part.time = button:CreateFontString(nil, "OVERLAY")
  part.time:SetPoint("CENTER", button, "CENTER", 0, 0)
  part.time:SetFont(ns.Font(), math.max(10, math.floor(part.size * 0.45)), "THICKOUTLINE")
  part.time:SetShadowColor(0, 0, 0, 1)
  part.time:SetShadowOffset(1, -1)
  ns.BindTimer(button, part.time, LOW)
  part.stacks = button:CreateFontString(nil, "OVERLAY")
  part.stacks:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
  part.stacks:SetFont(ns.Font(), math.max(8, math.floor(part.size * 0.3)), "OUTLINE")
  part.stacks:SetShadowColor(0, 0, 0, 1)
  part.stacks:SetShadowOffset(1, -1)
  ns.Try("debuff stacks", button.SetApplicationCount, button, part.stacks)
  local ok, fx = pcall(ns.Glow.BuildAlertFx, button, true)
  if ok then part.fx = fx end
  part.button = button
end

local function Place(part, btn)
  local button = part.button
  if not button then return end
  pcall(button.SetSize, button, part.size, part.size)
  pcall(button.ClearAllPoints, button)
  pcall(button.SetPoint, button, "CENTER", btn, "CENTER")
  part.time:SetFont(ns.Font(), math.max(10, math.floor(part.size * 0.45)), "THICKOUTLINE")
  part.stacks:SetFont(ns.Font(), math.max(8, math.floor(part.size * 0.3)), "OUTLINE")
end

local function Create(filter, candidates, size)
  local part = { size = size }
  part.holder = CreateFrame("Frame", nil, UIParent)
  part.holder:EnableMouse(false)
  local container = ns.Aura.NewContainer(part.holder)
  container:SetPoint("TOPLEFT", part.holder, "TOPLEFT")
  part.container = container
  local function Init(button) BuildNative(button, part) end
  -- A sorted group shows the debuff ending first; a slot only where the game can't sort.
  local method, direction = SortOrder()
  if not method and container.AddAuraSlot and pcall(container.AddAuraSlot, container, SLOT, filter,
      { candidateFilters = candidates, initializeFrame = Init }) and part.button then
    part.slot = true
    return part
  end
  local ok, err = pcall(container.AddAuraGroup, container, SLOT, filter, {
    candidateFilters = candidates, maxFrameCount = 1, layout = { elementWidth = size, elementHeight = size },
    sortMethod = method, sortDirection = direction, initializeFrame = Init,
  })
  if not ok then
    ns.Print("Couldn't show the target debuff on a button: " .. tostring(err))
    ns.Aura.Unbind(container)
    return
  end
  return part
end

local function ResetPooled(part)
  ns.Aura.Unbind(part.container)
  part.holder:Hide()
  part.holder:ClearAllPoints()
end

pool = ns.CreatePool(Create, ResetPooled, retired)

-- Lays a debuff part over a cooldown button for its spell.
function Debuff.Attach(btn)
  local filter = "HARMFUL|PLAYER"
  local candidates = { includeSpellIDs = ns.Groups.DebuffIDs(btn.entry, btn.spellID) }
  local size = btn:GetWidth()
  local part = pool.Acquire(nil, filter, candidates, size)
  if not part then return end
  local container = part.container
  part.size = size
  if part.slot then
    ns.Try("debuff filter", container.SetAuraSlotFilterString, container, SLOT, filter)
    ns.Try("debuff spells", container.SetAuraSlotCandidateFilters, container, SLOT, candidates)
    if container.SetAuraSlotEnabled then ns.Try("debuff enable", container.SetAuraSlotEnabled, container, SLOT, true) end
  else
    ns.Try("debuff spells", container.SetAuraGroupCandidateFilters, container, SLOT, candidates)
    ns.Try("debuff layout", container.SetAuraGroupLayout, container, SLOT, { elementWidth = size, elementHeight = size })
    local method, direction = SortOrder()
    if method and container.SetAuraGroupSortMethod then
      ns.Try("debuff order", container.SetAuraGroupSortMethod, container, SLOT, method, direction)
    end
    if container.SetAuraGroupEnabled then ns.Try("debuff enable", container.SetAuraGroupEnabled, container, SLOT, true) end
  end
  part.holder:SetParent(btn)
  part.holder:ClearAllPoints()
  part.holder:SetAllPoints(btn)
  part.holder:SetFrameLevel(btn:GetFrameLevel() + 2) -- above the icon, under the swipes
  part.container:SetFrameLevel(part.holder:GetFrameLevel())
  part.holder:Show()
  Place(part, btn)
  if part.fx then
    ns.Glow.StyleAlertFx(part.fx, ns.Alerts.VisualFor(btn.opts, "applied"))
    ns.Glow.SizeAlertFx(part.fx, part.size)
  end
  if not ns.Try("debuff unit", ns.Aura.Bind, part.container, "target") then
    Debuff.Detach(btn, part)
    return
  end
  btn.debuff = part
  table.insert(ns.activeAuras, { unit = "target", container = part.container, name = btn.spellName, natives = {} })
end

function Debuff.Detach(btn, part)
  part = part or btn.debuff
  if not part then return end
  btn.debuff = nil
  pool.Release(part)
end
