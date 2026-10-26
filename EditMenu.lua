-- The right-click menus of edit mode: one for a button, one for a bar. They
-- hold the everyday choices in short submenus, each labelled with what it's
-- set to; every option is also on the button's or the bar's page in the
-- settings window ("Settings..."). Every change is written into the profile
-- and the HUD is rebuilt.
local _, ns = ...
local issecret = ns.issecret

local function PluginsAPI()
  return ns.Plugins or ns.Modules
end

local EditMenu = {}
ns.EditMenu = EditMenu

-- An open settings window shows the change too.
local function Changed()
  ns.Rebuild(true)
  ns.Options.Refresh()
end

local function Radio(text, current, value, apply)
  return { text = text, checked = current == value, func = function() apply(value); Changed() end }
end

local function Toggle(text, current, apply)
  return { text = text, checked = current == true, func = function() apply(not current); Changed() end }
end

-- A submenu of fixed items.
local function Sub(text, items)
  return { text = text, submenu = function() return items end }
end

local SEPARATOR = { separator = true }

local function Remove(config, index)
  return { text = "Remove", func = function() ns.RemoveButton(config, index) end }
end

-- What a spell's button on a cooldown bar shows: its cooldown, or one of its
-- auras. { key, label, unit, show }
EditMenu.SHOW_AS = {
  { "cooldown", "Its cooldown" },
  { "cooldownDebuff", "Its cooldown + my debuff on target" },
  { "buff", "My buff while it's up", "player", "active" },
  { "debuff", "My debuff on the target", "target", "active" },
  { "missing", "Alert when my buff is missing", "player", "missing" },
  { "targetMissing", "Alert when my debuff is missing on the target", "target", "missing" },
}

function EditMenu.ShowsAs(entry)
  if not entry.aura then return entry.targetDebuff and "cooldownDebuff" or "cooldown" end
  for _, choice in ipairs(EditMenu.SHOW_AS) do
    if choice[3] == (entry.unit or "player") and choice[4] == (entry.show or "active") then return choice[1] end
  end
  return "buff"
end

-- Turns a spell's button into one of its auras, or back to its cooldown.
function EditMenu.SetShowsAs(entry, key)
  local choice = ns.Find(EditMenu.SHOW_AS, key)
  if choice[1] == "cooldown" then
    entry.targetDebuff = nil
    entry.aura, entry.unit, entry.show = nil, nil, nil
  elseif choice[1] == "cooldownDebuff" then
    entry.targetDebuff = true
    entry.aura, entry.unit, entry.show = nil, nil, nil
  else
    entry.targetDebuff = nil
    entry.aura = entry.aura or { (ns.ResolveSpell(entry.spell)) or (type(entry.spell) == "table" and entry.spell[1] or entry.spell) }
    entry.unit, entry.show = choice[3], choice[4]
  end
end

local function ShowAsMenu(entry)
  local current = EditMenu.ShowsAs(entry)
  local items = {}
  for _, choice in ipairs(EditMenu.SHOW_AS) do
    items[#items + 1] = Radio(choice[2], current, choice[1], function(value) EditMenu.SetShowsAs(entry, value) end)
  end
  return Sub("Show: " .. ns.ListLabel(EditMenu.SHOW_AS, current), items)
end

-- Alerts: what's set (clicking one takes it out) and a way to add one.
local function AlertsMenu(btn)
  local entry = btn.entry
  local plugins = PluginsAPI()
  if not plugins then return Sub("Alerts", { { text = "Not ready yet; try again in a moment", disabled = true } }) end
  local ctx = plugins.Context(ns.profile, btn.bar.config, entry)
  local opts = plugins.Opts(ctx)
  local list = ns.Alerts.List(opts)
  local labels = {}
  for _, trigger in ipairs(ns.Alerts.Triggers(ctx, opts)) do labels[trigger.when] = trigger.label end
  local items = {}
  for index, alert in ipairs(list) do
    items[#items + 1] = { text = ("Take out: %s, %s"):format(labels[alert.when] or alert.when, ns.Alerts.Describe(alert)),
      func = function()
        local copy = ns.Alerts.Copy(list)
        table.remove(copy, index)
        plugins.Setter(ctx)("alerts", copy)
        Changed()
      end }
  end
  if #items > 0 then items[#items + 1] = SEPARATOR end
  items[#items + 1] = { text = "Add an alert...",
    func = function() ns.Options.OpenButton(btn.bar.config, entry, false, "alerts") end }
  return Sub(#list > 0 and ("Alerts: " .. #list) or "Alerts", items)
end

-- Shared cooldown: the members (click one to take it out), which icon shows,
-- and the rest of a known family to add in one go.
local function GroupMenu(btn)
  local entry = btn.entry
  local groups = ns.Groups
  local items = {}
  local members = groups.Members(entry)
  if groups.IsGroup(entry) then
    for index, id in ipairs(members) do
      if index > 1 then
        local name = entry.item and ns.Button.ItemName(id) or C_Spell.GetSpellName(id)
        local icon = entry.item and ns.Button.ItemIcon(id) or C_Spell.GetSpellTexture(id)
        items[#items + 1] = { text = "Take out " .. tostring(name), icon = icon,
          func = function() groups.Remove(entry, id); Changed() end }
      end
    end
    items[#items + 1] = SEPARATOR
    local icon = entry.groupIcon or "last"
    items[#items + 1] = Radio("Icon: the one used last", icon, "last", function() entry.groupIcon = nil end)
    items[#items + 1] = Radio("Icon: always its own", icon, "first", function() entry.groupIcon = "first" end)
  end
  local family = entry.spell and groups.FamilyOf(btn.spellID or members[1])
  local missing = family and groups.Missing(entry, family) or {}
  if #missing > 0 then
    items[#items + 1] = { text = "Add the rest of " .. family.name, func = function()
      for _, id in ipairs(missing) do groups.Add(entry, { spell = id }) end
      Changed()
    end }
  end
  items[#items + 1] = { text = "To add one: Shift- or Alt-drop it on the button", disabled = true }
  local label = groups.IsGroup(entry) and ("Shared cooldown: " .. #members) or "Shared cooldown"
  return Sub(label, items)
end

-- Cooldown buttons ----------------------------------------------------------------------

local VISIBILITY = { { "always", "Always" }, { "cooldown", "Only while on cooldown" }, { "ready", "Hide while on cooldown" } }

local function CooldownItems(btn)
  local entry, opts = btn.entry, btn.opts
  local spell = btn.kind == "spell"
  local function Set(key) return function(value) entry[key] = value end end
  local items = {}
  local function Add(item) items[#items + 1] = item end

  if entry.spell then Add(ShowAsMenu(entry)) end

  local look = { Radio("Clock swipe", opts.cooldown, "swipe", Set("cooldown")) }
  if spell then look[#look + 1] = Radio("Left-to-right wipe", opts.cooldown, "wipe", Set("cooldown")) end
  look[#look + 1] = Radio("No cooldown animation", opts.cooldown, "none", Set("cooldown"))
  look[#look + 1] = SEPARATOR
  look[#look + 1] = Toggle("Countdown number", opts.numbers, Set("numbers"))
  look[#look + 1] = Toggle("Gray while on cooldown", opts.desaturate, Set("desaturate"))
  if spell then
    look[#look + 1] = Toggle("Global cooldown swipe", opts.gcd, Set("gcd"))
    look[#look + 1] = Toggle("Mana cost", opts.manaCost, Set("manaCost"))
  end
  Add(Sub("Cooldown look", look))

  local when = {}
  for _, choice in ipairs(VISIBILITY) do when[#when + 1] = Radio(choice[2], opts.visibility, choice[1], Set("visibility")) end
  Add(Sub("When to show: " .. ns.ListLabel(VISIBILITY, opts.visibility), when))
  if entry.spell or entry.item then Add(GroupMenu(btn)) end

  if spell then
    local glows = {
      Toggle("Glow on proc", opts.procGlow, Set("procGlow")),
      { text = "Glow while usable (Overpower, Execute...)", checked = btn.reactive == true,
        func = function() entry.reactive = not btn.reactive; Changed() end },
      Toggle("Glow when ready early (a reset)", opts.earlyReady, Set("earlyReady")),
    }
    glows[#glows + 1] = SEPARATOR
    if entry.swap then
      local name = C_Spell.GetSpellName(type(entry.swap) == "table" and entry.swap[1] or entry.swap)
      glows[#glows + 1] = { text = "Stop swapping to " .. tostring(name), func = function() entry.swap = nil; Changed() end }
    else
      glows[#glows + 1] = { text = "To swap icons: Shift-drop a spell on it", disabled = true }
    end
    Add(Sub("Glows", glows))

    local debuff = { Toggle("Show my debuff's time on the target", opts.targetDebuff, Set("targetDebuff")) }
    Add(Sub(opts.targetDebuff and "Debuff on target: shown" or "Debuff on target", debuff))
  end
  Add(AlertsMenu(btn))
  return items
end

-- Aura buttons -------------------------------------------------------------------------

local SHOW = { { "active", "While it's up" }, { "missing", "Alert when it's missing" }, { "always", "Always, dimmed when it's down" } }
local UNIT = { { "player", "A buff on me" }, { "target", "My debuff on the target" } }

local function AuraItems(btn)
  local entry, opts = btn.entry, btn.opts
  local function Set(key) return function(value) entry[key] = value end end
  local items = {}
  local function Add(item) items[#items + 1] = item end

  -- A spell's aura on a cooldown bar can go back to the cooldown.
  if entry.spell and ns.Bar.Type(btn.bar.config) == "cooldowns" then Add(ShowAsMenu(entry)) end
  local show, unit = {}, {}
  for _, choice in ipairs(SHOW) do show[#show + 1] = Radio(choice[2], opts.show, choice[1], Set("show")) end
  for _, choice in ipairs(UNIT) do unit[#unit + 1] = Radio(choice[2], opts.unit, choice[1], Set("unit")) end
  Add(Sub("When to show: " .. ns.ListLabel(SHOW, opts.show), show))
  Add(Sub("Whose: " .. ns.ListLabel(UNIT, opts.unit), unit))
  Add(Toggle("Glow while it's up", opts.auraGlow, Set("auraGlow")))
  Add(AlertsMenu(btn))
  return items
end

function EditMenu.ForButton(frame, btn)
  local icon = btn.texture or (btn.icon and btn.icon:GetTexture())
  local items = { { text = btn.module.Name(btn), isTitle = true, icon = icon } }
  if btn.kind == "totem" or btn.kind == "weapon" then
    -- Fixed slots: nothing to change or remove here.
    items[#items + 1] = { text = btn.kind == "totem" and "Fills itself when you drop a totem"
      or "Shows this hand's imbue, poison, oil or stone", disabled = true }
    items[#items + 1] = { text = "Bar settings...", func = function() ns.Options.Open(frame.config) end }
    ns.Menu.Open(items)
    return
  end
  items[#items + 1] = { text = "Settings...", func = function() ns.Options.OpenButton(frame.config, btn.entry) end }
  local extra
  if btn.kind == "aura" then
    extra = AuraItems(btn)
  elseif btn.kind == "charges" or btn.kind == "sample" then
    extra = { AlertsMenu(btn) }
  else
    extra = CooldownItems(btn)
  end
  for _, item in ipairs(extra) do items[#items + 1] = item end
  items[#items + 1] = { text = "Add a behavior...", func = function() ns.Options.OpenButton(frame.config, btn.entry, true) end }
  items[#items + 1] = SEPARATOR
  local entry = btn.entry
  if entry and frame.config.buttons and frame.config.buttons[btn.configIndex] == entry then
    items[#items + 1] = { text = entry.hidden and "Show this button again" or "Hide this button (keeps its settings)",
      func = function()
        entry.hidden = not entry.hidden or nil
        Changed()
      end }
  end
  items[#items + 1] = Remove(frame.config, btn.configIndex)
  ns.Menu.Open(items)
end

-- Combining ---------------------------------------------------------------------------------
-- A spell or item dropped on a button with Shift or Alt held: what to do with it.

local function DroppedName(dropped)
  if dropped.spell then return tostring(C_Spell.GetSpellName(dropped.spell) or dropped.spell) end
  if dropped.item then return ns.Button.ItemName(dropped.item) end
  return "it"
end

function EditMenu.Combine(frame, btn, dropped)
  local entry, config = btn.entry, frame.config
  local name, target = DroppedName(dropped), ns.Button.Name(btn)
  local items = { { text = ("%s on %s"):format(name, target), isTitle = true } }
  local function Add(item) items[#items + 1] = item end
  Add({ text = "Put it next to " .. target, func = function()
    if ns.Bar.Full(config) then
      ns.Print((config.name or "This bar") .. " is full.")
      return
    end
    ns.InsertButton(config, (btn.configIndex or #config.buttons) + 1, dropped)
  end })
  if btn.kind == "spell" and dropped.spell then
    Add({ text = "Show its icon while it procs (icon swap)", func = function()
      entry.swap = dropped.spell
      Changed()
      ns.Print(("%s now shows %s's icon while it procs. To undo: right-click it > Glows > Stop swapping."):format(target, name))
    end })
  end
  if (entry.spell and dropped.spell) or (entry.item and dropped.item) then
    Add({ text = "Stack them: one button, shared cooldown", func = function()
      ns.Groups.Add(entry, dropped)
      Changed()
      ns.Print(("%s and %s now share one button. To undo: right-click it > Shared cooldown."):format(target, name))
    end })
  end
  Add(SEPARATOR)
  Add({ text = "Cancel", func = function() end })
  ns.Menu.Open(items)
end

-- Bars --------------------------------------------------------------------------------------

local function AddAura(config, spellID, name, unit)
  local kind = ns.Bar.Type(config)
  if kind == "charges" and #(config.buttons or {}) >= 1 then
    ns.Print("Buff With Charges only allows one spell.")
    return
  end
  if ns.Bar.Full(config) then
    ns.Print((config.name or "This bar") .. " is full.")
    return
  end
  local entry = { aura = { spellID } }
  -- A cooldown bar needs to be told this one is an aura; the other bar types know.
  if kind == "cooldowns" then
    entry.unit, entry.show = unit, "active"
  elseif kind == "charges" then
    local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local found = false
    if getAura then
      for index = 1, 40 do
        local ok, aura = pcall(getAura, "player", index, "HELPFUL|PLAYER")
        if not ok or not aura or issecret(aura.spellId) then break end
        if aura.spellId == spellID then
          local apps = aura.applications
          if type(apps) == "number" and apps > 0 then
            found = true
            entry.pips = math.max(1, math.floor(apps))
          end
          break
        end
      end
    end
    if not found then
      ns.Print("That buff must be active with visible stacks/charges before adding it here.")
      return
    end
  end
  table.insert(config.buttons, entry)
  Changed()
  if kind == "charges" and entry.pips then
    ns.Print(("Added %s to %s (%d charges detected)." ):format(name, (config.name or "the bar"), entry.pips))
  else
    ns.Print("Added " .. name .. " to " .. (config.name or "the bar") .. ".")
  end
end

-- Buffs to add to a bar: the ones up now first, then the rest you've had
-- (Learn.lua), so ones that only show up in combat can be added any time.
local function BuffChoices(config)
  local items, listed = {}, {}
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  for index = 1, 40 do
    if not getAura then break end
    local ok, aura = pcall(getAura, "player", index, "HELPFUL")
    if not ok or not aura or issecret(aura.spellId) or issecret(aura.name) then break end
    local spellID, name = aura.spellId, aura.name
    if not listed[name] then
      listed[name] = true
      items[#items + 1] = {
        text = name .. " (up now)", icon = aura.icon,
        tooltip = function(row) ns.Learn.ShowTooltip(row, spellID) end,
        func = function() AddAura(config, spellID, name, "player") end,
      }
    end
  end
  for _, buff in ipairs(ns.Learn.Seen()) do
    if #items >= 30 then break end
    if buff.name and not listed[buff.name] then
      listed[buff.name] = true
      items[#items + 1] = {
        text = buff.name, icon = buff.icon,
        tooltip = function(row) ns.Learn.ShowTooltip(row, buff.id) end,
        func = function() AddAura(config, buff.id, buff.name, "player") end,
      }
    end
  end
  if #items == 0 then items[1] = { text = "None seen yet", disabled = true } end
  return items
end

-- Every-buff bars: hide one of your buffs (any you've had), or show a hidden one again.
local function HideAuras(config)
  local items = {}
  for _, buff in ipairs(ns.Learn.Buffs()) do
    if #items >= 30 then break end
    if not (config.hide and config.hide[buff.name]) then
      items[#items + 1] = {
        text = buff.name, icon = buff.icon, tooltip = function(row) ns.Learn.ShowTooltip(row, buff) end,
        func = function()
          ns.Learn.SetHidden(config, buff.name, true)
          Changed()
          ns.Print(buff.name .. " won't show on " .. (config.name or "the bar") .. ".")
        end,
      }
    end
  end
  if #items == 0 then items[1] = { text = "None seen yet", disabled = true } end
  items[#items + 1] = { text = "All of them: Manage buffs...", func = function() ns.Options.Open(config) end }
  return items
end

local function HiddenAuras(config)
  local items = {}
  for _, buff in ipairs(ns.Learn.Buffs()) do
    if config.hide and config.hide[buff.name] then
      items[#items + 1] = {
        text = buff.name, icon = buff.icon, tooltip = function(row) ns.Learn.ShowTooltip(row, buff) end,
        func = function()
          ns.Learn.SetHidden(config, buff.name, false)
          Changed()
          ns.Print(buff.name .. " will show on " .. (config.name or "the bar") .. " again.")
        end,
      }
    end
  end
  if #items == 0 then items[1] = { text = "None hidden", disabled = true } end
  return items
end

-- The auras on a unit right now (readable out of combat), as menu items that
-- add them to the bar.
local function CurrentAuras(config, unit, filter)
  local items = {}
  local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if getAura then
    for index = 1, 40 do
      local ok, aura = pcall(getAura, unit, index, filter)
      if not ok or not aura or issecret(aura.spellId) or issecret(aura.name) then break end
      local spellID, name = aura.spellId, aura.name
      items[#items + 1] = {
        text = ("%s (%d)"):format(name, spellID), icon = aura.icon,
        tooltip = function(row) ns.Learn.ShowTooltip(row, spellID) end,
        func = function() AddAura(config, spellID, name, unit) end,
      }
    end
  end
  if #items == 0 then items[1] = { text = "None right now", disabled = true } end
  return items
end

-- Bar types that take buffs and debuffs added from the menu.
local TAKES_AURAS = { cooldowns = true, buffs = true, debuffs = true, alerts = true, charges = true }

function EditMenu.ForBar(frame)
  local config = frame.config
  local kind = ns.Bar.Type(config)
  local items = { { text = config.name or "Bar", isTitle = true } }
  local function Add(item) items[#items + 1] = item end

  Add({ text = "Settings...", func = function() ns.Options.Open(config) end })
  local types = {}
  for _, choice in ipairs(ns.Bar.TYPES) do
    types[#types + 1] = Radio(choice[2], kind, choice[1], function(value) ns.Bar.SetType(config, value) end)
  end
  Add(Sub("Shows: " .. ns.ListLabel(ns.Bar.TYPES, kind), types))
  if kind == "allbuffs" then
    local anyHidden = (config.hide and next(config.hide)) or (config.exclude and next(config.exclude))
    Add({ text = "Hide a buff...", submenu = function() return HideAuras(config) end })
    Add({ text = "Show a hidden buff", disabled = not anyHidden, submenu = function() return HiddenAuras(config) end })
    Add({ text = "Show all hidden buffs", disabled = not anyHidden,
      func = function() config.hide, config.exclude = nil, nil; Changed() end })
    Add({ text = "Manage buffs...", func = function() ns.Options.Open(config) end })
  elseif TAKES_AURAS[kind] then
    Add(Sub("Add", {
      { text = "A buff", submenu = function() return BuffChoices(config) end },
      { text = "My debuff on the target", submenu = function() return CurrentAuras(config, "target", "HARMFUL|PLAYER") end },
    }))
  end
  Add(SEPARATOR)
  Add({ text = "Add a new bar", func = function() ns.AddBar("") end })
  if kind == "cooldowns" and ns.Groups.Collapsible(config.buttons or {}) > 0 then
    Add({ text = "Stack shared cooldowns (shocks, traps...)", func = function()
      ns.Groups.Collapse(config.buttons)
      Changed()
    end })
  end
  Add({ text = "Duplicate this bar", func = function() ns.DuplicateBar(config) end })
  Add({ text = "Export this bar", func = function() ns.Share.ShowExportBar(config) end })
  Add({ text = "Delete this bar", func = function() ns.DeleteBar(config) end })
  ns.Menu.Open(items)
end

-- Gears ---------------------------------------------------------------------------------------
-- The gear on a bar's name tab in edit mode: its size and layout, right there.

local SHOW_CHOICES = { { "always", "Always" }, { "combat", "In combat" } }

local function Number(get, fallback)
  return function() return get() or fallback end
end

function EditMenu.GearForBar(frame, gear)
  local config = frame.config
  if not config then return end
  local kind = ns.Bar.Type(config)
  local profile = ns.profile or {}
  local rows = {}
  local function Slider(label, key, fallback, low, high, step)
    rows[#rows + 1] = { slider = label, min = low, max = high, step = step,
      get = Number(function() return config[key] end, fallback), set = function(value) config[key] = value end }
  end
  if kind == "absorb" then
    Slider("Length", "width", 160, 20, 600, 10)
    Slider("Thickness", "size", 22, 2, 60, 1)
  elseif kind == "charges" then
    local look = ns.Bar.Options(profile, config, (config.buttons or {})[1]).chargeLook
    if look == "bar" then
      Slider("Width", "width", 120, 30, 600, 10)
      Slider("Height", "size", 12, 4, 40, 1)
    else
      Slider("Size", "size", 24, 8, 64, 1)
    end
  else
    Slider("Icon size", "size", 40, 16, 96, 2)
    Slider("Spacing", "spacing", 4, 0, 30, 1)
  end
  rows[#rows + 1] = { choice = "Direction", choices = { { "HORIZONTAL", "Across" }, { "VERTICAL", "Down" } },
    get = function() return config.orientation or "HORIZONTAL" end,
    set = function(value) config.orientation = value end }
  rows[#rows + 1] = { choice = "Show", choices = SHOW_CHOICES,
    get = function() return config.show or (profile.visibilityDefaults or {}).show or "always" end,
    set = function(value) config.show = value end }
  rows[#rows + 1] = { button = "All settings for this bar...", func = function() ns.Options.Open(config) end }
  rows[#rows + 1] = { button = "More...", func = function() EditMenu.ForBar(frame) end }
  ns.Popover.Open(gear, config.name or "Bar", rows)
end

-- key: the settings page ("power", "health", "cast" or "swing").
function EditMenu.GearForMeter(key, label, config, gear)
  if not config then return end
  local defaultHeight = key == "cast" and 16 or 14
  ns.Popover.Open(gear, label, {
    { slider = "Width", min = 60, max = 600, step = 10, get = Number(function() return config.width end, 250),
      set = function(value) config.width = value end },
    { slider = "Height", min = 4, max = 40, step = 1, get = Number(function() return config.height end, defaultHeight),
      set = function(value) config.height = value end },
    { choice = "Show", choices = SHOW_CHOICES,
      get = function() return config.show or ((ns.profile or {}).visibilityDefaults or {}).show or "always" end,
      set = function(value) config.show = value end },
    { button = "All settings...", func = function() ns.Options.Open(key) end },
  })
end
