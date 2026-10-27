-- Shield absorb bars: how much damage the shields on a unit (Power Word:
-- Shield, Ice Barrier, Mana Shield...) will still absorb, from
-- UnitGetTotalAbsorbs, with the amount written under the bar.
--
-- A bar is made of pieces: one for a plain bar, a pill per segment
-- (Media/Charges/pill_*.tga, tinted), or thin slices for a bent plain bar.
-- The pieces sit on a straight line or around a circle, each turned to
-- follow it. The amount may be secret in combat, so it's never read there:
-- each piece is lit by an invisible status bar the game fills from the
-- amount, through a clip frame that ends at the fill's edge (as on charge
-- bars). "Only while shielded" works the same way: everything sits in a clip
-- frame that another hidden bar opens as soon as there's any absorb.
--
-- A full bar is what the shield absorbed when it was cast. Your cast and the
-- absorb change that follows it on a unit are matched up: when the amount
-- can be read (out of combat), that's the shield's size, saved per spell rank
-- and character. When it can't (in combat), the saved size for the spell you
-- just cast is used, else the number in its tooltip. Other shields going up
-- (someone else's) count while the amount can be read; a shield never seen
-- falls back to the biggest seen on you.
--
-- A bar for the target only shows while one of your own shields is on it:
-- a hidden aura group of your shields (HELPFUL|PLAYER) opens the clip, like
-- a missing-buff alert in reverse. The game only reports all of a unit's
-- shields together, so if someone else's shield is on it too, its amount
-- counts.
local _, ns = ...
local issecret = ns.issecret

local Absorb = {}
ns.Absorb = Absorb

local WHITE = ns.WHITE
local ART = ns.MEDIA .. "Charges\\"
local SLICES = 24 -- pieces of a bent plain bar

-- { key, label, r, g, b }
Absorb.COLORS = {
  { "gold", "Gold", 1, 0.82, 0.25 },
  { "blue", "Blue", 0.35, 0.65, 1 },
  { "purple", "Purple", 0.75, 0.45, 1 },
  { "green", "Green", 0.4, 0.95, 0.45 },
  { "red", "Red", 1, 0.35, 0.3 },
  { "white", "White", 0.95, 0.95, 1 },
}


local active = {} -- bar frame -> its element, while shown
local warned

-- Shape --------------------------------------------------------------------------------------

-- Where each piece goes, from the bar's middle (y up): x, y, turn (radians),
-- width and height before turning, and the upright box around it. Also the
-- size of the box around them all and the look. Unflipped, a standing bar
-- bulges right and a lying one bulges down. Same layout as
-- tools/make_charge_art.py draws in its preview.
local function Pieces(config, length, thickness, scale)
  local look = config.look or "bar"
  local bend = math.rad(math.max(0, math.min(180, config.bend or 0)))
  local count, gap = 1, 0
  if look == "segments" then
    count = math.max(1, math.min(40, math.floor(config.segments or 16)))
    gap = math.floor((config.gap or 3) * scale + 0.5)
  elseif bend > 0 then
    count = SLICES
  end
  local vertical = config.orientation == "VERTICAL"
  local sign = config.bendFlip and -1 or 1
  local piece = math.max(1, (length - (count - 1) * gap) / count)
  local overlap = (look ~= "segments" and count > 1) and 1 or 0 -- slices overlap so no seams show

  local pieces = {}
  for index = 1, count do
    local distance = (index - 1) * (piece + gap) + piece / 2 - length / 2 -- along the bar, from its middle
    local turn, along, side = 0, distance, 0
    if bend > 0 then
      local radius = length / bend
      turn = distance / radius
      along, side = radius * math.sin(turn), radius * (1 - math.cos(turn))
    end
    local spot = { turn = turn * sign }
    if vertical then
      spot.x, spot.y, spot.width, spot.height = -side * sign, along, thickness, piece + overlap
    else
      spot.x, spot.y, spot.width, spot.height = along, side * sign, piece + overlap, thickness
    end
    local cos, sin = math.abs(math.cos(spot.turn)), math.abs(math.sin(spot.turn))
    spot.boxWidth = spot.width * cos + spot.height * sin
    spot.boxHeight = spot.width * sin + spot.height * cos
    pieces[index] = spot
  end

  local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
  for _, spot in ipairs(pieces) do
    left, right = math.min(left, spot.x - spot.boxWidth / 2), math.max(right, spot.x + spot.boxWidth / 2)
    bottom, top = math.min(bottom, spot.y - spot.boxHeight / 2), math.max(top, spot.y + spot.boxHeight / 2)
  end
  local middleX, middleY = (left + right) / 2, (bottom + top) / 2
  for _, spot in ipairs(pieces) do
    spot.x, spot.y = spot.x - middleX, spot.y - middleY
  end
  return pieces, math.max(1, right - left), math.max(1, top - bottom), look
end

-- The bar's size: length along it (the width setting) and thickness (the
-- size setting), both already scaled.
function Absorb.Size(config, length, thickness, scale)
  local _, width, height = Pieces(config, length, thickness, scale)
  return math.floor(width + 0.5), math.floor(height + 0.5)
end

-- Frames -----------------------------------------------------------------------------------

local function Create(frame)
  local element = CreateFrame("Frame", nil, frame)
  element:SetAllPoints()
  element:EnableMouse(false)
  element.presence = CreateFrame("StatusBar", nil, element)
  element.presence:SetStatusBarTexture(WHITE)
  element.presence:SetMinMaxValues(0, 1)
  element.presence:SetAlpha(0) -- only its fill is used
  element.content = CreateFrame("Frame", nil, element, "DisableUntrustedLayoutScriptsTemplate")
  element.content:SetClipsChildren(true)
  element.border = element.content:CreateTexture(nil, "BACKGROUND", nil, -1)
  element.border:SetColorTexture(0, 0, 0, 1)
  element.overlay = CreateFrame("Frame", nil, element.content)
  element.overlay:SetAllPoints(element)
  element.text = element.overlay:CreateFontString(nil, "OVERLAY")
  element.text:SetShadowColor(0, 0, 0, 1)
  element.text:SetShadowOffset(1, -1)
  element.pieces = {}
  frame.absorbElement = element
  return element
end

local function NewPiece(element)
  local piece = {}
  piece.box = CreateFrame("Frame", nil, element.content)
  piece.empty = piece.box:CreateTexture(nil, "BACKGROUND")
  piece.guide = CreateFrame("StatusBar", nil, piece.box)
  piece.guide:SetAllPoints()
  piece.guide:SetStatusBarTexture(WHITE)
  piece.guide:SetAlpha(0)
  piece.clip = CreateFrame("Frame", nil, element.content, "DisableUntrustedLayoutScriptsTemplate")
  piece.clip:SetClipsChildren(true)
  piece.lit = piece.clip:CreateTexture(nil, "ARTWORK")
  return piece
end

local function ShowPiece(piece, shown)
  piece.box:SetShown(shown)
  piece.clip:SetShown(shown)
end

-- Places a piece and lets its fill reveal it from the bar's start: bottom to
-- top on a standing bar, left to right on a lying one.
local function PlacePiece(element, piece, spot, texture, color, vertical)
  piece.box:ClearAllPoints()
  piece.box:SetPoint("CENTER", element, "CENTER", spot.x, spot.y)
  piece.box:SetSize(math.max(1, spot.boxWidth), math.max(1, spot.boxHeight))
  for _, art in ipairs({ piece.empty, piece.lit }) do
    art:SetTexture(texture)
    art:ClearAllPoints()
    art:SetPoint("CENTER", piece.box, "CENTER")
    art:SetSize(math.max(1, spot.width), math.max(1, spot.height))
    if art.SetRotation then art:SetRotation(spot.turn) end
  end
  local r, g, b = color[3], color[4], color[5]
  piece.lit:SetVertexColor(r, g, b, 1)
  piece.empty:SetVertexColor(r * 0.22, g * 0.22, b * 0.22, 0.8)

  piece.guide:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
  local fill = piece.guide:GetStatusBarTexture()
  piece.clip:ClearAllPoints()
  if vertical then
    piece.clip:SetPoint("BOTTOMLEFT", piece.guide, "BOTTOMLEFT")
    piece.clip:SetPoint("TOPRIGHT", fill, "TOPRIGHT")
  else
    piece.clip:SetPoint("TOPLEFT", piece.guide, "TOPLEFT")
    piece.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
  end
  piece.clip:SetFrameLevel(piece.box:GetFrameLevel() + 1)
  ShowPiece(piece, true)
end

-- How full is full ------------------------------------------------------------------------------

local peaks = {}     -- unit -> { peak = the shield's size, last = the last amount read }
local byGUID = {}    -- target GUID -> its peaks, for targets you come back to
local guidOrder = {} -- oldest to newest GUIDs kept in byGUID
local guidIndex = {} -- GUID -> index in guidOrder
local GUID_CACHE_LIMIT = 256
local targetGUID

local function ForgetGUID(guid)
  local index = guidIndex[guid]
  if not index then return end
  table.remove(guidOrder, index)
  guidIndex[guid] = nil
  for i = index, #guidOrder do
    guidIndex[guidOrder[i]] = i
  end
end

local function RememberGUID(guid, state)
  if not guid then return end
  if not state then
    byGUID[guid] = nil
    ForgetGUID(guid)
    return
  end
  byGUID[guid] = state
  local index = guidIndex[guid]
  if index then
    table.remove(guidOrder, index)
    for i = index, #guidOrder do
      guidIndex[guidOrder[i]] = i
    end
  end
  guidOrder[#guidOrder + 1] = guid
  guidIndex[guid] = #guidOrder
  while #guidOrder > GUID_CACHE_LIMIT do
    local oldest = table.remove(guidOrder, 1)
    if oldest then
      guidIndex[oldest] = nil
      byGUID[oldest] = nil
    end
    for i = 1, #guidOrder do
      guidIndex[guidOrder[i]] = i
    end
  end
end

local CharacterKey = ns.CharacterKey

-- The biggest shield seen on this character, for shields first seen in combat.
local function Biggest()
  local key = CharacterKey()
  return key and CombatHUDDB and CombatHUDDB.shieldPeaks and CombatHUDDB.shieldPeaks[key]
end

local function RememberBiggest(amount)
  local key = CharacterKey()
  if not key or not CombatHUDDB then return end
  CombatHUDDB.shieldPeaks = CombatHUDDB.shieldPeaks or {}
  CombatHUDDB.shieldPeaks[key] = math.max(CombatHUDDB.shieldPeaks[key] or 0, amount)
end

-- Shield sizes when cast, by spell ID (each rank has its own).
local function CastSizes()
  local key = CharacterKey()
  if not key or not CombatHUDDB then return {} end
  CombatHUDDB.shieldCasts = CombatHUDDB.shieldCasts or {}
  CombatHUDDB.shieldCasts[key] = CombatHUDDB.shieldCasts[key] or {}
  return CombatHUDDB.shieldCasts[key]
end

-- The number in a spell's tooltip ("absorbing 302 damage"), if it says one.
local function TooltipSize(spellID)
  if not C_Spell.GetSpellDescription then return end
  local ok, text = pcall(C_Spell.GetSpellDescription, spellID)
  if not ok or issecret(text) or type(text) ~= "string" then return end
  return tonumber(text:match("[Aa]bsorb%a*%s+(%d+)"))
end

local function CastSize(spellID)
  return CastSizes()[spellID] or TooltipSize(spellID)
end

-- A shield aura's first value, when it can be read: what it absorbed when
-- cast, gear bonuses included (the tooltip may leave those out).
-- Returns a number, "secret", or nil (no value).
local function AuraValue(aura)
  local points = aura.points
  if issecret(points) then return "secret" end
  if type(points) ~= "table" then return end
  local value = points[1]
  if issecret(value) then return "secret" end
  if type(value) == "number" and value > 0 then return value end
end

-- Your aura of this spell on the unit, or nil.
local function MyAura(unit, spellID)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  for index = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL|PLAYER")
    if not ok or issecret(aura) or not aura then return end
    if not issecret(aura.spellId) and aura.spellId == spellID then return aura end
  end
end

local function AuraSize(unit, spellID)
  local aura = MyAura(unit, spellID)
  local value = aura and AuraValue(aura)
  if type(value) == "number" then return value end
end

local SHIELD_NAMES = {
  ["Power Word: Shield"] = true, ["Ice Barrier"] = true, ["Mana Shield"] = true, ["Fire Ward"] = true,
  ["Frost Ward"] = true, ["Shadow Ward"] = true, ["Sacred Shield"] = true, ["Sacrifice"] = true,
}

-- Only shields are matched with absorb changes: a known shield, or a spell
-- whose tooltip says it absorbs.
local function IsShield(spellID)
  local name = C_Spell.GetSpellName(spellID)
  if not issecret(name) and name and SHIELD_NAMES[name] then return true end
  return TooltipSize(spellID) ~= nil
end

-- Your shields' spell IDs: every one measured, and the rank you know of each named shield.
local function MyShieldIDs()
  local ids = {}
  for spellID in pairs(CastSizes()) do ids[spellID] = true end
  for name in pairs(SHIELD_NAMES) do
    local info = C_Spell.GetSpellInfo(name)
    if info and not issecret(info.spellID) and info.spellID then ids[info.spellID] = true end
  end
  if not next(ids) then ids[17] = true end -- Power Word: Shield, so the filter is never empty
  return ids
end

-- Matching your cast with the absorb change it causes, whichever comes first:
-- a change up to a second after the cast, or a cast just after the change.
local CAST_WINDOW, LATE_CAST = 1, 0.3
local lastCast        -- { spellID, time, used }
local lastChange = {} -- unit -> GetTime() of its last absorb change (secret ones too)

local function RecentCast()
  if lastCast and not lastCast.used and GetTime() - lastCast.time <= CAST_WINDOW then return lastCast end
end

-- Readable: the rise is this shield (all of it unless another one was up; a
-- measurement on top of another shield doesn't replace a clean one).
local function LearnSize(state, cast)
  cast.used = true
  local sizes, before = CastSizes(), state.before or 0
  if before == 0 or not sizes[cast.spellID] then sizes[cast.spellID] = state.last - before end
  state.peak, state.mine = state.last, true
end

-- Secret: full is the shield aura's own value if it can be read, else its
-- measured size, else the number in its tooltip.
local function UseSize(unit, cast)
  cast.used = true
  local size = AuraSize(unit, cast.spellID) or CastSize(cast.spellID)
  if not size then return end
  local state = peaks[unit] or {}
  peaks[unit] = state
  state.peak, state.mine = size, true
end

-- The known shields on a unit (anyone's on you, only yours on the target),
-- their sizes added up: 0 when there are none, nil when the game hides its auras.
local function ShieldsOn(unit)
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
  local filter = unit == "player" and "HELPFUL" or "HELPFUL|PLAYER"
  local total = 0
  for index = 1, 40 do
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if not ok or issecret(aura) then return end
    if not aura then break end
    local id = aura.spellId
    if issecret(id) then return end
    if id and IsShield(id) then
      local value = AuraValue(aura)
      local size = type(value) == "number" and value or CastSize(id)
      if size then total = total + size end
    end
  end
  return total
end

local function AbsorbChanged(unit)
  lastChange[unit] = GetTime()
  if not issecret(UnitGetTotalAbsorbs(unit)) then return end -- readable: FullAmount sees it
  local cast = RecentCast()
  if cast then
    UseSize(unit, cast)
    return
  end
  -- A shield someone else cast (or one of yours seen late): the shields on
  -- the unit, if the game shows them. Only grows while one is up, in case
  -- the game's values count down as they absorb.
  local size = ShieldsOn(unit)
  if not size then return end
  local state = peaks[unit] or {}
  peaks[unit] = state
  if size == 0 then
    state.peak, state.mine = nil, nil
  elseif not state.peak or size > state.peak then
    state.peak = size
  end
end

ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if issecret(spellID) or not spellID or not UnitGetTotalAbsorbs or not next(active) then return end
  if not IsShield(spellID) then return end
  local now = GetTime()
  lastCast = { spellID = spellID, time = now }
  -- The shield showed up just before the cast event did.
  for unit, time in pairs(lastChange) do
    if not lastCast.used and now - time <= LATE_CAST then
      local state = peaks[unit]
      if issecret(UnitGetTotalAbsorbs(unit)) then
        UseSize(unit, lastCast)
      elseif state and state.riseTime and now - state.riseTime <= LATE_CAST then
        LearnSize(state, lastCast)
      end
    end
  end
end)

-- A full bar, as a plain number (each piece's range is worked out from it).
local function FullAmount(element, amount)
  local unit = element.unit

  local state = peaks[unit] or {}
  peaks[unit] = state
  if not issecret(amount) then
    if amount <= 0 then
      state.peak, state.last, state.mine = nil, 0, nil
    else
      local rise = amount > (state.last or 0)
      if rise then state.before, state.riseTime = state.last or 0, GetTime() end
      state.last = amount
      local cast = rise and RecentCast()
      if cast then
        LearnSize(state, cast)
      elseif not state.peak or (rise and not (unit ~= "player" and state.mine)) then
        -- Someone else's shield going up: full too, except on the target,
        -- where yours set it.
        state.peak = amount
      end
      if unit == "player" then RememberBiggest(amount) end
    end
  end
  -- Never measured: your biggest shield, else what is currently up.
  if state.peak then return state.peak end
  if not issecret(amount) and type(amount) == "number" and amount > 0 then return amount end
  return Biggest() or 1
end

-- Updating -----------------------------------------------------------------------------------

local function SetPieces(element, full, amount)
  if full ~= element.fullAmount then
    element.fullAmount = full
    for index = 1, element.count do
      element.pieces[index].guide:SetMinMaxValues((index - 1) * full / element.count, index * full / element.count)
    end
  end
  for index = 1, element.count do
    ns.Try("absorb piece", element.pieces[index].guide.SetValue, element.pieces[index].guide, amount)
  end
  ns.Try("absorb presence", element.presence.SetValue, element.presence, amount)
end

function Absorb.Update(element)
  if not UnitGetTotalAbsorbs then
    SetPieces(element, 1, 0)
    element.text:SetText(ns.editMode and "No absorb data on this client" or "")
    return
  end
  local unit = element.unit
  local amount = 0
  local exists = UnitExists(unit)
  if issecret(exists) or exists then amount = UnitGetTotalAbsorbs(unit) end
  if not issecret(amount) then amount = amount or 0 end
  local full = FullAmount(element, amount)

  -- Edit mode without a shield: show it part full, to see the look.
  if ns.editMode and not issecret(amount) and amount <= 0 then
    if full <= 1 then full = 100 end
    SetPieces(element, full, full * 0.7)
    element.text:SetText(element.showText and "Shield" or "")
    return
  end
  SetPieces(element, full, amount)
  if element.showText then
    ns.SetNumberText(element.text, "%d", amount)
  else
    element.text:SetText("")
  end
end

local function UpdateAll()
  for _, element in pairs(active) do Absorb.Update(element) end
end

-- The target's gate: a hidden aura group of your shields on the unit,
-- area-wide while one is up and 1 px wide otherwise.
local GATE = "MyShields"

local function EnsureGate(element, width, height, fontSize)
  element.gateWidth = width + 80 + 1 -- the presence area (see Build), plus the pixel it starts left of it
  element.gateHeight = height + 6 + fontSize + 12
  if element.gate then return element.gate end
  local gate = ns.Aura.NewContainer(element)
  local ok, err = pcall(gate.AddAuraGroup, gate, GATE, "HELPFUL|PLAYER", {
    candidateFilters = { includeSpellIDs = MyShieldIDs() }, maxFrameCount = 1,
    layout = { elementWidth = element.gateWidth, elementHeight = element.gateHeight },
    -- Draws nothing; only its width matters.
    initializeFrame = function(button)
      button:EnableMouse(false)
      pcall(button.SetSize, button, element.gateWidth, element.gateHeight)
    end,
  })
  if not ok then
    ns.Print("Couldn't watch your shields on the target: " .. tostring(err))
    ns.Aura.Unbind(gate)
    return
  end
  element.gate = gate
  return gate
end

-- frame: the bar; length, thickness: scaled sizes (see Absorb.Size).
function Absorb.Build(frame, config, length, thickness, scale)
  local element = frame.absorbElement or Create(frame)
  element.unit = config.unit or "player"
  element.showText = config.text ~= "none"
  element:SetFrameLevel(frame:GetFrameLevel() + 1)

  local pieces, width, height, look = Pieces(config, length, thickness, scale)
  local vertical = config.orientation == "VERTICAL"
  local texture = ns.BarTexture()
  if look == "segments" then texture = ART .. (vertical and "pill_h" or "pill_v") end
  local color = ns.Find(Absorb.COLORS, config.color)
  for index, spot in ipairs(pieces) do
    local piece = element.pieces[index] or NewPiece(element)
    element.pieces[index] = piece
    PlacePiece(element, piece, spot, texture, color, vertical)
  end
  for index = #pieces + 1, #element.pieces do ShowPiece(element.pieces[index], false) end
  element.count, element.fullAmount = #pieces, nil

  -- A plain straight bar keeps its thin black border.
  element.border:ClearAllPoints()
  element.border:SetPoint("TOPLEFT", element.pieces[1].box, "TOPLEFT", -1, 1)
  element.border:SetPoint("BOTTOMRIGHT", element.pieces[1].box, "BOTTOMRIGHT", 1, -1)
  element.border:SetShown(#pieces == 1)

  -- The amount under the bar: below its first piece when standing, below its middle when lying.
  local fontSize = math.max(9, math.min(18, math.floor(thickness * (vertical and 0.7 or 0.9))))
  element.text:SetFont(ns.Font(), fontSize, "OUTLINE")
  element.text:ClearAllPoints()
  if vertical then
    element.text:SetPoint("TOP", element.pieces[1].box, "BOTTOM", 0, -3)
  else
    element.text:SetPoint("TOP", element, "BOTTOM", 0, -3)
  end
  element.overlay:SetFrameLevel(element:GetFrameLevel() + 6)

  -- Room around the bar for the text, then the clip: following the hidden
  -- presence bar's fill when it should hide without a shield.
  element.presence:ClearAllPoints()
  element.presence:SetPoint("TOPLEFT", element, "TOPLEFT", -40, 6)
  element.presence:SetPoint("BOTTOMRIGHT", element, "BOTTOMRIGHT", 40, -(fontSize + 12))
  element.content:ClearAllPoints()
  if element.gate then ns.Aura.Unbind(element.gate) end
  local gate = element.unit ~= "player" and not ns.editMode and ns.Aura.Ready() and EnsureGate(element, width, height, fontSize)
  if gate then
    -- Your shield down: the gate is 1 px wide, ending where the bar's area
    -- starts, so the clip is closed. Up: it spans the area.
    ns.Try("shield gate spells", gate.SetAuraGroupCandidateFilters, gate, GATE, { includeSpellIDs = MyShieldIDs() })
    ns.Try("shield gate layout", gate.SetAuraGroupLayout, gate, GATE,
      { elementWidth = element.gateWidth, elementHeight = element.gateHeight })
    if gate.SetAuraGroupEnabled then ns.Try("shield gate enable", gate.SetAuraGroupEnabled, gate, GATE, true) end
    gate:ClearAllPoints()
    gate:SetPoint("TOPLEFT", element.presence, "TOPLEFT", -1, 0)
    gate:SetFrameLevel(element:GetFrameLevel())
    if ns.Try("shield gate unit", ns.Aura.Bind, gate, element.unit) then
      table.insert(ns.activeAuras, { unit = element.unit, container = gate, natives = {} })
    end
    element.content:SetPoint("TOPRIGHT", gate, "TOPRIGHT")
    element.content:SetPoint("BOTTOMLEFT", element.presence, "BOTTOMLEFT")
  elseif config.hideEmpty ~= false and not ns.editMode then
    element.content:SetPoint("TOPLEFT", element.presence, "TOPLEFT")
    element.content:SetPoint("BOTTOMRIGHT", element.presence:GetStatusBarTexture(), "BOTTOMRIGHT")
  else
    element.content:SetAllPoints(element.presence)
  end

  element:Show()
  active[frame] = element
  if not UnitGetTotalAbsorbs and not warned then
    warned = true
    ns.Print("This client doesn't report shield absorb amounts, so absorb bars stay empty.")
  end
  Absorb.Update(element)
end

function Absorb.Hide(frame)
  local element = frame.absorbElement
  if element then
    if element.gate then ns.Aura.Unbind(element.gate) end
    element:Hide()
  end
  active[frame] = nil
end

-- What the game reports, for /chud debug shield.
function Absorb.PrintDiag()
  if not UnitGetTotalAbsorbs then
    ns.Print("This client has no UnitGetTotalAbsorbs, so shield bars can't work.")
    return
  end
  local amount, health = UnitGetTotalAbsorbs("player"), UnitHealthMax("player")
  local state = peaks.player or {}
  local function Show(value) return issecret(value) and "secret" or tostring(value) end
  ns.Print(("Shield absorb now: %s. Max health: %s. In combat: %s."):format(
    Show(amount), Show(health), tostring(InCombatLockdown())))
  ns.Print(("Full bar now: %s."):format(tostring(state.peak)))
  if issecret(amount) and not InCombatLockdown() then
    ns.Print("The game hides shield amounts even out of combat, so a full bar comes from the shield's buff or its tooltip.")
  end

  -- Each of your shields up on you: what its buff and its tooltip say it absorbs.
  local found
  for spellID in pairs(MyShieldIDs()) do
    local aura = MyAura("player", spellID)
    if aura then
      found = true
      ns.Print(("%s (%d): buff says %s, tooltip says %s."):format(tostring(C_Spell.GetSpellName(spellID)), spellID,
        tostring(AuraValue(aura) or "nothing"), tostring(TooltipSize(spellID) or "nothing")))
    end
  end
  if not found then ns.Print("None of your shields is on you right now (or its buff can't be read): cast one and try again.") end

  local sizes = {}
  for spellID, size in pairs(CastSizes()) do
    sizes[#sizes + 1] = ("%s (%d): %d"):format(tostring(C_Spell.GetSpellName(spellID)), spellID, size)
  end
  if #sizes > 0 then ns.Print("Measured shield sizes: " .. table.concat(sizes, ", ")) end
end

-- Updates come from their own frame: these unit events are wanted for both
-- the player and the target.
local events = CreateFrame("Frame")
for _, event in ipairs({ "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_AURA" }) do
  pcall(events.RegisterUnitEvent, events, event, "player", "target")
end
pcall(events.RegisterEvent, events, "PLAYER_TARGET_CHANGED")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_TARGET_CHANGED" then
    if targetGUID then RememberGUID(targetGUID, peaks.target) end
    local guid = UnitGUID("target")
    targetGUID = not issecret(guid) and guid or nil
    peaks.target = targetGUID and byGUID[targetGUID] or nil
  end
  if not next(active) then return end
  if event == "UNIT_ABSORB_AMOUNT_CHANGED" and unit then AbsorbChanged(unit) end
  ns.Schedule(UpdateAll)
end)
