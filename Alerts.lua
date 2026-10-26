-- Alerts: what a button does to get your attention, like the game's own
-- "Add Alert". Each one is a trigger and a sound or a visual:
--   { when = "applied" | "removed" | "ready" | "readyEarly" | "cast",
--     kind = "sound" | "visual", sound = <Sounds key>, visual = <VISUALS key> }
-- A button's list is its "alerts" option (inherited from its bar like any
-- other); an empty list means none.
--
-- Who plays them: an aura being applied or removed is secret in combat, so
-- those sounds go to the game (C_UnitAuras.AddAuraSound, Sounds.lua) and the
-- visuals to the game's aura buttons (played as they show, Glow.lua). Being
-- removed has no visual: the game can't show anything for an aura that's
-- gone. Ready, ready early and used come from readable cooldown flags and
-- your own casts, so the addon plays those itself (Alerts.Fire).
local _, ns = ...

local Alerts = {}
ns.Alerts = Alerts

local NONE = {}

-- Visuals: { key, label, style, r, g, b }
Alerts.VISUALS = {
  { "ants:gold", "Marching ants", "ants", 1, 0.82, 0.2 },
  { "ants:cyan", "Marching ants (cyan)", "ants", 0.3, 0.9, 1 },
  { "ants:red", "Marching ants (red)", "ants", 1, 0.25, 0.2 },
  { "ants:green", "Marching ants (green)", "ants", 0.3, 1, 0.35 },
  { "ants:blue", "Marching ants (blue)", "ants", 0.35, 0.5, 1 },
  { "flash:white", "Flash", "flash", 1, 1, 1 },
  { "flash:cyan", "Flash (cyan)", "flash", 0.3, 0.9, 1 },
  { "flash:red", "Flash (red)", "flash", 1, 0.25, 0.2 },
  { "flash:green", "Flash (green)", "flash", 0.3, 1, 0.35 },
  { "flash:blue", "Flash (blue)", "flash", 0.35, 0.5, 1 },
}

function Alerts.Visual(key)
  for _, row in ipairs(Alerts.VISUALS) do
    if row[1] == key then return row end
  end
  return Alerts.VISUALS[1]
end

function Alerts.List(opts)
  if type(opts.alerts) == "table" then return opts.alerts end
  return NONE
end

-- The visual for a trigger (the first one set), as its VISUALS row, or nil.
function Alerts.VisualFor(opts, when)
  for _, alert in ipairs(Alerts.List(opts)) do
    if alert.when == when and alert.kind == "visual" then return Alerts.Visual(alert.visual) end
  end
end

-- Triggers ------------------------------------------------------------------------------------

-- The triggers that make sense where ctx is (Modules.lua's ctx), in order:
-- { when, label, visual = whether a visual can show }.
function Alerts.Triggers(ctx, opts)
  local rows = {}
  local function Row(when, label, visual) rows[#rows + 1] = { when = when, label = label, visual = visual } end
  local kind = ctx.barKind
  if kind == "charges" then
    Row("applied", "When charges come back", false)
    Row("removed", "When charges run out", false)
  elseif kind ~= "cooldowns" or (ctx.layer == "button" and ctx.entryKind == "aura") then
    -- A bar of auras shown together has one visual, set on the bar.
    local together = kind == "buffs" or kind == "debuffs" or kind == "allbuffs"
    Row("applied", "When it's applied", not (together and ctx.layer == "button"))
    Row("removed", "When it's removed", false)
  else
    Row("ready", "When it's ready", true)
    if ctx.entryKind ~= "item" and ctx.entryKind ~= "slot" then
      Row("readyEarly", "When it's ready early (a reset)", true)
    end
    Row("cast", "When I use it", true)
    if ctx.entryKind ~= "item" and ctx.entryKind ~= "slot" then
      local watch = ctx.layer == "button" and ctx.entry.watchAura
      if watch then
        Row("applied", "When my buff is applied", false) -- no aura button to show it on
        Row("removed", "When my buff expires", false)
      elseif opts.targetDebuff or ctx.layer == "bar" then
        Row("applied", "When my debuff is applied", true)
        Row("removed", "When my debuff expires", false)
      end
    end
  end
  return rows
end

-- The phrase "Say its name" falls back to for a trigger.
function Alerts.Fallback(when, ctx, opts)
  if when == "ready" or when == "readyEarly" then return "Ready" end
  if when == "cast" then return nil end
  local unit = (ctx.barKind == "debuffs" or opts.unit == "target" or opts.targetDebuff) and "target" or "player"
  return ns.Sounds.Fallback(when == "applied" and "Added" or "Removed", ctx.barKind, unit)
end

function Alerts.Describe(alert)
  if alert.kind == "visual" then return Alerts.Visual(alert.visual)[2] end
  return ns.Sounds.Label(alert.sound)
end

-- Lists ------------------------------------------------------------------------------------------

function Alerts.Copy(list)
  local copy = {}
  for index, alert in ipairs(type(list) == "table" and list or NONE) do
    copy[index] = { when = alert.when, kind = alert.kind, sound = alert.sound, visual = alert.visual }
  end
  return copy
end

function Alerts.Equal(a, b)
  a, b = type(a) == "table" and a or NONE, type(b) == "table" and b or NONE
  if #a ~= #b then return false end
  for index = 1, #a do
    local x, y = a[index], b[index]
    if x.when ~= y.when or x.kind ~= y.kind or x.sound ~= y.sound or x.visual ~= y.visual then return false end
  end
  return true
end

-- Before alerts, a layer had soundStart, soundEnd and earlySound. A layer
-- that set any of them gets its own list (maybe empty: "none here"); one
-- that set none keeps following the layer above.
function Alerts.MigrateLayer(layer)
  if type(layer) ~= "table" then return end
  local start, finish, early = layer.soundStart, layer.soundEnd, layer.earlySound
  layer.soundStart, layer.soundEnd, layer.earlySound = nil, nil, nil
  if layer.alerts ~= nil or (start == nil and finish == nil and early == nil) then return end
  local list = {}
  if start and start ~= "none" then list[#list + 1] = { when = "applied", kind = "sound", sound = start } end
  if finish and finish ~= "none" then list[#list + 1] = { when = "removed", kind = "sound", sound = finish } end
  if early and early ~= "none" then list[#list + 1] = { when = "readyEarly", kind = "sound", sound = early } end
  layer.alerts = list
end

function Alerts.MigrateProfile(profile)
  Alerts.MigrateLayer(profile.buttonDefaults)
  for _, bar in ipairs(profile.bars or {}) do
    Alerts.MigrateLayer(bar.buttonDefaults)
    for _, entry in ipairs(bar.buttons or {}) do Alerts.MigrateLayer(entry) end
  end
end

-- Playing --------------------------------------------------------------------------------------

-- Plays a button's alerts for a trigger the addon sees itself (ready, ready
-- early, used).
function Alerts.Fire(btn, when)
  for _, alert in ipairs(Alerts.List(btn.opts)) do
    if alert.when == when then
      if alert.kind == "visual" then
        if btn.alertFx then ns.Glow.PlayAlert(btn.alertFx, Alerts.Visual(alert.visual)) end
      else
        ns.Sounds.Preview(alert.sound, btn.spellName, when == "cast" and nil or "Ready")
      end
    end
  end
end
