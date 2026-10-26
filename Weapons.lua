-- Weapon enchants: a slot for each hand holding a weapon, with its temporary
-- enchant (Windfury Weapon, a poison, an oil or a sharpening stone): its
-- icon, time left and charges, and a pulsing alert when it's missing (red) or
-- about to run out (orange). By default a slot only shows while it needs you.
--
-- The enchants may be secret in combat. Then the last reading is counted
-- down here, and casting an imbue or applying a poison counts as renewing the
-- hand that needed it most (for as long as it lasted last time), until combat
-- ends and the real state can be read again.
local _, ns = ...
local issecret = ns.issecret

local Weapons = {}
ns.Weapons = Weapons

local HANDS = {
  main = { slot = 16, label = "Main hand", weaponSlot = "MainHand" },
  off = { slot = 17, label = "Off hand", weaponSlot = "OffHand" },
}
local ORDER = { "main", "off" }
local RED, ORANGE = { 1, 0.2, 0.15 }, { 1, 0.6, 0.1 }
local TICK = 0.25

local known = {} -- hand -> { has, expires, charges, icon, full, readable }
local items = {} -- hand -> its slot, while shown
local retired = CreateFrame("Frame")
retired:Hide()
local pool

-- Reading --------------------------------------------------------------------------------------

local Readable = ns.AllReadable

-- A hand's temporary enchant: { has, remaining (seconds), charges, icon },
-- or nil when it can't be read. Permanent enchants don't count; an imbue wins
-- over an oil or stone.
local function ReadModern(hand)
  local types = Enum.ItemEnchantType
  local ok, list = pcall(C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot[HANDS[hand].weaponSlot])
  if not ok or issecret(list) then return end
  local chosen
  for _, entry in ipairs(list or {}) do
    if issecret(entry) or not Readable(entry.hasEnchant, entry.enchantType, entry.timeLeft, entry.charges, entry.enchantIconID) then
      return
    end
    if entry.hasEnchant and (entry.enchantType == types.Temporary or entry.enchantType == types.Imbue) then
      if not chosen or entry.enchantType == types.Imbue then chosen = entry end
    end
  end
  if not chosen then return { has = false } end
  return { has = true, remaining = (chosen.timeLeft or 0) / 1000, charges = chosen.charges, icon = chosen.enchantIconID }
end

local function ReadLegacy(hand)
  local values = { pcall(GetWeaponEnchantInfo) }
  if not values[1] then return end
  local first = hand == "main" and 2 or 6
  local has, ms, charges = values[first], values[first + 1], values[first + 2]
  if not Readable(has, ms, charges) then return end
  if not has then return { has = false } end
  return { has = true, remaining = (ms or 0) / 1000, charges = charges }
end

local function ReadHand(hand)
  if C_Item and C_Item.GetWeaponEnchantInfo and Enum and Enum.WeaponSlot and Enum.ItemEnchantType then
    return ReadModern(hand)
  end
  if GetWeaponEnchantInfo then return ReadLegacy(hand) end
end

-- Reads both hands; a hand that can't be read keeps its last reading.
local function ReadAll()
  local now = GetTime()
  for hand in pairs(HANDS) do
    local reading = ReadHand(hand)
    local state = known[hand]
    if reading then
      state = state or {}
      state.has, state.charges, state.readable = reading.has, reading.charges, true
      state.expires = reading.has and now + reading.remaining or nil
      if reading.icon then state.icon = reading.icon end
      if reading.has then state.full = math.max(state.full or 0, reading.remaining) end
      known[hand] = state
    elseif state then
      state.readable = false
    end
  end
end

-- The weapon's icon, or nil when the hand holds no weapon (empty, a shield, an off-hand item).
local function WeaponIcon(hand)
  local slot = HANDS[hand].slot
  local itemID = GetInventoryItemID("player", slot)
  if issecret(itemID) or not itemID then return end
  local Instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  local _, _, _, _, icon, classID = Instant(itemID)
  local weapon = Enum.ItemClass and Enum.ItemClass.Weapon or 2
  if classID ~= weapon then return end
  return GetInventoryItemTexture("player", slot) or icon
end

-- Slots ------------------------------------------------------------------------------------------

local function Create()
  local item = CreateFrame("Frame", nil, UIParent)
  item:EnableMouse(false)
  item.border = item:CreateTexture(nil, "BACKGROUND", nil, -1)
  item.border:SetPoint("TOPLEFT", -1, 1)
  item.border:SetPoint("BOTTOMRIGHT", 1, -1)
  item.border:SetColorTexture(0, 0, 0, 1)
  item.icon = item:CreateTexture(nil, "ARTWORK")
  item.icon:SetAllPoints()
  item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  item.overlay = CreateFrame("Frame", nil, item)
  item.overlay:SetAllPoints()
  item.time = item.overlay:CreateFontString(nil, "OVERLAY")
  item.time:SetPoint("BOTTOM", 0, 2)
  item.time:SetShadowColor(0, 0, 0, 1)
  item.time:SetShadowOffset(1, -1)
  item.charges = item.overlay:CreateFontString(nil, "OVERLAY")
  item.charges:SetPoint("TOPRIGHT", -2, -2)
  item.charges:SetShadowColor(0, 0, 0, 1)
  item.charges:SetShadowOffset(1, -1)
  item.label = item.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  item.label:SetPoint("BOTTOM", item, "TOP", 0, 3)
  item.glow = ns.Glow.Create(item.overlay, 2, RED[1], RED[2], RED[3])
  return item
end

local function TimeText(seconds)
  if seconds >= 60 then return ("%dm"):format(math.ceil(seconds / 60)) end
  return ("%d"):format(math.ceil(seconds))
end

function Weapons.Refresh(item)
  local opts, state = item.opts, known[item.hand]
  local has = state and state.has
  local remaining
  if has and state.expires then remaining = state.expires - GetTime() end
  if remaining and remaining <= 0 then has, remaining = false, nil end -- ran out while counting here
  local missing = state ~= nil and not has -- never read at all: no alert
  local low = remaining ~= nil and remaining < (opts.weaponWarn or 60)

  item.icon:SetTexture((has and state.icon) or item.weaponIcon)
  item.icon:SetDesaturated(missing)
  item.icon:SetAlpha(missing and 0.6 or 1)
  if remaining and opts.numbers then
    item.time:SetText(TimeText(remaining))
    if low then item.time:SetTextColor(ORANGE[1], ORANGE[2], ORANGE[3]) else item.time:SetTextColor(1, 1, 1) end
  else
    item.time:SetText("")
  end
  local charges = has and state.charges
  item.charges:SetText((charges and charges > 0) and charges or "")

  local alert = (missing and "missing") or (low and "low") or nil
  if alert ~= item.alert then
    item.alert = alert
    if alert then
      local color = alert == "missing" and RED or ORANGE
      ns.Glow.SetColor(item.glow, color[1], color[2], color[3])
      ns.Glow.Show(item.glow)
    else
      ns.Glow.Hide(item.glow)
    end
  end
  item:SetAlpha((ns.editMode or opts.weaponShow == "always" or alert) and 1 or 0)
end

local function RefreshAll()
  for _, item in pairs(items) do
    if item.active then Weapons.Refresh(item) end
  end
end

local ticker = CreateFrame("Frame")
ticker:Hide()
ticker.elapsed = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
  self.elapsed = self.elapsed + elapsed
  if self.elapsed < TICK then return end
  self.elapsed = 0
  if not next(items) then
    self:Hide()
    return
  end
  RefreshAll()
end)

local function ResetPooled(item)
  item.active = false
  if items[item.hand] == item then items[item.hand] = nil end
  ns.Glow.Hide(item.glow)
  item.alert = nil
  item:Hide()
  item:ClearAllPoints()
end

pool = ns.CreatePool(Create, ResetPooled, retired)

function Weapons.Acquire(parent)
  return pool.Acquire(parent)
end

function Weapons.Release(item)
  pool.Release(item)
end

function Weapons.Name(item)
  return HANDS[item.hand].label .. " enchant"
end

function Weapons.Setup(item, entry, opts, size)
  local hand = entry.weaponHand
  if not HANDS[hand] then return false end
  local icon = WeaponIcon(hand)
  if not icon then return false end
  item.entry, item.opts, item.kind, item.hand, item.weaponIcon = entry, opts, "weapon", hand, icon
  item:SetSize(size, size)
  item.time:SetFont(ns.Font(), math.max(8, math.floor(size * 0.32)), "OUTLINE")
  item.charges:SetFont(ns.Font(), math.max(7, math.floor(size * 0.26)), "OUTLINE")
  item.label:SetText(ns.editMode and HANDS[hand].label or "")
  item.overlay:SetFrameLevel(item:GetFrameLevel() + 4)
  ns.Glow.Hide(item.glow)
  item.alert = nil
  item.active = true
  items[hand] = item
  item:Show()
  ReadAll()
  Weapons.Refresh(item)
  ticker:Show()
  return true
end

-- The two hands, in order (a hand without a weapon is left out when built).
function Weapons.Entries()
  return { { weaponHand = "main" }, { weaponHand = "off" } }
end

-- What's equipped, for the rebuild check: a new weapon may add or drop a slot.
function Weapons.Signature()
  return tostring(GetInventoryItemID("player", 16)) .. "/" .. tostring(GetInventoryItemID("player", 17))
end

-- Events ---------------------------------------------------------------------------------------

local function ReadAndRefresh()
  if not next(items) then return end
  ReadAll()
  RefreshAll()
end

ns.OnUnit("UNIT_INVENTORY_CHANGED", "player", function() ns.Schedule(ReadAndRefresh) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.Schedule(ReadAndRefresh) end)
ns.On("PLAYER_REGEN_ENABLED", function() ns.Schedule(ReadAndRefresh) end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.Schedule(ReadAndRefresh) end)

-- Imbues end in "Weapon"; poisons, oils and stones say what they are.
local function AppliesEnchant(name)
  return name:find("Weapon$") or name:find("Poison") or name:find(" Oil") or name:find("Sharpen")
    or name:find("Weightstone")
end

-- Applying an enchant while the enchants are secret: the hand that needed it
-- most (missing, else running out soonest) is taken as renewed.
ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID or not next(items) then return end
  local name = C_Spell.GetSpellName(spellID)
  if not name or issecret(name) or not AppliesEnchant(name) then return end
  ReadAll()
  local pick, soonest
  for _, hand in ipairs(ORDER) do
    local state = known[hand]
    if items[hand] and state and not state.readable then
      local left = (state.has and state.expires) and state.expires - GetTime() or 0
      if not soonest or left < soonest then pick, soonest = hand, left end
    end
  end
  if pick then
    known[pick].has, known[pick].expires = true, GetTime() + (known[pick].full or 300)
  end
  RefreshAll()
end)

-- What the game reports, for /chud debug weapons.
function Weapons.PrintDiag()
  for _, hand in ipairs(ORDER) do
    local reading = ReadHand(hand)
    local state = known[hand]
    local now
    if not WeaponIcon(hand) then
      now = "no weapon"
    elseif not reading then
      now = "can't be read (secret, or no enchant API)"
    elseif reading.has then
      now = ("enchanted, %d s left, charges %s"):format(reading.remaining, tostring(reading.charges))
    else
      now = "no temporary enchant"
    end
    ns.Print(("%s: %s. Longest seen: %s s."):format(HANDS[hand].label, now, tostring(state and state.full and math.floor(state.full))))
  end
end
