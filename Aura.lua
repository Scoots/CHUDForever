-- Aura buttons, drawn by the game's own aura widget (Blizzard_AuraContainer).
--
-- In combat, aura data is secret: the addon can't ask "is Flurry up?". An
-- AuraContainer is told what to look for (unit, filter, spell IDs) and shows,
-- times and counts matching auras itself. A button on a static bar has one of
-- three looks:
--   active:  the aura's icon, timer and stacks while it's up; empty otherwise
--   always:  the same, over a dimmed icon while it's down
--   missing: an alert icon only while it's down. A second, invisible
--            container is one pixel wide while the aura is down and wider
--            while it's up. A clipping frame hangs off its right edge, so it
--            closes over the alert icon whenever the aura is present.
-- A dynamic bar puts all its auras in one container, which lays out only the
-- ones that are up, so the gaps close.
local _, ns = ...
local issecret = ns.issecret

local Aura = {}
ns.Aura = Aura
ns.activeAuras = {} -- everything bound to a unit: {unit, container, missingPart?}

local SLOT, PRESENCE, GROUP = "Aura", "Presence", "Auras"
local ALERT_COLOR = { 1, 0.15, 0.15 }

-- Setup ------------------------------------------------------------------------

local ready
local function Ready()
  if ready ~= nil then return ready end
  local addons = C_AddOns
  if addons and addons.IsAddOnLoaded and addons.LoadAddOn and not addons.IsAddOnLoaded("Blizzard_AuraContainer") then
    pcall(addons.LoadAddOn, "Blizzard_AuraContainer")
  end
  ready = CustomAuraContainerAuraProcessingPolicy ~= nil
  if not ready then ns.Print("This client has no aura widget, so aura buttons are turned off.") end
  return ready
end

local function NewContainer(parent)
  local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  container:SetEnabled(false)
  container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)
  return container
end

-- Points the container at a unit and has it read that unit's auras.
local function Bind(container, unit)
  if container.unit ~= unit then
    container:SetEnabled(false)
    container:SetUnit(unit)
    container.unit = unit
  end
  container:Show()
  container:SetEnabled(true)
  container:UpdateAllAuras()
  container.bound = true
end

local function Unbind(container)
  container:SetEnabled(false)
  container:Hide()
  container.bound = false
end

-- Entries ----------------------------------------------------------------------

-- The spell IDs an entry watches, as a set: its aura list and the spell it was
-- made from. Each is also looked up by name, which adds the rank the player
-- actually has (buffs you cast carry the ID of the rank you cast), plus any
-- buff learned for that spell (Learn.lua).
function Aura.SpellIDs(entry)
  local ids = {}
  local function Add(spell)
    if type(spell) == "table" then
      for _, id in ipairs(spell) do Add(id) end
    elseif type(spell) == "number" then
      ids[spell] = true
      local resolved = ns.ResolveSpell(spell)
      if resolved then ids[resolved] = true end
      local linked = ns.Learn.Linked(C_Spell.GetSpellName(spell))
      for _, id in ipairs(linked or {}) do ids[id] = true end
    end
  end
  Add(entry.aura)
  Add(entry.spell)
  return ids
end

-- The spell whose icon and name the entry shows.
local function IconSpell(entry)
  local first = entry.aura or entry.spell
  if type(first) == "table" then first = first[1] end
  return type(first) == "number" and first or nil
end

local SpellName = ns.SpellName

-- The game's aura filter: HELPFUL or HARMFUL, plus PLAYER for "cast by me".
-- Auras on the target count only if they're yours unless the entry says otherwise.
function Aura.Filter(entry, unit)
  local filter = unit == "target" and "HARMFUL" or "HELPFUL"
  local mine = entry.mine
  if mine == nil then mine = unit == "target" end
  if mine then filter = filter .. "|PLAYER" end
  return filter
end

-- Native buttons -----------------------------------------------------------------

-- glow: whether the rotating border shows while the aura is up.
-- red: seconds left when the time turns red (0: never).
-- visual: the alert visual played as it shows (an Alerts.VISUALS row), or nil.
-- timer: "spinner" (the clock swipe), "number" or "both".
local function StyleNative(native, size, glow, red, visual, timer)
  size = size or 30
  timer = timer or "spinner"
  native.time:SetShown(timer ~= "spinner")
  native.cooldown:SetDrawSwipe(timer ~= "number")
  if red ~= native.red then
    native.red = red
    if native.button.ClearDurationText then pcall(native.button.ClearDurationText, native.button) end
    ns.BindTimer(native.button, native.time, red)
  end
  -- The game's layout places native buttons but doesn't size them.
  pcall(native.button.SetSize, native.button, size, size)
  if native.glow then
    ns.Glow.SizeShownAlert(native.glow, size, size)
    native.glow:SetShown(glow ~= false)
  end
  if native.fx then
    ns.Glow.StyleAlertFx(native.fx, visual)
    ns.Glow.SizeAlertFx(native.fx, size)
  end
  native.time:SetFont(ns.Font(), math.max(8, math.floor(size * 0.36)), "OUTLINE")
  native.stacks:SetFont(ns.Font(), math.max(7, math.floor(size * 0.3)), "OUTLINE")
end

-- Called by the game for each button it creates. The game fills in the icon,
-- timer and stack count; we only provide the widgets.
local GLOW_COLOR = { 0.75, 0.9, 1 }

local function BuildNative(button, size, glow, red, visual, timer)
  local native = { button = button }
  button:EnableMouse(false)

  local border = button:CreateTexture(nil, "BACKGROUND")
  border:SetColorTexture(0, 0, 0, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)

  native.icon = button:CreateTexture(nil, "ARTWORK")
  native.icon:SetAllPoints()
  native.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button:SetIcon(native.icon)

  native.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
  native.cooldown:SetAllPoints()
  native.cooldown:SetDrawBling(false)
  native.cooldown:SetDrawEdge(false)
  native.cooldown:SetHideCountdownNumbers(true)
  native.cooldown:SetSwipeColor(0, 0, 0, 0.6)
  ns.Try("aura swipe", button.SetDurationCooldown, button, native.cooldown)

  local overlay = CreateFrame("Frame", nil, button)
  overlay:SetAllPoints()
  overlay:SetFrameLevel(native.cooldown:GetFrameLevel() + 1)
  native.time = overlay:CreateFontString(nil, "OVERLAY")
  native.time:SetPoint("CENTER", 0, 0)
  native.stacks = overlay:CreateFontString(nil, "OVERLAY")
  native.stacks:SetPoint("BOTTOMRIGHT", -1, 2)
  -- A rotating border while the aura is up, like the proc alert.
  local ok, holder = pcall(ns.Glow.BuildShownAlert, button, GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
  if ok then native.glow = holder end
  local made, fx = pcall(ns.Glow.BuildAlertFx, button, true)
  if made then native.fx = fx end
  native.red = red
  StyleNative(native, size, glow, red, visual, timer) -- fonts must exist before the game writes text
  ns.BindTimer(button, native.time, red)
  ns.Try("aura stacks", button.SetApplicationCount, button, native.stacks)
  return native
end

-- Static aura buttons ------------------------------------------------------------

local pool

local function NewIconFrame(parent)
  local frame = CreateFrame("Frame", nil, parent)
  frame:EnableMouse(false)
  frame.border = frame:CreateTexture(nil, "BACKGROUND")
  frame.border:SetColorTexture(0, 0, 0, 1)
  frame.border:SetPoint("TOPLEFT", -1, 1)
  frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  return frame
end

local function Create()
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:EnableMouse(false)
  -- "always": the dimmed icon under the native one, seen while the aura is down.
  holder.dim = NewIconFrame(holder)
  holder.dim:SetAllPoints()
  holder.dim.icon:SetDesaturated(true)
  holder.dim:SetAlpha(0.35)
  -- Edit mode: a plain copy of the icon on top, with a tag saying what it tracks.
  holder.sample = NewIconFrame(holder)
  holder.sample:SetAllPoints()
  holder.sample.tag = holder.sample:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  holder.sample.tag:SetPoint("BOTTOM", 0, 2)
  return holder
end

local function EnsureActive(holder)
  if holder.activePart then return holder.activePart end
  local part = {}
  local container = NewContainer(holder)
  container:SetPoint("TOPLEFT", holder, "TOPLEFT")
  part.container = container
  local function Init(button)
    part.native = BuildNative(button, holder.size, holder.opts.auraGlow, holder.opts.timerRed,
      ns.Alerts.VisualFor(holder.opts, "applied"), holder.opts.auraTimer)
  end

  -- One aura: a slot, whose single button we place ourselves. Older clients
  -- only have groups, laid out by the game.
  if container.AddAuraSlot and pcall(container.AddAuraSlot, container, SLOT, holder.filter,
      { candidateFilters = holder.candidates, initializeFrame = Init }) and part.native then
    part.slot = true
  else
    part.native = nil
    local ok, err = pcall(container.AddAuraGroup, container, SLOT, holder.filter, {
      candidateFilters = holder.candidates, maxFrameCount = 1,
      layout = { elementWidth = holder.size, elementHeight = holder.size },
      initializeFrame = Init,
    })
    if not ok then
      ns.Print("Couldn't create an aura button: " .. tostring(err))
      Unbind(container)
      return
    end
  end
  holder.activePart = part
  return part
end

local function PlaceNative(holder, button)
  button:SetSize(holder.size, holder.size)
  button:ClearAllPoints()
  button:SetPoint("CENTER", holder, "CENTER")
end

local function ApplyActive(holder, part)
  local container = part.container
  container:SetFrameLevel(holder:GetFrameLevel() + 1)
  if part.slot then
    ns.Try("aura filter", container.SetAuraSlotFilterString, container, SLOT, holder.filter)
    ns.Try("aura spells", container.SetAuraSlotCandidateFilters, container, SLOT, holder.candidates)
    if part.native then ns.Try("aura button layout", PlaceNative, holder, part.native.button) end
  else
    ns.Try("aura filter", container.SetAuraGroupFilterString, container, SLOT, holder.filter)
    ns.Try("aura spells", container.SetAuraGroupCandidateFilters, container, SLOT, holder.candidates)
    ns.Try("aura layout", container.SetAuraGroupLayout, container, SLOT,
      { elementWidth = holder.size, elementHeight = holder.size })
  end
  -- Switched on explicitly, as ForeverAuras does.
  if part.slot and container.SetAuraSlotEnabled then
    ns.Try("aura enable", container.SetAuraSlotEnabled, container, SLOT, true)
  elseif not part.slot and container.SetAuraGroupEnabled then
    ns.Try("aura enable", container.SetAuraGroupEnabled, container, SLOT, true)
  end
  if part.native then
    StyleNative(part.native, holder.size, holder.opts.auraGlow, holder.opts.timerRed, ns.Alerts.VisualFor(holder.opts, "applied"),
      holder.opts.auraTimer)
  end
end

-- How far the alert's clip reaches past the icon (room for its glow).
local function Margin(size) return size + 16 end

-- A presence group's element: while the aura is up the container is this
-- wide, and 1 px wide while it's down. Also used by the totem range alert.
local function PresenceLayout(size)
  return { elementWidth = size + 1 + 2 * Margin(size), elementHeight = size }
end
Aura.PresenceMargin, Aura.PresenceLayout = Margin, PresenceLayout

local function EnsureMissing(holder)
  if holder.missingPart then return holder.missingPart end
  local part = {}
  local presence = NewContainer(holder)
  presence:SetPoint("TOPLEFT", holder, "TOPLEFT")
  local ok, err = pcall(presence.AddAuraGroup, presence, PRESENCE, holder.filter, {
    candidateFilters = holder.candidates, maxFrameCount = 1, layout = PresenceLayout(holder.size),
    -- Draws nothing; only its width matters.
    initializeFrame = function(button)
      button:EnableMouse(false)
      local layout = PresenceLayout(holder.size)
      pcall(button.SetSize, button, layout.elementWidth, layout.elementHeight)
    end,
  })
  if not ok then
    ns.Print("Couldn't create a missing-aura alert: " .. tostring(err))
    Unbind(presence)
    return
  end
  -- Frames anchored to a container with an aura group must opt out of
  -- untrusted layout scripts.
  local clip = CreateFrame("Frame", nil, holder, "DisableUntrustedLayoutScriptsTemplate")
  clip:SetClipsChildren(true)
  clip:EnableMouse(false)
  local alert = NewIconFrame(clip)
  alert:SetAllPoints(holder)
  alert.glow = ns.Glow.Create(alert, 2, ALERT_COLOR[1], ALERT_COLOR[2], ALERT_COLOR[3])
  part.presence, part.clip, part.alert = presence, clip, alert
  holder.missingPart = part
  return part
end

local function ApplyMissing(holder, part)
  local presence, clip = part.presence, part.clip
  presence:SetFrameLevel(holder:GetFrameLevel() + 1)
  ns.Try("alert filter", presence.SetAuraGroupFilterString, presence, PRESENCE, holder.filter)
  ns.Try("alert spells", presence.SetAuraGroupCandidateFilters, presence, PRESENCE, holder.candidates)
  ns.Try("alert layout", presence.SetAuraGroupLayout, presence, PRESENCE, PresenceLayout(holder.size))
  if presence.SetAuraGroupEnabled then ns.Try("alert enable", presence.SetAuraGroupEnabled, presence, PRESENCE, true) end
  -- Aura down: the presence container is 1 px wide and the clip spans the icon.
  -- Aura up: its right edge lands on the clip's right edge, closing it.
  local margin = Margin(holder.size)
  clip:ClearAllPoints()
  clip:SetPoint("TOPLEFT", presence, "TOPRIGHT", -1 - margin, margin)
  clip:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", margin, -margin)
  clip:SetFrameLevel(holder:GetFrameLevel() + 3)
  part.alert.icon:SetTexture(holder.texture)
  clip:SetAlpha(1)
  clip:Show()
  ns.Glow.Show(part.alert.glow)
end

local function Deactivate(holder)
  if holder.activePart then Unbind(holder.activePart.container) end
  if holder.missingPart then
    Unbind(holder.missingPart.presence)
    ns.Glow.Hide(holder.missingPart.alert.glow)
    holder.missingPart.clip:Hide()
  end
end

local function ResetPooled(holder)
  holder.active = false
  Deactivate(holder)
  holder:Hide()
  holder:ClearAllPoints()
end

local TAGS = { active = "up", missing = "missing", always = "always" }

function Aura.Acquire(parent)
  return pool.Acquire(parent)
end

-- Pooled frames wait under a hidden frame of their own rather than under a
-- bar, so the game's aura widgets inside them never tie a bar down in combat.
local retired = CreateFrame("Frame")
retired:Hide()

pool = ns.CreatePool(Create, ResetPooled, retired)

function Aura.Release(holder)
  pool.Release(holder)
end

function Aura.Name(holder)
  return holder.spellName or "aura"
end

function Aura.Setup(holder, entry, opts, size)
  if not Ready() then return false end
  local iconSpell = IconSpell(entry)
  if not iconSpell then return false end
  Deactivate(holder)

  holder.entry, holder.opts, holder.size, holder.kind = entry, opts, size, "aura"
  -- unit and show come from the bar's settings unless the button sets its own.
  holder.unit = opts.unit or "player"
  holder.filter = Aura.Filter(entry, holder.unit)
  holder.candidates = { includeSpellIDs = Aura.SpellIDs(entry) }
  holder.show = opts.show or "active"
  holder.spellName = SpellName(iconSpell)
  holder.texture = C_Spell.GetSpellTexture(iconSpell)
  holder:SetSize(size, size)
  holder.dim.icon:SetTexture(holder.texture)
  holder.sample.icon:SetTexture(holder.texture)
  holder.sample.tag:SetText(TAGS[holder.show] or "")
  holder.sample.tag:SetFont(ns.Font(), math.max(7, math.floor(size * 0.24)), "OUTLINE")
  holder.sample:SetFrameLevel(holder:GetFrameLevel() + 8)
  holder.sample:SetShown(ns.editMode)
  holder.dim:SetFrameLevel(holder:GetFrameLevel()) -- under the native button
  holder.dim:SetShown(holder.show == "always")

  local record = { unit = holder.unit, name = holder.spellName }
  if holder.show == "missing" then
    local part = EnsureMissing(holder)
    if not part then return false end
    ApplyMissing(holder, part)
    record.container, record.missingPart = part.presence, part
  else
    local part = EnsureActive(holder)
    if not part then return false end
    ApplyActive(holder, part)
    record.container = part.container
    record.natives = { part.native }
  end
  if not ns.Try("aura unit", Bind, record.container, holder.unit) then return false end
  table.insert(ns.activeAuras, record)
  if record.missingPart and holder.unit == "target" then
    record.missingPart.clip:SetAlpha(Aura.EnemyTarget() and 1 or 0)
  end

  holder.active = true
  holder:Show()
  return true
end

-- Edit-mode stand-ins on dynamic bars ------------------------------------------------
-- A dynamic bar's container only shows auras that are up, so in edit mode the
-- bar shows a plain icon per entry instead, to drag onto and right-click.

local Sample = {}
Aura.Sample = Sample
local function ResetSample(sample)
  sample:Hide()
  sample:ClearAllPoints()
end

local samplePool = ns.CreatePool(function() return NewIconFrame(UIParent) end, ResetSample)

function Sample.Acquire(parent)
  return samplePool.Acquire(parent)
end

function Sample.Release(sample)
  samplePool.Release(sample)
end

function Sample.Name(sample)
  return sample.spellName or "aura"
end

function Sample.Setup(sample, entry, opts, size)
  local iconSpell = IconSpell(entry)
  if not iconSpell then return false end
  sample.entry, sample.opts, sample.kind = entry, opts, "sample"
  sample.spellName = SpellName(iconSpell)
  sample.icon:SetTexture(C_Spell.GetSpellTexture(iconSpell))
  sample:SetSize(size, size)
  sample:SetFrameLevel(sample:GetParent():GetFrameLevel() + 1)
  sample:SetShown(ns.editMode)
  return true
end

-- Dynamic bars ---------------------------------------------------------------------------

-- Where the container sits on the bar and which way the game fills it.
local function Flow(vertical, grow)
  local axis = vertical and AnchorUtil.FlowLayoutAxis.Vertical or AnchorUtil.FlowLayoutAxis.Horizontal
  local right, left = AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Left
  local down, up = AnchorUtil.FlowDirection.Down, AnchorUtil.FlowDirection.Up
  if grow == "LEFT" then return "RIGHT", "TOPRIGHT", axis, left, down end
  if grow == "RIGHT" then return "LEFT", "TOPLEFT", axis, right, down end
  if grow == "UP" then return "BOTTOM", "BOTTOMLEFT", axis, right, up end
  if grow == "DOWN" then return "TOP", "TOPLEFT", axis, right, down end
  return "CENTER", "TOPLEFT", axis, right, down
end

local function ApplyFlow(container, axis, flowAnchor, horizontal, vertical)
  container:SetFlowLayoutAxis(axis)
  container:SetFlowLayoutAnchorPoint(flowAnchor)
  container:SetFlowLayoutGrowthDirection(horizontal, vertical)
end

function Aura.BuildDynamic(frame, config, size, spacing)
  if not Ready() then return end
  local ids = {}
  for _, entry in ipairs(config.buttons) do
    for id in pairs(Aura.SpellIDs(entry)) do ids[id] = true end
  end
  local unit = config.unit or "player"
  local filter = Aura.Filter(config, unit)
  local candidates = { includeSpellIDs = ids }
  local count = math.max(1, #config.buttons)
  if ns.Bar.Type(config) == "allbuffs" then
    -- Every buff you cast on yourself: no list, just what's hidden and how long is too long.
    candidates = {}
    local hidden = ns.Learn.HiddenIDs(config)
    if next(hidden) then candidates.excludeSpellIDs = hidden end
    if (config.maxDuration or 0) > 0 then candidates.maxDuration = config.maxDuration + 0.05 end
    count = config.maxIcons or 8
  end
  local layout = { elementWidth = size, elementHeight = size, elementSpacing = spacing, lineSpacing = spacing }

  local dynamic = frame.dynamic
  if not dynamic then
    -- The size has to be known before AddAuraGroup: the game may build the
    -- buttons (initializeFrame) right away.
    dynamic = { natives = {}, size = size }
    dynamic.container = NewContainer(frame)
    local ok, err = pcall(dynamic.container.AddAuraGroup, dynamic.container, GROUP, filter, {
      candidateFilters = candidates, maxFrameCount = count, layout = layout,
      initializeFrame = function(button)
        table.insert(dynamic.natives, BuildNative(button, dynamic.size, dynamic.glow, dynamic.red, dynamic.visual, dynamic.timer))
      end,
    })
    if not ok then
      ns.Print("Couldn't create the dynamic bar " .. (config.name or "") .. ": " .. tostring(err))
      Unbind(dynamic.container)
      return
    end
    frame.dynamic = dynamic
  end
  -- Set on every build, the first included: options passed to AddAuraGroup
  -- aren't all applied, and the group is switched on explicitly.
  local container = dynamic.container
  ns.Try("dynamic filter", container.SetAuraGroupFilterString, container, GROUP, filter)
  ns.Try("dynamic spells", container.SetAuraGroupCandidateFilters, container, GROUP, candidates)
  ns.Try("dynamic layout", container.SetAuraGroupLayout, container, GROUP, layout)
  ns.Try("dynamic size", container.SetAuraGroupMaxFrameCount, container, GROUP, count)
  if container.SetAuraGroupEnabled then ns.Try("dynamic enable", container.SetAuraGroupEnabled, container, GROUP, true) end
  dynamic.size = size
  local barOpts = ns.Bar.Options(ns.profile, config, {})
  dynamic.glow, dynamic.red = barOpts.auraGlow, barOpts.timerRed
  dynamic.visual = ns.Alerts.VisualFor(barOpts, "applied") -- one for the whole bar
  dynamic.timer = barOpts.auraTimer
  for _, native in ipairs(dynamic.natives) do
    StyleNative(native, size, dynamic.glow, dynamic.red, dynamic.visual, dynamic.timer)
  end

  local point, flowAnchor, axis, horizontal, vertical = Flow(config.orientation == "VERTICAL", frame.grow)
  ns.Try("dynamic flow", ApplyFlow, container, axis, flowAnchor, horizontal, vertical)
  container:ClearAllPoints()
  container:SetPoint(point, frame, point)
  container:SetFrameLevel(frame:GetFrameLevel() + 1)

  if ns.editMode then
    Unbind(container)
  elseif ns.Try("dynamic unit", Bind, container, unit) then
    table.insert(ns.activeAuras, { unit = unit, container = container, natives = dynamic.natives, name = config.name })
  end
end

function Aura.HideDynamic(frame)
  if not frame.dynamic then return end
  local container = frame.dynamic.container
  Unbind(container)
  -- Unanchored, so a bar that no longer uses it stays free to change in combat.
  container:ClearAllPoints()
end

-- Target changes -------------------------------------------------------------------------
-- A container re-reads its unit on UNIT_AURA or when enabled, not when the
-- target changes, so target containers are told to re-read.

-- Whether a missing debuff on the target is worth flagging: a living target
-- you can attack. Anything that can't be read counts as yes.
function Aura.EnemyTarget()
  local exists = UnitExists("target")
  if issecret(exists) then return true end
  if not exists then return false end
  local dead, enemy = UnitIsDead("target"), UnitCanAttack("player", "target")
  if not issecret(dead) and dead then return false end
  if issecret(enemy) then return true end
  return enemy == true
end

local function RefreshTargetAlerts()
  local enemy = Aura.EnemyTarget()
  for _, record in ipairs(ns.activeAuras) do
    if record.unit == "target" and record.missingPart then record.missingPart.clip:SetAlpha(enemy and 1 or 0) end
  end
end

ns.On("PLAYER_TARGET_CHANGED", function()
  for _, record in ipairs(ns.activeAuras) do
    if record.unit == "target" then
      ns.Try("aura target refresh", record.container.UpdateAllAuras, record.container)
    end
  end
  RefreshTargetAlerts()
end)
-- The target dying: no more alerts for it.
ns.OnUnit("UNIT_HEALTH", "target", function() ns.Schedule(RefreshTargetAlerts) end)

-- Troubleshooting (/chud debug auras) ------------------------------------------------------------

local function IDList(ids)
  local list = {}
  for id in pairs(ids) do list[#list + 1] = id end
  table.sort(list)
  for index, id in ipairs(list) do list[index] = tostring(id) end
  return table.concat(list, ", ")
end

function Aura.PrintDiag()
  ns.Print("Aura widget: " .. (Ready() and "loaded" or "missing"))

  -- Your buffs right now (readable out of combat).
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if not getAura then
    ns.Print("This client has no C_UnitAuras.GetAuraDataByIndex.")
  else
    local count = 0
    for index = 1, 40 do
      local ok, aura = pcall(getAura, "player", index, "HELPFUL")
      if not ok then
        ns.Print("Reading your buffs failed: " .. tostring(aura))
        break
      end
      if not aura then break end
      if issecret(aura.spellId) or issecret(aura.name) then
        ns.Print("Buff details are hidden right now (in combat?).")
        break
      end
      local source = aura.sourceUnit
      if issecret(source) then source = "?" end
      ns.Print(("Your buff: %s (%d), cast by %s"):format(aura.name, aura.spellId, tostring(source)))
      count = count + 1
    end
    if count == 0 then ns.Print("You have no buffs right now.") end
    local ok, err = pcall(getAura, "player", 1, "HELPFUL|PLAYER")
    if not ok then ns.Print("The HELPFUL|PLAYER filter fails: " .. tostring(err)) end
  end

  -- What each aura button and aura bar watches.
  for _, bar in ipairs(ns.profile and ns.profile.bars or {}) do
    local kind = ns.Bar.Type(bar)
    for _, entry in ipairs(bar.buttons or {}) do
      if (kind ~= "cooldowns" or entry.aura) and not entry.slot and not entry.item then
        ns.Print(("%s (%s): %s watches %s"):format(bar.name or "Bar", kind,
          SpellName(IconSpell(entry)) or "?", IDList(Aura.SpellIDs(entry))))
      end
    end
  end

  -- The live containers.
  if #ns.activeAuras == 0 then ns.Print("No aura containers are running (edit mode turns them off).") end
  local function Readout(value)
    if issecret(value) then return "hidden" end
    if type(value) == "number" then return ("%.0f"):format(value) end
    return tostring(value)
  end
  for _, record in ipairs(ns.activeAuras) do
    local container = record.container
    ns.Print(("Container %s: unit %s, shown %s, running %s, buttons built %d, size %sx%s"):format(
      tostring(record.name), tostring(record.unit), tostring(container:IsShown()),
      tostring(container.bound), record.natives and #record.natives or 0,
      Readout(container:GetWidth()), Readout(container:GetHeight())))
    -- The first few buttons: size, whether shown, and the icon the game gave it.
    for index = 1, math.min(3, record.natives and #record.natives or 0) do
      local native = record.natives[index]
      local button = native.button
      ns.Print(("  button %d: %sx%s, shown %s, icon %s"):format(index, Readout(button:GetWidth()),
        Readout(button:GetHeight()), Readout(button:IsShown()), Readout(native.icon:GetTexture())))
    end
  end
end

-- Shared with the charge bars (Charges.lua).
Aura.Ready, Aura.NewContainer, Aura.Bind, Aura.Unbind = Ready, NewContainer, Bind, Unbind
Aura.IconSpell, Aura.SpellName = IconSpell, SpellName
