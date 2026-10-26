-- Pulsing border used for proc glows and missing-aura alerts.
local _, ns = ...

local Glow = {}
ns.Glow = Glow

local WHITE = ns.WHITE

-- A border `thickness` pixels wide just outside parent, hidden until shown.
function Glow.Create(parent, thickness, r, g, b)
  local glow = CreateFrame("Frame", nil, parent)
  glow:SetPoint("TOPLEFT", -thickness, thickness)
  glow:SetPoint("BOTTOMRIGHT", thickness, -thickness)
  glow:EnableMouse(false)
  glow.edges = {}
  local function Edge(p1, p2, horizontal)
    local edge = glow:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(WHITE)
    edge:SetPoint(p1)
    edge:SetPoint(p2)
    if horizontal then edge:SetHeight(thickness) else edge:SetWidth(thickness) end
    table.insert(glow.edges, edge)
  end
  Edge("TOPLEFT", "TOPRIGHT", true)
  Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  Edge("TOPLEFT", "BOTTOMLEFT", false)
  Edge("TOPRIGHT", "BOTTOMRIGHT", false)

  glow.pulse = glow:CreateAnimationGroup()
  glow.pulse:SetLooping("BOUNCE")
  local fade = glow.pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.3)
  fade:SetDuration(0.45)

  Glow.SetColor(glow, r or 1, g or 0.82, b or 0.2)
  glow:Hide()
  return glow
end

function Glow.SetColor(glow, r, g, b)
  for _, edge in ipairs(glow.edges) do edge:SetVertexColor(r, g, b) end
  -- An alert's soft glow and ants too.
  if glow.outer then glow.outer:SetVertexColor(r, g, b) end
  if glow.ants then glow.ants:SetVertexColor(r, g, b) end
end

function Glow.Show(glow)
  if glow:IsShown() then return end
  glow:Show()
  glow.pulse:Play()
end

function Glow.Hide(glow)
  glow.pulse:Stop()
  glow:Hide()
end

-- A Blizzard-style alert, like the action bar's proc glow: a soft outer glow
-- and the marching "ants" border, tinted (whitish blue for "ready early"),
-- plus a crisp pulsing edge in case this client lacks the glow textures.
-- Shown and hidden with Glow.Show / Glow.Hide.
local ALERT = "Interface\\SpellActivationOverlay\\IconAlert"
local ANTS = "Interface\\SpellActivationOverlay\\IconAlertAnts"
local ANT_FRAMES, ANT_SIZE, ANT_SHEET, ANT_SPEED = 22, 48, 256, 0.01

local function AnimateAnts(texture, elapsed)
  texture.elapsed = (texture.elapsed or 0) + elapsed
  if texture.elapsed < ANT_SPEED then return end
  texture.elapsed = 0
  texture.frame = ((texture.frame or 0) + 1) % ANT_FRAMES
  local perRow = math.floor(ANT_SHEET / ANT_SIZE)
  local column, row = texture.frame % perRow, math.floor(texture.frame / perRow)
  local step = ANT_SIZE / ANT_SHEET
  texture:SetTexCoord(column * step, (column + 1) * step, row * step, (row + 1) * step)
end

-- Colors to pick from for glows: { key, label, r, g, b }.
Glow.COLORS = {
  { "gold", "Gold", 1, 0.82, 0.2 },
  { "cyan", "Cyan", 0.3, 0.9, 1 },
  { "red", "Red", 1, 0.25, 0.2 },
  { "green", "Green", 0.3, 1, 0.35 },
  { "blue", "Blue", 0.35, 0.5, 1 },
  { "purple", "Purple", 0.75, 0.4, 1 },
  { "white", "White", 1, 1, 1 },
}

function Glow.Color(key)
  for _, color in ipairs(Glow.COLORS) do
    if color[1] == key then return color end
  end
  return Glow.COLORS[1]
end

function Glow.CreateAlert(parent, r, g, b)
  local glow = Glow.Create(parent, 2, r, g, b)
  local holder = CreateFrame("Frame", nil, glow)
  holder:SetPoint("CENTER", parent, "CENTER")
  holder:EnableMouse(false)
  glow.alert = holder

  local outer = holder:CreateTexture(nil, "ARTWORK")
  outer:SetAllPoints()
  outer:SetTexture(ALERT)
  outer:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
  outer:SetDesaturated(true)
  outer:SetVertexColor(r, g, b)
  outer:SetBlendMode("ADD")

  local ants = holder:CreateTexture(nil, "OVERLAY")
  ants:SetAllPoints()
  ants:SetTexture(ANTS)
  ants:SetDesaturated(true)
  ants:SetVertexColor(r, g, b)
  ants:SetBlendMode("ADD")
  holder:SetScript("OnUpdate", function(_, elapsed) AnimateAnts(ants, elapsed) end)
  glow.outer, glow.ants = outer, ants

  -- Sized to the parent each time it's shown (buttons change size).
  glow:HookScript("OnShow", function()
    local width, height = parent:GetSize()
    holder:SetSize(width * 1.4, height * 1.4)
  end)
  return glow
end

-- The same alert for one of the game's aura buttons, shown while the aura is
-- up. Addon code can't animate anything inside those buttons, so the
-- animations (the ants as a flipbook, the edge's pulse) are handed to the
-- game with AddAuraShownAnimation, and it plays them while the aura shows.
function Glow.BuildShownAlert(button, r, g, b)
  local holder = CreateFrame("Frame", nil, button)
  holder:SetPoint("CENTER", button, "CENTER")
  holder:EnableMouse(false)
  holder:SetFrameLevel(button:GetFrameLevel() + 4)

  local outer = holder:CreateTexture(nil, "ARTWORK")
  outer:SetAllPoints()
  outer:SetTexture(ALERT)
  outer:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
  outer:SetDesaturated(true)
  outer:SetVertexColor(r, g, b)
  outer:SetBlendMode("ADD")

  local ants = holder:CreateTexture(nil, "OVERLAY")
  ants:SetAllPoints()
  ants:SetTexture(ANTS)
  ants:SetDesaturated(true)
  ants:SetVertexColor(r, g, b)
  ants:SetBlendMode("ADD")
  local spin = ants:CreateAnimationGroup()
  spin:SetLooping("REPEAT")
  local flip = spin:CreateAnimation("FlipBook")
  flip:SetDuration(ANT_FRAMES * ANT_SPEED)
  flip:SetFlipBookRows(5)
  flip:SetFlipBookColumns(5)
  flip:SetFlipBookFrames(ANT_FRAMES)
  flip:SetFlipBookFrameWidth(ANT_SIZE)
  flip:SetFlipBookFrameHeight(ANT_SIZE)

  -- The crisp edge just outside the icon, pulsing.
  local edge = CreateFrame("Frame", nil, holder)
  edge:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
  edge:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
  local function Edge(p1, p2, horizontal)
    local line = edge:CreateTexture(nil, "OVERLAY")
    line:SetTexture(WHITE)
    line:SetVertexColor(r, g, b)
    line:SetPoint(p1)
    line:SetPoint(p2)
    if horizontal then line:SetHeight(2) else line:SetWidth(2) end
  end
  Edge("TOPLEFT", "TOPRIGHT", true)
  Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  Edge("TOPLEFT", "BOTTOMLEFT", false)
  Edge("TOPRIGHT", "BOTTOMRIGHT", false)
  local pulse = edge:CreateAnimationGroup()
  pulse:SetLooping("BOUNCE")
  local fade = pulse:CreateAnimation("Alpha")
  fade:SetFromAlpha(1)
  fade:SetToAlpha(0.3)
  fade:SetDuration(0.45)

  for _, group in ipairs({ spin, pulse }) do
    if button.AddAuraShownAnimation then
      ns.Try("aura glow", button.AddAuraShownAnimation, button, group)
    else
      group:Play() -- older clients: just keep it running
    end
  end
  return holder
end

function Glow.SizeShownAlert(holder, width, height)
  holder:SetSize(width * 1.4, height * 1.4)
end

-- Short alerts (Alerts.lua) ----------------------------------------------------------------
-- Two seconds of marching ants with the soft outer glow, or three flashes of
-- the icon, in a color. Each sits in a frame that's see-through except while
-- its animation plays. On one of the game's aura buttons (native) the
-- animations are handed to the game, which plays them as the aura shows; on
-- the addon's own buttons Glow.PlayAlert plays them.

local function Fade(group, from, to, duration, order)
  local fade = group:CreateAnimation("Alpha")
  fade:SetFromAlpha(from)
  fade:SetToAlpha(to)
  fade:SetDuration(duration)
  fade:SetOrder(order)
end

function Glow.BuildAlertFx(button, native)
  local fx = CreateFrame("Frame", nil, button)
  fx:SetPoint("CENTER", button, "CENTER")
  fx:SetFrameLevel(button:GetFrameLevel() + 7)
  fx:EnableMouse(false)
  fx.button, fx.native = button, native

  fx.antsFrame = CreateFrame("Frame", nil, fx)
  fx.antsFrame:SetAllPoints()
  fx.antsFrame:SetAlpha(0)
  fx.glow = fx.antsFrame:CreateTexture(nil, "ARTWORK")
  fx.glow:SetAllPoints()
  fx.glow:SetTexture(ALERT)
  fx.glow:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
  fx.glow:SetDesaturated(true)
  fx.glow:SetBlendMode("ADD")
  fx.ants = fx.antsFrame:CreateTexture(nil, "OVERLAY")
  fx.ants:SetAllPoints()
  fx.ants:SetTexture(ANTS)
  fx.ants:SetDesaturated(true)
  fx.ants:SetBlendMode("ADD")
  fx.spin = fx.ants:CreateAnimationGroup()
  fx.spin:SetLooping("REPEAT")
  local flip = fx.spin:CreateAnimation("FlipBook")
  flip:SetDuration(ANT_FRAMES * ANT_SPEED)
  flip:SetFlipBookRows(5)
  flip:SetFlipBookColumns(5)
  flip:SetFlipBookFrames(ANT_FRAMES)
  flip:SetFlipBookFrameWidth(ANT_SIZE)
  flip:SetFlipBookFrameHeight(ANT_SIZE)
  fx.antsShow = fx.antsFrame:CreateAnimationGroup()
  Fade(fx.antsShow, 0, 1, 0.15, 1)
  Fade(fx.antsShow, 1, 1, 1.8, 2)
  Fade(fx.antsShow, 1, 0, 0.5, 3)

  fx.flashFrame = CreateFrame("Frame", nil, fx)
  fx.flashFrame:SetAllPoints(button)
  fx.flashFrame:SetAlpha(0)
  fx.flash = fx.flashFrame:CreateTexture(nil, "OVERLAY")
  fx.flash:SetAllPoints()
  fx.flash:SetTexture(WHITE)
  fx.flash:SetBlendMode("ADD")
  fx.flashShow = fx.flashFrame:CreateAnimationGroup()
  for round = 0, 2 do
    Fade(fx.flashShow, 0, 0.8, 0.12, round * 2 + 1)
    Fade(fx.flashShow, 0.8, 0, 0.22, round * 2 + 2)
  end

  if native and button.AddAuraShownAnimation then
    for _, group in ipairs({ fx.spin, fx.antsShow, fx.flashShow }) do
      ns.Try("alert visual", button.AddAuraShownAnimation, button, group)
    end
  else
    -- The ants only need to march while they can be seen.
    fx.antsShow:SetScript("OnFinished", function() fx.spin:Stop() end)
  end
  fx:Hide()
  return fx
end

-- Which visual it shows (an Alerts.VISUALS row), or none.
function Glow.StyleAlertFx(fx, visual)
  if not visual then
    fx:Hide()
    return
  end
  local style, r, g, b = visual[3], visual[4], visual[5], visual[6]
  fx.antsFrame:SetShown(style == "ants")
  fx.flashFrame:SetShown(style == "flash")
  fx.glow:SetVertexColor(r, g, b)
  fx.ants:SetVertexColor(r, g, b)
  fx.flash:SetVertexColor(r, g, b)
  fx:Show()
end

function Glow.SizeAlertFx(fx, size)
  fx:SetSize(size * 1.4, size * 1.4)
end

-- Plays a visual on one of the addon's own buttons.
function Glow.PlayAlert(fx, visual)
  Glow.StyleAlertFx(fx, visual)
  Glow.SizeAlertFx(fx, (fx.button:GetWidth()))
  if visual[3] == "ants" then
    fx.spin:Play()
    fx.antsShow:Stop()
    fx.antsShow:Play()
  else
    fx.flashShow:Stop()
    fx.flashShow:Play()
  end
end
