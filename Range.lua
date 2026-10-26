-- Out-of-range tint. The client reports range changes for action bar slots
-- (ACTION_RANGE_CHECK_UPDATE), and on this client that report isn't secret in
-- combat. So each spell is matched to the action slots holding it (any rank),
-- and each item to the slots holding that item (a trinket button: whatever is
-- equipped in its slot); hidden bars count. One that isn't on any action bar
-- never shows as out of range.
local _, ns = ...
local issecret = ns.issecret

local Range = {}
ns.Range = Range

local NUM_SLOTS = 180
local owners = {}     -- action slot -> list of buttons showing what's in it
local lastChecks = {} -- action slot -> whether its last range report checked range at all

local function Apply(slot, outOfRange)
  local list = owners[slot]
  if not list then return end
  for _, btn in ipairs(list) do
    if btn.active and btn.outOfRange ~= outOfRange then
      btn.outOfRange = outOfRange
      ns.Button.RefreshTint(btn)
    end
  end
end

-- Reads a slot's current range: out of range only when the client says so.
local function Seed(slot)
  local inRange = C_ActionBar.IsActionInRange(slot)
  if issecret(inRange) then return end
  Apply(slot, inRange == false)
end

-- The item a button shows: its item, or what's equipped in its slot.
local function ItemOf(btn)
  if btn.kind == "item" then return btn.itemID end
  if btn.kind == "slot" then
    local id = GetInventoryItemID("player", btn.slot)
    if not issecret(id) then return id end
  end
end

-- What an action slot holds, as a key buttons are filed under: "spell:Name" or "item:ID".
local function SlotKey(slot)
  local actionType, id = GetActionInfo(slot)
  if issecret(actionType) or issecret(id) or not id then return end
  if actionType == "spell" then
    local name = C_Spell.GetSpellName(id)
    if name and not issecret(name) then return "spell:" .. name end
  elseif actionType == "item" then
    return "item:" .. id
  end
end

local function ButtonKey(btn)
  if btn.kind == "spell" and btn.spellName then return "spell:" .. btn.spellName end
  local item = ItemOf(btn)
  if item then return "item:" .. item end
end

function Range.Scan()
  wipe(owners)
  local byKey = {}
  for _, btn in ipairs(ns.activeButtons) do
    btn.rangeSlot = nil
    local key = btn.opts.rangeTint and ButtonKey(btn)
    if key then
      btn.outOfRange = false
      byKey[key] = byKey[key] or {}
      table.insert(byKey[key], btn)
    end
  end
  if not next(byKey) then return end

  for slot = 1, NUM_SLOTS do
    local key = SlotKey(slot)
    local list = key and byKey[key]
    if list then
      owners[slot] = list
      for _, btn in ipairs(list) do btn.rangeSlot = btn.rangeSlot or slot end
      if C_ActionBar.EnableActionRangeCheck then C_ActionBar.EnableActionRangeCheck(slot, true) end
      Seed(slot)
    end
  end
end

-- Whether the game says an action slot's spell or item has a range at all:
-- true, false, or nil when it can't tell.
local function HasRange(slot)
  local check = (C_ActionBar and C_ActionBar.HasRangeRequirements) or ActionHasRange
  if not check then return lastChecks[slot] end
  local ok, has = pcall(check, slot)
  if not ok or issecret(has) then return lastChecks[slot] end
  return has == true or has == 1
end

-- For the settings window: the action slot a button with range tint was
-- found on, and whether the game says it has a range.
function Range.SlotFor(entry)
  for _, btn in ipairs(ns.activeButtons) do
    if btn.entry == entry and btn.rangeSlot then return btn.rangeSlot, HasRange(btn.rangeSlot) end
  end
end

-- /chud debug range: for each item and trinket button, where it is on the
-- action bars and what the game reports about its range right now.
function Range.Probe()
  local function Show(value)
    if issecret(value) then return "secret" end
    return tostring(value)
  end
  local any
  for _, btn in ipairs(ns.activeButtons) do
    local item = ItemOf(btn)
    if item then
      any = true
      local name = ns.Button.Name(btn)
      local found
      for slot = 1, NUM_SLOTS do
        if SlotKey(slot) == "item:" .. item then
          found = slot
          break
        end
      end
      if not found then
        ns.Print(name .. ": not on any action bar (put it on one; a hidden bar is fine).")
      else
        ns.Print(("%s: action slot %d. In range: %s. Has a range: %s. Last report checked range: %s. In combat: %s."):format(
          name, found, Show(C_ActionBar.IsActionInRange(found)), Show(HasRange(found)), Show(lastChecks[found]),
          tostring(InCombatLockdown())))
      end
    end
  end
  if not any then ns.Print("No item or trinket buttons on the HUD.") end
end

ns.On("ACTION_RANGE_CHECK_UPDATE", function(_, slot, inRange, checksRange)
  if issecret(slot) or issecret(inRange) or issecret(checksRange) then return end
  lastChecks[slot] = checksRange == true
  if not owners[slot] then return end
  Apply(slot, checksRange == true and inRange == false)
end)

ns.On("PLAYER_TARGET_CHANGED", function()
  for slot in pairs(owners) do Seed(slot) end
end)

ns.On("ACTIONBAR_SLOT_CHANGED", function()
  ns.Schedule(Range.Scan)
end)
