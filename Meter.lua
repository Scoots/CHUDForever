-- A meter: a bordered status bar with a faint shine, centered text (value,
-- percent or both) and an edit-mode mover. The power and health bars are
-- both meters; each says what it reads and what color it is.
--
-- Values may be secret in combat: they're handed to the bar and text without
-- being read. A percent is worked out only from readable values, or else by
-- the meter's own percent function (the client's), when it has one.
local _, ns = ...
local issecret = ns.issecret
local WHITE = ns.WHITE

local Meter = {}
ns.Meter = Meter

-- The frame, shared with the cast bar: label names its mover, getConfig()
-- returns its settings (for moving it).
function Meter.BuildFrame(label, getConfig)
  local frame = CreateFrame("Frame", nil, UIParent)
  -- 1-pixel black border, then a dark tint of the bar's color behind the fill.
  local border = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetColorTexture(0, 0, 0, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetTexture(WHITE)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetAllPoints()
  frame.bar:SetStatusBarTexture(WHITE)

  -- Faint highlight along the top half, for a bit of depth.
  local shine = frame.bar:CreateTexture(nil, "OVERLAY")
  shine:SetTexture(WHITE)
  shine:SetVertexColor(1, 1, 1, 0.07)
  shine:SetPoint("TOPLEFT")
  shine:SetPoint("TOPRIGHT")
  shine:SetPoint("BOTTOM", frame.bar, "CENTER")

  frame.text = frame.bar:CreateFontString(nil, "OVERLAY")
  frame.text:SetPoint("CENTER", 0, 0)
  frame.text:SetShadowColor(0, 0, 0, 1)
  frame.text:SetShadowOffset(1, -1)

  ns.AttachMover(frame, getConfig, function() return "CENTER" end, {
    onGear = function(gear) ns.EditMenu.GearForMeter(label:lower(), label, getConfig(), gear) end,
  })
  frame.mover.SetLabel(label)
  return frame
end

-- Sizes, textures and places a meter frame from its settings. Returns its height.
function Meter.Layout(frame, config, defaultHeight)
  local scale = ns.profile and ns.profile.scale or 1
  local height = math.floor((config.height or defaultHeight or 14) * scale + 0.5)
  frame:SetSize(math.floor((config.width or 250) * scale + 0.5), height)
  frame.bar:SetStatusBarTexture(ns.BarTexture(config.texture))
  frame.text:SetFont(ns.Font(), math.max(8, height - 3), "")
  ns.PlaceFrame(frame, config, "CENTER")
  frame.mover:SetShown(ns.editMode)
  return height
end

-- Percent of maximum (possibly secret, so never tested), and whether it
-- could be worked out at all.
local function Percent(meter, current, maximum)
  if not issecret(current) and not issecret(maximum) then
    if maximum > 0 then return current / maximum * 100, true end
    return 0, true
  end
  if meter.secretPercent then return meter.secretPercent() end
  return nil, false
end

local function SetText(meter, current, maximum)
  local text, mode = meter.frame.text, meter.config.text
  if mode == "value" then
    ns.SetNumberText(text, "%d", current)
    return
  end
  if mode ~= "percent" and mode ~= "both" then
    text:SetText("")
    return
  end
  local percent, ok = Percent(meter, current, maximum)
  if not ok then
    text:SetText("")
  elseif mode == "percent" then
    ns.SetNumberText(text, "%.0f%%", percent)
  else
    ns.SetNumberText(text, "%d  %.0f%%", current, percent)
  end
end

-- label: the mover's name ("Power"). read(): current, maximum (either may be
-- secret). secretPercent(): optional, the percent when the values are secret,
-- and whether it could be worked out.
function Meter.New(label, read, secretPercent)
  local meter = { secretPercent = secretPercent }
  local failMax, failValue = label:lower() .. " bar maximum", label:lower() .. " bar value"

  function meter.Update()
    local frame = meter.frame
    if not frame or not frame:IsShown() then return end
    local current, maximum = read()
    ns.Try(failMax, frame.bar.SetMinMaxValues, frame.bar, 0, maximum)
    ns.Try(failValue, frame.bar.SetValue, frame.bar, current)
    SetText(meter, current, maximum)
  end

  -- An update on the next frame (several events often come at once).
  function meter.Changed()
    ns.Schedule(meter.Update)
  end

  -- Shows it as config says, or hides it. Returns whether it's shown.
  function meter.Apply(config)
    meter.config = config
    if not config or not config.enabled then
      if meter.frame then meter.frame:Hide() end
      return false
    end
    meter.frame = meter.frame or Meter.BuildFrame(label, function() return meter.config end)
    Meter.Layout(meter.frame, config)
    meter.frame:Show()
    return true
  end

  -- The fill's color, and a dark tint of it behind.
  function meter.SetColor(r, g, b)
    if not meter.frame then return end
    meter.frame.bar:SetStatusBarColor(r, g, b)
    meter.frame.bg:SetVertexColor(r * 0.2, g * 0.2, b * 0.2, 0.9)
  end

  function meter.SetMoverShown(shown)
    if meter.frame and meter.frame:IsShown() then meter.frame.mover:SetShown(shown) end
  end

  function meter.Frame()
    return meter.frame
  end

  return meter
end
