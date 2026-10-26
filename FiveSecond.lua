-- The 5-second rule, as a spark crossing the mana bar: after you spend mana,
-- spirit regeneration stops for 5 seconds, and the spark takes those 5
-- seconds to cross. (On WoW Forever mana comes back as a steady stream, not
-- in ticks, so there's nothing else to time.)
--
-- Mana is secret in combat, so the rule restarts on any cast of a spell that
-- costs mana; costs are noted whenever they can be read. Out of combat a drop
-- in mana restarts it too.
local _, ns = ...
local issecret = ns.issecret

local RULE = 5
local AUTO_ATTACK = 6603
local SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"

local ruleStart, lastMana
local costs = {} -- spell ID -> mana cost, from when it could be read

local spark
local driver = CreateFrame("Frame")
driver:Hide()

driver:SetScript("OnUpdate", function(self)
  local bar = ns.Power.Bar()
  local power = ns.profile and ns.profile.power or {}
  local elapsed = ruleStart and GetTime() - ruleStart
  if not bar or not spark or not ns.Power.IsMana() or power.fiveSecond == false or not elapsed or elapsed >= RULE then
    if spark then spark:Hide() end
    self:Hide()
    return
  end
  spark:ClearAllPoints()
  spark:SetPoint("CENTER", bar, "LEFT", bar:GetWidth() * elapsed / RULE, 0)
  spark:Show()
end)

local function Start()
  ruleStart = GetTime()
  local bar = ns.Power.Bar()
  if not bar then return end
  if not spark then
    spark = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    spark:SetVertexColor(1, 0.85, 0.35)
  end
  spark:SetSize(14, bar:GetHeight() * 2.2)
  driver:Show()
end

-- A cast restarts the rule if the spell costs mana (or its cost is unknown).
ns.OnUnit("UNIT_SPELLCAST_SUCCEEDED", "player", function(_, _, _, spellID)
  if not issecret(spellID) and spellID then
    if spellID == AUTO_ATTACK then return end
    local cost = ns.ManaCost(spellID)
    if cost then costs[spellID] = cost else cost = costs[spellID] end
    if cost ~= nil and cost <= 0 then return end
  end
  Start()
end)

-- Out of combat, a drop in mana restarts it too (mana spent some other way).
ns.OnUnit("UNIT_POWER_FREQUENT", "player", function(_, _, token)
  if issecret(token) or token ~= "MANA" then return end
  local current = UnitPower("player", 0)
  if issecret(current) then
    lastMana = nil
    return
  end
  if lastMana and current < lastMana then Start() end
  lastMana = current
end)
