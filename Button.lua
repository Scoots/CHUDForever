-- One HUD button: icon, cooldown swipe or wipe, GCD swipe, countdown number,
-- range/mana tint and mana cost. Display only: buttons never take the mouse.
local _, ns = ...
local issecret = ns.issecret

local Button = {}
ns.Button = Button

local SWIPE_ALPHA = 0.7
local GCD_ALPHA = 0.45
local WHITE = ns.WHITE

local TINT_RANGE = { 0.95, 0.3, 0.3 }
local TINT_MANA = { 0.4, 0.5, 1 }
local TINT_UNUSABLE = { 0.45, 0.45, 0.45 }

local retired = CreateFrame("Frame")
retired:Hide()

local function ResetPooled(btn)
  btn.active = false
  btn.duration = nil
  btn:Hide()
  btn:ClearAllPoints()
  btn.cd:Clear()
  btn.gcd:Clear()
  btn.wipe:Hide()
  ns.Glow.Hide(btn.glow)
  ns.Glow.Hide(btn.procAnts)
  ns.Glow.Hide(btn.reactiveGlow)
  ns.Debuff.Detach(btn)
  ns.Glow.Hide(btn.earlyGlow)
  btn.earlyHolder:SetAlpha(1)
  btn.earlyGlowUntil, btn.cooldownSnapshot, btn.cooldownEnd, btn.cooldownStartedAt = nil, nil, nil, nil
end

local pool

-- Layers, bottom to top: icon, wipe, the target-debuff part (Debuff.lua, at
-- +2), GCD swipe, cooldown swipe and number, then texts and glows.
local function ApplyLevels(btn)
  local base = btn:GetFrameLevel()
  btn.wipe:SetFrameLevel(base + 1)
  btn.gcd:SetFrameLevel(base + 5)
  btn.cd:SetFrameLevel(base + 6)
  btn.overlay:SetFrameLevel(base + 8)
end

-- The icon pops bigger once, for an early reset.
local function NewPop(texture)
  local group = texture:CreateAnimationGroup()
  group:SetLooping("NONE")
  for order, step in ipairs({ { 1, 1.35, 0.12 }, { 1.35, 1, 0.2 } }) do
    local anim = group:CreateAnimation("Scale")
    anim:SetOrder(order)
    anim:SetDuration(step[3])
    anim:SetOrigin("CENTER", 0, 0)
    if anim.SetScaleFrom then
      anim:SetScaleFrom(step[1], step[1])
      anim:SetScaleTo(step[2], step[2])
    else
      anim:SetScale(step[2] / step[1], step[2] / step[1])
    end
  end
  return group
end

local function NewCooldown(parent)
  local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
  cd:SetAllPoints()
  cd:SetDrawEdge(false)
  cd:SetDrawBling(false)
  return cd
end

local function Create()
  local btn = CreateFrame("Frame", nil, UIParent)
  btn:EnableMouse(false)

  btn.border = btn:CreateTexture(nil, "BACKGROUND")
  btn.border:SetColorTexture(0, 0, 0, 1)
  btn.border:SetPoint("TOPLEFT", -1, 1)
  btn.border:SetPoint("BOTTOMRIGHT", 1, -1)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetAllPoints()
  btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  -- Left-to-right wipe: a dark bar over the part of the cooldown still to go.
  btn.wipe = CreateFrame("StatusBar", nil, btn)
  btn.wipe:SetAllPoints()
  btn.wipe:SetStatusBarTexture(WHITE)
  btn.wipe:SetStatusBarColor(0, 0, 0, SWIPE_ALPHA)
  btn.wipe:SetReverseFill(true)
  btn.wipe:SetMinMaxValues(0, 1)
  btn.wipe:Hide()

  btn.gcd = NewCooldown(btn)
  btn.gcd:SetSwipeColor(0, 0, 0, GCD_ALPHA)
  btn.gcd:SetHideCountdownNumbers(true)

  btn.cd = NewCooldown(btn)
  btn.cd:SetSwipeColor(0, 0, 0, SWIPE_ALPHA)
  btn.cd:SetScript("OnCooldownDone", function()
    if not btn.active then return end
    Button.RefreshCooldown(btn)
    -- The client can still report a few milliseconds left right at the end.
    C_Timer.After(0.1, function()
      if btn.active then Button.RefreshCooldown(btn) end
    end)
  end)

  btn.overlay = CreateFrame("Frame", nil, btn)
  btn.overlay:SetAllPoints()
  btn.cost = btn.overlay:CreateFontString(nil, "OVERLAY")
  btn.cost:SetPoint("BOTTOMRIGHT", -1, 2)
  btn.tag = btn.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") -- "not learned", in edit mode
  btn.tag:SetPoint("BOTTOM", 0, 2)
  btn.glow = ns.Glow.Create(btn.overlay, 2)
  btn.procAnts = ns.Glow.CreateAlert(btn.overlay, 1, 0.82, 0.2) -- the proc glow's "ants" look
  -- Reactive abilities: a glow while usable, in a holder whose alpha can
  -- follow a secret "usable".
  btn.reactiveHolder = CreateFrame("Frame", nil, btn.overlay)
  btn.reactiveHolder:SetAllPoints()
  btn.reactiveGlow = ns.Glow.Create(btn.reactiveHolder, 2)
  -- Ready sooner than its cooldown: a Blizzard-style alert in whitish blue, and a pop.
  -- Its holder's opacity can be the game's (secret) answer to "was it early?";
  -- the glow's own pulse animates the glow, so it can't override that.
  btn.earlyHolder = CreateFrame("Frame", nil, btn.overlay)
  btn.earlyHolder:SetAllPoints()
  btn.earlyGlow = ns.Glow.CreateAlert(btn.earlyHolder, 0.75, 0.9, 1)
  btn.alertFx = ns.Glow.BuildAlertFx(btn, false) -- alerts' visuals (Alerts.lua)
  btn.pop = NewPop(btn.icon)

  ApplyLevels(btn)
  return btn
end

pool = ns.CreatePool(Create, ResetPooled, retired)

function Button.Acquire(parent)
  local btn = pool.Acquire(parent)
  ApplyLevels(btn)
  return btn
end

function Button.Release(btn)
  pool.Release(btn)
end

local GetItemCooldown = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown

local function ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(itemID) end
  if GetItemIcon then return GetItemIcon(itemID) end
end

local function ItemName(itemID)
  local name = itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  return name or "item " .. tostring(itemID)
end

-- The spell an item casts when used, by name (nil if it has none).
local GetItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
function Button.UseName(itemID)
  if issecret(itemID) or not itemID or not GetItemSpell then return end
  local ok, name = pcall(GetItemSpell, itemID)
  if ok and not issecret(name) then return name end
end
Button.ItemIcon, Button.ItemName = ItemIcon, ItemName

-- A readable name for chat messages.
function Button.Name(btn)
  if btn.kind == "spell" then return btn.spellName or ("spell " .. tostring(btn.spellID)) end
  if btn.kind == "slot" then return ItemName(GetInventoryItemID("player", btn.slot)) end
  return ItemName(btn.itemID)
end

-- Fills the button from its saved entry. Returns false when there is nothing
-- to show (a spell you don't know, an empty trinket slot).
function Button.Setup(btn, entry, opts, size)
  btn.entry, btn.opts = entry, opts
  btn.kind, btn.spellID, btn.spellName, btn.slot, btn.itemID = nil, nil, nil, nil, nil
  btn.outOfRange, btn.cachedCost, btn.itemOnCooldown, btn.onCooldown = false, nil, nil, nil
  btn.visible, btn.reactive = true, false
  btn.texture, btn.swapName, btn.swapTexture = nil, nil, nil
  btn.groupNames, btn.groupTexture, btn.useName = nil, nil, nil
  btn.queueMembers, btn.queueTexture, btn.queued = nil, nil, nil
  btn.lockout, btn.lockedOut = nil, nil
  btn.tag:SetText("")
  ns.Glow.Hide(btn.earlyGlow)

  if entry.slot then
    local texture = GetInventoryItemTexture("player", entry.slot)
    if not texture then return false end
    btn.kind, btn.slot = "slot", entry.slot
    btn.useName = Button.UseName(GetInventoryItemID("player", entry.slot))
    btn.icon:SetTexture(texture)
  elseif entry.item then
    -- A shared cooldown of items (potions, say) tracks one you carry.
    local itemID = ns.Groups.ResolveItem(entry)
    local texture = ItemIcon(itemID)
    if not texture then return false end
    btn.kind, btn.itemID, btn.texture = "item", itemID, texture
    btn.useName = Button.UseName(itemID) -- its use, for "When I use it"
    btn.icon:SetTexture(texture)
  elseif entry.spell then
    local spellID, name = ns.Groups.ResolveSpell(entry)
    if not spellID then
      -- Not learned: left out of the HUD (it appears by itself once learned,
      -- since learning a spell rebuilds the HUD). Edit mode shows a faded stand-in.
      if not ns.editMode then return false end
      return Button.SetupUnlearned(btn, entry, size)
    end
    btn.kind, btn.spellID, btn.spellName = "spell", spellID, name
    btn.texture = C_Spell.GetSpellTexture(spellID)
    btn.icon:SetTexture(btn.texture)
    -- Swap: show another spell's icon while the game highlights that spell
    -- (Frostbolt turning into Ice Lance on a proc, say).
    if entry.swap then
      local swapID, swapName = ns.ResolveSpell(entry.swap)
      swapID = swapID or (type(entry.swap) == "number" and entry.swap)
      if swapID then
        btn.swapName = swapName or C_Spell.GetSpellName(swapID)
        btn.swapTexture = C_Spell.GetSpellTexture(swapID)
      end
    end
  else
    return false
  end

  -- Target debuff on "auto": settled now the spell is known (Debuff.lua).
  if btn.kind == "spell" then ns.Debuff.ApplyAuto(opts, entry, btn.spellID) end

  btn:SetSize(size, size)

  -- Item cooldowns only come as start/duration, which the wipe can't draw.
  local mode = opts.cooldown
  if btn.kind ~= "spell" and mode == "wipe" then mode = "swipe" end
  btn.mode = mode
  btn.cd:SetDrawSwipe(mode == "swipe")
  btn.cd:SetHideCountdownNumbers(not opts.numbers)
  btn.gcd:SetShown(opts.gcd and btn.kind == "spell")

  local countdown = btn.cd.GetCountdownFontString and btn.cd:GetCountdownFontString()
  if countdown then
    countdown:ClearAllPoints()
    if opts.targetDebuff and btn.kind == "spell" then
      countdown:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1, -2)
      countdown:SetFont(ns.Font(), math.max(8, math.floor(size * 0.26)), "OUTLINE")
    else
      countdown:SetPoint("CENTER", btn, "CENTER", 0, 0)
      countdown:SetFont(ns.Font(), math.max(8, math.floor(size * 0.36)), "OUTLINE")
    end
  end
  btn.cost:SetFont(ns.Font(), math.max(7, math.floor(size * 0.24)), "OUTLINE")
  btn.cost:SetShown(opts.manaCost and btn.kind == "spell")

  btn.active = true
  btn:Show()
  Button.RefreshCost(btn)
  Button.RefreshCooldown(btn)
  Button.RefreshTint(btn)
  Button.ApplyGroup(btn, entry)
  if entry.queue and btn.kind == "spell" then Button.SetupQueue(btn, entry) end
  if entry.lockout and btn.kind == "spell" then Button.SetupLockout(btn, entry) end
  Button.RefreshProc(btn)
  btn.reactive = Button.IsReactive(btn)
  Button.RefreshReactive(btn)
  if btn.kind == "spell" and opts.targetDebuff then ns.Debuff.Attach(btn) end
  return true
end

-- Reactive abilities -------------------------------------------------------------------
-- Abilities that only become usable when something happens (Overpower after
-- a dodge, Execute under 20% health...) glow while usable and off cooldown.
-- "auto" turns this on for the ones listed here; any spell can be switched on.

local REACTIVE = {
  ["Overpower"] = true, ["Revenge"] = true, ["Execute"] = true, ["Victory Rush"] = true,
  ["Riposte"] = true, ["Counterattack"] = true, ["Mongoose Bite"] = true, ["Hammer of Wrath"] = true,
}
Button.REACTIVE = REACTIVE

function Button.IsReactive(btn)
  if btn.kind ~= "spell" then return false end
  local setting = btn.opts.reactive
  if setting == "auto" then return REACTIVE[btn.spellName or ""] == true end
  return setting == true
end

function Button.RefreshReactive(btn)
  if not btn.reactive or btn.onCooldown then
    ns.Glow.Hide(btn.reactiveGlow)
    return
  end
  local ok, usable = pcall(C_Spell.IsSpellUsable, btn.spellID)
  if not ok then
    ns.Glow.Hide(btn.reactiveGlow)
  elseif issecret(usable) then
    -- Can't be read in combat: the glow's holder is shown or hidden by the game.
    ns.Glow.Show(btn.reactiveGlow)
    ns.Try("reactive glow", function()
      btn.reactiveHolder:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(usable, 1, 0))
    end)
  else
    btn.reactiveHolder:SetAlpha(1)
    if usable then ns.Glow.Show(btn.reactiveGlow) else ns.Glow.Hide(btn.reactiveGlow) end
  end
end

-- Procs -----------------------------------------------------------------------------
-- The game highlights a spell (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW) when a proc
-- makes it worth casting. Matched by name, so any rank counts.

local highlighted = {} -- spell name -> true while the game highlights it

local ReadableName = ns.SpellName

local IsOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed) or IsSpellOverlayed

-- Picks up highlights that started before the button existed.
local function CheckHighlight(spellID, name)
  if not IsOverlayed or not spellID or not name then return end
  local ok, on = pcall(IsOverlayed, spellID)
  if ok and not issecret(on) and on then highlighted[name] = true end
end

function Button.RefreshProc(btn)
  if btn.kind ~= "spell" then
    ns.Glow.Hide(btn.glow)
    ns.Glow.Hide(btn.procAnts)
    return
  end
  local swapped = btn.swapName and highlighted[btn.swapName]
  btn.icon:SetTexture(swapped and btn.swapTexture or btn.queueTexture or btn.groupTexture or btn.texture)
  local on = btn.opts.procGlow and (swapped or highlighted[btn.spellName])
  local style = btn.opts.procStyle or "border"
  local color = ns.Glow.Color(btn.opts.procColor)
  ns.Glow.SetColor(btn.glow, color[3], color[4], color[5])
  ns.Glow.SetColor(btn.procAnts, color[3], color[4], color[5])
  if on and style ~= "ants" then ns.Glow.Show(btn.glow) else ns.Glow.Hide(btn.glow) end
  if on and style ~= "border" then ns.Glow.Show(btn.procAnts) else ns.Glow.Hide(btn.procAnts) end
end

-- Ready early ---------------------------------------------------------------------
-- Some cooldowns reset early (Stormstrike after a dodge or parry, with the
-- right talent). When the cooldown starts, its end is noted: the time, if
-- it's readable, and the game's duration object either way. When the
-- on-cooldown flag (readable in combat) turns off well before that end, it
-- was a reset, and the button glows until you cast it, with an optional sound.
-- When neither is readable, the glow's opacity is the game's own answer to
-- "did the old cooldown have time left?", so it still shows only for a reset.

local EARLY_GLOW_TIME = 6
local EARLY_MARGIN = 1 -- seconds: ending this much sooner than expected is a reset
local castTimes = {} -- spell name -> GetTime() of your last cast

-- 1 while more than EARLY_MARGIN seconds remain, else 0.
local curveEarly
if C_CurveUtil and C_CurveUtil.CreateCurve then
  curveEarly = C_CurveUtil.CreateCurve()
  curveEarly:AddPoint(0, 0)
  curveEarly:AddPoint(EARLY_MARGIN, 0)
  curveEarly:AddPoint(EARLY_MARGIN + 0.001, 1)
end

local function ClearEarlyGlow(btn)
  btn.earlyGlowUntil = nil
  btn.earlyGlowCast = nil
  ns.Glow.Hide(btn.earlyGlow)
  btn.earlyHolder:SetAlpha(1)
end

-- The cooldown just started: note when it should end.
function Button.CooldownStarted(btn, duration)
  btn.cooldownSnapshot, btn.cooldownEnd = duration, nil
  btn.cooldownStartedAt = GetTime()
  local ok, info = pcall(C_Spell.GetSpellCooldown, btn.spellID)
  if ok and info and not issecret(info.startTime) and not issecret(info.duration)
      and type(info.startTime) == "number" and type(info.duration) == "number" and info.duration > 1.5 then
    btn.cooldownEnd = info.startTime + info.duration
  end
end

local function ShowEarly(btn, untilTime, alpha)
  if not btn.opts.earlyReady then return end
  btn.earlyGlowUntil = untilTime
  ns.Glow.Show(btn.earlyGlow)
  -- It ends by itself then (out of combat no cooldown event would end it).
  C_Timer.After(math.max(0.1, untilTime - GetTime()), function()
    if btn.earlyGlowUntil == untilTime then ClearEarlyGlow(btn) end
  end)
  if alpha ~= nil then
    ns.Try("early glow", btn.earlyHolder.SetAlpha, btn.earlyHolder, alpha)
  else
    btn.earlyHolder:SetAlpha(1)
    btn.pop:Play()
  end
end

function Button.CooldownEnded(btn)
  local now = GetTime()
  local started, expected, snapshot = btn.cooldownStartedAt, btn.cooldownEnd, btn.cooldownSnapshot
  btn.cooldownStartedAt, btn.cooldownEnd, btn.cooldownSnapshot = nil, nil, nil
  if started and now - started < 1.6 then return end -- only the global cooldown

  -- Was it early? true / false, or nil when only the game can tell.
  local early
  if expected then
    early = now < expected - EARLY_MARGIN
  elseif snapshot and curveEarly then
    local left = ns.Evaluate(snapshot, curveEarly, nil)
    if left ~= nil and not issecret(left) then early = left > 0.5 end
  else
    early = false -- nothing to go by: a normal ready
  end

  if early == nil then
    -- Secret: the glow shows (or not) by the game's answer; no early sound.
    ShowEarly(btn, now + EARLY_GLOW_TIME, ns.Evaluate(snapshot, curveEarly, 0))
    ns.Alerts.Fire(btn, "ready")
  elseif early then
    if btn.earlyAlerted ~= started then -- once per reset: the flag can flicker
      btn.earlyAlerted = started
      ns.Alerts.Fire(btn, "readyEarly")
    end
    ShowEarly(btn, expected or (now + EARLY_GLOW_TIME))
  else
    ClearEarlyGlow(btn)
    ns.Alerts.Fire(btn, "ready")
  end
end

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID then return end
  local name = C_Spell.GetSpellName(spellID)
  if not name or issecret(name) then return end
  castTimes[name] = GetTime()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.spellName == name then ClearEarlyGlow(btn) end
    if btn.spellName == name or btn.useName == name or (btn.groupNames and btn.groupNames[name]) then
      ns.Alerts.Fire(btn, "cast")
    end
    -- A shared cooldown's button takes the icon of the member just used.
    local texture = btn.groupNames and btn.groupNames[name]
    if texture and btn.groupIcon ~= "first" then
      btn.groupTexture = texture
      if btn.kind == "spell" then Button.RefreshProc(btn) else btn.icon:SetTexture(texture) end
    end
  end
end)

-- A shared cooldown's button starts with the icon of the member used last, if any.
-- Lockouts --------------------------------------------------------------------------------
-- A spell that leaves a debuff stopping it being cast again on the same
-- target (Power Word: Shield and Weakened Soul): entry.lockout is that
-- debuff's spell ID, entry.lockoutTime how long it lasts. The button is gray
-- while it's on your friendly target, or on you when your target is hostile
-- or you have none. Read from the target's auras when the game allows; in
-- combat, from your own casts (someone else's shield isn't seen then).
local lockUntil = {} -- unit GUID -> GetTime() its lockout from your cast ends
local GetAuraByName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName

local function LockoutUnit()
  local exists = UnitExists("target")
  if not issecret(exists) and exists then
    local friend = UnitIsFriend("player", "target")
    if not issecret(friend) and friend then return "target" end
  end
  return "player"
end

function Button.RefreshLockout(btn)
  local lock = btn.lockout
  if not lock then return end
  local unit = LockoutUnit()
  local locked
  if GetAuraByName and lock.name then
    local ok, aura = pcall(GetAuraByName, unit, lock.name, "HARMFUL")
    if ok and not issecret(aura) then locked = aura ~= nil end
  end
  if locked == nil then
    local guid = UnitGUID(unit)
    locked = guid ~= nil and not issecret(guid) and (lockUntil[guid] or 0) > GetTime()
  end
  btn.lockedOut = locked == true
  Button.RefreshState(btn)
end

function Button.SetupLockout(btn, entry)
  btn.lockout = { name = ns.SpellName(entry.lockout), seconds = entry.lockoutTime or 15 }
  Button.RefreshLockout(btn)
end

local function RefreshLockouts()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.lockout then Button.RefreshLockout(btn) end
  end
end

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  local name = ns.SpellName(spellID)
  if not name then return end
  for _, btn in ipairs(ns.activeButtons) do
    if btn.lockout and btn.spellName == name then
      local guid = UnitGUID(LockoutUnit())
      if guid and not issecret(guid) then lockUntil[guid] = GetTime() + btn.lockout.seconds end
      ns.Schedule(RefreshLockouts)
      C_Timer.After(btn.lockout.seconds + 0.1, RefreshLockouts)
      return
    end
  end
end)
ns.On("PLAYER_TARGET_CHANGED", function() ns.Schedule(RefreshLockouts) end)
ns.OnUnit("UNIT_AURA", "target", function() ns.Schedule(RefreshLockouts) end)
ns.OnUnit("UNIT_AURA", "player", function() ns.Schedule(RefreshLockouts) end)

-- Stealth --------------------------------------------------------------------------------
-- Whether you're stealthed (or in Prowl). If the game hides it, taken as yes,
-- so an opener never goes missing when you need it.
function Button.Stealthed()
  if not IsStealthed then return true end
  local stealthed = IsStealthed()
  if issecret(stealthed) then return true end
  return stealthed == true or stealthed == 1
end

-- Druid forms: entry.form "cat", "bear" or "feral" (either). The game's form
-- IDs: 1 Cat, 5 Bear, 8 Dire Bear. If the form can't be read, taken as yes.
local FORMS = { cat = { [1] = true }, bear = { [5] = true, [8] = true }, feral = { [1] = true, [5] = true, [8] = true } }

function Button.InForm(form)
  if not GetShapeshiftFormID or not FORMS[form] then return true end
  local id = GetShapeshiftFormID()
  if issecret(id) then return true end
  return FORMS[form][id] == true
end

-- Whether a button's stealth or form condition keeps it hidden right now.
function Button.Gated(entry)
  if not entry then return false end
  if entry.stealthOnly and not Button.Stealthed() then return true end
  if entry.form and not Button.InForm(entry.form) then return true end
  return false
end

local function RefreshGated()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.entry and (btn.entry.stealthOnly or btn.entry.form) then Button.RefreshState(btn) end
  end
end
ns.On("UPDATE_STEALTH", function() ns.Schedule(RefreshGated) end)
ns.On("UPDATE_SHAPESHIFT_FORM", function() ns.Schedule(RefreshGated) end)

-- Next-swing abilities (Heroic Strike, Cleave): a group with entry.queue
-- shows whichever member is queued for your next swing, and is gray while
-- none is.
local IsCurrent = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell

function Button.SetupQueue(btn, entry)
  local members = {}
  for _, id in ipairs(ns.Groups.Members(entry)) do
    local known = ns.ResolveSpell(id)
    if known then members[#members + 1] = { id = known, texture = C_Spell.GetSpellTexture(known) } end
  end
  if #members == 0 or not IsCurrent then return end
  btn.queueMembers = members
  Button.RefreshQueue(btn)
end

function Button.RefreshQueue(btn)
  local members = btn.queueMembers
  if not members then return end
  local queued
  for _, member in ipairs(members) do
    local ok, current = pcall(IsCurrent, member.id)
    -- In combat the answer may be hidden: then the button keeps what it showed.
    if not ok or issecret(current) then return end
    if current then
      queued = member
      break
    end
  end
  btn.queued = queued ~= nil
  btn.queueTexture = (queued or members[1]).texture
  btn.icon:SetTexture(btn.queueTexture)
  Button.RefreshState(btn)
end

local function RefreshQueues()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.queueMembers then Button.RefreshQueue(btn) end
  end
end
ns.On("CURRENT_SPELL_CAST_CHANGED", function() ns.Schedule(RefreshQueues) end)
ns.On("PLAYER_LEAVE_COMBAT", function() ns.Schedule(RefreshQueues) end)

function Button.ApplyGroup(btn, entry)
  if not ns.Groups.IsGroup(entry) then return end
  btn.groupNames, btn.groupIcon = ns.Groups.Names(entry), entry.groupIcon
  if btn.groupIcon == "first" then return end
  local latest
  for name, texture in pairs(btn.groupNames) do
    local cast = castTimes[name]
    if cast and (not latest or cast > latest) then latest, btn.groupTexture = cast, texture end
  end
  if btn.groupTexture and btn.kind ~= "spell" then btn.icon:SetTexture(btn.groupTexture) end
end

local function OnHighlight(event, spellID)
  local name = ReadableName(spellID)
  if not name then return end
  highlighted[name] = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or nil
  for _, btn in ipairs(ns.activeButtons) do
    if btn.spellName == name or btn.swapName == name then Button.RefreshProc(btn) end
  end
end

ns.On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", OnHighlight)
ns.On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", OnHighlight)

-- Called once per build, for highlights already showing.
function Button.SeedHighlights()
  for _, btn in ipairs(ns.activeButtons) do
    if btn.kind == "spell" then
      CheckHighlight(btn.spellID, btn.spellName)
      Button.RefreshProc(btn)
    end
  end
end

-- Cooldown ----------------------------------------------------------------------

-- Whether the spell is on a real cooldown (not just the GCD). The client keeps
-- these flags readable in combat even though the times are secret. Returns
-- nil when it can't tell right now.
local function PublicOnCooldown(spellID, duration)
  local info = C_Spell.GetSpellCooldown(spellID)
  if not info then return false end
  local enabled, running, onGCD = info.isEnabled, info.isActive, info.isOnGCD
  if not issecret(enabled) and enabled == false then return true end -- held, e.g. until a buff ends
  if not issecret(running) and running == false then return false end
  if duration and duration.IsZero then
    local zero = duration:IsZero() -- the GCD-free timer
    if not issecret(zero) then return not zero end
  end
  if not issecret(onGCD) and onGCD ~= nil then return not onGCD end
end

-- Edit mode's stand-in for a spell you haven't learned: faded and gray.
function Button.SetupUnlearned(btn, entry, size)
  local first = type(entry.spell) == "table" and entry.spell[1] or entry.spell
  btn.kind, btn.spellName = "unlearned", C_Spell.GetSpellName(first)
  btn.texture = C_Spell.GetSpellTexture(first)
  btn:SetSize(size, size)
  btn.icon:SetTexture(btn.texture)
  btn.icon:SetDesaturation(1)
  btn.icon:SetVertexColor(1, 1, 1)
  btn.cd:Clear()
  btn.gcd:Hide()
  btn.wipe:Hide()
  btn.cost:Hide()
  ns.Glow.Hide(btn.glow)
  btn.tag:SetFont(ns.Font(), math.max(7, math.floor(size * 0.22)), "OUTLINE")
  btn.tag:SetText("not learned")
  btn:SetAlpha(0.5)
  btn.active = true
  btn:Show()
  return true
end

function Button.RefreshCooldown(btn)
  if btn.kind == "unlearned" then return end
  if btn.kind == "spell" then
    local duration = ns.SpellCooldown(btn.spellID)
    btn.duration = duration
    local before = btn.onCooldown
    local ok, onCooldown = pcall(PublicOnCooldown, btn.spellID, duration)
    if ok and onCooldown ~= nil then btn.onCooldown = onCooldown end
    if before ~= true and btn.onCooldown == true then Button.CooldownStarted(btn, duration) end
    if before == true and btn.onCooldown == false then Button.CooldownEnded(btn) end
    if duration then
      ns.Try("cooldown swipe", btn.cd.SetCooldownFromDurationObject, btn.cd, duration, true)
      if btn.mode == "wipe" then
        btn.wipe:Show()
        ns.Try("cooldown wipe", btn.wipe.SetTimerDuration, btn.wipe, duration,
          Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
      end
    else
      btn.cd:Clear()
      btn.wipe:Hide()
    end
  else
    local start, length
    if btn.kind == "slot" then
      start, length = GetInventoryItemCooldown("player", btn.slot)
    elseif GetItemCooldown then
      start, length = GetItemCooldown(btn.itemID)
    end
    if issecret(start) or issecret(length) then
      ns.Try("item cooldown", btn.cd.SetCooldown, btn.cd, start, length)
      btn.itemOnCooldown = nil
    elseif start and length and length > 1.5 then -- 1.5 seconds or less is only the GCD
      btn.cd:SetCooldown(start, length)
      btn.itemOnCooldown = true
    else
      btn.cd:Clear()
      if btn.itemOnCooldown == true then ns.Alerts.Fire(btn, "ready") end
      btn.itemOnCooldown = false
    end
    if btn.itemOnCooldown ~= nil then btn.onCooldown = btn.itemOnCooldown end
  end
  if btn.earlyGlowUntil and GetTime() >= btn.earlyGlowUntil then
    ClearEarlyGlow(btn)
  end
  Button.RefreshState(btn)
end

function Button.RefreshGCD(btn, duration)
  if btn.kind ~= "spell" or not btn.opts.gcd then return end
  if duration then
    ns.Try("gcd swipe", btn.gcd.SetCooldownFromDurationObject, btn.gcd, duration, true)
  else
    btn.gcd:Clear()
  end
end

-- Gray and visibility follow the cooldown. For spells, the game works them
-- out from the remaining time, which may be secret, so the results are only
-- ever handed to widgets, never tested.
function Button.RefreshState(btn)
  local opts = btn.opts
  local running, done
  if btn.kind == "spell" then
    running = ns.Evaluate(btn.duration, ns.curveRunning, 0)
    done = ns.Evaluate(btn.duration, ns.curveDone, 1)
  elseif btn.itemOnCooldown then
    running, done = 1, 0
  else
    running, done = 0, 1 -- a secret item cooldown counts as ready
  end

  local gray = 0
  if opts.desaturate then gray = running end
  -- Next-swing button: gray while nothing is queued.
  if btn.queueMembers then gray = btn.queued and 0 or 1 end
  -- Locked out (Weakened Soul on whoever it would go on): gray.
  if btn.lockedOut then gray = 1 end
  -- A debuff spell without a cooldown: gray, until its debuff (in color) covers it.
  if opts.debuffGray and opts.targetDebuff then gray = 1 end
  ns.Try("desaturate", btn.icon.SetDesaturation, btn.icon, gray)

  -- Stealth openers (entry.stealthOnly) only while stealthed; cat and bear
  -- abilities (entry.form) only in that form.
  if not ns.editMode and Button.Gated(btn.entry) then
    if btn.collapse and btn.visible ~= false then
      btn.visible = false
      ns.Bar.RequestLayout(btn.bar)
    end
    btn:SetAlpha(0)
    return
  end

  if ns.editMode or opts.visibility == "always" then
    if btn.collapse and btn.visible == false then ns.Bar.RequestLayout(btn.bar) end
    btn.visible = true
    btn:SetAlpha(ns.editMode and btn.entry and btn.entry.hidden and 0.35 or 1)
  elseif btn.collapse then
    -- On a bar that closes gaps, the public on-cooldown flag decides, and the
    -- bar moves the other buttons up. While the client can't tell, the
    -- button keeps its last state.
    if btn.onCooldown ~= nil then
      local visible = btn.onCooldown
      if opts.visibility == "ready" then visible = not btn.onCooldown end
      if visible ~= btn.visible then
        btn.visible = visible
        ns.Bar.RequestLayout(btn.bar)
      end
    end
    btn:SetAlpha(btn.visible == false and 0 or 1)
  else
    -- Otherwise the game fades the button from the remaining time; it keeps its place.
    local alpha = running
    if opts.visibility == "ready" then alpha = done end
    ns.Try("visibility", btn.SetAlpha, btn, alpha)
  end
end

-- Tint --------------------------------------------------------------------------

local function SetTint(btn, tint)
  btn.icon:SetVertexColor(tint[1], tint[2], tint[3])
end

-- The game picks the color from a yes/no we aren't allowed to read.
local function SecretManaTint(btn, noMana)
  local pick = C_CurveUtil.EvaluateColorValueFromBoolean
  btn.icon:SetVertexColor(pick(noMana, TINT_MANA[1], 1), pick(noMana, TINT_MANA[2], 1), pick(noMana, TINT_MANA[3], 1))
end

function Button.RefreshTint(btn)
  local opts = btn.opts
  if opts.rangeTint and btn.outOfRange then
    SetTint(btn, TINT_RANGE)
    return
  end
  if btn.kind ~= "spell" or not (opts.manaTint or opts.usableTint) then
    btn.icon:SetVertexColor(1, 1, 1)
    return
  end

  local usable, noMana = C_Spell.IsSpellUsable(btn.spellID)
  if opts.manaTint then
    if issecret(noMana) then
      if ns.Try("mana tint", SecretManaTint, btn, noMana) then return end
    elseif noMana then
      SetTint(btn, TINT_MANA)
      return
    end
  end
  if opts.usableTint and not issecret(usable) and not usable then
    SetTint(btn, TINT_UNUSABLE)
    return
  end
  btn.icon:SetVertexColor(1, 1, 1)
end

-- Mana cost ---------------------------------------------------------------------

-- The cost is kept from the last time it could be read, so it still shows
-- if the client hides it in combat.
function Button.RefreshCost(btn)
  if btn.kind ~= "spell" or not btn.opts.manaCost then return end
  local cost = ns.ManaCost(btn.spellID)
  if cost then btn.cachedCost = cost end
  if btn.cachedCost and btn.cachedCost > 0 then
    btn.cost:SetText(btn.cachedCost)
  else
    btn.cost:SetText("")
  end
end
