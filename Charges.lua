-- Charge bars: one piece per charge of a buff of yours (Lightning Shield's
-- orbs, say), drawn as plain segments, orbs, gems or the spell's icon. The
-- orb and gem art is drawn by tools/make_charge_art.py into Media\Charges.
--
-- The count is secret in combat, so the game does the counting: one of its
-- aura buttons fills an invisible status bar from the aura's stack count
-- (SetApplicationBar). Every charge has an "empty" piece underneath that's
-- always drawn, and a "lit" piece on top inside a clipping frame that ends at
-- the bar's fill edge. With 2 of 3 charges the fill reaches the gap after the
-- second piece, so two lit pieces show over three empty ones. The lit pieces
-- live inside the game's button, so they vanish when the buff does.
local _, ns = ...

local Charges = {}
ns.Charges = Charges

local SLOT = "Charges"
local WHITE = ns.WHITE
local ART = ns.MEDIA .. "Charges\\"
local COLOR = { 0.35, 0.65, 1 }

-- Orb themes and gem colors: { key, label }.
Charges.ORBS = {
  { "lightning", "Lightning" }, { "water", "Water" }, { "fire", "Fire" }, { "nature", "Nature" },
  { "arcane", "Arcane" }, { "shadow", "Shadow" }, { "holy", "Holy" }, { "frost", "Frost" },
}
Charges.GEMS = {
  { "red", "Red" }, { "yellow", "Yellow" }, { "green", "Green" },
  { "blue", "Blue" }, { "purple", "Purple" }, { "white", "White" },
}


-- The texture of a lit or spent piece: look "orbs" with a theme, or "gems"
-- with a color. nil for the looks drawn otherwise (segments, the spell icon).
function Charges.Texture(look, style, lit)
  if look == "orbs" then
    return ART .. "orb_" .. ns.Find(Charges.ORBS, style)[1] .. (lit and "_full" or "_empty")
  elseif look == "gems" then
    return ART .. (lit and "gem_" .. ns.Find(Charges.GEMS, style)[1] or "gem_empty")
  end
end

local retired = CreateFrame("Frame")
retired:Hide()
local pool

-- Width of one piece and the distance from one piece to the next.
local function Geometry(holder)
  local piece = holder.height
  if holder.look == "bar" then
    piece = (holder.width - (holder.pips - 1) * holder.gap) / holder.pips
  end
  return piece, piece + holder.gap
end

local function StylePiece(texture, holder, lit)
  texture:SetDesaturated(false)
  texture:SetAlpha(1)
  texture:SetVertexColor(1, 1, 1, 1)
  texture:SetTexCoord(0, 1, 0, 1)
  local art = Charges.Texture(holder.look, holder.look == "gems" and holder.gem or holder.orb, lit)
  if art then
    texture:SetTexture(art)
  elseif holder.look == "icon" then
    texture:SetTexture(holder.texture)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if not lit then
      texture:SetDesaturated(true)
      texture:SetAlpha(0.45)
    end
  else
    texture:SetTexture(ns.BarTexture())
    if lit then
      texture:SetVertexColor(COLOR[1], COLOR[2], COLOR[3], 1)
    else
      texture:SetVertexColor(COLOR[1] * 0.18, COLOR[2] * 0.18, COLOR[3] * 0.18, 0.9)
    end
  end
end

local function PlacePiece(texture, holder, index, piece, step)
  texture:ClearAllPoints()
  texture:SetSize(piece, holder.height)
  texture:SetPoint("TOPLEFT", holder, "TOPLEFT", (index - 1) * step, 0)
  texture:Show()
end

local function Create()
  local holder = CreateFrame("Frame", nil, UIParent)
  holder:EnableMouse(false)
  holder.empties, holder.borders = {}, {}
  holder.overlay = CreateFrame("Frame", nil, holder) -- the edit-mode label, above everything
  holder.overlay:SetAllPoints()
  holder.label = holder.overlay:CreateFontString(nil, "OVERLAY")
  holder.label:SetPoint("CENTER")
  holder.label:SetShadowColor(0, 0, 0, 1)
  holder.label:SetShadowOffset(1, -1)
  return holder
end

-- The empty pieces (and, for segments and icons, a black border around each).
local function DrawEmpties(holder)
  local piece, step = Geometry(holder)
  local bordered = holder.look == "bar" or holder.look == "icon"
  for index = 1, holder.pips do
    local border = holder.borders[index] or holder:CreateTexture(nil, "BACKGROUND", nil, -1)
    holder.borders[index] = border
    border:SetColorTexture(0, 0, 0, 1)
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", holder, "TOPLEFT", (index - 1) * step - 1, 1)
    border:SetSize(piece + 2, holder.height + 2)
    border:SetShown(bordered)
    local empty = holder.empties[index] or holder:CreateTexture(nil, "BACKGROUND")
    holder.empties[index] = empty
    StylePiece(empty, holder, false)
    PlacePiece(empty, holder, index, piece, step)
  end
  for index = holder.pips + 1, #holder.empties do
    holder.empties[index]:Hide()
    holder.borders[index]:Hide()
  end
end

-- The game's button for the buff: the guide bar it fills, the clip that
-- follows the fill, the lit pieces inside it, and the count.
local function BuildNative(button)
  local native = { button = button, lits = {} }
  button:EnableMouse(false)
  native.bar = CreateFrame("StatusBar", nil, button)
  native.bar:SetStatusBarTexture(WHITE)
  native.bar:SetStatusBarColor(0, 0, 0, 0)
  native.bar:SetAlpha(0) -- only its fill edge is used
  -- Anchored to a bar inside the game's aura button, so it has to opt out of
  -- untrusted layout scripts.
  native.clip = CreateFrame("Frame", nil, button, "DisableUntrustedLayoutScriptsTemplate")
  native.clip:SetClipsChildren(true)
  native.clip:EnableMouse(false)
  native.count = button:CreateFontString(nil, "OVERLAY")
  native.count:SetShadowColor(0, 0, 0, 1)
  native.count:SetShadowOffset(1, -1)
  return native
end

local function Configure(holder, native)
  local button = native.button
  local piece, step = Geometry(holder)
  pcall(button.SetSize, button, holder.width, holder.height)
  if holder.part and holder.part.slot then
    pcall(button.ClearAllPoints, button)
    pcall(button.SetPoint, button, "CENTER", holder, "CENTER")
  end

  -- The guide bar starts half a gap before the first piece and is one step
  -- per charge long, so with n charges its fill ends halfway through the gap
  -- after piece n.
  local bar = native.bar
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", holder, "TOPLEFT", -holder.gap / 2, 0)
  bar:SetSize(holder.pips * step, holder.height)
  native.clip:ClearAllPoints()
  native.clip:SetPoint("TOPLEFT", bar, "TOPLEFT")
  native.clip:SetPoint("BOTTOMRIGHT", bar:GetStatusBarTexture(), "BOTTOMRIGHT")
  native.clip:SetFrameLevel(button:GetFrameLevel() + 2)

  for index = 1, holder.pips do
    local lit = native.lits[index] or native.clip:CreateTexture(nil, "ARTWORK")
    native.lits[index] = lit
    StylePiece(lit, holder, true)
    PlacePiece(lit, holder, index, piece, step)
  end
  for index = holder.pips + 1, #native.lits do native.lits[index]:Hide() end

  native.count:ClearAllPoints()
  native.count:SetPoint("LEFT", holder, "RIGHT", 4, 0)
  native.count:SetFont(ns.Font(), math.max(9, math.min(holder.height, 20)), "OUTLINE")
  if button.ClearApplicationBar then pcall(button.ClearApplicationBar, button) end
  ns.Try("charge bar", button.SetApplicationBar, button, bar, { maxApplications = holder.pips })
  if button.ClearApplicationCount then pcall(button.ClearApplicationCount, button) end
  if holder.showCount then
    native.count:Show()
    ns.Try("charge count", button.SetApplicationCount, button, native.count)
  else
    native.count:Hide()
  end
end

local function EnsurePart(holder, filter, candidates)
  local part = holder.part
  if part then
    local container = part.container
    if part.slot then
      ns.Try("charge filter", container.SetAuraSlotFilterString, container, SLOT, filter)
      ns.Try("charge spells", container.SetAuraSlotCandidateFilters, container, SLOT, candidates)
      if container.SetAuraSlotEnabled then ns.Try("charge enable", container.SetAuraSlotEnabled, container, SLOT, true) end
    else
      ns.Try("charge filter", container.SetAuraGroupFilterString, container, SLOT, filter)
      ns.Try("charge spells", container.SetAuraGroupCandidateFilters, container, SLOT, candidates)
      ns.Try("charge layout", container.SetAuraGroupLayout, container, SLOT,
        { elementWidth = holder.width, elementHeight = holder.height })
      if container.SetAuraGroupEnabled then ns.Try("charge enable", container.SetAuraGroupEnabled, container, SLOT, true) end
    end
    return part
  end

  part = {}
  holder.part = part
  local container = ns.Aura.NewContainer(holder)
  container:SetPoint("TOPLEFT", holder, "TOPLEFT")
  part.container = container
  local function Init(button)
    part.native = BuildNative(button)
    Configure(holder, part.native)
  end
  if container.AddAuraSlot and pcall(container.AddAuraSlot, container, SLOT, filter,
      { candidateFilters = candidates, initializeFrame = Init }) and part.native then
    part.slot = true
  else
    part.native = nil
    local ok, err = pcall(container.AddAuraGroup, container, SLOT, filter, {
      candidateFilters = candidates, maxFrameCount = 1,
      layout = { elementWidth = holder.width, elementHeight = holder.height },
      initializeFrame = Init,
    })
    if not ok then
      ns.Print("Couldn't create a charge bar: " .. tostring(err))
      ns.Aura.Unbind(container)
      holder.part = nil
      return
    end
    if container.SetAuraGroupEnabled then ns.Try("charge enable", container.SetAuraGroupEnabled, container, SLOT, true) end
  end
  return part
end

local function ResetPooled(holder)
  if holder.part then ns.Aura.Unbind(holder.part.container) end
  holder:Hide()
  holder:ClearAllPoints()
end

pool = ns.CreatePool(Create, ResetPooled, retired)

function Charges.Acquire(parent)
  return pool.Acquire(parent)
end

function Charges.Release(holder)
  pool.Release(holder)
end

function Charges.Name(holder)
  return holder.spellName or "charges"
end

function Charges.Setup(holder, entry, opts)
  if not ns.Aura.Ready() then return false end
  local iconSpell = ns.Aura.IconSpell(entry)
  if not iconSpell then return false end
  local bar = holder.bar
  holder.entry, holder.opts, holder.kind = entry, opts, "charges"
  holder.width, holder.height = bar.itemWidth, bar.itemHeight
  holder.pips = math.max(1, math.floor(opts.pips or 3))
  holder.gap = math.max(0, math.floor(opts.chargeGap or 3))
  holder.look = opts.chargeLook or "bar"
  holder.orb, holder.gem = opts.chargeOrb, opts.chargeGem
  holder.showCount = opts.numbers ~= false
  holder.spellName = ns.Aura.SpellName(iconSpell)
  holder.texture = C_Spell.GetSpellTexture(iconSpell)
  holder:SetSize(holder.width, holder.height)
  DrawEmpties(holder)
  holder.label:SetFont(ns.Font(), math.max(8, math.min(holder.height - 2, 14)), "")
  holder.label:SetText(ns.editMode and (holder.spellName or "") or "")

  local filter = ns.Aura.Filter(entry, "player")
  local candidates = { includeSpellIDs = ns.Aura.SpellIDs(entry) }
  local part = EnsurePart(holder, filter, candidates)
  if not part then return false end
  part.container:SetFrameLevel(holder:GetFrameLevel() + 1)
  holder.overlay:SetFrameLevel(holder:GetFrameLevel() + 8)
  if part.native then Configure(holder, part.native) end
  if not ns.Try("charge unit", ns.Aura.Bind, part.container, "player") then return false end
  table.insert(ns.activeAuras, { unit = "player", container = part.container, name = holder.spellName, natives = { part.native } })
  holder:Show()
  return true
end

-- How wide a charge bar is: its width setting for segments; for orbs, gems
-- and icons, square pieces as tall as the bar, plus the gaps.
function Charges.Width(opts, height, width)
  if (opts.chargeLook or "bar") == "bar" then return width end
  local pips, gap = math.max(1, math.floor(opts.pips or 3)), math.max(0, math.floor(opts.chargeGap or 3))
  return pips * height + (pips - 1) * gap
end
