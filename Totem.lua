-- Totem bar: four fixed slots (Earth, Fire, Water, Air by default). A slot
-- shows the totem you dropped with its time left, a thin bar for the totem
-- spell's cooldown, a pulse timer for totems that pulse (Tremor...), and a red
-- glow while you're out of range of a totem that buffs you.
--
-- In combat the totem slots can be secret. The time left still works: the
-- game draws it from GetTotemDuration. Which totem it is comes from your own
-- cast (its spell ID is usually readable) or, out of combat, from
-- GetTotemInfo, which also teaches us which slot unfamiliar totems use.
-- "Out of range" means the totem's buff is missing on you, decided by the
-- game's aura widget the same way as the missing-buff alerts.
local _, ns = ...
local issecret = ns.issecret

local Totem = {}
ns.Totem = Totem

local WHITE = ns.WHITE
local PRESENCE = "TotemRange"
local MAX_PULSE_TIME = 300

-- Slot numbers on this client: 1 Fire, 2 Earth, 3 Water, 4 Air.
local ELEMENTS = {
  [1] = { name = "Fire", color = { 1, 0.4, 0.15 }, icon = 3599 },   -- Searing Totem
  [2] = { name = "Earth", color = { 0.6, 0.85, 0.3 }, icon = 8075 }, -- Strength of Earth Totem
  [3] = { name = "Water", color = { 0.3, 0.6, 1 }, icon = 5394 },    -- Healing Stream Totem
  [4] = { name = "Air", color = { 0.85, 0.85, 1 }, icon = 8835 },    -- Grace of Air Totem
}
local DEFAULT_ORDER = { 2, 1, 3, 4 }

-- Every rank of each Classic totem: its slot, the buff it puts on you (for
-- range), how often it pulses (for totems without a buff), and its reach in
-- yards: 30 for party totems on WoW Forever, the Classic tooltip otherwise.
-- (Reaches used to be learned from when a totem's buff left you, but the buffs
-- also drop and come back by themselves, which made them far too short.)
local TOTEMS = {
  -- Fire
  { slot = 1, ranks = { 3599, 6363, 6364, 6365, 10437, 10438 }, range = 20 },                -- Searing
  { slot = 1, ranks = { 8190, 10585, 10586, 10587 }, pulse = 2, range = 8 },                 -- Magma
  { slot = 1, ranks = { 8227, 8249, 10526, 16387 }, range = 30 },                             -- Flametongue
  { slot = 1, ranks = { 8181, 10478, 10479 }, buffs = { 8182, 10476, 10477 }, range = 30 },   -- Frost Resistance
  { slot = 1, ranks = { 1535, 8498, 8499, 11314, 11315 }, range = 10 },                       -- Fire Nova
  -- Earth
  { slot = 2, ranks = { 8071, 8154, 8155, 10406, 10407, 10408 }, buffs = { 8072, 8156, 8157, 10403, 10404, 10405 }, range = 30 }, -- Stoneskin
  { slot = 2, ranks = { 5730, 6390, 6391, 6392, 10427, 10428 }, range = 20 },                 -- Stoneclaw
  { slot = 2, ranks = { 8075, 8160, 8161, 10442, 25361 }, buffs = { 8076, 8162, 8163, 10441, 25362 }, range = 30 }, -- Strength of Earth
  { slot = 2, ranks = { 2484 }, pulse = 3, range = 10 },                                      -- Earthbind
  { slot = 2, ranks = { 8143 }, pulse = 4, range = 30 },                                      -- Tremor
  -- Water
  { slot = 3, ranks = { 5394, 6375, 6377, 10462, 10463 }, buffs = { 5672, 6371, 6372, 10460, 10461 }, range = 30 }, -- Healing Stream
  { slot = 3, ranks = { 5675, 10495, 10496, 10497 }, buffs = { 5677, 10491, 10493, 10494 }, range = 30 },          -- Mana Spring
  { slot = 3, ranks = { 16190, 17354, 17359 }, range = 30 },                                  -- Mana Tide
  { slot = 3, ranks = { 8166 }, pulse = 5, range = 30 },                                      -- Poison Cleansing
  { slot = 3, ranks = { 8170 }, pulse = 5, range = 30 },                                      -- Disease Cleansing
  { slot = 3, ranks = { 8184, 10537, 10538 }, buffs = { 8185, 10534, 10535 }, range = 30 },   -- Fire Resistance
  -- Air
  { slot = 4, ranks = { 8835, 10627, 25359 }, buffs = { 8836, 10626, 25360 }, range = 30 },   -- Grace of Air
  { slot = 4, ranks = { 8177 }, pulse = 10, range = 30 },                                     -- Grounding
  { slot = 4, ranks = { 10595, 10600, 10601 }, buffs = { 10596, 10598, 10599 }, range = 30 }, -- Nature Resistance
  { slot = 4, ranks = { 8512, 10613, 10614 }, range = 30 },                                   -- Windfury
  { slot = 4, ranks = { 15107, 15111, 15112 }, buffs = { 15108, 15109, 15110 }, range = 30 }, -- Windwall
  { slot = 4, ranks = { 25908 }, buffs = { 25909 }, range = 30 },                             -- Tranquil Air
  { slot = 4, ranks = { 6495 } },                                                 -- Sentry
}

local bySpell = {} -- totem spell ID -> its TOTEMS entry
for _, totem in ipairs(TOTEMS) do
  for _, id in ipairs(totem.ranks) do bySpell[id] = totem end
end

-- State per slot, kept across rebuilds.
local slotSpell = {}  -- slot -> spell ID of the totem last dropped there
local pulseStart = {} -- slot -> GetTime() when its pulsing totem went down
local items = {}      -- slot -> the item showing it
local drops = {}      -- slot -> { x, y, instance } where the totem landed (its corner, see TotemSpot)

-- Slots learned for totems not in the table, by spell name (CombatHUDDB.totemSlots).
local function Learned()
  if not CombatHUDDB then return {} end
  CombatHUDDB.totemSlots = CombatHUDDB.totemSlots or {}
  return CombatHUDDB.totemSlots
end

local SpellName = ns.SpellName

local function SlotForSpell(spellID)
  local totem = bySpell[spellID]
  if totem then return totem.slot end
  local name = SpellName(spellID)
  return name and Learned()[name]
end

-- Buff IDs that mean "in range" for a totem: from the table, plus any learned
-- for its name (Learn.lua).
local function BuffsFor(spellID)
  local ids = {}
  local totem = bySpell[spellID]
  for _, id in ipairs(totem and totem.buffs or {}) do ids[#ids + 1] = id end
  for _, id in ipairs(ns.Learn.Linked(SpellName(spellID)) or {}) do ids[#ids + 1] = id end
  return ids
end

-- The table's buffs for a totem, as a set (already known, so not "learned").
function Totem.BuffSet(spellID)
  local set = {}
  local totem = bySpell[spellID]
  for _, id in ipairs(totem and totem.buffs or {}) do set[id] = true end
  return set
end

local function PulseFor(spellID)
  local totem = spellID and bySpell[spellID]
  return totem and totem.pulse
end

-- Every totem spell the player knows, for learning their buffs.
function Totem.KnownSpells()
  local known = {}
  for id in pairs(bySpell) do
    if ns.IsSpellKnown(id) then known[#known + 1] = id end
  end
  return known
end

-- Distance ---------------------------------------------------------------------------------
-- Where a totem landed, against where you are now, in yards (world
-- coordinates are yards). Positions are readable in combat in the open
-- world; where they aren't (instances), no distance is shown.

local function PlayerPosition()
  if not UnitPosition then return end
  local ok, y, x, _, instance = pcall(UnitPosition, "player")
  if not ok or issecret(y) or issecret(x) or issecret(instance) or not y or not x then return end
  return x, y, instance
end

-- Totems don't go down at your feet: each element has its corner, 5 yards
-- out at 45 degrees from the way you face. Fire front left, Earth front
-- right, Water back right, Air back left (angles counter-clockwise from your
-- facing).
local SPOT_DISTANCE = 5
local SPOT_ANGLE = { [1] = math.pi / 4, [2] = -math.pi / 4, [3] = -3 * math.pi / 4, [4] = 3 * math.pi / 4 }

-- Where a totem for this slot lands if dropped now. UnitPosition's x grows
-- to the west and y to the north; facing is 0 to the north, growing
-- counter-clockwise, so straight ahead is (sin, cos). Without a readable
-- facing, where you stand.
local function TotemSpot(slot)
  local x, y, instance = PlayerPosition()
  if not x then return end
  local ok, facing = pcall(GetPlayerFacing)
  if ok and not issecret(facing) and type(facing) == "number" and SPOT_ANGLE[slot] then
    local angle = facing + SPOT_ANGLE[slot]
    x, y = x + math.sin(angle) * SPOT_DISTANCE, y + math.cos(angle) * SPOT_DISTANCE
  end
  return x, y, instance
end

-- A totem's reach in yards (plus the bar's Extra reach), or nil if unknown.
local function RangeFor(spellID, extra)
  local totem = bySpell[spellID]
  if not totem or not totem.range then return end
  return totem.range + (extra or 0)
end

local function TotemDuration(slot)
  if not GetTotemDuration then return end
  local ok, duration = pcall(GetTotemDuration, slot)
  if ok then return duration end
end

-- Out of combat: who's in the slot, learned for next time.
local function ReadSlot(slot)
  if not GetTotemInfo then return end
  local ok, have, _, start, _, icon, _, spellID = pcall(GetTotemInfo, slot)
  if not ok then return end
  for _, value in ipairs({ have, start, icon, spellID }) do
    if issecret(value) then return end
  end
  if have and start and start ~= 0 then
    if type(spellID) == "number" and spellID > 0 then
      slotSpell[slot] = spellID
      local name = SpellName(spellID)
      if name and not bySpell[spellID] then Learned()[name] = slot end
    end
    return true, icon
  end
  return false
end

-- Items ----------------------------------------------------------------------------------

local retired = CreateFrame("Frame")
retired:Hide()
local pool

local function Create()
  local item = CreateFrame("Frame", nil, UIParent)
  item:EnableMouse(false)
  item.border = item:CreateTexture(nil, "BACKGROUND", nil, -1)
  item.border:SetPoint("TOPLEFT", -1, 1)
  item.border:SetPoint("BOTTOMRIGHT", 1, -1)
  item.bg = item:CreateTexture(nil, "BACKGROUND")
  item.bg:SetAllPoints()
  item.bg:SetColorTexture(0.06, 0.06, 0.08, 0.9)
  -- The element's own icon, faint, while the slot is empty.
  item.placeholder = item:CreateTexture(nil, "ARTWORK")
  item.placeholder:SetAllPoints()
  item.placeholder:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  item.placeholder:SetDesaturated(true)
  item.placeholder:SetAlpha(0.25)

  -- Everything about a dropped totem; faded out by the game when it ends.
  item.live = CreateFrame("Frame", nil, item)
  item.live:SetAllPoints()
  item.icon = item.live:CreateTexture(nil, "ARTWORK")
  item.icon:SetAllPoints()
  item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  item.timer = CreateFrame("Cooldown", nil, item.live, "CooldownFrameTemplate")
  item.timer:SetAllPoints()
  item.timer:SetDrawEdge(false)
  item.timer:SetDrawBling(false)
  item.timer:SetReverse(true)
  item.timer:SetSwipeColor(0, 0, 0, 0.55)
  item.timer:SetScript("OnCooldownDone", function()
    if item.active then Totem.Refresh(item) end
  end)
  item.pulse = CreateFrame("StatusBar", nil, item.live)
  item.pulse:SetStatusBarTexture(WHITE)
  item.pulse:SetMinMaxValues(0, 1)
  item.pulse:SetPoint("BOTTOMLEFT", 1, 1)
  item.pulse:SetPoint("BOTTOMRIGHT", -1, 1)
  item.pulse:SetHeight(3)
  item.pulse:Hide()
  item.pulse.item = item
  -- Yards of reach left (or, in red, how far out you are).
  item.distance = item.live:CreateFontString(nil, "OVERLAY")
  item.distance:SetPoint("TOP", 0, -5)
  item.distance:SetShadowColor(0, 0, 0, 1)
  item.distance:SetShadowOffset(1, -1)
  item.outside = CreateFrame("Frame", nil, item.live) -- out of reach, for totems without a buff
  item.outside:SetAllPoints()
  local tint = item.outside:CreateTexture(nil, "OVERLAY")
  tint:SetAllPoints()
  tint:SetColorTexture(1, 0.1, 0.1, 0.3)
  item.outside.glow = ns.Glow.Create(item.outside, 2, 1, 0.15, 0.15)
  item.outside:Hide()

  -- The totem spell's cooldown: a thin bar along the top, also after the totem is gone.
  item.cooldown = CreateFrame("StatusBar", nil, item)
  item.cooldown:SetStatusBarTexture(WHITE)
  item.cooldown:SetStatusBarColor(1, 1, 1, 0.85)
  item.cooldown:SetPoint("TOPLEFT", 1, -1)
  item.cooldown:SetPoint("TOPRIGHT", -1, -1)
  item.cooldown:SetHeight(3)
  item.cooldown:Hide()

  item.overlay = CreateFrame("Frame", nil, item) -- edit-mode label
  item.overlay:SetAllPoints()
  item.label = item.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  item.label:SetPoint("BOTTOM", 0, 2)
  return item
end

-- Range: like a missing-buff alert, but only shown while the slot's totem is down.
local Margin, PresenceLayout = ns.Aura.PresenceMargin, ns.Aura.PresenceLayout

local function EnsureRange(item)
  local range = item.range
  local filter, candidates = "HELPFUL", { includeSpellIDs = item.rangeIDs }
  if not range then
    range = {}
    local presence = ns.Aura.NewContainer(item)
    presence:SetPoint("TOPLEFT", item, "TOPLEFT")
    local ok, err = pcall(presence.AddAuraGroup, presence, PRESENCE, filter, {
      candidateFilters = candidates, maxFrameCount = 1, layout = PresenceLayout(item.size),
      initializeFrame = function(button)
        button:EnableMouse(false)
        local layout = PresenceLayout(item.size)
        pcall(button.SetSize, button, layout.elementWidth, layout.elementHeight)
      end,
    })
    if not ok then
      ns.Print("Couldn't create the totem range check: " .. tostring(err))
      ns.Aura.Unbind(presence)
      return
    end
    -- Anchored to a container with an aura group, so it opts out of untrusted layout scripts.
    range.clip = CreateFrame("Frame", nil, item, "DisableUntrustedLayoutScriptsTemplate")
    range.clip:SetClipsChildren(true)
    range.clip:EnableMouse(false)
    range.alert = CreateFrame("Frame", nil, range.clip)
    range.alert:SetAllPoints(item)
    range.tint = range.alert:CreateTexture(nil, "OVERLAY")
    range.tint:SetAllPoints()
    range.tint:SetColorTexture(1, 0.1, 0.1, 0.3)
    range.glow = ns.Glow.Create(range.alert, 2, 1, 0.15, 0.15)
    range.presence = presence
    item.range = range
  else
    ns.Try("totem range filter", range.presence.SetAuraGroupCandidateFilters, range.presence, PRESENCE, candidates)
    ns.Try("totem range layout", range.presence.SetAuraGroupLayout, range.presence, PRESENCE, PresenceLayout(item.size))
  end
  if range.presence.SetAuraGroupEnabled then
    ns.Try("totem range enable", range.presence.SetAuraGroupEnabled, range.presence, PRESENCE, true)
  end
  -- Buff down: the container is 1 px wide and the clip spans the slot.
  -- Buff up: the container's right edge closes the clip.
  local margin = Margin(item.size)
  range.clip:ClearAllPoints()
  range.clip:SetPoint("TOPLEFT", range.presence, "TOPRIGHT", -1 - margin, margin)
  range.clip:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", margin, -margin)
  range.presence:SetFrameLevel(item:GetFrameLevel() + 1)
  range.clip:SetFrameLevel(item:GetFrameLevel() + 6)
  range.clip:Show()
  ns.Glow.Show(range.glow)
  if not ns.Try("totem range unit", ns.Aura.Bind, range.presence, "player") then return end
  return range
end

local function HideRange(item)
  local range = item.range
  if not range then return end
  ns.Aura.Unbind(range.presence)
  ns.Glow.Hide(range.glow)
  range.clip:Hide()
end

-- The slot's buff IDs: the buffs of every totem of its element, so the check
-- doesn't need changing in combat when a different totem goes down.
local function RangeIDs(slot)
  local ids = {}
  for id, totem in pairs(bySpell) do
    if totem.slot == slot then
      for _, buff in ipairs(BuffsFor(id)) do ids[buff] = true end
    end
  end
  for name, learnedSlot in pairs(Learned()) do
    if learnedSlot == slot then
      for _, buff in ipairs(ns.Learn.Linked(name) or {}) do ids[buff] = true end
    end
  end
  return ids
end

local function StopPulse(bar)
  bar:Hide()
  bar:SetScript("OnUpdate", nil)
end

local function PulseTick(bar)
  local item = bar.item
  local elapsed = GetTime() - item.pulseFrom
  if elapsed > MAX_PULSE_TIME then return StopPulse(bar) end
  bar:SetValue((elapsed % item.pulseEvery) / item.pulseEvery)
end

local function UpdatePulse(item)
  local slot = item.slot
  local interval = PulseFor(slotSpell[slot])
  local start = pulseStart[slot]
  if not item.opts.totemPulse or not interval or not start or GetTime() - start > MAX_PULSE_TIME then
    return StopPulse(item.pulse)
  end
  item.pulseFrom, item.pulseEvery = start, interval
  item.pulse:Show()
  item.pulse:SetScript("OnUpdate", PulseTick)
end

-- Shows the reach left for one slot. Returns true while there's a drop point to track.
local function UpdateDistance(item, x, y, instance)
  local slot = item.slot
  local drop, spell = drops[slot], slotSpell[slot]
  local range = spell and RangeFor(spell, item.opts.totemExtraRange)
  if not (item.opts.totemDistance and drop and range and x and drop.instance == instance) then
    item.distance:SetText("")
    if item.outside:IsShown() then
      ns.Glow.Hide(item.outside.glow)
      item.outside:Hide()
    end
    return drop ~= nil
  end
  local margin = range - math.sqrt((x - drop.x) ^ 2 + (y - drop.y) ^ 2)
  if margin >= 0 then
    item.distance:SetText(("%d"):format(math.floor(margin)))
    item.distance:SetTextColor(0.5, 1, 0.5)
  else
    item.distance:SetText(("-%d"):format(math.ceil(-margin)))
    item.distance:SetTextColor(1, 0.3, 0.3)
  end
  -- Buff totems have the game's own range check; the others get this one.
  local outside = margin < 0 and #BuffsFor(spell) == 0
  if outside and not item.outside:IsShown() then
    item.outside:Show()
    ns.Glow.Show(item.outside.glow)
  elseif not outside and item.outside:IsShown() then
    ns.Glow.Hide(item.outside.glow)
    item.outside:Hide()
  end
  return true
end

local ticker = CreateFrame("Frame")
ticker:Hide()
local sinceTick = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  sinceTick = sinceTick + elapsed
  if sinceTick < 0.1 then return end
  sinceTick = 0
  local x, y, instance = PlayerPosition()
  local tracking = false
  for _, item in pairs(items) do
    if item.active and UpdateDistance(item, x, y, instance) then tracking = true end
  end
  if not tracking then self:Hide() end
end)

local function StartTicker()
  if next(drops) then ticker:Show() end
end

local function ResetPooled(item)
  item.active = false
  if items[item.slot] == item then items[item.slot] = nil end
  HideRange(item)
  item.pulse:SetScript("OnUpdate", nil)
  item:Hide()
  item:ClearAllPoints()
end

pool = ns.CreatePool(Create, ResetPooled, retired)

function Totem.Refresh(item)
  local slot = item.slot
  local readable, have, icon = false, nil, nil
  if not InCombatLockdown() then
    have, icon = ReadSlot(slot)
    readable = have ~= nil
  end
  local spell = slotSpell[slot]
  if readable and not have then pulseStart[slot], drops[slot] = nil, nil end

  -- Icon: the totem's spell if known, else whatever the client gives (it may be secret).
  if spell then
    item.icon:SetTexture(C_Spell.GetSpellTexture(spell))
  elseif GetTotemInfo then
    local ok, _, _, _, _, totemIcon = pcall(GetTotemInfo, slot)
    if ok and totemIcon ~= nil then ns.Try("totem icon", item.icon.SetTexture, item.icon, totemIcon) end
  end

  -- Time left, drawn by the game; the live layer fades out when it runs out.
  local duration = TotemDuration(slot)
  if duration then
    ns.Try("totem timer", item.timer.SetCooldownFromDurationObject, item.timer, duration, true)
  else
    item.timer:Clear()
  end
  local live = ns.Evaluate(duration, ns.curveRunning, readable and have and 1 or 0)
  ns.Try("totem fade", item.live.SetAlpha, item.live, live)

  -- Range: only for totems that buff you, and only while one is down.
  if item.range then
    if spell and #BuffsFor(spell) > 0 then
      ns.Try("totem range fade", item.range.alert.SetAlpha, item.range.alert, live)
    else
      item.range.alert:SetAlpha(0)
    end
  end

  -- The totem spell's cooldown.
  local cooldown = item.opts.totemCooldown and spell and ns.SpellCooldown(spell)
  if cooldown then
    item.cooldown:Show()
    ns.Try("totem cooldown", item.cooldown.SetTimerDuration, item.cooldown, cooldown,
      Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
  else
    item.cooldown:Hide()
  end

  UpdatePulse(item)
end

function Totem.Acquire(parent)
  return pool.Acquire(parent)
end

function Totem.Release(item)
  pool.Release(item)
end

function Totem.Name(item)
  local element = ELEMENTS[item.slot]
  return (element and element.name or "Totem") .. " totem"
end

function Totem.Setup(item, entry, opts, size)
  local slot = entry.totemSlot
  local element = ELEMENTS[slot]
  if not element then return false end
  item.entry, item.opts, item.kind, item.slot, item.size = entry, opts, "totem", slot, size
  item:SetSize(size, size)
  local r, g, b = element.color[1], element.color[2], element.color[3]
  item.border:SetColorTexture(r * 0.6, g * 0.6, b * 0.6, 1)
  item.placeholder:SetTexture(C_Spell.GetSpellTexture(element.icon))
  item.pulse:SetStatusBarColor(r, g, b, 0.9)
  item.live:SetFrameLevel(item:GetFrameLevel() + 2)
  item.cooldown:SetFrameLevel(item:GetFrameLevel() + 4)
  item.overlay:SetFrameLevel(item:GetFrameLevel() + 10)
  item.timer:SetHideCountdownNumbers(not opts.numbers)
  local countdown = item.timer.GetCountdownFontString and item.timer:GetCountdownFontString()
  if countdown then countdown:SetFont(ns.Font(), math.max(8, math.floor(size * 0.36)), "OUTLINE") end
  item.label:SetText(ns.editMode and element.name or "")
  item.distance:SetFont(ns.Font(), math.max(8, math.floor(size * 0.3)), "OUTLINE")
  item.distance:SetText("")
  ns.Glow.Hide(item.outside.glow)
  item.outside:Hide()
  item.outside:SetFrameLevel(item.live:GetFrameLevel() + 3)

  if opts.totemRange and ns.Aura.Ready() then
    item.rangeIDs = RangeIDs(slot)
    EnsureRange(item)
  else
    HideRange(item)
  end

  item.active = true
  items[slot] = item
  item:Show()
  Totem.Refresh(item)
  StartTicker()
  return true
end

-- The four slots in the bar's order.
function Totem.Entries(config)
  local entries = {}
  for _, slot in ipairs(config.totemOrder or DEFAULT_ORDER) do
    entries[#entries + 1] = { totemSlot = slot }
  end
  return entries
end

-- Events ------------------------------------------------------------------------------------

local function RefreshAll()
  for _, item in pairs(items) do
    if item.active then Totem.Refresh(item) end
  end
end

-- A slot changing well after its totem was cast means that totem is gone
-- (killed, recalled, or run out): its pulse and drop point end now. (In
-- combat the slot itself can't be read; a fresh cast sets them again.)
local GONE_AFTER = 0.5

ns.On("PLAYER_TOTEM_UPDATE", function(_, slot)
  if not issecret(slot) and type(slot) == "number" and pulseStart[slot]
      and GetTime() - pulseStart[slot] > GONE_AFTER then
    pulseStart[slot], drops[slot] = nil, nil
  end
  ns.Schedule(RefreshAll)
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.Schedule(RefreshAll) end)
ns.On("SPELL_UPDATE_COOLDOWN", function() if next(items) then ns.Schedule(RefreshAll) end end)

-- Your own cast says which totem went down, even when the slot is secret.
local PROJECTION = "Totemic Projection"

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID then return end
  if SpellName(spellID) == PROJECTION then
    wipe(drops) -- the totems moved to a spot we can't know
    return
  end
  local slot = SlotForSpell(spellID)
  if not slot then return end
  slotSpell[slot] = spellID
  pulseStart[slot] = PulseFor(spellID) and GetTime() or nil
  local x, y, instance = TotemSpot(slot)
  drops[slot] = x and { x = x, y = y, instance = instance } or nil
  StartTicker()
  ns.Schedule(RefreshAll)
end)

-- /chud debug totems
function Totem.PrintDiag()
  ns.Print("GetTotemInfo: " .. (GetTotemInfo and "yes" or "no") .. ", GetTotemDuration: " .. (GetTotemDuration and "yes" or "no"))
  for slot = 1, 4 do
    local text = "?"
    if GetTotemInfo then
      local ok, have, name, start, length, _, _, spellID = pcall(GetTotemInfo, slot)
      if not ok then
        text = "error"
      elseif issecret(have) or issecret(name) then
        text = "hidden right now"
      elseif have and start and start ~= 0 then
        text = ("%s (%s), %ss"):format(tostring(name), tostring(spellID), tostring(length))
      else
        text = "empty"
      end
    end
    local known = slotSpell[slot] and (SpellName(slotSpell[slot]) or tostring(slotSpell[slot])) or "none"
    local reach = slotSpell[slot] and RangeFor(slotSpell[slot])
    ns.Print(("%s: %s; last cast here: %s; pulse: %s; reach: %s; drop point: %s"):format(ELEMENTS[slot].name, text, known,
      tostring(PulseFor(slotSpell[slot])), reach and ("%.1f yd"):format(reach) or "?", drops[slot] and "known" or "unknown"))
  end
end

-- Reaches learned by earlier versions were wrong; they're forgotten.
ns.On("PLAYER_LOGIN", function()
  if CombatHUDDB then CombatHUDDB.totemRanges, CombatHUDDB.totemRangesFrom = nil, nil end
end)
