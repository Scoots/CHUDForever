-- /chud report: what a bug report needs, in a box to copy from. The version,
-- game build, character and profile, problems caught along the way, then what
-- each troubleshooting command (/chud debug) would print for the parts in
-- use, and last the profile itself as an export string, so the layout can be
-- rebuilt to look at.
local _, ns = ...
local issecret = ns.issecret

local Report = {}
ns.Report = Report

local function Show(value)
  if issecret(value) then return "hidden" end
  return tostring(value)
end

-- What fn prints to chat, as lines, instead of in chat.
local function Capture(fn)
  local lines, print = {}, ns.Print
  ns.Print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = Show((select(i, ...))) end
    lines[#lines + 1] = table.concat(parts, " ")
  end
  local ok, err = pcall(fn)
  ns.Print = print
  if not ok then lines[#lines + 1] = "(failed: " .. tostring(err) .. ")" end
  return lines
end

local function Has(kind)
  for _, bar in ipairs(ns.profile and ns.profile.bars or {}) do
    if ns.Bar.Type(bar) == kind then return true end
  end
  return false
end

local function Header(out)
  local version, build, date, toc = GetBuildInfo()
  out[#out + 1] = "CHUDForever " .. ns.Version()
  out[#out + 1] = ("Game: %s (build %s, %s), interface %s"):format(Show(version), Show(build), Show(date), Show(toc))
  local _, class = UnitClass("player")
  local _, race = UnitRace("player")
  out[#out + 1] = ("Character: %s %s, level %s; in combat: %s"):format(Show(race), Show(class), Show(UnitLevel("player")),
    tostring(InCombatLockdown()))
  local profile = ns.profile or {}
  out[#out + 1] = ("Profile: %s, %d bars, HUD scale %s%%"):format(tostring(ns.profileName), #(profile.bars or {}),
    tostring(math.floor((profile.scale or 1) * 100 + 0.5)))
  local meters = {}
  for _, key in ipairs({ "power", "health", "cast", "swing" }) do
    meters[#meters + 1] = key .. " " .. ((profile[key] or {}).enabled and "on" or "off")
  end
  out[#out + 1] = "Meters: " .. table.concat(meters, ", ")
  if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
    UpdateAddOnMemoryUsage()
    out[#out + 1] = ("Memory: %.0f KB"):format(GetAddOnMemoryUsage(ns.name))
  end
  local problems = ns.problems or {}
  out[#out + 1] = "Problems caught: " .. (#problems > 0 and "" or "none")
  for _, problem in ipairs(problems) do out[#out + 1] = "  " .. problem end
end

-- The troubleshooting output worth including, for the parts in use.
local function Sections()
  local profile = ns.profile or {}
  local list = {
    { "Bars and spells (/chud debug info)", ns.PrintInfo },
    { "Spec detection (/chud debug spec)", ns.PrintDiag },
    { "Auras (/chud debug auras)", ns.Aura.PrintDiag },
    { "Item range (/chud debug range)", ns.Range.Probe },
    { "Learned buffs (/chud debug links)", ns.Learn.Print },
  }
  if Has("totems") then list[#list + 1] = { "Totems (/chud debug totems)", ns.Totem.PrintDiag } end
  if Has("weapons") then list[#list + 1] = { "Weapon enchants (/chud debug weapons)", ns.Weapons.PrintDiag } end
  if Has("absorb") then list[#list + 1] = { "Shield (/chud debug shield)", ns.Absorb.PrintDiag } end
  if (profile.swing or {}).enabled then list[#list + 1] = { "Swing timer (/chud debug swing)", ns.Swing.Probe } end
  return list
end

-- Chat color codes and links don't belong in a pasted report.
local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

function Report.Build()
  local out = {}
  Header(out)
  for _, section in ipairs(Sections()) do
    out[#out + 1] = ""
    out[#out + 1] = "== " .. section[1]
    for _, line in ipairs(Capture(section[2])) do out[#out + 1] = Plain(line) end
  end
  if ns.profile then
    out[#out + 1] = ""
    out[#out + 1] = "== Profile (import it with Import Profile to see the layout)"
    local ok, text = pcall(ns.Share.Encode, ns.profile)
    out[#out + 1] = ok and text or ("(failed: " .. tostring(text) .. ")")
  end
  return table.concat(out, "\n")
end

function Report.Show()
  ns.Share.ShowText("CHUDForever report",
    "Press Ctrl+C to copy, then paste it into your bug report. Nothing is sent anywhere.", Report.Build())
end
