-- Bars: rows or columns of buttons placed relative to the screen center, and
-- edit mode (/chud edit): drag a bar by its name to move it, drag its buttons
-- to rearrange them (or onto another bar), drop spells or items on it to add
-- buttons, right-click a button or the bar for its options.
local _, ns = ...

local Bar = {}
ns.Bar = Bar
ns.activeButtons = {} -- every button on screen, across all bars

local frames = {} -- bar frames, reused by position in the profile
local Layout, Options -- defined further down
local StartHold, EndHold -- dragging a button, further down
local profileMover

-- The point of the bar that stays put as it grows.
local ANCHORS = { CENTER = "CENTER", RIGHT = "LEFT", LEFT = "RIGHT", DOWN = "TOP", UP = "BOTTOM" }

local EDIT_HINT = "Click a button for its options, or drag it to move it, here or onto another bar. Drag the bar by its name (or an empty part of it); the gear on its name changes its size. Drop spells or items here to add them. Hold Shift or Alt while dropping one on a button to combine them (swap its icon on a proc, or stack them on a shared cooldown). Right-click the bar for its own options."

local function Grow(config)
  local grow = config.grow
  if config.orientation == "VERTICAL" then
    if grow ~= "UP" and grow ~= "DOWN" then grow = "CENTER" end
  elseif grow ~= "LEFT" and grow ~= "RIGHT" then
    grow = "CENTER"
  end
  return grow
end

-- Where a frame's anchor point is, as an offset from the screen center.
local function OffsetOf(frame, anchor)
  local left, bottom, width, height = frame:GetRect()
  local x, y = left + width / 2, bottom + height / 2
  if anchor:find("LEFT") then x = left elseif anchor:find("RIGHT") then x = left + width end
  if anchor:find("BOTTOM") then y = bottom elseif anchor:find("TOP") then y = bottom + height end
  local centerX, centerY = UIParent:GetCenter()
  return math.floor(x - centerX + 0.5), math.floor(y - centerY + 0.5)
end

function ns.PlaceFrame(frame, config, anchor)
  frame:ClearAllPoints()
  frame:SetPoint(anchor, UIParent, "CENTER", config.x or 0, config.y or 0)
end

-- Gives a frame an edit-mode overlay. Dragging it moves the frame and saves
-- the new position into the frame's config, measured from its anchor point.
-- handlers (all optional): onGear(gear) for the gear on the name tab;
-- onHover(over) each frame while it's shown; and for bars onDrop,
-- onRightClick, onClick (a left click that wasn't a drag), onMouseDown,
-- onDragStart and onDragStop.
function ns.AttachMover(frame, getConfig, getAnchor, handlers)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)

  local mover = CreateFrame("Frame", nil, frame)
  mover:SetAllPoints()
  mover:SetFrameLevel(frame:GetFrameLevel() + 20)
  local fill = mover:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(0.2, 0.6, 1, 0.3)
  mover.hint = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  mover.hint:SetPoint("CENTER")
  mover.hint:Hide()

  local function StartMove()
    frame.isMoving = true
    frame:StartMoving()
  end
  local function StopMove()
    if not frame.isMoving then return end
    frame.isMoving = false
    frame:StopMovingOrSizing()
    local config, anchor = getConfig(), getAnchor()
    config.x, config.y = ns.Snap(OffsetOf(frame, anchor))
    ns.PlaceFrame(frame, config, anchor)
  end

  -- Dragging the overlay moves the frame, unless it picks up a button.
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")
  mover:SetScript("OnDragStart", function()
    mover.dragged = true
    if GetCursorInfo() then return end -- holding a spell: this is a drop, not a move
    if handlers and handlers.onDragStart and handlers.onDragStart() then return end
    StartMove()
  end)
  mover:SetScript("OnDragStop", function()
    if handlers and handlers.onDragStop and handlers.onDragStop() then return end
    StopMove()
  end)

  -- A tab with the frame's name above it: dragging it always moves the frame.
  local grip = CreateFrame("Frame", nil, mover)
  grip:SetPoint("BOTTOM", mover, "TOP", 0, 1)
  grip:SetHeight(14)
  local tab = grip:CreateTexture(nil, "BACKGROUND")
  tab:SetAllPoints()
  tab:SetColorTexture(0.2, 0.6, 1, 0.6)
  mover.label = grip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  mover.label:SetPoint("CENTER")
  -- Quick settings: a gear at the end of the name tab, faint until the
  -- pointer is over the frame.
  local gear
  if handlers and handlers.onGear then
    gear = CreateFrame("Button", nil, grip)
    gear:SetSize(12, 12)
    gear:SetPoint("RIGHT", -2, 0)
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ns.GEAR)
    gear:SetAlpha(0.4)
    gear:SetScript("OnClick", function(self) handlers.onGear(self) end)
    gear:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Size and layout")
      GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mover.label:SetPoint("CENTER", -7, 0)
    mover.gear = gear
  end
  grip:EnableMouse(true)
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", StartMove)
  grip:SetScript("OnDragStop", StopMove)
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Drag to move")
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function mover.SetLabel(text)
    mover.label:SetText(text)
    grip:SetWidth(math.max(30, mover.label:GetStringWidth() + 12 + (gear and 14 or 0)))
  end
  if gear or (handlers and handlers.onHover) then
    mover:SetScript("OnUpdate", function()
      if gear then gear:SetAlpha((mover:IsMouseOver() or grip:IsMouseOver()) and 1 or 0.4) end
      if handlers.onHover then handlers.onHover(mover:IsMouseOver()) end
    end)
  end
  if handlers and handlers.onRightClick then
    grip:SetScript("OnMouseUp", function(_, button)
      if button == "RightButton" then handlers.onRightClick() end
    end)
  end

  if handlers and handlers.onDrop then
    mover:SetScript("OnReceiveDrag", handlers.onDrop)
    -- What's under the cursor is noted when the button goes down: by the time
    -- a drag starts, the cursor has already moved, often onto a neighbour.
    mover:SetScript("OnMouseDown", function(_, button)
      mover.dragged = nil
      if button == "LeftButton" and handlers.onMouseDown then handlers.onMouseDown() end
    end)
    mover:SetScript("OnMouseUp", function(_, button)
      if button == "LeftButton" and GetCursorInfo() then
        handlers.onDrop()
      elseif button == "RightButton" then
        handlers.onRightClick()
      elseif button == "LeftButton" and not mover.dragged and handlers.onClick then
        handlers.onClick()
      end
      mover.dragged = nil
    end)
    mover:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(getConfig().name or "Bar")
      GameTooltip:AddLine(EDIT_HINT, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  mover:Hide()
  frame.mover = mover
end

-- Drag and drop -----------------------------------------------------------------

-- Turns whatever is on the cursor into a button entry, or returns nil and
-- the reason it can't be used.
local function CursorEntry()
  local kind, a, b, c = GetCursorInfo()
  if kind == "spell" then
    local spellID = c
    if type(spellID) ~= "number" and type(a) == "number" and C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
      local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, a, b)
      if ok and type(info) == "table" then spellID = info.spellID end
    end
    if type(spellID) == "number" then return { spell = spellID } end
    return nil, "Couldn't tell which spell that is."
  elseif kind == "item" and type(a) == "number" then
    -- An equipped trinket is tracked by its slot, so swapping trinkets keeps the button.
    for _, slot in ipairs({ 13, 14 }) do
      if GetInventoryItemID("player", slot) == a then return { slot = slot } end
    end
    return { item = a }
  elseif kind == "macro" then
    return nil, "Macros can't be tracked. Drag the spell itself from your spellbook."
  elseif kind then
    return nil, "That can't go on the HUD."
  end
end

-- How far along the bar the cursor is, in button steps from the first button.
-- and on a bar that wraps, which line (0 for the first).
local function CursorStep(frame)
  local scale = frame:GetEffectiveScale()
  local x, y = GetCursorPosition()
  x, y = x / scale, y / scale
  local left, bottom, width, height = frame:GetRect()
  local along, across
  if frame.vertical then
    if frame.grow == "UP" then along = y - bottom else along = bottom + height - y end
    if frame.lineDir == "LEFT" then across = left + width - x else across = x - left end
  else
    if frame.grow == "LEFT" then along = left + width - x else along = x - left end
    if frame.lineDir == "UP" then across = y - bottom else across = bottom + height - y end
  end
  local line = 0
  if (frame.perLine or 0) > 0 then
    local depth = (frame.vertical and frame.itemWidth or frame.itemHeight) + frame.spacing
    line = math.max(0, math.floor(across / depth))
  end
  return along / frame.step, line
end

-- The slot index (0-based) a place on a bar is: along the line, then line by line.
local function CellIndex(frame, step, line)
  local perLine = frame.perLine or 0
  local along = math.floor(step)
  if perLine > 0 then
    along = math.max(0, math.min(along, perLine - 1))
    return line * perLine + along
  end
  return along
end

local held     -- the button being dragged: { frame, btn, configIndex, entry, totem }
local gapFrame -- the bar showing a gap

-- The slot under the cursor: 1 for the first, one past the end beyond the
-- last (not counting a button picked up from this bar).
local function SlotUnderCursor(frame)
  local count = #frame.buttons - ((held and held.frame == frame) and 1 or 0)
  return math.max(1, math.min(CellIndex(frame, CursorStep(frame)) + 1, count + 1))
end

-- Opens a gap in a bar's slot (closing any other), or closes it with no frame.
local function SetGap(frame, slot)
  if gapFrame and gapFrame ~= frame then
    gapFrame.gapAt = nil
    Layout(gapFrame, true)
  end
  gapFrame = frame
  if frame and frame.gapAt ~= slot then
    frame.gapAt = slot
    Layout(frame, true)
  end
end

-- The button under the cursor, or nil over a gap or empty space.
local function ButtonUnderCursor(frame)
  local step, line = CursorStep(frame)
  if step < 0 then return end
  if (frame.perLine or 0) > 0 and math.floor(step) >= frame.perLine then return end
  local btn = frame.buttons[CellIndex(frame, step, line) + 1]
  local extent = frame.vertical and frame.itemHeight or frame.itemWidth
  if not btn or (step - math.floor(step)) * frame.step > extent then return end
  return btn
end

local function Drop(frame)
  if not GetCursorInfo() then return end
  if Bar.Type(frame.config) == "totems" then
    ClearCursor()
    ns.Print("The totem bar fills itself: drop a totem in the world and it shows in its element's slot.")
    return
  end
  if Bar.Type(frame.config) == "weapons" then
    ClearCursor()
    ns.Print("The weapon bar fills itself: a slot for each hand holding a weapon.")
    return
  end
  local entry, problem = CursorEntry()
  ClearCursor()
  if not entry then
    if problem then ns.Print(problem) end
    return
  end
  local kind = Bar.Type(frame.config)
  if kind == "charges" then
    if entry.item or entry.slot then
      ns.Print("Buff With Charges only takes spells that apply a buff with charges.")
      return
    end
    if #(frame.config.buttons or {}) >= 1 then
      ns.Print("Buff With Charges only allows one spell.")
      return
    end
    local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local found = false
    if entry.spell and getAura then
      local ids = { [entry.spell] = true }
      local name = C_Spell.GetSpellName(entry.spell)
      for _, linked in ipairs((name and ns.Learn.Linked(name)) or {}) do ids[linked] = true end
      for index = 1, 40 do
        local ok, aura = pcall(getAura, "player", index, "HELPFUL|PLAYER")
        if not ok or not aura or issecret(aura.spellId) then break end
        if ids[aura.spellId] then
          local apps = aura.applications
          if type(apps) == "number" and apps > 0 then
            found = true
            entry = { aura = { aura.spellId }, pips = math.max(1, math.floor(apps)) }
          end
          break
        end
      end
    end
    if not found then
      ns.Print("That spell must be added while its charge buff is active (with visible stacks/charges).")
      return
    end
  end
  -- Shift or Alt held over a button: ask how to combine them.
  local onto = (IsShiftKeyDown() or IsAltKeyDown()) and ButtonUnderCursor(frame)
  if onto and onto.entry then
    ns.EditMenu.Combine(frame, onto, entry)
    return
  end
  if Bar.Full(frame.config) then
    ns.Print(("%s is full (%d buttons). Raise its limit on its Layout tab in /chud."):format(
      frame.config.name or "This bar", frame.config.maxButtons))
    return
  end
  -- A spell that shares a cooldown with a button already here stacks onto it.
  -- (Holding Shift while dropping offers "Put it next to" instead.)
  local family = entry.spell and Bar.Type(frame.config) == "cooldowns"
    and ns.Groups.FamilyButton(frame.config.buttons, entry.spell)
  if family then
    SetGap(nil)
    ns.Groups.Add(family, entry)
    ns.Rebuild(true)
    ns.Options.Refresh()
    ns.Print(("%s shares a cooldown with a button on this bar, so it went on that button. To put it next to it instead, hold Shift while you drop it."):format(
      tostring(C_Spell.GetSpellName(entry.spell))))
    return
  end
  -- Insert in the gap: the slot under the cursor.
  local position = frame.gapAt or SlotUnderCursor(frame)
  SetGap(nil)
  local target = frame.buttons[position]
  local configIndex = target and target.configIndex or #frame.config.buttons + 1
  ns.InsertButton(frame.config, configIndex, entry)

  -- On a buff bar the ability's own ID may not be its buff's ID.
  if entry.spell and (kind == "buffs" or kind == "alerts" or kind == "charges") then
    local name = C_Spell.GetSpellName(entry.spell)
    if name and not ns.Learn.Linked(name) then
      ns.Print(("If %s's buff doesn't show while it's up, cast %s once out of combat and CHUDForever will learn which buff it gives."):format(name, name))
    end
  end
end

local function OpenMenu(frame)
  local btn = ButtonUnderCursor(frame)
  if btn then
    ns.EditMenu.ForButton(frame, btn)
  else
    ns.EditMenu.ForBar(frame)
  end
end

-- The button under the pointer in edit mode: highlighted, with a gear in its
-- corner (a click opens its menu). One for the whole HUD.
local hover

local function ShowHover(frame, btn)
  if not btn then
    if hover and hover.frame == frame then
      hover:Hide()
      hover.frame = nil
    end
    return
  end
  if not hover then
    hover = CreateFrame("Frame")
    hover:EnableMouse(false)
    local shade = hover:CreateTexture(nil, "ARTWORK")
    shade:SetAllPoints()
    shade:SetColorTexture(1, 1, 1, 0.12)
    hover.edges = {}
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local edge = hover:CreateTexture(nil, "OVERLAY")
      edge:SetColorTexture(1, 0.82, 0.2, 0.9)
      edge:SetPoint(side[1])
      edge:SetPoint(side[2])
      if side[1] == "TOPLEFT" and side[2] == "BOTTOMLEFT" or side[1] == "TOPRIGHT" then edge:SetWidth(2) else edge:SetHeight(2) end
    end
    hover.gear = hover:CreateTexture(nil, "OVERLAY", nil, 1)
    hover.gear:SetTexture(ns.GEAR)
    hover.gear:SetPoint("TOPRIGHT", -1, -1)
  end
  if hover.btn == btn and hover.frame == frame and hover:IsShown() then return end
  hover.frame, hover.btn = frame, btn
  hover:SetParent(frame.mover)
  hover:SetFrameLevel(frame.mover:GetFrameLevel() + 5)
  hover:ClearAllPoints()
  hover:SetAllPoints(btn)
  local size = math.max(10, math.min(18, math.floor((btn:GetHeight() or 30) * 0.4)))
  hover.gear:SetSize(size, size)
  hover:Show()
end

-- Building ------------------------------------------------------------------------

local function NewBarFrame()
  local frame = CreateFrame("Frame", nil, UIParent)
  frame.buttons = {}
  frame.layoutJob = function() Layout(frame) end
  ns.AttachMover(frame, function() return frame.config end, function() return frame.anchor end, {
    onDrop = function() Drop(frame) end,
    onRightClick = function() OpenMenu(frame) end,
    onClick = function()
      local btn = ButtonUnderCursor(frame)
      if btn then ns.EditMenu.ForButton(frame, btn) end
    end,
    onGear = function(gear) ns.EditMenu.GearForBar(frame, gear) end,
    onHover = function(over) ShowHover(frame, over and not held and not GetCursorInfo() and ButtonUnderCursor(frame) or nil) end,
    onMouseDown = function() frame.pressed = ButtonUnderCursor(frame) end,
    onDragStart = function() return StartHold(frame) end,
    onDragStop = function() return EndHold() end,
  })
  return frame
end

-- Sliding -------------------------------------------------------------------------
-- While buttons are rearranged in edit mode they glide to their new places
-- instead of jumping: a button keeps its new anchor (btn.place) plus an extra
-- offset that eases to nothing.

local SLIDE_TIME = 0.15
local sliding = {} -- button -> true while it glides

local function Place(btn)
  local place = btn.place
  btn:ClearAllPoints()
  btn:SetPoint(place.point, place.frame, place.point, place.x + (btn.slideX or 0), place.y + (btn.slideY or 0))
end

local slider = CreateFrame("Frame")
slider:Hide()
slider:SetScript("OnUpdate", function(self)
  local now = GetTime()
  for btn in pairs(sliding) do
    local progress = (now - btn.slideStart) / SLIDE_TIME
    if progress >= 1 or not btn.place then
      sliding[btn] = nil
      btn.slideX, btn.slideY = 0, 0
    else
      local left = (1 - progress) ^ 3 -- eases out: fast at first, settling gently
      btn.slideX, btn.slideY = btn.slideFromX * left, btn.slideFromY * left
    end
    if btn.place then Place(btn) end
  end
  if not next(sliding) then self:Hide() end
end)

local function StopSlide(btn)
  sliding[btn] = nil
  btn.slideX, btn.slideY = 0, 0
end

-- Glides a button from a point on screen (where it was drawn) to its place.
local function SlideFrom(btn, oldX, oldY)
  StopSlide(btn)
  Place(btn)
  local x, y = btn:GetCenter()
  if not (x and oldX) then return end
  local dx, dy = oldX - x, oldY - y
  if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return end
  btn.slideFromX, btn.slideFromY, btn.slideStart = dx, dy, GetTime()
  btn.slideX, btn.slideY = dx, dy
  Place(btn)
  sliding[btn] = true
  slider:Show()
end

local function ReleaseButtons(frame)
  for _, btn in ipairs(frame.buttons) do
    StopSlide(btn)
    btn.place = nil
    btn.module.Release(btn)
  end
  wipe(frame.buttons)
end

-- Bar types ------------------------------------------------------------------------
--   cooldowns: spells and items with their cooldowns; gaps can close
--   buffs:     my buffs, only while up, gaps close (one shared aura container)
--   debuffs:   my debuffs on the target, the same way
--   alerts:    an icon for each buff while it's missing
--   charges:   a segmented bar per buff, one segment per charge (Charges.lua)
--   absorb:    how much damage shields on a unit will still absorb, as a plain or
--              segmented bar, straight or bent (Absorb.lua)
--   totems:    four fixed slots, one per element (Totem.lua)
--   weapons:   a slot per hand holding a weapon, for its imbue, poison, oil or
--              stone, alerting when it's missing or running out (Weapons.lua)
--   allbuffs:  every buff you cast on yourself (items and procs included),
--              while up, with no list to keep; some can be hidden

Bar.TYPES = {
  { "cooldowns", "Cooldowns" },
  { "buffs", "My Active Buffs (auto)" },
  { "debuffs", "Debuffs" },
  { "alerts", "Missing buffs" },
  { "charges", "Buff With Charges" },
  { "absorb", "Shield absorb amount" },
  { "totems", "Totems" },
  { "weapons", "Weapon enchants (imbues, poisons)" },
}

-- Bars made before types existed only have dynamic/unit.
function Bar.Type(config)
  if config.type then return config.type end
  if config.dynamic then return config.unit == "target" and "debuffs" or "buffs" end
  return "cooldowns"
end

function Bar.SetType(config, kind)
  config.type = kind
  config.dynamic = (kind == "buffs" or kind == "debuffs" or kind == "allbuffs") or nil
  config.unit = (kind == "debuffs" and "target") or ((kind == "buffs" or kind == "allbuffs") and "player") or nil
  config.mine = kind == "allbuffs" or nil
  if kind == "allbuffs" then config.maxIcons = config.maxIcons or 8 end
  config.filter = (kind == "debuffs" and "HARMFUL") or (kind == "buffs" and "HELPFUL") or nil
  config.buttonDefaults = config.buttonDefaults or {}
  config.buttonDefaults.show = kind == "alerts" and "missing" or nil
  -- Charge bars are wide and short.
  if kind == "charges" then
    config.width = config.width or 120
    config.maxButtons = 1
    if (config.size or 40) > 24 then config.size = 12 end
  end
  -- Shield bars start as a standing column of segments.
  if kind == "absorb" then
    config.unit = config.unit or "player"
    config.width = config.width or 160
    if (config.size or 40) > 30 then config.size = 22 end
    if not config.look then
      config.look, config.orientation = "segments", "VERTICAL"
    end
  end
end

-- Bars laid out by Layout can wrap into more rows or columns; bars of saved
-- buttons can have a limit.
Bar.WRAPS = { cooldowns = true, alerts = true, charges = true, totems = true, weapons = true }
Bar.LIMITS = { cooldowns = true, buffs = true, debuffs = true, alerts = true, charges = true }

-- Whether a bar has as many buttons as its limit allows.
function Bar.Full(config)
  local most = Bar.LIMITS[Bar.Type(config)] and config.maxButtons
  return most ~= nil and most > 0 and #(config.buttons or {}) >= most
end

-- The point of a bar that stays put. Wrapping, the first line stays put too,
-- so the anchor moves to its side.
local function AnchorFor(config, grow)
  local anchor = ANCHORS[grow]
  if not (Bar.WRAPS[Bar.Type(config)] and (config.perLine or 0) > 0) then return anchor end
  if config.orientation == "VERTICAL" then
    local side = config.lineDir == "LEFT" and "RIGHT" or "LEFT"
    if anchor == "CENTER" then return side end
    return anchor .. side
  end
  local top = config.lineDir == "UP" and "BOTTOM" or "TOP"
  if anchor == "CENTER" then return top end
  return top .. anchor
end

-- After a change to how a bar wraps: keeps it where it is on screen, measured
-- from its new anchor.
function Bar.Reanchor(config)
  for _, frame in ipairs(frames) do
    if frame.config == config and frame:IsShown() then
      config.x, config.y = ns.Snap(OffsetOf(frame, AnchorFor(config, Grow(config))))
      return
    end
  end
end

-- Which module draws an entry: cooldown buttons, aura buttons, or (on a
-- dynamic bar) edit-mode stand-ins for the bar's shared aura container.
local function ModuleFor(config, entry)
  local kind = Bar.Type(config)
  if kind == "buffs" or kind == "debuffs" then return ns.Aura.Sample end
  if kind == "allbuffs" then return nil end
  if kind == "absorb" then return nil end
  if kind == "charges" then return (not entry.slot and not entry.item) and ns.Charges or nil end
  if kind == "totems" then return entry.totemSlot and ns.Totem or nil end
  if kind == "weapons" then return entry.weaponHand and ns.Weapons or nil end
  if entry.slot or entry.item then return ns.Button end
  if kind == "alerts" or entry.aura then return ns.Aura end
  return ns.Button
end

-- Layout ----------------------------------------------------------------------------

-- offset: distance along the line; lineOffset: distance to its line (wrapping).
local function Position(btn, frame, offset, lineOffset)
  lineOffset = lineOffset or 0
  local point, x, y
  if frame.vertical then
    local side = frame.lineDir == "LEFT" and "RIGHT" or "LEFT"
    point = (frame.grow == "UP" and "BOTTOM" or "TOP") .. side
    y = frame.grow == "UP" and offset or -offset
    x = side == "LEFT" and lineOffset or -lineOffset
  else
    local top = frame.lineDir == "UP" and "BOTTOM" or "TOP"
    point = top .. (frame.grow == "LEFT" and "RIGHT" or "LEFT")
    x = frame.grow == "LEFT" and -offset or offset
    y = top == "TOP" and -lineOffset or lineOffset
  end
  local place = btn.place
  if place then
    place.point, place.frame, place.x, place.y = point, frame, x, y
  else
    btn.place = { point = point, frame = frame, x = x, y = y }
  end
  StopSlide(btn)
  Place(btn)
end

-- Lines the buttons up. On a bar that closes gaps, hidden buttons are left
-- out (parked, invisible, under the first slot) and the bar shrinks around
-- the rest; its anchor point keeps it in place. With animate, buttons that
-- move glide there. (Declared above NewBarFrame.)
function Layout(frame, animate)
  if InCombatLockdown() and frame:IsProtected() then
    frame.layoutPending = true
    return
  end
  frame.layoutPending = nil
  local width, height, spacing = frame.itemWidth, frame.itemHeight, frame.spacing
  local along = frame.vertical and height or width
  local across = frame.vertical and width or height
  local perLine = frame.perLine or 0
  local collapsing = frame.collapse and not ns.editMode
  local shown = 0
  for _, btn in ipairs(frame.buttons) do
    if btn == frame.lifted then
      -- Picked up: out of the row while it's dragged.
    elseif collapsing and btn.visible == false then
      Position(btn, frame, 0)
    else
      if frame.gapAt == shown + 1 then shown = shown + 1 end -- the gap's slot stays empty
      local oldX, oldY
      if animate and btn:IsShown() then oldX, oldY = btn:GetCenter() end
      local line, slot = 0, shown
      if perLine > 0 then line, slot = math.floor(shown / perLine), shown % perLine end
      Position(btn, frame, slot * frame.step, line * (across + spacing))
      if oldX then SlideFrom(btn, oldX, oldY) end
      shown = shown + 1
    end
  end
  -- While something is held over it, a bar keeps its size, so nothing
  -- slides out from under the cursor.
  if frame.gapAt or frame.lifted then return end
  local count, lines = math.max(1, shown), 1
  if perLine > 0 then
    lines = math.ceil(count / perLine)
    count = math.min(count, perLine)
  end
  local length = count * along + (count - 1) * spacing
  if #frame.buttons == 0 then length = math.max(along, 40) * 4 end -- room to drop the first button
  local depth = lines * across + (lines - 1) * spacing
  if frame.fixedSize then
    frame:SetSize(width, height) -- absorb bars: one bar, no items
  elseif frame.vertical then
    frame:SetSize(depth, length)
  else
    frame:SetSize(length, depth)
  end
end

-- Asks for a layout on the next frame (several buttons often change at once).
function Bar.RequestLayout(frame)
  if frame and frame.layoutJob then ns.Schedule(frame.layoutJob) end
end

-- Layouts that couldn't run in combat.
function Bar.FlushLayouts()
  for _, frame in ipairs(frames) do
    if frame.layoutPending and frame:IsShown() then Layout(frame) end
  end
end

-- Rearranging -----------------------------------------------------------------------------------
-- In edit mode a button can be dragged to another place on its bar or onto
-- another bar; a spell or item dragged from the spellbook or bags lands the
-- same way. While something is held over a bar, it opens a gap in the slot
-- under the cursor, where it would land.

-- Bars whose buttons can change places and move between them. Totem slots
-- only change places on their own bar; weapon slots stay in order.
local REARRANGE = { cooldowns = true, buffs = true, debuffs = true, alerts = true, charges = true }

local ghost = CreateFrame("Frame", nil, UIParent)
ghost:SetFrameStrata("TOOLTIP")
ghost:EnableMouse(false)
ghost:SetAlpha(0.85)
ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
ghost.icon:SetAllPoints()
ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
ghost:Hide()
ghost:SetScript("OnUpdate", function(self)
  local scale = UIParent:GetEffectiveScale()
  local x, y = GetCursorPosition()
  self:ClearAllPoints()
  self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end)

local function Picture(btn)
  if btn.texture then return btn.texture end
  for _, key in ipairs({ "icon", "placeholder" }) do
    local texture = btn[key] and btn[key].GetTexture and btn[key]:GetTexture()
    if texture and not ns.issecret(texture) then return texture end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function BarUnderCursor()
  for _, frame in ipairs(frames) do
    if frame:IsShown() and frame.config and frame.mover:IsShown() and frame:IsMouseOver(6, -6, -6, 6) then
      return frame
    end
  end
end

-- Whether a bar can take what's held: the dragged button, or the spell or
-- item on the cursor.
local function Accepts(frame)
  local kind = Bar.Type(frame.config)
  if held then
    if held.totem then return frame == held.frame end
    if frame ~= held.frame and Bar.Full(frame.config) then return false end
    return REARRANGE[kind] == true and ModuleFor(frame.config, held.entry) ~= nil
  end
  return REARRANGE[kind] == true and not Bar.Full(frame.config)
end

-- Keeps the gap under the cursor while something is held (edit mode only).
local watcher = CreateFrame("Frame")
watcher:Hide()
watcher:SetScript("OnUpdate", function()
  local target
  local cursor = GetCursorInfo()
  if held or ((cursor == "spell" or cursor == "item") and not IsShiftKeyDown() and not IsAltKeyDown()) then
    target = BarUnderCursor()
    if target and not Accepts(target) then target = nil end
  end
  if target then SetGap(target, SlotUnderCursor(target)) elseif gapFrame then SetGap(nil) end
end)

-- The button in a slot, not counting one that's held: the held entry goes in front of it.
local function ButtonAt(frame, slot, skip)
  local count = 0
  for _, btn in ipairs(frame.buttons) do
    if btn ~= skip then
      count = count + 1
      if count == slot then return btn end
    end
  end
end

local function MoveEntry(drag, target, slot)
  local source = drag.frame.config.buttons
  if source[drag.configIndex] ~= drag.entry then return end
  local before = ButtonAt(target, slot, drag.btn)
  table.remove(source, drag.configIndex)
  local list = target.config.buttons
  local index = before and before.configIndex or #list + 1
  if list == source and before and before.configIndex > drag.configIndex then index = index - 1 end
  table.insert(list, math.min(index, #list + 1), drag.entry)
end

local function MoveTotem(drag, slot)
  local config = drag.frame.config
  local order = {}
  for _, entry in ipairs(ns.Totem.Entries(config)) do order[#order + 1] = entry.totemSlot end
  local element = table.remove(order, drag.configIndex)
  table.insert(order, math.min(slot, #order + 1), element)
  config.totemOrder = order
end

-- Picks up the button under the cursor. Returns false when there's none to pick up.
-- The button is the one pressed on, not the one under the cursor now.
function StartHold(frame)
  local btn = frame.pressed
  frame.pressed = nil
  local kind = Bar.Type(frame.config)
  if not REARRANGE[kind] and kind ~= "totems" then return false end
  if not (btn and tContains(frame.buttons, btn)) then return false end
  held = { frame = frame, btn = btn, configIndex = btn.configIndex, entry = btn.entry, totem = kind == "totems" }
  frame.lifted = btn
  btn:Hide()
  local size = math.max(24, math.min(48, frame.size or 36))
  ghost:SetSize(size, size)
  ghost.icon:SetTexture(Picture(btn))
  ghost:Show()
  GameTooltip:Hide()
  SetGap(frame, SlotUnderCursor(frame))
  return true
end

-- Puts the held button in the gap, if any, and rebuilds. Returns false when nothing was held.
-- What a button shows, across rebuilds: its saved entry (a totem slot's element).
local function Key(btn)
  local entry = btn.entry
  return entry and (entry.totemSlot or entry)
end

function EndHold()
  if not held then return false end
  local drag = held
  held = nil
  -- Where everything is drawn now (the dropped button: where the ghost is),
  -- so the rebuilt bars can glide from there.
  local from = {}
  for _, frame in ipairs(frames) do
    for _, btn in ipairs(frame.buttons) do
      local x, y = btn:GetCenter()
      if x and btn:IsShown() and Key(btn) then from[Key(btn)] = { x, y } end
    end
  end
  local ghostX, ghostY = ghost:GetCenter()
  if ghostX and Key(drag.btn) then
    -- The ghost is on UIParent, the buttons on their bars: compare in screen pixels.
    local ratio = ghost:GetEffectiveScale() / drag.btn:GetEffectiveScale()
    from[Key(drag.btn)] = { ghostX * ratio, ghostY * ratio }
  end
  ghost:Hide()

  local target = gapFrame
  local slot = target and target.gapAt
  drag.frame.lifted = nil
  SetGap(nil)
  if target and slot then
    if drag.totem then MoveTotem(drag, slot) else MoveEntry(drag, target, slot) end
  end
  ns.Rebuild(true)
  for _, frame in ipairs(frames) do
    for _, btn in ipairs(frame.buttons) do
      local old = Key(btn) and from[Key(btn)]
      if old and btn.place then SlideFrom(btn, old[1], old[2]) end
    end
  end
  ns.Options.Refresh()
  return true
end

-- A button's options: built-in defaults, then the profile's, the bar's and
-- the button's own settings, each overriding the one before.
function Bar.Options(profile, config, entry) return Options(profile, config, entry) end
function Options(profile, config, entry)
  local opts = {}
  for key, value in pairs(ns.BUTTON_DEFAULTS) do opts[key] = value end
  local layer = profile.buttonDefaults or {}
  for key in pairs(ns.BUTTON_DEFAULTS) do
    if layer[key] ~= nil then opts[key] = layer[key] end
  end
  layer = config.buttonDefaults or {}
  for key in pairs(ns.BUTTON_DEFAULTS) do
    if layer[key] ~= nil then opts[key] = layer[key] end
  end
  layer = entry
  if layer then
    for key in pairs(ns.BUTTON_DEFAULTS) do
      if layer[key] ~= nil then opts[key] = layer[key] end
    end
  end
  return opts
end

local function Build(frame, config, profile)
  frame.config = config
  config.buttons = config.buttons or {}
  frame.gapAt, frame.lifted, frame.pressed = nil, nil, nil
  ReleaseButtons(frame)

  local defaults = profile.visibilityDefaults or {}
  local scale = (config.scale or defaults.scale or 1) * (profile.scale or 1)
  local size = math.floor((config.size or 40) * scale + 0.5)
  local spacing = math.floor((config.spacing or 4) * scale + 0.5)
  local grow = Grow(config)
  local kind = Bar.Type(config)
  frame.size, frame.spacing, frame.grow = size, spacing, grow
  frame.vertical = config.orientation == "VERTICAL"
  frame.perLine = Bar.WRAPS[kind] and math.max(0, math.floor(config.perLine or 0)) or 0
  frame.lineDir = config.lineDir
  -- Icons are square; charge bars are as wide as the bar's width setting.
  -- A shield bar is as long as that, as thick as the size setting, and as
  -- big as its shape needs when bent.
  frame.itemWidth, frame.itemHeight = size, size
  local length = math.floor((config.width or 120) * scale + 0.5)
  if kind == "charges" then frame.itemWidth = length end
  if kind == "absorb" then
    frame.itemWidth, frame.itemHeight = ns.Absorb.Size(config, length, size, scale)
  end
  if kind == "charges" then
    -- Orbs and icons are square pieces, so their bar is as wide as they need.
    frame.itemWidth = ns.Charges.Width(Options(profile, config, {}), size, frame.itemWidth)
  end
  frame.step = (frame.vertical and frame.itemHeight or frame.itemWidth) + spacing
  frame.fixedSize = kind == "absorb" or kind == "allbuffs"
  if kind == "allbuffs" then
    -- Room for the most icons it shows at once.
    local count = config.maxIcons or 8
    local length = count * size + (count - 1) * spacing
    if frame.vertical then frame.itemHeight = length else frame.itemWidth = length end
  end

  -- Gaps close only on bars of plain cooldown buttons: aura buttons are drawn
  -- by the game's widget, which can't be moved around in combat.
  local collapse = Bar.Type(config) == "cooldowns" and config.collapse ~= false
  for _, entry in ipairs(config.buttons) do
    if ModuleFor(config, entry) ~= ns.Button then collapse = false end
    -- A button showing a debuff on the target holds a game aura widget too.
    if Options(profile, config, entry).targetDebuff then collapse = false end
  end
  frame.collapse = collapse

  -- Totem and weapon bars' slots aren't saved buttons: always the four
  -- elements, or both hands.
  local entries = config.buttons
  if kind == "totems" then entries = ns.Totem.Entries(config) end
  if kind == "weapons" then entries = ns.Weapons.Entries() end
  local most = Bar.LIMITS[kind] and config.maxButtons
  for index, entry in ipairs(entries) do
    -- No module: nothing to draw for this entry here (absorb bars have no
    -- buttons; items can't go on a charge bar). Past the bar's limit, nothing.
    local module = ModuleFor(config, entry)
    if most and most > 0 and #frame.buttons >= most then module = nil end
    -- Hidden buttons ("Hide this button") only show in edit mode, faded.
    if entry.hidden and not ns.editMode then module = nil end
    if module then
      local btn = module.Acquire(frame)
      btn.module, btn.bar, btn.collapse = module, frame, collapse
      if module.Setup(btn, entry, Options(profile, config, entry), size) then
        btn.configIndex = index
        if entry.hidden then btn:SetAlpha(0.35) end
        table.insert(frame.buttons, btn)
        if module == ns.Button then table.insert(ns.activeButtons, btn) end
      else
        module.Release(btn)
      end
    end
  end
  Layout(frame)

  frame.anchor = AnchorFor(config, grow)
  ns.PlaceFrame(frame, config, frame.anchor)
  frame.mover.SetLabel(config.name or "Bar")
  frame.mover.hint:SetText(kind == "allbuffs" and "Your own buffs show here" or "Drop spells here")
  frame.mover.hint:SetShown((#frame.buttons == 0 and kind ~= "absorb" and kind ~= "weapons") or kind == "allbuffs")
  frame.mover:SetShown(ns.editMode)
  frame:Show()

  if kind == "buffs" or kind == "debuffs" or kind == "allbuffs" then
    config.unit = kind == "debuffs" and "target" or "player"
    ns.Aura.BuildDynamic(frame, config, size, spacing)
  else
    ns.Aura.HideDynamic(frame)
  end
  if kind == "absorb" then
    ns.Absorb.Build(frame, config, length, size, scale)
  else
    ns.Absorb.Hide(frame)
  end
end

function Bar.BuildAll(profile)
  -- A rebuild in the middle of a drag drops it.
  if held then
    held = nil
    ghost:Hide()
  end
  gapFrame = nil
  if ns.editMode then watcher:Show() else watcher:Hide() end
  wipe(ns.activeButtons)
  wipe(ns.activeAuras)
  local configs = profile.bars or {}
  for i, config in ipairs(configs) do
    frames[i] = frames[i] or NewBarFrame()
    Build(frames[i], config, profile)
  end
  for i = #configs + 1, #frames do
    ReleaseButtons(frames[i])
    ns.Aura.HideDynamic(frames[i])
    ns.Absorb.Hide(frames[i])
    frames[i]:Hide()
  end
  ns.Button.SeedHighlights()
end

function Bar.Frames()
  return frames
end

-- Edit-mode grid -----------------------------------------------------------------------
-- With snapping on, dragged bars land on a grid (positions rounded to it).
-- Edit mode draws it: a faint line every 4 grid steps, brighter center lines.

local function GridSize()
  return ns.profile and ns.profile.gridSize or 8
end

function ns.Snap(x, y)
  if ns.profile and ns.profile.snap == false then return x, y end
  local size = GridSize()
  return math.floor(x / size + 0.5) * size, math.floor(y / size + 0.5) * size
end

local grid

function Bar.ShowGrid(shown)
  if not shown or (ns.profile and ns.profile.snap == false) then
    if grid then grid:Hide() end
    return
  end
  if not grid then
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:EnableMouse(false)
    grid.lines = {}
  end
  local count = 0
  local function Line(vertical, offset, alpha)
    count = count + 1
    local line = grid.lines[count] or grid:CreateTexture(nil, "BACKGROUND")
    grid.lines[count] = line
    line:ClearAllPoints()
    line:SetColorTexture(1, 1, 1, alpha)
    if vertical then
      line:SetPoint("TOP", grid, "TOP", offset, 0)
      line:SetPoint("BOTTOM", grid, "BOTTOM", offset, 0)
      line:SetWidth(1)
    else
      line:SetPoint("LEFT", grid, "LEFT", 0, offset)
      line:SetPoint("RIGHT", grid, "RIGHT", 0, offset)
      line:SetHeight(1)
    end
    line:Show()
  end
  local step = GridSize() * 4
  for x = 0, UIParent:GetWidth() / 2, step do
    Line(true, x, x == 0 and 0.35 or 0.07)
    if x > 0 then Line(true, -x, 0.07) end
  end
  for y = 0, UIParent:GetHeight() / 2, step do
    Line(false, y, y == 0 and 0.35 or 0.07)
    if y > 0 then Line(false, -y, 0.07) end
  end
  for index = count + 1, #grid.lines do grid.lines[index]:Hide() end
  grid:Show()
end

local function EnsureProfileMover()
  if profileMover then return profileMover end
  local mover = CreateFrame("Frame", nil, UIParent)
  mover:SetPoint("CENTER")
  mover:SetFrameStrata("MEDIUM")
  mover:SetFrameLevel(1)
  mover:SetClampedToScreen(false)
  mover:EnableMouse(true)
  mover:RegisterForDrag("LeftButton")

  local fill = mover:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints()
  fill:SetColorTexture(0.2, 0.6, 1, 0.08)

  mover.edges = {}
  for i = 1, 4 do mover.edges[i] = mover:CreateTexture(nil, "BORDER") end
  mover.edges[1]:SetPoint("TOPLEFT")
  mover.edges[1]:SetPoint("TOPRIGHT")
  mover.edges[1]:SetHeight(2)
  mover.edges[2]:SetPoint("BOTTOMLEFT")
  mover.edges[2]:SetPoint("BOTTOMRIGHT")
  mover.edges[2]:SetHeight(2)
  mover.edges[3]:SetPoint("TOPLEFT")
  mover.edges[3]:SetPoint("BOTTOMLEFT")
  mover.edges[3]:SetWidth(2)
  mover.edges[4]:SetPoint("TOPRIGHT")
  mover.edges[4]:SetPoint("BOTTOMRIGHT")
  mover.edges[4]:SetWidth(2)
  for _, edge in ipairs(mover.edges) do edge:SetColorTexture(0.7, 0.85, 1, 0.95) end

  local title = CreateFrame("Frame", nil, mover)
  title:SetHeight(18)
  title:SetPoint("BOTTOMLEFT", mover, "TOPLEFT", 0, 2)
  title:SetPoint("BOTTOMRIGHT", mover, "TOPRIGHT", 0, 2)
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  local titleBg = title:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints()
  titleBg:SetColorTexture(0.2, 0.6, 1, 0.55)

  local text = title:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER")
  text:SetText("Move profile")
  mover.title = title
  mover.text = text

  local dragging = nil

  local function SnapshotBounds()
    local left, right, top, bottom
    local targets = {}
    local minX, maxX = -math.huge, math.huge
    local minY, maxY = -math.huge, math.huge

    local function AddTarget(frame, config, anchor)
      if frame and frame:IsShown() and config then
        local fLeft, fBottom, fWidth, fHeight = frame:GetRect()
        if fLeft and fWidth and fHeight then
          local fRight = fLeft + fWidth
          local fTop = fBottom + fHeight
          local x, y = config.x or 0, config.y or 0
          local snapX, snapY = ns.Snap(x, y)
          local shiftX, shiftY = snapX - x, snapY - y
          local sLeft, sRight = fLeft + shiftX, fRight + shiftX
          local sBottom, sTop = fBottom + shiftY, fTop + shiftY

          left = left and math.min(left, sLeft) or sLeft
          right = right and math.max(right, sRight) or sRight
          bottom = bottom and math.min(bottom, sBottom) or sBottom
          top = top and math.max(top, sTop) or sTop
          targets[#targets + 1] = { frame = frame, config = config, anchor = anchor or "CENTER", x = snapX, y = snapY }

          minX = math.max(minX, -sLeft)
          maxX = math.min(maxX, UIParent:GetWidth() - sRight)
          minY = math.max(minY, -sBottom)
          maxY = math.min(maxY, UIParent:GetHeight() - sTop)
        end
      end
    end

    for _, frame in ipairs(frames) do
      if frame.config then AddTarget(frame, frame.config, frame.anchor) end
    end
    AddTarget(ns.Power and ns.Power.Frame and ns.Power.Frame() or nil, ns.profile and ns.profile.power or nil, "CENTER")
    AddTarget(ns.Health and ns.Health.Frame and ns.Health.Frame() or nil, ns.profile and ns.profile.health or nil, "CENTER")
    AddTarget(ns.Cast and ns.Cast.Frame() or nil, ns.profile and ns.profile.cast or nil, "CENTER")
    AddTarget(ns.Swing and ns.Swing.Frame and ns.Swing.Frame() or nil, ns.profile and ns.profile.swing or nil, "CENTER")

    if not left then return end
    local centerX, centerY = UIParent:GetCenter()
    local x = left - centerX
    local y = bottom - centerY
    mover:ClearAllPoints()
    mover:SetPoint("BOTTOMLEFT", UIParent, "CENTER", x, y)
    local width, height = math.max(36, right - left), math.max(24, top - bottom)
    mover:SetSize(width, height)
    return targets, { minX = minX, maxX = maxX, minY = minY, maxY = maxY }, x, y, x + width / 2, y + height / 2
  end

  local function ApplyDelta(dx, dy)
    for _, state in ipairs(dragging.targets) do
      state.config.x = state.x + dx
      state.config.y = state.y + dy
      ns.PlaceFrame(state.frame, state.config, state.anchor)
    end
    mover:ClearAllPoints()
    mover:SetPoint("BOTTOMLEFT", UIParent, "CENTER", dragging.boxX + dx, dragging.boxY + dy)
  end

  local function DragStart(self)
    if self == mover and BarUnderCursor() then return end
    local targets, clamp, boxX, boxY, boxCenterX, boxCenterY = SnapshotBounds()
    if not targets then return end
    local startX, startY = GetCursorPosition()
    local grid = ns.profile and ns.profile.gridSize or 8
    dragging = {
      targets = targets, clamp = clamp,
      startX = startX, startY = startY,
      dx = 0, dy = 0,
      boxX = boxX, boxY = boxY,
      boxCenterX = boxCenterX, boxCenterY = boxCenterY,
      centerSnap = math.max(4, grid),
      snap = not (ns.profile and ns.profile.snap == false)
    }
    ApplyDelta(0, 0)
  end

  local function DragStop()
    if not dragging then return end
    local dx, dy = dragging.dx or 0, dragging.dy or 0
    for _, state in ipairs(dragging.targets) do
      state.config.x = state.x + dx
      state.config.y = state.y + dy
    end
    dragging = nil
    ns.Rebuild(true)
    SnapshotBounds()
    if ns.Options and ns.Options.Refresh then ns.Options.Refresh() end
  end

  title:SetScript("OnDragStart", DragStart)
  title:SetScript("OnDragStop", DragStop)
  mover:SetScript("OnDragStart", DragStart)
  mover:SetScript("OnDragStop", DragStop)

  local refreshElapsed = 0
  mover:SetScript("OnUpdate", function(_, elapsed)
    if dragging then
      local x, y = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      local dx, dy = ns.Snap((x - dragging.startX) / scale, (y - dragging.startY) / scale)
      if dragging.snap then
        if math.abs(dragging.boxCenterX + dx) <= dragging.centerSnap then dx = -dragging.boxCenterX end
        if math.abs(dragging.boxCenterY + dy) <= dragging.centerSnap then dy = -dragging.boxCenterY end
      end
      dx = math.max(dragging.clamp.minX, math.min(dragging.clamp.maxX, dx))
      dy = math.max(dragging.clamp.minY, math.min(dragging.clamp.maxY, dy))
      dragging.dx, dragging.dy = dx, dy
      ApplyDelta(dx, dy)
      return
    end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed >= 0.15 then
      refreshElapsed = 0
      SnapshotBounds()
    end
  end)

  mover:SetScript("OnShow", function()
    refreshElapsed = 0
    SnapshotBounds()
  end)
  mover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Drag to move every bar in this profile")
    GameTooltip:AddLine("Bars are clamped to stay on screen.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  mover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  mover:Hide()
  profileMover = mover
  return mover
end

function Bar.SetProfileMoverShown(shown)
  EnsureProfileMover():SetShown(shown == true)
end
