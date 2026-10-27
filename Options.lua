-- Settings window (/chud). On the left, your profiles; the one you open lists
-- its pages underneath: each bar, the power bar, and its general look, and
-- under the open bar each of its buttons. On the right, the settings of
-- what's selected. Changes apply straight away. Any profile can be changed;
-- only the one in use is on screen (and in edit mode). Buttons are added by
-- dragging spells onto a bar in edit mode.
--
-- A button's page (and a bar's) is made of plugin cards (Modules.lua): each
-- feature on it, with a switch, a one-line summary and a tag saying whether
-- it comes from the bar or this button changed it; "+ Add plugin" lists the
-- rest. The older pages of plain settings are kept as the "Advanced" tab.
local _, ns = ...

local Options = {}
ns.Options = Options

local WIDTH, HEIGHT, LIST_WIDTH = 680, 640, 150
local LABEL_WIDTH = 110
local window, list, listChild, panel, newProfileButton, listHeader, panelWidth
local deleteModal
local viewedName    -- the profile opened in the list
local selected      -- what's shown on the right: "general", "power" or a bar's config
local selectedEntry -- with a bar selected: one of its buttons, for that button's page
local listButtons = {}

local TYPE_NOTES = {
  cooldowns = "Drop spells and items here to see their cooldowns.",
  buffs = "Shows your own buffs automatically (including trinkets/procs), while up. Use edit-mode right-click to hide ones you don't care about, then re-show them later.",
  debuffs = "Debuffs on your target, while they're up. Gaps close; they update when you switch targets.",
  alerts = "Drop a buff's spell here: its icon shows, with a red glow, only while the buff is missing.",
  charges = "Track one buff that has charges (Lightning Shield, for example): one segment per charge.",
  absorb = "How much damage your shields will still absorb, with the amount underneath. A full bar is the shield's size when it went up.",
  totems = "One slot per element: the totem's time left, and the yards of reach you have left from where you dropped it (red: how far out you are).",
  weapons = "A slot for each hand holding a weapon: its imbue, poison, oil or stone with the time left. Pulses red when it's missing, orange when it's running out.",
  allbuffs = "Shows your own buffs automatically (including trinkets/procs), while up. Use edit-mode right-click to hide ones you don't care about, then re-show them later.",
}

local function Changed()
  ns.Rebuild(true)
  Options.Refresh()
end

-- Widgets --------------------------------------------------------------------------------

local function Flat(button, selectedLook)
  if selectedLook then
    button.bg:SetColorTexture(0.85, 0.6, 0.1, 1)
    button.text:SetTextColor(0, 0, 0)
  else
    button.bg:SetColorTexture(0.18, 0.18, 0.22, 1)
    button.text:SetTextColor(1, 1, 1)
  end
end

local function NewButton(parent, width, height)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(width, height)
  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.1)
  button.highlight = highlight
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.text:SetPoint("LEFT", 4, 0)
  button.text:SetPoint("RIGHT", -4, 0)
  button.text:SetWordWrap(false)
  button.text:SetShadowColor(0, 0, 0, 0)
  button.text:SetShadowOffset(0, 0)
  Flat(button, false)
  return button
end

local pools, active = {}, {}
local cursorY
local indentLeft, indentRight = 0, 0 -- inside a plugin card, widgets are drawn narrower

local function Acquire(kind, create)
  pools[kind] = pools[kind] or {}
  local widget = table.remove(pools[kind]) or create()
  widget.poolKind = kind
  table.insert(active, widget)
  widget:Show()
  return widget
end

local function ReleaseAll()
  for _, widget in ipairs(active) do
    widget:Hide()
    widget:ClearAllPoints()
    table.insert(pools[widget.poolKind], widget)
  end
  wipe(active)
end

-- Places a full-width widget at the cursor and moves the cursor down.
local function Place(widget, height, gap)
  widget:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft, cursorY)
  widget:SetPoint("RIGHT", panel, "RIGHT", -indentRight, 0)
  widget:SetHeight(height)
  cursorY = cursorY - height - (gap or 6)
end

local function Label(parent)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT")
  label:SetWidth(LABEL_WIDTH - 4)
  label:SetJustifyH("LEFT")
  return label
end

local function Header(text)
  cursorY = cursorY - 4
  local widget = Acquire("header", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.text:SetPoint("BOTTOMLEFT", 0, 3)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0.2, 0.3)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    return frame
  end)
  widget.text:SetText(text)
  Place(widget, 20)
end

-- The width widgets get here, inside any card.
local function Room()
  return panelWidth - indentLeft - indentRight
end

-- Grey text, as tall as it needs.
local function Note(text)
  local widget = Acquire("note", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    return frame
  end)
  widget.text:SetWidth(Room())
  widget.text:SetText(text)
  Place(widget, math.max(12, math.ceil(widget.text:GetStringHeight()) + 2))
end

-- A row of buttons, one per choice; the current one is highlighted.
local function Choice(labelText, choices, current, pick)
  local widget = Acquire("choice", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.label = Label(frame)
    frame.segments = {}
    return frame
  end)
  widget.label:SetText(labelText)
  local count = #choices
  local width = math.floor((Room() - LABEL_WIDTH - (count - 1) * 3) / count)
  for index, choice in ipairs(choices) do
    local segment = widget.segments[index] or NewButton(widget, width, 20)
    widget.segments[index] = segment
    segment:SetSize(width, 20)
    segment:ClearAllPoints()
    segment:SetPoint("LEFT", widget, "LEFT", LABEL_WIDTH + (index - 1) * (width + 3), 0)
    segment.text:SetText(choice[2])
    segment.text:SetJustifyH("CENTER")
    Flat(segment, choice[1] == current)
    segment:SetScript("OnClick", function() pick(choice[1]); Changed() end)
    segment:Show()
  end
  for index = count + 1, #widget.segments do widget.segments[index]:Hide() end
  Place(widget, 22)
end

-- Check boxes (or radio choices), two to a row.
-- items: { {text, checked, onClick}, ... }
local function Checks(items)
  local column = 0
  local half = math.floor(Room() / 2)
  for _, item in ipairs(items) do
    local widget = Acquire("check", function()
      local button = CreateFrame("Button", nil, panel)
      button.box = button:CreateTexture(nil, "ARTWORK")
      button.box:SetSize(13, 13)
      button.box:SetPoint("LEFT")
      button.box:SetColorTexture(0.18, 0.18, 0.22, 1)
      button.mark = button:CreateTexture(nil, "OVERLAY")
      button.mark:SetSize(7, 7)
      button.mark:SetPoint("CENTER", button.box)
      button.mark:SetColorTexture(1, 0.82, 0.2, 1)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      button.text:SetPoint("LEFT", button.box, "RIGHT", 6, 0)
      button.text:SetPoint("RIGHT")
      button.text:SetJustifyH("LEFT")
      local highlight = button:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetColorTexture(1, 1, 1, 0.05)
      return button
    end)
    widget.text:SetText(item[1])
    widget.mark:SetShown(item[2] == true)
    widget:SetScript("OnClick", function() item[3](); Changed() end)
    widget:SetSize(half - 4, 18)
    widget:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft + column * half, cursorY)
    column = column + 1
    if column == 2 then
      column = 0
      cursorY = cursorY - 22
    end
  end
  if column == 1 then cursorY = cursorY - 22 end
  cursorY = cursorY - 2
end

local function Stepper(labelText, value, step, low, high, set)
  local widget = Acquire("stepper", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.label = Label(frame)
    frame.minus = NewButton(frame, 22, 20)
    frame.minus.text:SetText("-")
    frame.minus.text:SetJustifyH("CENTER")
    frame.minus:SetPoint("LEFT", LABEL_WIDTH, 0)
    -- The number can be typed too (Enter or clicking away sets it; Escape undoes).
    frame.value = CreateFrame("EditBox", nil, frame)
    frame.value:SetPoint("LEFT", frame.minus, "RIGHT", 4, 0)
    frame.value:SetSize(44, 20)
    frame.value:SetAutoFocus(false)
    frame.value:SetNumeric(true)
    frame.value:SetMaxLetters(5)
    frame.value:SetFontObject("GameFontHighlight")
    frame.value:SetJustifyH("CENTER")
    local box = frame.value:CreateTexture(nil, "BACKGROUND")
    box:SetAllPoints()
    box:SetColorTexture(0.12, 0.12, 0.15, 1)
    frame.value:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.value:SetScript("OnEscapePressed", function(self)
      self:SetText(self.shown or "")
      self:ClearFocus()
    end)
    frame.plus = NewButton(frame, 22, 20)
    frame.plus.text:SetText("+")
    frame.plus.text:SetJustifyH("CENTER")
    frame.plus:SetPoint("LEFT", frame.value, "RIGHT", 4, 0)
    return frame
  end)
  widget.label:SetText(labelText)
  widget.value.shown = tostring(value)
  widget.value:SetText(widget.value.shown)
  widget.value:SetScript("OnEditFocusLost", function(self)
    local typed = tonumber(self:GetText() or "")
    if not typed then
      self:SetText(self.shown)
      return
    end
    typed = math.max(low, math.min(high, math.floor(typed + 0.5)))
    if typed == value then
      self:SetText(self.shown)
      return
    end
    set(typed)
    -- Focus is also lost when the window redraws; finish that first.
    ns.Schedule(Changed)
  end)
  widget.minus:SetScript("OnClick", function() set(math.max(low, value - step)); Changed() end)
  widget.plus:SetScript("OnClick", function() set(math.min(high, value + step)); Changed() end)
  Place(widget, 22)
end

local function NameBox(value, set)
  local widget = Acquire("name", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.label = Label(frame)
    frame.label:SetText("Name")
    local box = CreateFrame("EditBox", nil, frame)
    box:SetPoint("LEFT", LABEL_WIDTH, 0)
    box:SetSize(180, 20)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(6, 6, 0, 0)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.15, 1)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    frame.box = box
    return frame
  end)
  widget.box:SetText(value or "")
  widget.box:SetScript("OnEditFocusLost", function(self)
    local text = strtrim(self:GetText() or "")
    if text ~= "" and text ~= value then
      set(text)
      -- Focus is also lost when the window redraws; finish that first.
      ns.Schedule(Changed)
    end
  end)
  Place(widget, 22)
end

-- A label and a button showing the current choice; clicking opens a menu of
-- items (from items(), so it's built when opened).
local function Dropdown(labelText, valueText, items)
  local widget = Acquire("dropdown", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.label = Label(frame)
    frame.button = NewButton(frame, 220, 20)
    frame.button:SetPoint("LEFT", LABEL_WIDTH, 0)
    frame.button.text:SetJustifyH("LEFT")
    frame.button.text:SetPoint("RIGHT", -18, 0)
    local arrow = frame.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    return frame
  end)
  widget.label:SetText(labelText)
  widget.button:SetWidth(math.min(220, Room() - LABEL_WIDTH))
  widget.button.text:SetText(valueText)
  widget.button:SetScript("OnClick", function() ns.Menu.Open(items()) end)
  Place(widget, 22)
end

local function Action(text, onClick)
  local widget = Acquire("action", function() return NewButton(panel, 200, 22) end)
  widget.text:SetText(text)
  widget.text:SetJustifyH("CENTER")
  widget:SetScript("OnClick", onClick)
  widget:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft, cursorY)
  cursorY = cursorY - 28
end

local function ActionRow(leftText, leftClick, rightText, rightClick)
  local width = math.floor((Room() - 6) / 2)
  local left = Acquire("actionRow", function() return NewButton(panel, width, 22) end)
  left:SetSize(width, 22)
  left.text:SetText(leftText)
  left.text:SetJustifyH("CENTER")
  left:SetScript("OnClick", leftClick)
  left:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft, cursorY)

  if rightText then
    local right = Acquire("actionRow", function() return NewButton(panel, width, 22) end)
    right:SetSize(width, 22)
    right.text:SetText(rightText)
    right.text:SetJustifyH("CENTER")
    right:SetScript("OnClick", rightClick)
    right:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft + width + 6, cursorY)
  end
  cursorY = cursorY - 28
end

local function ActionTriple(leftText, leftClick, middleText, middleClick, rightText, rightClick)
  local width = math.floor((Room() - 12) / 3)

  local left = Acquire("actionRow", function() return NewButton(panel, width, 22) end)
  left:SetSize(width, 22)
  left.text:SetText(leftText)
  left.text:SetJustifyH("CENTER")
  left:SetScript("OnClick", leftClick)
  left:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft, cursorY)

  local middle = Acquire("actionRow", function() return NewButton(panel, width, 22) end)
  middle:SetSize(width, 22)
  middle.text:SetText(middleText)
  middle.text:SetJustifyH("CENTER")
  middle:SetScript("OnClick", middleClick)
  middle:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft + width + 6, cursorY)

  local right = Acquire("actionRow", function() return NewButton(panel, width, 22) end)
  right:SetSize(width, 22)
  right.text:SetText(rightText)
  right.text:SetJustifyH("CENTER")
  right:SetScript("OnClick", rightClick)
  right:SetPoint("TOPLEFT", panel, "TOPLEFT", indentLeft + (width + 6) * 2, cursorY)

  cursorY = cursorY - 28
end

local function ProfileActionGrid(name, profile)
  ActionRow("Export Profile", function() ns.Share.ShowExport(profile, name) end,
    "Import Profile", function() ns.Share.ShowImport() end)
  ActionRow("Duplicate Profile", function()
    viewedName = ns.DuplicateProfile(name) or viewedName
    selected = "general"
    Options.Refresh()
  end, "Import Bar", function() ns.Share.ShowImportBar(name) end)
  ActionRow("Rebuild From Bars", function() ns.RebuildFromActionBars(name) end,
    "Quick Setup", function() ns.QuickSetup.Show(profile) end)
end

local function HideDeleteProfileModal()
  if deleteModal then deleteModal:Hide() end
end

local function ShowDeleteProfileModal(name)
  if not deleteModal then return end
  deleteModal.text:SetText("Delete profile \"" .. tostring(name) .. "\"?")
  deleteModal.yes:SetScript("OnClick", function()
    HideDeleteProfileModal()
    ns.DeleteProfile(name)
    viewedName, selected = nil, "general"
    Options.Refresh()
  end)
  deleteModal.no:SetScript("OnClick", function() HideDeleteProfileModal() end)
  deleteModal:Show()
end

-- A page's title, with tabs on the right (tabs: { { key, label }, ... }).
local function PageHeader(text, tabs, current, pick)
  local widget = Acquire("pagehead", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.text:SetPoint("LEFT")
    frame.text:SetJustifyH("LEFT")
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0.2, 0.35)
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 0, -4)
    line:SetPoint("BOTTOMRIGHT", 0, -4)
    frame.tabs = {}
    return frame
  end)
  widget.text:SetText(text)
  local right, count = 0, tabs and #tabs or 0
  for index = count, 1, -1 do
    local tab = widget.tabs[index] or NewButton(widget, 80, 22)
    widget.tabs[index] = tab
    local choice = tabs[index]
    tab.text:SetText(choice[2])
    tab.text:SetJustifyH("CENTER")
    local width = math.max(64, math.ceil(tab.text:GetStringWidth()) + 22)
    tab:SetSize(width, 22)
    tab:ClearAllPoints()
    tab:SetPoint("RIGHT", widget, "RIGHT", -right, 0)
    right = right + width + 3
    Flat(tab, choice[1] == current)
    tab:SetScript("OnClick", function() pick(choice[1]) end)
    tab:Show()
  end
  for index = count + 1, #widget.tabs do widget.tabs[index]:Hide() end
  widget.text:SetPoint("RIGHT", widget, "RIGHT", -right - 6, 0)
  Place(widget, 26, 12)
end

-- A full-width button in gold text ("+ Add plugin").
local function AddButton(text, onClick, leftInset, rightInset)
  local widget = Acquire("add", function()
    local button = NewButton(panel, 200, 30)
    button.bg:SetColorTexture(0.08, 0.08, 0.1, 1)
    local edge = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.42, 0.36, 0.22, 1)
    button.text:SetJustifyH("CENTER")
    button.text:SetTextColor(1, 0.82, 0.2)
    return button
  end)
  widget.text:SetText(text)
  widget:SetScript("OnClick", onClick)
  widget:SetPoint("TOPLEFT", panel, "TOPLEFT", leftInset or indentLeft, cursorY)
  widget:SetPoint("RIGHT", panel, "RIGHT", -(rightInset or indentRight), 0)
  widget:SetHeight(30)
  cursorY = cursorY - 40
end

-- Panels -------------------------------------------------------------------------------------

local function Grows(vertical)
  if vertical then return { { "CENTER", "From center" }, { "DOWN", "Down" }, { "UP", "Up" } } end
  return { { "CENTER", "From center" }, { "RIGHT", "Right" }, { "LEFT", "Left" } }
end

local function CurrentGrow(bar)
  local grow = bar.grow or "CENTER"
  for _, choice in ipairs(Grows(bar.orientation == "VERTICAL")) do
    if choice[1] == grow then return grow end
  end
  return "CENTER"
end

-- Visibility options, with optional profile defaults + per-config overrides.
local function VisibilitySection(config, scaleKey, defaults, title)
  Header(title or "Visibility")

  if defaults then
    local function DefaultSetting(key, fallback)
      local value = defaults[key]
      if value == nil then return fallback end
      return value
    end
    local function ShowLabel(value)
      return ns.ListLabel({
        { "always", "always" },
        { "combat", "in combat" },
      }, value)
    end
    local function AlphaLabel(alpha)
      local percent = math.floor((alpha or 0) * 100 + 0.5)
      if percent <= 0 then return "hidden otherwise" end
      return ("faded to %d%% otherwise"):format(percent)
    end

    local profileShow = DefaultSetting("show", "always")
    Choice("Show", {
      { "default", "Default" },
      { "always", "Always" },
      { "combat", "In combat" },
    }, config.show == nil and "default" or config.show, function(value)
      config.show = value ~= "default" and value or nil
    end)

    local showValue = config.show ~= nil and config.show or profileShow
    local profileFade = DefaultSetting("fadeAlpha", 0)
    Choice("When hidden", {
      { "default", "Default" },
      { "hide", "Hide" },
      { "fade", "Fade" },
    }, config.fadeAlpha == nil and "default" or ((config.fadeAlpha or 0) <= 0 and "hide" or "fade"), function(value)
      if value == "default" then
        config.fadeAlpha = nil
      elseif value == "hide" then
        config.fadeAlpha = 0
      else
        if config.fadeAlpha == nil or config.fadeAlpha <= 0 then config.fadeAlpha = profileFade > 0 and profileFade or 0.3 end
      end
    end)
    local fadeShown = (config.fadeAlpha ~= nil and config.fadeAlpha > 0)
      or (config.fadeAlpha == nil and profileFade > 0 and showValue ~= "always")
    if fadeShown and showValue ~= "always" then
      local current = config.fadeAlpha
      if current == nil then current = profileFade > 0 and profileFade or 0.3 end
      Stepper("Fade opacity %", math.floor(current * 100 + 0.5), 10, 10, 100,
        function(value) config.fadeAlpha = value / 100 end)
    end

    local profileMounted = DefaultSetting("hideMounted", false)
    Choice("Mounted", {
      { "default", "Default" },
      { "hide", "Hide" },
      { "show", "Keep shown" },
    }, config.hideMounted == nil and "default" or (config.hideMounted and "hide" or "show"), function(value)
      if value == "default" then
        config.hideMounted = nil
      else
        config.hideMounted = (value == "hide") or false
      end
    end)
    Note(("Default is the profile's choice (on its General page): shown %s, %s, %s while mounted."):format(
      ShowLabel(profileShow), AlphaLabel(profileFade), profileMounted and "hidden" or "kept"))

    local profileAlpha = DefaultSetting("alpha", 1)
    local alphaOverride = config.alpha ~= nil
    Checks({ { "Own opacity", alphaOverride, function()
      if config.alpha ~= nil then config.alpha = nil else config.alpha = profileAlpha end
    end } })
    if config.alpha ~= nil then
      Stepper("Opacity %", math.floor((config.alpha or profileAlpha) * 100 + 0.5), 10, 10, 100,
        function(value) config.alpha = value / 100 end)
    end
  else
    Choice("Show", { { "always", "Always" }, { "combat", "In combat" } },
      config.show or "always", function(value) config.show = value end)
    if (config.show or "always") ~= "always" then
      Choice("Otherwise", { { 0, "Hidden" }, { 0.3, "Faded" } }, config.fadeAlpha or 0,
        function(value) config.fadeAlpha = value > 0 and value or nil end)
    end
    Checks({ { "Hide while mounted", config.hideMounted == true, function() config.hideMounted = not config.hideMounted or nil end } })
    Stepper("Opacity %", math.floor((config.alpha or 1) * 100 + 0.5), 10, 10, 100,
      function(value) config.alpha = value / 100 end)
  end

  if scaleKey then
    Stepper("Scale %", math.floor((config[scaleKey] or 1) * 100 + 0.5), 10, 50, 200,
      function(value) config[scaleKey] = value / 100 end)
  end
end

-- Buttons ------------------------------------------------------------------------------------

-- Bars whose buttons each have a page (listed under the bar).
local BUTTON_PAGES = { cooldowns = true, buffs = true, debuffs = true, alerts = true, charges = true }
local SLOT_NAMES = { [13] = "Trinket 1", [14] = "Trinket 2" }

local function FirstID(value)
  if type(value) == "table" then return value[1] end
  return value
end

local function EntryName(entry)
  if entry.slot then return SLOT_NAMES[entry.slot] or ("Slot " .. entry.slot) end
  if entry.item then return ns.Button.ItemName(entry.item) end
  local id = FirstID(entry.aura) or FirstID(entry.spell)
  local name = id and C_Spell.GetSpellName(id)
  if not ns.issecret(name) and name then return name end
  return "?"
end

local function EntryIcon(entry)
  if entry.slot then return GetInventoryItemTexture("player", entry.slot) end
  if entry.item then return ns.Button.ItemIcon(entry.item) end
  local id = FirstID(entry.aura) or FirstID(entry.spell)
  return id and C_Spell.GetSpellTexture(id)
end

local function WithIcon(icon, text)
  if ns.issecret(icon) or not icon then return text end
  return ("|T%s:14:14:0:0:64:64:5:59:5:59|t %s"):format(tostring(icon), text)
end

local BAR_TABS = { { "plugins", "Behaviors" }, { "layout", "Layout" }, { "advanced", "Advanced" } }

-- Remembered choices of the window itself (account-wide): the tab last used.
local function UI()
  CombatHUDDB.ui = CombatHUDDB.ui or {}
  return CombatHUDDB.ui
end

local function PickTab(key)
  return function(tab)
    UI()[key] = tab
    if window.scroll and window.scroll.SetVerticalScroll then window.scroll:SetVerticalScroll(0) end
    Options.Refresh()
  end
end

local BarPluginsPanel

-- The every-buff bar's list: each buff of yours on this class, shown on the
-- bar or hidden. Buffs longer than the bar's limit can't show, so they're
-- kept apart; so are the hidden ones. Sections remember being opened.
local openSections = { shown = true }

local function DurationText(duration)
  if duration == nil then return "?" end
  if duration <= 0 then return "no limit" end
  if duration < 60 then return ("%d sec"):format(duration) end
  if duration < 3600 then return ("%d min"):format(math.floor(duration / 60 + 0.5)) end
  return ("%d hr"):format(math.floor(duration / 3600 + 0.5))
end

-- A section's title, which opens or closes it. Returns whether it's open.
local function SectionToggle(key, text, count)
  local open = openSections[key] == true
  local widget = Acquire("sectionToggle", function()
    local button = CreateFrame("Button", nil, panel)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.text:SetPoint("LEFT")
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)
    return button
  end)
  widget.text:SetText(("%s  %s"):format(open and "-" or "+", count and ("%s (%d)"):format(text, count) or text))
  widget:SetScript("OnClick", function()
    openSections[key] = not open
    Options.Refresh()
  end)
  Place(widget, 18, 2)
  return open
end

-- over: longer than the bar's limit, so it doesn't show: drawn dimmed.
local function BuffRow(buff, actionText, action, over)
  local widget = Acquire("buffRow", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(18, 18)
    frame.icon:SetPoint("LEFT", 12, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    frame.button = NewButton(frame, 56, 18)
    frame.button:SetPoint("RIGHT")
    frame.button.text:SetJustifyH("CENTER")
    frame.time = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.time:SetPoint("RIGHT", frame.button, "LEFT", -8, 0)
    frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.name:SetPoint("LEFT", frame.icon, "RIGHT", 6, 0)
    frame.name:SetPoint("RIGHT", frame.time, "LEFT", -6, 0)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    -- Hovering the row shows the buff's tooltip.
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self) ns.Learn.ShowTooltip(self, self.buff) end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)
    return frame
  end)
  widget.buff = buff
  widget.icon:SetTexture(buff.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  widget.name:SetText(buff.name)
  widget.time:SetText((buff.guessed and "~" or "") .. DurationText(buff.duration))
  widget.time:SetTextColor(over and 1 or 0.6, over and 0.45 or 0.6, over and 0.2 or 0.6)
  widget.icon:SetDesaturated(over == true)
  widget.name:SetTextColor(over and 0.5 or 1, over and 0.5 or 1, over and 0.5 or 1)
  widget.button.text:SetText(actionText)
  widget.button:SetScript("OnClick", action)
  Place(widget, 20, 2)
end

local function BuffList(bar)
  Header("Your buffs")
  local buffs = ns.Learn.Buffs()
  if #buffs == 0 then
    Note("None yet on this class. Every buff you give yourself is listed here once you've had it, to show or hide on this bar.")
    return
  end
  -- Every buff not hidden, in one list: the ones over the bar's length limit
  -- are dimmed, so changing the limit shows straight away what it lets in.
  local limit = bar.maxDuration or 0
  local function Over(buff)
    return limit > 0 and buff.duration ~= nil and (buff.duration <= 0 or buff.duration > limit)
  end
  local fits, over, hidden = {}, {}, {}
  for _, buff in ipairs(buffs) do
    if bar.hide and bar.hide[buff.name] then
      hidden[#hidden + 1] = buff
    elseif Over(buff) then
      over[#over + 1] = buff
    else
      fits[#fits + 1] = buff
    end
  end
  local function Set(buff, hide)
    return function()
      ns.Learn.SetHidden(bar, buff.name, hide)
      Changed()
    end
  end
  local title = ("On this bar: %d show"):format(#fits)
  if #over > 0 then title = title .. (", %d too long"):format(#over) end
  if SectionToggle("shown", title) then
    for _, buff in ipairs(fits) do BuffRow(buff, "Hide", Set(buff, true)) end
    for _, buff in ipairs(over) do BuffRow(buff, "Hide", Set(buff, true), true) end
  end
  if SectionToggle("hidden", "Hidden", #hidden) then
    for _, buff in ipairs(hidden) do BuffRow(buff, "Show", Set(buff, false)) end
  end
  if #over > 0 then
    Note(("Dimmed ones last longer than %s, so they don't show: raise Shorter than to let them in. ~ means the length is read from the buff's description."):format(DurationText(limit)))
  end
  Note("Most recent first. Buffs not seen for two months drop off the list.")
end

-- A bar's page of plain settings. mode "layout": only its own layout and
-- look (the Layout tab; the buttons' options are on the Plugins tab).
-- tabs: whether it's one of the tabs (bars without buttons have only this page).
local function BarPanel(bar, profile, mode, tabs)
  local full = true
  local defaults = bar.buttonDefaults or {}
  bar.buttonDefaults = defaults
  local profileDefaults = profile.buttonDefaults or {}
  local function Opt(key)
    local value = defaults[key]
    if value == nil then value = profileDefaults[key] end
    if value == nil then value = ns.BUTTON_DEFAULTS[key] end
    return value
  end
  -- A bar setting is what every button starts with; a button with its own
  -- choice keeps it (the Plugins tab shows which differ).
  local function SetOpt(key, value)
    defaults[key] = value
  end
  local function Toggle(key) return function() SetOpt(key, not Opt(key)) end end

  local kind = ns.Bar.Type(bar)
  Header(bar.name or "Bar")
  NameBox(bar.name, function(name) bar.name = name end)
  local kindShown = kind == "allbuffs" and "buffs" or kind
  local typeLabel = kindShown
  for _, choice in ipairs(ns.Bar.TYPES) do
    if choice[1] == kindShown then typeLabel = choice[2] end
  end
  Dropdown("Shows", typeLabel, function()
    local items = {}
    for _, choice in ipairs(ns.Bar.TYPES) do
      if choice[1] ~= "allbuffs" then
        items[#items + 1] = { text = choice[2], checked = kindShown == choice[1],
          func = function()
            local selectedKind = choice[1] == "buffs" and "allbuffs" or choice[1]
            ns.Bar.SetType(bar, selectedKind)
            Changed()
          end }
      end
    end
    return items
  end)
  Note(TYPE_NOTES[kindShown] or TYPE_NOTES[kind])
  if full and BUTTON_PAGES[kind] and #(bar.buttons or {}) > 0 then
    Note("What you set here is what every button starts with; a button with its own choice keeps it. Each button has its own page, listed under the bar on the left.")
  end

  ActionTriple("Duplicate", function()
    selected, selectedEntry = ns.DuplicateBar(bar, profile), nil
    Options.Refresh()
  end, "Export", function()
    ns.Share.ShowExportBar(bar)
  end, "Delete", function()
    ns.DeleteBar(bar, profile)
    selected, selectedEntry = "general", nil
    Options.Refresh()
  end)

  Header("Layout")
  local wide = kind == "charges"
  Choice("Direction", { { "HORIZONTAL", "Horizontal" }, { "VERTICAL", "Vertical" } }, bar.orientation or "HORIZONTAL",
    function(value) bar.orientation = value end)
  if kind ~= "absorb" then
    Choice("Grow", Grows(bar.orientation == "VERTICAL"), CurrentGrow(bar), function(value) bar.grow = value end)
  end
  if kind == "absorb" then
    Stepper("Length", bar.width or 160, 10, 20, 600, function(value) bar.width = value end)
    Stepper("Thickness", bar.size or 22, 1, 2, 60, function(value) bar.size = value end)
  elseif kind == "charges" and Opt("chargeLook") ~= "bar" then
    Stepper("Size", bar.size or 24, 1, 8, 64, function(value) bar.size = value end)
  elseif wide then
    Stepper("Width", bar.width or 120, 10, 30, 600, function(value) bar.width = value end)
    Stepper("Height", bar.size or 12, 1, 4, 40, function(value) bar.size = value end)
  else
    Stepper("Icon size", bar.size or 40, 2, 16, 96, function(value) bar.size = value end)
  end
  if kind ~= "absorb" then
    Stepper("Spacing", bar.spacing or 4, 1, 0, 30, function(value) bar.spacing = value end)
  end
  if kind == "cooldowns" then
    Checks({ { "Close gaps when buttons hide", bar.collapse ~= false, function() bar.collapse = bar.collapse == false end } })
  end
  if ns.Bar.LIMITS[kind] then
    Stepper("Most buttons", bar.maxButtons or 0, 1, 0, 40, function(value) bar.maxButtons = value > 0 and value or nil end)
    local count = #(bar.buttons or {})
    if (bar.maxButtons or 0) > 0 and count > bar.maxButtons then
      Note(("It has %d, so the last %d don't show. 0: no limit."):format(count, count - bar.maxButtons))
    else
      Note("0: no limit. A full bar takes no more (drops and new buttons are refused).")
    end
  end
  if ns.Bar.WRAPS[kind] then
    local vertical = bar.orientation == "VERTICAL"
    Stepper(vertical and "Per column" or "Per row", bar.perLine or 0, 1, 0, 40, function(value)
      bar.perLine = value > 0 and value or nil
      ns.Bar.Reanchor(bar)
    end)
    if (bar.perLine or 0) > 0 then
      local sides = vertical and { { "RIGHT", "To the right" }, { "LEFT", "To the left" } } or { { "DOWN", "Below" }, { "UP", "Above" } }
      local current = bar.lineDir or sides[1][1]
      Choice(vertical and "Next column" or "Next row", sides, current, function(value)
        bar.lineDir = value ~= sides[1][1] and value or nil
        ns.Bar.Reanchor(bar)
      end)
    else
      Note(("0: one %s. With a number, it starts a new %s after that many."):format(vertical and "column" or "row", vertical and "column" or "row"))
    end
  end

  VisibilitySection(bar, nil, profile.visibilityDefaults or {})

  -- Charge, cooldown, aura and alert settings for the buttons are in the
  -- plugins below (BarPluginsPanel), not repeated here.
  if kind == "totems" then
    Header("Totems")
    Checks({
      { "Range alert", Opt("totemRange"), Toggle("totemRange") },
      { "Pulse timer", Opt("totemPulse"), Toggle("totemPulse") },
      { "Cooldown bar", Opt("totemCooldown"), Toggle("totemCooldown") },
      { "Countdown number", Opt("numbers"), Toggle("numbers") },
      { "Yards of reach left", Opt("totemDistance"), Toggle("totemDistance") },
    })
    Stepper("Extra reach", Opt("totemExtraRange"), 1, 0, 20, function(value) SetOpt("totemExtraRange", value) end)
  elseif kind == "weapons" then
    Header("Weapon enchants")
    Choice("Show", { { "alert", "When missing or low" }, { "always", "Always" } }, Opt("weaponShow"),
      function(value) SetOpt("weaponShow", value) end)
    Stepper("Low under (sec)", Opt("weaponWarn"), 15, 0, 900, function(value) SetOpt("weaponWarn", value) end)
    Checks({ { "Time left", Opt("numbers"), Toggle("numbers") } })
    Note("In combat the game may hide your enchants: the time is then counted down from the last reading, and casting an imbue or applying a poison counts as renewing it.")
  elseif kind == "allbuffs" or kind == "buffs" then
    Header("Which buffs")
    Stepper("Most icons", bar.maxIcons or 8, 1, 1, 20, function(value) bar.maxIcons = value end)
    Choice("Shorter than", { { 0, "Any length" }, { 30, "30 sec" }, { 60, "1 min" }, { 300, "5 min" } },
      bar.maxDuration or 0, function(value) bar.maxDuration = value > 0 and value or nil end)
    if kind == "allbuffs" then BuffList(bar) end
  elseif kind == "absorb" then
    Header("Shield")
    Choice("Shields on", { { "player", "Me" }, { "target", "My target (mine only)" } }, bar.unit or "player",
      function(value) bar.unit = value end)
    Choice("Text", { { "value", "Amount" }, { "none", "None" } }, bar.text == "none" and "none" or "value",
      function(value) bar.text = value end)
    Choice("Look", { { "bar", "Plain bar" }, { "segments", "Segments" } }, bar.look or "bar",
      function(value) bar.look = value end)
    if bar.look == "segments" then
      Stepper("Segments", bar.segments or 16, 1, 2, 40, function(value) bar.segments = value end)
      Stepper("Gap", bar.gap or 3, 1, 0, 12, function(value) bar.gap = value end)
    end
    Stepper("Bend (degrees)", bar.bend or 0, 15, 0, 180, function(value) bar.bend = value > 0 and value or nil end)
    if (bar.bend or 0) > 0 then
      local sides = bar.orientation == "VERTICAL" and { { false, "Right" }, { true, "Left" } } or { { false, "Down" }, { true, "Up" } }
      Choice("Bulges", sides, bar.bendFlip == true, function(value) bar.bendFlip = value or nil end)
    end
    Dropdown("Color", ns.ListLabel(ns.Absorb.COLORS, bar.color), function()
      local items = {}
      for _, color in ipairs(ns.Absorb.COLORS) do
        items[#items + 1] = { text = color[2], checked = (bar.color or "gold") == color[1],
          func = function() bar.color = color[1]; Changed() end }
      end
      return items
    end)
    Checks({ { "Only while shielded", bar.hideEmpty ~= false, function() bar.hideEmpty = bar.hideEmpty == false end } })
    Note("Full is always the shield's size when cast: its buff's own value when the game shows it, else the number in its tooltip (which may leave out +healing from gear). On the target, the bar only shows while your shield is on it; the game only reports all its shields together, so someone else's shield on it counts too. /chud debug shield shows what the game reports.")
  end

  -- The every-buff bar has no plugins, so its aura settings are here.
  if full and kind == "allbuffs" then
    Header("Auras")
    Choice("Time left", { { "spinner", "Spinner" }, { "number", "Number" }, { "both", "Both" } }, Opt("auraTimer"),
      function(value) SetOpt("auraTimer", value) end)
    Checks({ { "Rotating border while up", Opt("auraGlow"), Toggle("auraGlow") } })
    Stepper("Time red under", Opt("timerRed"), 1, 0, 15, function(value) SetOpt("timerRed", value) end)
  end

  if full and BUTTON_PAGES[kind] then
    BarPluginsPanel(bar, profile, true)
  end

  cursorY = cursorY - 8
  if ns.Bar.Type(bar) == "cooldowns" then
    local count = ns.Groups.Collapsible(bar.buttons or {})
    if count > 0 then
      Action(("Stack shared cooldowns (%d)"):format(count), function()
        ns.Groups.Collapse(bar.buttons)
        ns.Rebuild(true)
        Options.Refresh()
      end)
    end
  end
end

-- A meter's own bar texture, or the HUD's.
local function TexturePick(config)
  local current = config.texture and ns.ListLabel(ns.TEXTURES, config.texture) or "Same as the HUD"
  Dropdown("Bar texture", current, function()
    local items = { { text = "Same as the HUD", checked = config.texture == nil,
      func = function() config.texture = nil; Changed() end } }
    for _, texture in ipairs(ns.TEXTURES) do
      items[#items + 1] = { text = texture[2], checked = config.texture == texture[1],
        func = function() config.texture = texture[1]; Changed() end }
    end
    return items
  end)
end

-- One of the glow colors (Glow.COLORS) for config[key].
local function ColorPick(labelText, config, key, fallback)
  local current = config[key] or fallback
  Dropdown(labelText, ns.ListLabel(ns.Glow.COLORS, current), function()
    local items = {}
    for _, color in ipairs(ns.Glow.COLORS) do
      items[#items + 1] = { text = color[2], checked = current == color[1],
        func = function() config[key] = color[1]; Changed() end }
    end
    return items
  end)
end

local function PowerPanel(profile)
  local power = profile.power or {}
  profile.power = power
  Header("Power bar")
  Checks({
    { "Show the power bar", power.enabled ~= false, function() power.enabled = power.enabled == false end },
    { "5-second rule spark", power.fiveSecond ~= false, function() power.fiveSecond = power.fiveSecond == false end },
  })
  Stepper("Width", power.width or 250, 10, 60, 600, function(value) power.width = value end)
  Stepper("Height", power.height or 14, 1, 4, 40, function(value) power.height = value end)
  TexturePick(power)
  Choice("Text", { { "value", "Value" }, { "percent", "Percent" }, { "both", "Both" }, { "none", "None" } },
    power.text or "value", function(value) power.text = value end)
  VisibilitySection(power, nil, profile.visibilityDefaults or {})
  cursorY = cursorY - 8
end

local function HealthPanel(profile)
  local health = profile.health or {}
  profile.health = health
  Header("Health bar")
  Checks({
    { "Show the health bar", health.enabled == true, function() health.enabled = health.enabled ~= true end },
  })
  Stepper("Width", health.width or 250, 10, 60, 600, function(value) health.width = value end)
  Stepper("Height", health.height or 14, 1, 4, 40, function(value) health.height = value end)
  TexturePick(health)
  Choice("Text", { { "value", "Value" }, { "percent", "Percent" }, { "both", "Both" }, { "none", "None" } },
    health.text or "value", function(value) health.text = value end)
  VisibilitySection(health, nil, profile.visibilityDefaults or {})
  cursorY = cursorY - 8
end

local function CastPanel(profile)
  -- Profiles from before the cast bar get one under the power bar.
  local cast = profile.cast or { width = 250, height = 16, x = 0, y = -170 }
  profile.cast = cast
  Header("Cast bar")
  Checks({
    { "Show the cast bar", cast.enabled == true, function() cast.enabled = cast.enabled ~= true end },
    { "Hide the game's cast bar", cast.hideGame ~= false, function() cast.hideGame = cast.hideGame == false end },
    { "Spell name", cast.showName ~= false, function() cast.showName = cast.showName == false end },
    { "Time left", cast.showTime ~= false, function() cast.showTime = cast.showTime == false end },
  })
  Stepper("Width", cast.width or 250, 10, 60, 600, function(value) cast.width = value end)
  Stepper("Height", cast.height or 16, 1, 6, 40, function(value) cast.height = value end)
  TexturePick(cast)
  ColorPick("Cast color", cast, "castColor", "gold")
  ColorPick("Channel color", cast, "channelColor", "green")
  Note("Interrupted casts flash red.")
  VisibilitySection(cast, nil, profile.visibilityDefaults or {})
  cursorY = cursorY - 8
end

local function SwingPanel(profile)
  local swing = profile.swing or {}
  profile.swing = swing
  Header("Swing timer")
  Checks({
    { "Show the swing timer", swing.enabled == true, function() swing.enabled = swing.enabled ~= true end },
  })
  -- Auto: what you have equipped. Otherwise any of the three rows.
  local auto = swing.mode ~= "pick"
  local hands = swing.hands or {}
  local function Hand(key)
    return function()
      swing.hands = swing.hands or {}
      swing.hands[key] = not swing.hands[key] or nil
    end
  end
  Checks({
    { "Auto: what's equipped", auto, function()
      if auto then
        swing.mode = "pick"
        swing.hands = swing.hands or { main = true }
      else
        swing.mode = "auto"
      end
    end },
  })
  if auto then
    Note("Main hand always, off hand while you dual wield, ranged for hunters.")
  else
    Checks({
      { "Main hand", hands.main == true, Hand("main") },
      { "Off hand", hands.off == true, Hand("off") },
      { "Ranged", hands.ranged == true, Hand("ranged") },
    })
  end
  Choice("Fill", { { "down", "Count down" }, { "up", "Fill up" } },
    swing.fill or "down", function(value) swing.fill = value end)
  Stepper("Gap between rows", swing.gap or 1, 1, 0, 20, function(value) swing.gap = value end)
  Choice("Row background", {
      { "dark", "Dark" }, { "slate", "Slate" }, { "blue", "Blue" }, { "green", "Green" }, { "red", "Red" },
    }, swing.bgColor or "dark", function(value) swing.bgColor = value end)
  Stepper("Container opacity %", math.floor((swing.containerAlpha or 0.8) * 100 + 0.5), 10, 0, 100,
    function(value) swing.containerAlpha = value / 100 end)
  Stepper("Width", swing.width or 250, 10, 60, 600, function(value) swing.width = value end)
  Stepper("Height", swing.height or 14, 1, 4, 40, function(value) swing.height = value end)
  VisibilitySection(swing, nil, profile.visibilityDefaults or {})
  cursorY = cursorY - 8
end

local deleteArmed -- what a first click on Delete or Rebuild was for

-- A second click within the same page does it.
local function Confirm(key, label, confirmLabel, action)
  Action(deleteArmed == key and confirmLabel or label, function()
    if deleteArmed == key then
      deleteArmed = nil
      action()
    else
      deleteArmed = key
    end
    Options.Refresh()
  end)
end

-- Plugin cards -------------------------------------------------------------------------------------
local Plugins = ns.Plugins or ns.Modules
local Modules = Plugins

local shownCards = setmetatable({}, { __mode = "k" }) -- layer (entry or bar) -> plugin id -> shown though off
local openCards = setmetatable({}, { __mode = "k" })  -- layer -> plugin id -> open

local function Mark(store, layerKey, id, value)
  store[layerKey] = store[layerKey] or {}
  store[layerKey][id] = value or nil
end

local function Marked(store, layerKey, id)
  return store[layerKey] ~= nil and store[layerKey][id] == true
end

local function ActionSlotLabel(slot)
  return ("action slot %d (bar %d, button %d)"):format(slot, math.ceil(slot / 12), (slot - 1) % 12 + 1)
end

-- A sound choice with a button to hear it.
local function SoundRow(labelText, value, pick, name, fallback)
  local widget = Acquire("soundrow", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.label = Label(frame)
    frame.button = NewButton(frame, 200, 20)
    frame.button:SetPoint("LEFT", LABEL_WIDTH, 0)
    frame.button.text:SetJustifyH("LEFT")
    frame.button.text:SetPoint("RIGHT", -18, 0)
    local arrow = frame.button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    frame.play = NewButton(frame, 22, 20)
    frame.play.text:SetText(">")
    frame.play.text:SetJustifyH("CENTER")
    frame.play:SetPoint("LEFT", frame.button, "RIGHT", 4, 0)
    return frame
  end)
  widget.label:SetText(labelText)
  widget.button:SetWidth(math.max(100, Room() - LABEL_WIDTH - 28))
  widget.button.text:SetText(ns.Sounds.Label(value))
  widget.button:SetScript("OnClick", function()
    ns.Menu.Open(ns.Sounds.MenuItems(value, function(key) pick(key); Changed() end, name, fallback))
  end)
  widget.play:SetScript("OnClick", function() ns.Sounds.Preview(value, name, fallback) end)
  widget.play:SetShown(value ~= nil and value ~= "none")
  Place(widget, 22)
end

-- A line with an optional small "x" to take it out.
-- A line with an optional small "x" to take it out (and ">" to hear it).
local function MemberRow(text, onRemove, onPlay)
  local widget = Acquire("member", function()
    local frame = CreateFrame("Frame", nil, panel)
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.text:SetPoint("LEFT")
    frame.text:SetJustifyH("LEFT")
    frame.remove = NewButton(frame, 20, 18)
    frame.remove.text:SetText("x")
    frame.remove.text:SetJustifyH("CENTER")
    frame.remove:SetPoint("RIGHT")
    frame.play = NewButton(frame, 20, 18)
    frame.play.text:SetText(">")
    frame.play.text:SetJustifyH("CENTER")
    frame.play:SetPoint("RIGHT", frame.remove, "LEFT", -3, 0)
    return frame
  end)
  widget.text:SetText(text)
  widget.text:SetPoint("RIGHT", widget, "RIGHT", -50, 0)
  widget.remove:SetShown(onRemove ~= nil)
  widget.remove:SetScript("OnClick", function()
    if onRemove then onRemove() end
  end)
  widget.play:SetShown(onPlay ~= nil)
  widget.play:SetScript("OnClick", function()
    if onPlay then onPlay() end
  end)
  Place(widget, 20, 2)
end

-- A cooldown's own buff, or one picked from the buffs on you now, for the
-- alerts "When my buff is applied" and "When my buff expires".
local function WatchAuraPicker(ctx)
  local entry = ctx.entry
  local label = "Nothing"
  if entry.watchAura == true then
    label = "Its own buff"
  elseif type(entry.watchAura) == "table" then
    label = tostring(C_Spell.GetSpellName(entry.watchAura[1]) or entry.watchAura[1])
  end
  Dropdown("Watch my buff", label, function()
    local items = {
      { text = "Nothing", checked = entry.watchAura == nil, func = function() entry.watchAura = nil; Changed() end },
      { text = "Its own buff (learned when you cast it)", checked = entry.watchAura == true,
        func = function() entry.watchAura = true; Changed() end },
      { separator = true },
      { text = "A buff I have now", isTitle = true },
    }
    local getAura = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for index = 1, 40 do
      if not getAura then break end
      local ok, aura = pcall(getAura, "player", index, "HELPFUL")
      if not ok or ns.issecret(aura) or not aura or ns.issecret(aura.spellId) or ns.issecret(aura.name) then break end
      local id = aura.spellId
      items[#items + 1] = { text = ("%s (%d)"):format(aura.name, id), icon = aura.icon,
        checked = type(entry.watchAura) == "table" and entry.watchAura[1] == id,
        func = function() entry.watchAura = { id }; Changed() end }
    end
    return items
  end)
end

-- Where the game's range check for a button comes from.
local function RangeInfo(ctx)
  if ctx.layer ~= "button" or viewedName ~= ns.profileName then
    Note("The game reports range for what's on an action bar, so each spell or item needs to be on one (a hidden bar is fine).")
    return
  end
  local slot, hasRange = ns.Range.SlotFor(ctx.entry)
  if not slot then
    Note("|cffff8040Not on an action bar:|r put it on one (a hidden bar is fine) so the game reports its range.")
  elseif hasRange == false then
    Note(("Found on %s, but the game reports no range for it."):format(ActionSlotLabel(slot)))
  else
    Note(("Found on %s."):format(ActionSlotLabel(slot)))
  end
end

-- A shared cooldown's members, its icon choice, and a known family's rest.
local function GroupMembers(ctx)
  local entry = ctx.entry
  local groups = ns.Groups
  local members = groups.Members(entry)
  for index, id in ipairs(members) do
    local name = entry.item and ns.Button.ItemName(id) or C_Spell.GetSpellName(id) or tostring(id)
    local icon = entry.item and ns.Button.ItemIcon(id) or C_Spell.GetSpellTexture(id)
    local text = WithIcon(icon, tostring(name))
    if index == 1 then text = text .. "  |cff888888(the button's own)|r" end
    MemberRow(text, index > 1 and function()
      groups.Remove(entry, id)
      Changed()
    end or nil)
  end
  cursorY = cursorY - 4
  if groups.IsGroup(entry) then
    Choice("Icon", { { "last", "The one used last" }, { "first", "Always its own" } }, entry.groupIcon or "last",
      function(value) entry.groupIcon = value ~= "last" and value or nil end)
  end
  local family = entry.spell and groups.FamilyOf(members[1])
  local missing = family and groups.Missing(entry, family) or {}
  if #missing > 0 then
    Action("Add the rest: " .. family.name, function()
      for _, id in ipairs(missing) do groups.Add(entry, { spell = id }) end
      Changed()
    end)
  end
  Note("To add one, hold Shift or Alt and drop a spell or item on this button in edit mode, then pick \"Stack them\". They share one cooldown; with Target debuff, every member's debuff shows.")
end

-- The Icon swap card: which spell's icon shows on a proc, and how to stop it.
local function SwapInfo(ctx)
  local entry = ctx.entry
  if entry.swap then
    local id = FirstID(entry.swap)
    MemberRow(WithIcon(C_Spell.GetSpellTexture(id), tostring(C_Spell.GetSpellName(id) or id)) .. "  |cff888888(while it's highlighted)|r")
    Action("Stop swapping", function()
      entry.swap = nil
      Changed()
    end)
  end
  Note("To swap to a spell, hold Shift or Alt and drop it on this button in edit mode, then pick \"Show its icon while it procs\".")
end

-- A charge bar's look: segments, orbs (with a theme), gems (with a color) or the spell's icon.
local function ChargeLook(ctx, get, set)
  local bar = ctx.bar
  Choice("Look", { { "bar", "Segments" }, { "orbs", "Orbs" }, { "gems", "Gems" }, { "icon", "Spell icon" } }, get("chargeLook"),
    function(value)
      set("chargeLook", value)
      -- Orbs and icons need some size to read.
      if value ~= "bar" and (bar.size or 12) < 20 then bar.size = 24 end
      if value == "bar" and (bar.size or 12) > 24 then bar.size = 12 end
    end)
  local look = get("chargeLook")
  if look == "orbs" or look == "gems" then
    local list, key = ns.Charges.ORBS, "chargeOrb"
    if look == "gems" then list, key = ns.Charges.GEMS, "chargeGem" end
    Dropdown(look == "orbs" and "Orb style" or "Gem color", ns.ListLabel(list, get(key)), function()
      local items = {}
      for _, style in ipairs(list) do
        items[#items + 1] = { text = style[2], icon = ns.Charges.Texture(look, style[1], true),
          checked = get(key) == style[1], func = function() set(key, style[1]); Changed() end }
      end
      return items
    end)
  end
end

-- The Alerts card: existing alerts plus modal add/edit.
local alertModal

local function EnsureAlertModal()
  if alertModal then return alertModal end
  alertModal = CreateFrame("Frame", "CombatHUDAlertModal", UIParent)
  alertModal:SetFrameStrata("FULLSCREEN_DIALOG")
  alertModal:SetSize(420, 240)
  alertModal:SetPoint("CENTER")
  alertModal:EnableMouse(true)
  alertModal:SetMovable(true)
  alertModal:SetClampedToScreen(true)
  alertModal:RegisterForDrag("LeftButton")
  alertModal:SetScript("OnDragStart", alertModal.StartMoving)
  alertModal:SetScript("OnDragStop", alertModal.StopMovingOrSizing)
  alertModal:Hide()

  local edge = alertModal:CreateTexture(nil, "BACKGROUND", nil, -1)
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.35, 0.35, 0.4, 1)
  local bg = alertModal:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.98)

  alertModal.title = alertModal:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  alertModal.title:SetPoint("TOPLEFT", 14, -12)

  alertModal.type = NewButton(alertModal, 180, 22)
  alertModal.type:SetPoint("TOPLEFT", 14, -42)
  alertModal.type.text:SetJustifyH("LEFT")
  alertModal.type.text:SetPoint("RIGHT", -16, 0)
  local typeArrow = alertModal.type:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  typeArrow:SetPoint("RIGHT", -6, 0)
  typeArrow:SetText("v")

  alertModal.when = NewButton(alertModal, 390, 22)
  alertModal.when:SetPoint("TOPLEFT", 14, -72)
  alertModal.when.text:SetJustifyH("LEFT")
  alertModal.when.text:SetPoint("RIGHT", -16, 0)
  local whenArrow = alertModal.when:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  whenArrow:SetPoint("RIGHT", -6, 0)
  whenArrow:SetText("v")

  alertModal.value = NewButton(alertModal, 326, 22)
  alertModal.value:SetPoint("TOPLEFT", 14, -102)
  alertModal.value.text:SetJustifyH("LEFT")
  alertModal.value.text:SetPoint("RIGHT", -16, 0)
  local valueArrow = alertModal.value:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueArrow:SetPoint("RIGHT", -6, 0)
  valueArrow:SetText("v")

  alertModal.preview = NewButton(alertModal, 58, 22)
  alertModal.preview:SetPoint("LEFT", alertModal.value, "RIGHT", 6, 0)
  alertModal.preview.text:SetText("Play")
  alertModal.preview.text:SetJustifyH("CENTER")

  alertModal.help = alertModal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  alertModal.help:SetPoint("TOPLEFT", 14, -134)
  alertModal.help:SetPoint("RIGHT", -14, 0)
  alertModal.help:SetJustifyH("LEFT")

  alertModal.save = NewButton(alertModal, 120, 24)
  alertModal.save.text:SetText("Save")
  alertModal.save.text:SetJustifyH("CENTER")
  alertModal.save:SetPoint("BOTTOMLEFT", 42, 18)

  alertModal.cancel = NewButton(alertModal, 120, 24)
  alertModal.cancel.text:SetText("Cancel")
  alertModal.cancel.text:SetJustifyH("CENTER")
  alertModal.cancel:SetPoint("BOTTOMRIGHT", -42, 18)

  table.insert(UISpecialFrames, "CombatHUDAlertModal")
  return alertModal
end

local function OpenAlertModal(ctx, opts, set, list, editIndex)
  local modal = EnsureAlertModal()
  local triggers = ns.Alerts.Triggers(ctx, opts)
  local byWhen = {}
  for _, trigger in ipairs(triggers) do byWhen[trigger.when] = trigger end
  if #triggers == 0 then return end

  local existing = editIndex and list[editIndex] or nil
  local state = {
    kind = existing and existing.kind or "sound",
    when = existing and existing.when or triggers[1].when,
    sound = existing and existing.sound or "blip",
    visual = existing and existing.visual or "ants:gold",
  }
  if not byWhen[state.when] then state.when = triggers[1].when end

  local function Refresh()
    local trigger = byWhen[state.when]
    modal.title:SetText(editIndex and "Edit Alert" or "Add New Alert")
    modal.type.text:SetText(state.kind == "sound" and "Sound" or "Visual")
    modal.when.text:SetText(trigger and trigger.label or state.when)
    local blocked = state.kind == "visual" and trigger and not trigger.visual
    if state.kind == "sound" then
      modal.value.text:SetText(ns.Sounds.Label(state.sound))
      modal.preview:SetShown(true)
      modal.help:SetText("")
    else
      modal.value.text:SetText(ns.Alerts.Visual(state.visual)[2])
      modal.preview:SetShown(false)
      modal.help:SetText(blocked and "The game can't show a visual for this trigger in combat." or "")
    end
    modal.save:SetEnabled(not blocked)
  end

  modal.type:SetScript("OnClick", function()
    ns.Menu.Open({
      { text = "Sound", checked = state.kind == "sound", func = function() state.kind = "sound"; Refresh() end },
      { text = "Visual", checked = state.kind == "visual", func = function() state.kind = "visual"; Refresh() end },
    })
  end)

  modal.when:SetScript("OnClick", function()
    local items = {}
    for _, option in ipairs(triggers) do
      local usable = state.kind ~= "visual" or option.visual
      items[#items + 1] = {
        text = option.label .. (usable and "" or " (sound only)"),
        checked = state.when == option.when,
        disabled = not usable,
        func = function() state.when = option.when; Refresh() end,
      }
    end
    ns.Menu.Open(items)
  end)

  modal.value:SetScript("OnClick", function()
    if state.kind == "sound" then
      ns.Menu.Open(ns.Sounds.MenuItems(state.sound, function(key) state.sound = key; Refresh() end, ctx.name,
        ns.Alerts.Fallback(state.when, ctx, opts)))
    else
      local items = {}
      for _, row in ipairs(ns.Alerts.VISUALS) do
        items[#items + 1] = { text = row[2], checked = state.visual == row[1], func = function()
          state.visual = row[1]
          Refresh()
        end }
      end
      ns.Menu.Open(items)
    end
  end)

  modal.preview:SetScript("OnClick", function()
    ns.Sounds.Preview(state.sound, ctx.name, ns.Alerts.Fallback(state.when, ctx, opts))
  end)

  modal.cancel:SetScript("OnClick", function()
    modal:Hide()
  end)

  modal.save:SetScript("OnClick", function()
    local copy = ns.Alerts.Copy(list)
    local alert = { when = state.when, kind = state.kind }
    if state.kind == "sound" then alert.sound = state.sound else alert.visual = state.visual end
    if editIndex then copy[editIndex] = alert else copy[#copy + 1] = alert end
    set("alerts", copy)
    modal:Hide()
    Changed()
  end)

  Refresh()
  modal:Show()
end

local function AlertsEditor(ctx, opts, set)
  local list = ns.Alerts.List(opts)
  local triggers = ns.Alerts.Triggers(ctx, opts)
  local byWhen = {}
  for _, trigger in ipairs(triggers) do byWhen[trigger.when] = trigger end

  if ctx.layer == "button" and ctx.entryKind == "spell" then WatchAuraPicker(ctx) end
  for index, alert in ipairs(list) do
    local trigger = byWhen[alert.when]
    local text = ("%s: %s"):format(trigger and trigger.label or alert.when, ns.Alerts.Describe(alert))
    if not trigger then text = text .. "  |cff888888(doesn't apply here)|r" end
    MemberRow(text, function()
      local copy = ns.Alerts.Copy(list)
      table.remove(copy, index)
      set("alerts", copy)
      Changed()
    end, alert.kind == "sound" and function()
      ns.Sounds.Preview(alert.sound, ctx.name, ns.Alerts.Fallback(alert.when, ctx, opts))
    end or nil)
    Action("Edit alert " .. index, function()
      OpenAlertModal(ctx, opts, set, list, index)
    end)
  end
  if #list == 0 then Note("No alerts yet.") end
  if #triggers == 0 then return end
  Action("Add New Alert", function()
    OpenAlertModal(ctx, opts, set, list, nil)
  end)
end

-- The widget helpers a module's card body draws with (Modules.lua: draw(h, ctx)).
local function Helper(ctx, opts, set)
  local function Get(key)
    if ns.BUTTON_DEFAULTS[key] == nil then return ctx.entry and ctx.entry[key] end
    return opts[key]
  end
  local h = { Opt = Get, Set = set, Note = Note, Action = Action }
  function h.Opts() return opts end
  function h.Choice(labelText, choices, key)
    Choice(labelText, choices, Get(key), function(value) set(key, value) end)
  end
  function h.Checks(items)
    local list = {}
    for _, item in ipairs(items) do
      local key = item[2]
      list[#list + 1] = { item[1], Get(key) == true, function() set(key, Get(key) ~= true) end }
    end
    Checks(list)
  end
  -- A dropdown over a { key, label, ... } list.
  function h.Pick(labelText, list, key)
    Dropdown(labelText, ns.ListLabel(list, Get(key)), function()
      local items = {}
      for _, choice in ipairs(list) do
        items[#items + 1] = { text = choice[2], checked = Get(key) == choice[1],
          func = function() set(key, choice[1]); Changed() end }
      end
      return items
    end)
  end
  function h.Stepper(labelText, key, step, low, high)
    Stepper(labelText, Get(key) or low, step, low, high, function(value) set(key, value) end)
  end
  function h.Sound(labelText, key, fallback)
    SoundRow(labelText, Get(key), function(value) set(key, value) end, ctx.name, fallback)
  end
  function h.WatchAura() WatchAuraPicker(ctx) end
  function h.Alerts() AlertsEditor(ctx, opts, set) end
  function h.RangeInfo() RangeInfo(ctx) end
  function h.GroupMembers() GroupMembers(ctx) end
  function h.SwapInfo() SwapInfo(ctx) end
  function h.ChargeLook() ChargeLook(ctx, Get, set) end
  return h
end

-- The + Add picker --------------------------------------------------------------------------------------
local picker

local function ClosePicker()
  if picker then picker:Hide() end
end

local function CreatePicker()
  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("FULLSCREEN_DIALOG")
  catcher:RegisterForClicks("AnyUp")
  catcher:SetScript("OnClick", ClosePicker)
  catcher:Hide()

  picker = CreateFrame("Frame", "CombatHUDPicker", UIParent)
  picker:SetFrameStrata("FULLSCREEN_DIALOG")
  picker:SetFrameLevel(catcher:GetFrameLevel() + 10)
  picker:SetWidth(440)
  picker:EnableMouse(true)
  local border = picker:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  border:SetColorTexture(0.85, 0.6, 0.1, 1)
  local bg = picker:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.08, 0.11, 0.98)
  picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  picker.title:SetPoint("TOPLEFT", 14, -12)
  picker.texts, picker.rows, picker.presets = {}, {}, {}
  picker.catcher = catcher
  picker:SetScript("OnHide", function() catcher:Hide() end)
  table.insert(UISpecialFrames, "CombatHUDPicker") -- Escape closes it
  picker:Hide()
end

local function PickerText(index)
  local text = picker.texts[index] or picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  picker.texts[index] = text
  text:ClearAllPoints()
  text:Show()
  return text
end

local function PickerRow(index)
  local row = picker.rows[index]
  if not row then
    row = CreateFrame("Button", nil, picker)
    row:SetHeight(26)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.14, 0.14, 0.17, 1)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(0.85, 0.6, 0.1, 0.35)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetWidth(130)
    row.name:SetJustifyH("LEFT")
    row.blurb = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.blurb:SetPoint("LEFT", 142, 0)
    row.blurb:SetPoint("RIGHT", -56, 0)
    row.blurb:SetJustifyH("LEFT")
    row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.tag:SetPoint("RIGHT", -8, 0)
    picker.rows[index] = row
  end
  row:ClearAllPoints()
  row:Show()
  return row
end

local function PickerPreset(index)
  local button = picker.presets[index] or NewButton(picker, 90, 30)
  picker.presets[index] = button
  button.text:SetJustifyH("CENTER")
  button:ClearAllPoints()
  button:Show()
  return button
end

-- card: { ctx, layerKey, title }. Picking a plugin switches it on (on the
-- button, or on the bar for every button), shows its card open, and redraws.
local function OpenPicker(card)
  if not picker then CreatePicker() end
  for _, list in ipairs({ picker.texts, picker.rows, picker.presets }) do
    for _, widget in ipairs(list) do widget:Hide() end
  end
  local ctx, layerKey = card.ctx, card.layerKey
  local opts, set = Modules.Opts(ctx), Modules.Setter(ctx)
  picker.title:SetText(card.title)
  local y, texts, rows = -38, 0, 0

  local function Done(ids)
    for _, id in ipairs(ids) do
      Mark(shownCards, layerKey, id, true)
      Mark(openCards, layerKey, id, true)
    end
    ClosePicker()
    Changed()
  end

  if ctx.layer == "button" then
    texts = texts + 1
    local label = PickerText(texts)
    label:SetText("Quick start:")
    label:SetPoint("TOPLEFT", 14, y - 8)
    local x = 86
    for index, preset in ipairs(Modules.PRESETS) do
      local button = PickerPreset(index)
      button.text:SetText(preset.name)
      button:SetSize(80, 30)
      button:SetPoint("TOPLEFT", x, y)
      x = x + 84
      button:SetScript("OnClick", function() Done(Modules.ApplyPreset(preset, ctx, set)) end)
    end
    y = y - 40
  end

  local available = Modules.ForContext(ctx)
  for _, group in ipairs(Modules.GROUPS) do
    local first = true
    for _, module in ipairs(available) do
      if module.group == group[1] and not module.fixed then
        if first then
          first = false
          texts = texts + 1
          local header = PickerText(texts)
          header:SetText(group[2])
          header:SetPoint("TOPLEFT", 14, y - 4)
          y = y - 20
        end
        rows = rows + 1
        local row = PickerRow(rows)
        row:SetPoint("TOPLEFT", 14, y)
        row:SetPoint("RIGHT", picker, "RIGHT", -14, 0)
        local added = Modules.IsOn(module, opts, ctx) or Marked(shownCards, layerKey, module.id)
        row.name:SetText(module.title)
        row.blurb:SetText(module.blurb)
        row.tag:SetText(added and "added" or "")
        row:SetAlpha(added and 0.45 or 1)
        row:SetScript("OnClick", function()
          if added then return end
          module.enable(set, ctx)
          Done({ module.id })
        end)
        y = y - 28
      end
    end
    if not first then y = y - 6 end
  end
  picker:SetHeight(-y + 8)
  picker:ClearAllPoints()
  picker:SetPoint("CENTER", window, "CENTER", LIST_WIDTH / 2, 0)
  picker.catcher:Show()
  picker:Show()
end

-- One card: the header row (switch, title, summary, tag, arrow) and, while
-- open, the plugin's settings inside it. card: { ctx, opts, set, h, layerKey,
-- on, chip, chipOwn, onChip, after }.
local CARD_HEAD = 30

local function Card(module, card)
  local top = cursorY
  local box = Acquire("cardbox", function()
    local frame = CreateFrame("Frame", nil, panel)
    local edge = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0.24, 0.24, 0.29, 1)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.13, 1)
    frame.split = frame:CreateTexture(nil, "ARTWORK")
    frame.split:SetHeight(1)
    frame.split:SetColorTexture(0.24, 0.24, 0.29, 1)
    frame.split:SetPoint("TOPLEFT", 0, -CARD_HEAD)
    frame.split:SetPoint("TOPRIGHT", 0, -CARD_HEAD)
    return frame
  end)
  box:SetFrameLevel(panel:GetFrameLevel()) -- behind the card's widgets
  box:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, top)
  box:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

  local head = Acquire("cardhead", function()
    local frame = CreateFrame("Button", nil, panel)
    local highlight = frame:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.04)
    frame.switch = CreateFrame("Button", nil, frame)
    frame.switch:SetSize(28, 14)
    frame.switch:SetPoint("LEFT", 10, 0)
    frame.track = frame.switch:CreateTexture(nil, "ARTWORK")
    frame.track:SetAllPoints()
    frame.knob = frame.switch:CreateTexture(nil, "OVERLAY")
    frame.knob:SetSize(10, 10)
    frame.knob:SetColorTexture(1, 1, 1, 1)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWidth(140)
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.summary:SetJustifyH("LEFT")
    frame.summary:SetWordWrap(false)
    frame.chip = CreateFrame("Button", nil, frame)
    frame.chip:SetHeight(16)
    frame.chip.edge = frame.chip:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.chip.edge:SetPoint("TOPLEFT", -1, 1)
    frame.chip.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.chip.bg = frame.chip:CreateTexture(nil, "BACKGROUND")
    frame.chip.bg:SetAllPoints()
    frame.chip.bg:SetColorTexture(0.1, 0.1, 0.13, 1)
    frame.chip.text = frame.chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.chip.text:SetPoint("CENTER")
    frame.arrow = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.arrow:SetPoint("RIGHT", -10, 0)
    return frame
  end)
  head:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, top)
  head:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
  head:SetHeight(CARD_HEAD)

  -- The switch (none on plugins an aura or charge button always has).
  local ctx, layerKey = card.ctx, card.layerKey
  head.switch:SetShown(not module.fixed)
  if card.on then
    head.track:SetColorTexture(0.85, 0.6, 0.1, 1)
    head.knob:ClearAllPoints()
    head.knob:SetPoint("RIGHT", head.switch, "RIGHT", -2, 0)
  else
    head.track:SetColorTexture(0.3, 0.3, 0.35, 1)
    head.knob:ClearAllPoints()
    head.knob:SetPoint("LEFT", head.switch, "LEFT", 2, 0)
  end
  head.switch:SetScript("OnClick", function()
    local set = Modules.Setter(ctx)
    if card.on then module.disable(set, ctx) else module.enable(set, ctx) end
    Mark(shownCards, layerKey, module.id, true) -- keeps the card on screen this session
    Changed()
  end)

  local left = module.fixed and 12 or 46
  head.title:ClearAllPoints()
  head.title:SetPoint("LEFT", left, 0)
  head.title:SetText(module.title)
  head.title:SetTextColor(card.on and 1 or 0.6, card.on and 1 or 0.6, card.on and 1 or 0.6)

  -- The tag: "from bar", "this button" (gold; clicking it goes back to the bar's), "2 buttons differ".
  head.chip:SetShown(card.chip ~= nil)
  if card.chip then
    head.chip.text:SetText(card.chip)
    head.chip:SetWidth(math.ceil(head.chip.text:GetStringWidth()) + 16)
    local r, g, b = 0.5, 0.5, 0.55
    if card.chipOwn then r, g, b = 1, 0.75, 0.15 end
    head.chip.text:SetTextColor(r, g, b)
    head.chip.edge:SetColorTexture(r * 0.8, g * 0.8, b * 0.8, 1)
    head.chip:ClearAllPoints()
    head.chip:SetPoint("RIGHT", head, "RIGHT", -28, 0)
    head.chip:SetScript("OnClick", function()
      if card.onChip then card.onChip() end
    end)
  end

  local openable = module.draw ~= nil or card.after ~= nil
  local open = openable and Marked(openCards, layerKey, module.id)
  head.arrow:SetText(openable and (open and "v" or ">") or "")
  head.summary:ClearAllPoints()
  head.summary:SetPoint("LEFT", left + 150, 0)
  if card.chip then
    head.summary:SetPoint("RIGHT", head.chip, "LEFT", -8, 0)
  else
    head.summary:SetPoint("RIGHT", head, "RIGHT", -28, 0)
  end
  local summary
  if card.on then summary = module.summary(card.opts, ctx) else summary = ctx.layer == "bar" and "Off on this bar" or "Off" end
  head.summary:SetText(summary)
  head:SetScript("OnClick", function()
    if not openable then return end
    Mark(openCards, layerKey, module.id, not open)
    Options.Refresh()
  end)

  cursorY = top - CARD_HEAD
  box.split:SetShown(open)
  if open then
    cursorY = cursorY - 10
    indentLeft, indentRight = 56, 14
    if module.draw then module.draw(card.h, ctx) end
    if card.after then card.after() end
    indentLeft, indentRight = 0, 0
    cursorY = cursorY - 4
  end
  box:SetHeight(top - cursorY)
  cursorY = cursorY - 8
end

-- Every plugin card for a button or bar: the ones on, plus any switched or
-- added this session (and on a bar, any a button sets for itself).
local function PluginCards(ctx, layerKey)
  local opts, set = Modules.Opts(ctx), Modules.Setter(ctx)
  local h = Helper(ctx, opts, set)
  for _, module in ipairs(Modules.ForContext(ctx)) do
    local on = module.fixed or Modules.IsOn(module, opts, ctx)
    local differ = ctx.layer == "bar" and Modules.Differing(module, ctx.bar) or 0
    if on or differ > 0 or Marked(shownCards, layerKey, module.id) then
      local card = { ctx = ctx, opts = opts, set = set, h = h, layerKey = layerKey, on = on }
      if ctx.layer == "button" then
        if module.own then
          if on then card.chip, card.chipOwn = "this button", true end
        elseif Modules.IsOwn(module, ctx.entry) then
          card.chip, card.chipOwn = "this button", true
          card.onChip = function()
            Modules.Reset(module, ctx.entry)
            Changed()
          end
        elseif not module.fixed or Modules.IsOwn(module, Modules.Layer(Modules.Context(ctx.profile, ctx.bar, nil))) then
          card.chip = "from bar"
        end
      elseif differ > 0 then
        local word = differ == 1 and "button" or "buttons"
        card.chip = on and ("%d %s differ"):format(differ, word) or ("%d %s add it"):format(differ, word)
        if differ == 1 and on then card.chip = "1 button differs" end
        if differ == 1 and not on then card.chip = "1 button adds it" end
        card.after = function()
          Action("Make every button match", function()
            for _, entry in ipairs(ctx.bar.buttons or {}) do Modules.Reset(module, entry) end
            Changed()
          end)
        end
      end
      if ctx.layer == "bar" and not module.fixed and Modules.IsOwn(module, Modules.Layer(ctx)) then
        local previous = card.after
        card.after = function()
          if previous then previous() end
          Action("Remove from this bar", function()
            Modules.Reset(module, Modules.Layer(ctx))
            Changed()
          end)
        end
      end
      Card(module, card)
    end
  end
end

-- What a cooldown bar's spell button shows: its cooldown or one of its auras.
local function ShowsDropdown(entry)
  local current = ns.EditMenu.ShowsAs(entry)
  Dropdown("Shows", ns.ListLabel(ns.EditMenu.SHOW_AS, current), function()
    local items = {}
    for _, choice in ipairs(ns.EditMenu.SHOW_AS) do
      items[#items + 1] = { text = choice[2], checked = current == choice[1],
        func = function() ns.EditMenu.SetShowsAs(entry, choice[1]); Changed() end }
    end
    return items
  end)
end

local function OpenButtonPicker(profile, bar, entry)
  OpenPicker({ ctx = Modules.Context(profile, bar, entry), layerKey = entry,
    title = "Add a behavior to " .. EntryName(entry) })
end

local function EntryOwnOptionKeys(entry)
  local keys = {}
  for key in pairs(ns.BUTTON_DEFAULTS) do
    if entry[key] ~= nil then keys[#keys + 1] = key end
  end
  return keys
end

-- A button's page of plugin cards (its Plugins tab).
local function ButtonPluginsPanel(bar, entry, profile)
  local ctx = Modules.Context(profile, bar, entry)
  local name = EntryName(entry)
  Header(WithIcon(EntryIcon(entry), name))
  local item = ctx.entryKind == "item" or ctx.entryKind == "slot"
  if item then
    local what = entry.slot and (SLOT_NAMES[entry.slot] or "A trinket slot") or "An item"
    Note(("%s, on %s. This is an item, so only the behaviors that work for items are offered."):format(what, bar.name or "the bar"))
  else
    Note(("On %s. Every behavior starts from the bar's settings; a gold tag means this button changed it."):format(bar.name or "the bar"))
  end
  if ctx.barKind == "cooldowns" and entry.spell then ShowsDropdown(entry) end
  cursorY = cursorY - 4
  PluginCards(ctx, entry)
  AddButton("+ Add a behavior", function() OpenButtonPicker(profile, bar, entry) end, 8, 8)
  if item then
    Note("Not offered for items: Mana cost, Proc glow, Usable glow, Mana tint, Ready-early glow, Target debuff, Sound.")
  end

  cursorY = cursorY - 8
  if #EntryOwnOptionKeys(entry) > 0 then
    Action("Reset to the bar's settings", function()
      for _, key in ipairs(EntryOwnOptionKeys(entry)) do entry[key] = nil end
      Changed()
    end)
  end
  Confirm("remove:" .. tostring(entry), "Remove from the bar", "Click again to remove it", function()
    for index, other in ipairs(bar.buttons) do
      if other == entry then
        table.remove(bar.buttons, index)
        break
      end
    end
    selectedEntry = nil
    ns.Rebuild(true)
  end)
end

-- A line for a button that differs from its bar, opening its page.
local function DiffRow(entry, text, onOpen)
  local widget = Acquire("diff", function()
    local button = CreateFrame("Button", nil, panel)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.13, 1)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.05)
    button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.name:SetPoint("LEFT", 8, 0)
    button.name:SetWidth(150)
    button.name:SetJustifyH("LEFT")
    button.summary = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    button.summary:SetPoint("LEFT", 164, 0)
    button.summary:SetPoint("RIGHT", -50, 0)
    button.summary:SetJustifyH("LEFT")
    button.open = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.open:SetPoint("RIGHT", -10, 0)
    button.open:SetText("Open")
    return button
  end)
  widget.name:SetText(WithIcon(EntryIcon(entry), EntryName(entry)))
  widget.summary:SetText(text)
  widget:SetScript("OnClick", onOpen)
  Place(widget, 34, 4)
end

-- A bar's page of plugin cards (its Plugins tab): what every button starts with.
BarPluginsPanel = function(bar, profile, embedded)
  local ctx = Modules.Context(profile, bar, nil)
  if not embedded then
    PageHeader(bar.name or "Bar", BAR_TABS, "plugins", PickTab("barTab"))
  end
  Note("What every button on this bar starts with. Each button can switch a behavior off, change it, or add one of its own.")
  Header("Behaviors on every button")
  PluginCards(ctx, bar)
  AddButton("+ Add a behavior to this bar", function()
    OpenPicker({ ctx = ctx, layerKey = bar, title = "Add a behavior to " .. (bar.name or "the bar") })
  end, 8, 8)

  local differ = {}
  for _, entry in ipairs(bar.buttons or {}) do
    local text = Modules.DiffSummary(profile, bar, entry)
    if text ~= "" then differ[#differ + 1] = { entry, text } end
  end
  if #differ > 0 then
    Header("Buttons that differ")
    for _, row in ipairs(differ) do
      DiffRow(row[1], row[2], function()
        selectedEntry, deleteArmed = row[1], nil
        if window.scroll and window.scroll.SetVerticalScroll then window.scroll:SetVerticalScroll(0) end
        Options.Refresh()
      end)
    end
  end
  if not embedded then
    cursorY = cursorY - 8
    if ns.Bar.Type(bar) == "cooldowns" then
      local count = ns.Groups.Collapsible(bar.buttons or {})
      if count > 0 then
        Action(("Stack shared cooldowns (%d)"):format(count), function()
          ns.Groups.Collapse(bar.buttons)
          ns.Rebuild(true)
          Options.Refresh()
        end)
      end
    end
    Action("Duplicate this bar", function()
      selected, selectedEntry = ns.DuplicateBar(bar, profile), nil
      Options.Refresh()
    end)
    Action("Export this bar", function() ns.Share.ShowExportBar(bar) end)
    Action("Delete this bar", function()
      ns.DeleteBar(bar, profile)
      selected, selectedEntry = "general", nil
      Options.Refresh()
    end)
  end
end

local function GeneralPanel(profile)
  local settings = profile.visibilityDefaults or {}
  profile.visibilityDefaults = settings
  local name = viewedName

  Header(name or "Profile")
  if name then
    NameBox(name, function(newName)
      ns.RenameProfile(name, newName)
      if CombatHUDDB.profiles[newName] then viewedName = newName end
    end)
    if name == ns.profileName then
      Note("In use on this character, whatever its talents. Its bars are listed under it on the left.")
    else
      Action("Use This Profile", function()
        ns.UseProfile(name)
        Options.Refresh()
      end)
      Note("Its bars are listed under it on the left.")
    end
    Note("Profiles are shared: any character can use one.")
    cursorY = cursorY - 8
    ProfileActionGrid(name, profile)
    cursorY = cursorY - 8
  end

  Header("Profile settings")
  Stepper("HUD scale %", math.floor((profile.scale or 1) * 100 + 0.5), 10, 50, 200,
    function(value) profile.scale = value / 100 end)
  Dropdown("Font", ns.ListLabel(ns.FONTS, profile.font), function()
    local items = {}
    for _, font in ipairs(ns.FONTS) do
      items[#items + 1] = { text = font[2], checked = (profile.font or "default") == font[1],
        func = function() profile.font = font[1]; Changed() end }
    end
    return items
  end)
  Dropdown("Bar texture", ns.ListLabel(ns.TEXTURES, profile.barTexture), function()
    local items = {}
    for _, texture in ipairs(ns.TEXTURES) do
      items[#items + 1] = { text = texture[2], checked = (profile.barTexture or "flat") == texture[1],
        func = function() profile.barTexture = texture[1]; Changed() end }
    end
    return items
  end)
  Header("Spoken alerts")
  Choice("Voice", ns.Sounds.VOICES, profile.voice or "female", function(value)
    profile.voice = value
    ns.Sounds.Preview("say:Shield down", nil, nil, value)
  end)
  Header("Edit mode")
  Checks({ { "Snap to grid", profile.snap ~= false, function() profile.snap = profile.snap == false end } })
  Stepper("Grid size", profile.gridSize or 8, 2, 4, 32, function(value) profile.gridSize = value end)
  VisibilitySection(settings, "scale", nil, "Bar Visibility")
  Note("These are defaults for bars. A bar with its own saved visibility values keeps them.")
  Note("These are part of the profile, so each profile can look different.")
end

-- Window ---------------------------------------------------------------------------------------

local function Select(profileName, key, entry)
  if viewedName ~= profileName or selected ~= key or selectedEntry ~= entry then
    deleteArmed = nil
    if window.scroll and window.scroll.SetVerticalScroll then window.scroll:SetVerticalScroll(0) end
  end
  viewedName, selected, selectedEntry = profileName, key, entry
  Options.Refresh()
end

-- Reordering rows in the left tree: bars and (inside an open bar) buttons.
-- Dragging rows, like buttons in edit mode: a bar (with its buttons, if
-- they're listed) or one of a bar's buttons lifts onto the cursor, and the
-- rows around it slide apart to show where it will land. A bar let go over
-- another profile's row moves to the end of that profile. Rows glide to their
-- new places after a drop.
local ROW_STEP = 23
local listRows = {}  -- list index -> { button, row, x, y (its place), current, target, selected }
local rowDrag        -- the drag going on
local lastDrop = 0   -- GetTime() of the last drop: its click doesn't also open the row

local function RowY(slot)
  return -24 - (slot - 1) * ROW_STEP
end

local function CursorListY()
  local scale = listChild:GetEffectiveScale()
  local _, y = GetCursorPosition()
  return y / scale - listChild:GetTop()
end

local function PlaceRow(item, y)
  item.current = y
  item.button:ClearAllPoints()
  item.button:SetPoint("TOPLEFT", listChild, "TOPLEFT", item.x, y)
end

-- Where it would land: the list index of the row it goes before, or the
-- name of another profile it would move to.
local function DragTarget(drag)
  local cursor = CursorListY()
  if drag.kind == "bar" then
    for _, item in ipairs(listRows) do
      local row = item.row
      if row.indent == 0 and row.profile ~= drag.profile and math.abs(cursor - (item.y - 10)) <= 11 then
        return nil, row.profile
      end
    end
  end
  for _, index in ipairs(drag.slots) do
    if cursor > listRows[index].y - 10 then return index end
  end
  return drag.endBefore
end

-- Every row's place while dragging: the rest close up around a gap the size
-- of what's carried, which follows the cursor.
local function DragLayout(drag)
  local order, gap = {}, nil
  for index = 1, #listRows do
    if not drag.block[index] then order[#order + 1] = index end
  end
  for position, index in ipairs(order) do
    if index == drag.before then gap = position end
  end
  for position, index in ipairs(order) do
    local slot = position
    if gap and position >= gap then slot = position + #drag.blockList end
    listRows[index].target = RowY(slot)
  end
  local top = CursorListY() + drag.grab
  for offset, index in ipairs(drag.blockList) do listRows[index].target = top - (offset - 1) * ROW_STEP end
end

local animator = CreateFrame("Frame")
animator:Hide()
animator:SetScript("OnUpdate", function(self, elapsed)
  local drag = rowDrag
  if drag and not drag.active and math.abs(CursorListY() - drag.startY) > 4 then
    drag.active = true
    for _, index in ipairs(drag.blockList) do
      local button = listRows[index].button
      button:SetFrameLevel(listChild:GetFrameLevel() + 20)
      button:SetAlpha(0.85)
    end
  end
  if drag and drag.active then
    drag.before, drag.profileTarget = DragTarget(drag)
    DragLayout(drag)
    for _, item in ipairs(listRows) do
      if item.row.indent == 0 then Flat(item.button, item.selected or item.row.profile == drag.profileTarget) end
    end
  end
  local moving = false
  local speed = math.min(1, elapsed * 16)
  for index, item in ipairs(listRows) do
    if item.target and item.current then
      local y
      if drag and drag.active and drag.block[index] then
        y = item.target
      else
        y = item.current + (item.target - item.current) * speed
        if math.abs(item.target - y) < 0.5 then y = item.target end
      end
      if y ~= item.current then PlaceRow(item, y) end
      if y ~= item.target then moving = true end
    end
  end
  if not drag and not moving then self:Hide() end
end)

local function StartRowDrag(index)
  local item = listRows[index]
  if not item then return end
  local row = item.row
  local drag = { startY = CursorListY(), profile = row.profile, block = { [index] = true }, blockList = { index }, slots = {} }
  if row.barIndex then
    drag.kind, drag.from = "bar", row.barIndex
    -- Its buttons, listed under it, go with it.
    for other = index + 1, #listRows do
      if (listRows[other].row.indent or 0) < 2 then break end
      drag.block[other] = true
      drag.blockList[#drag.blockList + 1] = other
    end
    for other, entry in ipairs(listRows) do
      if entry.row.barIndex and entry.row.profile == row.profile and not drag.block[other] then
        drag.slots[#drag.slots + 1] = other
      end
      if entry.row.key == "power" and entry.row.profile == row.profile then drag.endBefore = other end
    end
  elseif row.buttonIndex then
    drag.kind, drag.bar, drag.from = "button", row.key, row.buttonIndex
    local last
    for other, entry in ipairs(listRows) do
      if entry.row.buttonIndex and entry.row.key == row.key then
        if not drag.block[other] then drag.slots[#drag.slots + 1] = other end
        last = other
      end
    end
    drag.endBefore = last and last + 1
  else
    return
  end
  drag.grab = item.y - drag.startY -- keeps the row where it was taken hold of
  for _, entry in ipairs(listRows) do entry.target = entry.current end
  rowDrag = drag
  animator:Show()
end

local function MoveWithin(list, from, to)
  if not (list and to) or to == from or to == from + 1 then return end
  local moved = table.remove(list, from)
  if to > from then to = to - 1 end
  table.insert(list, to, moved)
  return moved
end

local function StopRowDrag()
  local drag = rowDrag
  rowDrag = nil
  if not (drag and drag.active) then return end -- only a click
  lastDrop = GetTime()
  local before = drag.before and listRows[drag.before]
  if drag.kind == "bar" then
    local source = CombatHUDDB.profiles[drag.profile]
    local dest = drag.profileTarget and CombatHUDDB.profiles[drag.profileTarget]
    if source and dest then
      local moved = table.remove(source.bars, drag.from)
      ns.AddBarConfig(moved, dest)
      if selected == moved then selected, selectedEntry = "general", nil end
      if drag.profile == ns.profileName then ns.Rebuild(true) end
      ns.Print(("Moved the bar %s to %s."):format(moved.name or "", drag.profileTarget))
    elseif source and before then
      local to = before.row.barIndex
      if not (to and before.row.profile == drag.profile) then to = #source.bars + 1 end
      if MoveWithin(source.bars, drag.from, to) and drag.profile == ns.profileName then ns.Rebuild(true) end
    end
  elseif drag.kind == "button" and before then
    local buttons = drag.bar.buttons
    local to = before.row.buttonIndex
    if not (to and before.row.key == drag.bar) then to = #buttons + 1 end
    if MoveWithin(buttons, drag.from, to) then ns.Rebuild(true) end
  end
  Options.Refresh()
end

local function NewGrip(button)
  local grip = CreateFrame("Button", nil, button)
  grip:SetSize(12, 18)
  grip:SetPoint("LEFT", 1, 0)
  for column = 0, 1 do
    for row = 0, 2 do
      local dot = grip:CreateTexture(nil, "OVERLAY")
      dot:SetSize(2, 2)
      dot:SetColorTexture(0.6, 0.6, 0.65, 1)
      dot:SetPoint("TOPLEFT", 3 + column * 4, -4 - row * 4)
    end
  end
  grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.kind == "bar" and "Drag to reorder, or onto another profile to move it there"
      or "Drag to reorder")
    GameTooltip:Show()
  end)
  grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
  grip:SetScript("OnMouseDown", function(self, mouse)
    if mouse == "LeftButton" and self.index then StartRowDrag(self.index) end
  end)
  grip:SetScript("OnMouseUp", function() StopRowDrag() end)
  return grip
end

-- The tree: every profile (clicking one opens its General page); under the
-- open one, its bars (under the open bar, its buttons), power bar, health bar and "+ New bar".
local function RefreshList()
  listHeader = listHeader or listChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  listHeader:ClearAllPoints()
  listHeader:SetPoint("TOPLEFT", listChild, "TOPLEFT", 8, -8)
  listHeader:SetText("PROFILES")

  local rows = {}
  for _, name in ipairs(ns.ProfileNames()) do
    rows[#rows + 1] = { id = "profile:" .. name, text = name, profile = name, key = "general", indent = 0,
      inUse = name == ns.profileName }
    if name == viewedName then
      local profile = CombatHUDDB.profiles[name]
      for barIndex, bar in ipairs(profile.bars or {}) do
        rows[#rows + 1] = { id = "bar:" .. tostring(bar), text = bar.name or "Bar", profile = name, key = bar,
          indent = 1, barIndex = barIndex }
        if bar == selected and BUTTON_PAGES[ns.Bar.Type(bar)] then
          for buttonIndex, entry in ipairs(bar.buttons or {}) do
            local text = WithIcon(EntryIcon(entry), EntryName(entry)) .. (entry.hidden and " |cff888888(hidden)|r" or "")
            rows[#rows + 1] = { id = "entry:" .. tostring(entry), text = text,
              profile = name, key = bar, entry = entry, indent = 2, buttonIndex = buttonIndex }
          end
        end
      end
      rows[#rows + 1] = { id = "power:" .. name, text = "Power bar", profile = name, key = "power", indent = 1 }
      rows[#rows + 1] = { id = "health:" .. name, text = "Health bar", profile = name, key = "health", indent = 1 }
      rows[#rows + 1] = { id = "cast:" .. name, text = "Cast bar", profile = name, key = "cast", indent = 1 }
      rows[#rows + 1] = { id = "swing:" .. name, text = "Swing timer", profile = name, key = "swing", indent = 1 }
      rows[#rows + 1] = { id = "newbar:" .. name, text = "+ New bar", indent = 1, action = function()
        local bar = ns.AddBar("", profile)
        if bar then selected, selectedEntry = bar, nil end
        Options.Refresh()
      end }
    end
  end

  -- Where each row was, so they can glide to their new places.
  local was = {}
  for _, item in ipairs(listRows) do
    if item.row.id and item.current then was[item.row.id] = item.current end
  end
  wipe(listRows)
  for index, row in ipairs(rows) do
    local button = listButtons[index] or NewButton(listChild, LIST_WIDTH - 10, 20)
    listButtons[index] = button
    local indent = row.indent * 12
    local y = -24 - (index - 1) * 23
    local x = 5 + indent
    local w = LIST_WIDTH - 10 - indent

    button:SetWidth(w)
    button:SetHeight(20)
    button:SetAlpha(1)
    button:SetFrameLevel(listChild:GetFrameLevel() + 1)
    local item = { button = button, row = row, x = x, y = y, target = y,
      selected = row.profile == viewedName and selected == row.key and selectedEntry == row.entry }
    listRows[index] = item
    PlaceRow(item, (row.id and was[row.id]) or y)

    -- Reset pooled row visuals/scripts every refresh so no stale text or handlers leak.
    button:SetScript("OnClick", nil)
    button:SetScript("OnMouseDown", nil)
    button:SetScript("OnMouseUp", nil)
    button:SetScript("OnUpdate", nil)
    button.text:SetText("")
    button.text:SetAlpha(1)
    button.text:SetJustifyH("LEFT")
    button.text:SetPoint("LEFT", 4, 0)
    button.text:SetPoint("RIGHT", -4, 0)
    if button.highlight then button.highlight:SetColorTexture(1, 1, 1, 0.1) end
    button.bg:SetColorTexture(0.18, 0.18, 0.22, 1)

    button.grip = button.grip or NewGrip(button)
    button.grip:SetShown(row.barIndex ~= nil or row.buttonIndex ~= nil)
    button.grip.kind = row.barIndex and "bar" or (row.buttonIndex and "button" or nil)
    button.grip.index = index

    button.text:SetPoint("LEFT", (row.barIndex or row.buttonIndex) and 16 or 4, 0)

    if row.barIndex or row.buttonIndex then
      button:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then StartRowDrag(index) end
      end)
      button:SetScript("OnMouseUp", function() StopRowDrag() end)
    end

    button.trash = button.trash or CreateFrame("Button", nil, button)
    button.trash:SetSize(16, 16)
    button.trash:SetPoint("RIGHT", -2, 0)
    button.trash.bg = button.trash.bg or button.trash:CreateTexture(nil, "BACKGROUND")
    button.trash.bg:SetAllPoints()
    button.trash.bg:SetColorTexture(0.25, 0.12, 0.12, 1)
    button.trash.icon = button.trash.icon or button.trash:CreateTexture(nil, "ARTWORK")
    button.trash.icon:SetPoint("TOPLEFT", 2, -2)
    button.trash.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.trash.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    button.trash:SetScript("OnClick", function()
      if row.profile then ShowDeleteProfileModal(row.profile) end
    end)
    button.trash:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("Delete profile")
      GameTooltip:Show()
    end)
    button.trash:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if row.action then
      button.text:SetText(row.text .. (row.inUse and "  |cff88ff88(in use)|r" or ""))
      button.text:SetJustifyH("CENTER")
      Flat(button, row.profile == viewedName and selected == row.key and selectedEntry == row.entry)
      button:SetScript("OnClick", row.action)
      button.trash:Hide()
    else
      button.text:SetText(row.text .. (row.inUse and "  |cff88ff88(in use)|r" or ""))
      button.text:SetJustifyH("LEFT")
      Flat(button, row.profile == viewedName and selected == row.key and selectedEntry == row.entry)
      button:SetScript("OnClick", function()
        if GetTime() - lastDrop < 0.2 then return end -- that was a drop
        Select(row.profile, row.key, row.entry)
      end)
      button.trash:SetShown(row.indent == 0 and row.profile == viewedName and selected == "general" and not selectedEntry)
    end
    button:Show()
  end
  for index = #rows + 1, #listButtons do listButtons[index]:Hide() end
  listChild:SetHeight(24 + #rows * 23 + 4)
  animator:Show() -- rows that moved glide to their places
end

local function Create()
  window = CreateFrame("Frame", "CombatHUDOptions", UIParent)
  window:SetSize(WIDTH, HEIGHT)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)

  local border = window:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetColorTexture(0.35, 0.35, 0.4, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  local bg = window:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.97)
  bg:SetAllPoints()

  window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  window.title:SetPoint("TOPLEFT", 12, -10)
  window.title:SetText("CHUDForever")
  window.profile = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  window.profile:SetPoint("LEFT", window.title, "RIGHT", 10, -1)

  local close = NewButton(window, 22, 20)
  close.text:SetText("X")
  close.text:SetJustifyH("CENTER")
  close:SetPoint("TOPRIGHT", -8, -8)
  close:SetScript("OnClick", function() window:Hide() end)

  window.editModeButton = NewButton(window, 128, 20)
  window.editModeButton.text:SetJustifyH("CENTER")
  window.editModeButton:SetPoint("RIGHT", close, "LEFT", -8, 0)
  window.editModeButton:SetScript("OnClick", function()
    ns.SetEditMode(not ns.editMode)
    Options.Refresh()
  end)

  list = CreateFrame("Frame", nil, window)
  list:SetPoint("TOPLEFT", 10, -36)
  list:SetPoint("BOTTOMLEFT", 10, 10)
  list:SetWidth(LIST_WIDTH)
  local listBg = list:CreateTexture(nil, "BACKGROUND")
  listBg:SetAllPoints()
  listBg:SetColorTexture(0.1, 0.1, 0.13, 1)
  -- The tree scrolls with the mouse wheel when it's longer than the window.
  local listScroll = CreateFrame("ScrollFrame", nil, list)
  listScroll:SetPoint("TOPLEFT")
  listScroll:SetPoint("BOTTOMRIGHT", 0, 32)
  listChild = CreateFrame("Frame", nil, listScroll)
  listChild:SetSize(LIST_WIDTH, 10)
  listScroll:SetScrollChild(listChild)
  listScroll:EnableMouseWheel(true)
  listScroll:SetScript("OnMouseWheel", function(self, delta)
    local most = math.max(0, listChild:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(most, self:GetVerticalScroll() - delta * 46)))
  end)

  -- A new profile from the class's defaults, put in use.
  newProfileButton = NewButton(list, LIST_WIDTH - 10, 22)
  newProfileButton.text:SetText("+ New profile")
  newProfileButton.text:SetJustifyH("CENTER")
  newProfileButton:SetPoint("BOTTOMLEFT", 5, 5)
  newProfileButton:SetScript("OnClick", function()
    local name = ns.CreateProfile(nil)
    if name then Select(name, "general") end
  end)

  -- The settings scroll when they don't fit.
  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
  if not ok then scroll = CreateFrame("ScrollFrame", nil, window) end
  scroll:SetPoint("TOPLEFT", list, "TOPRIGHT", 16, -2)
  scroll:SetPoint("BOTTOMRIGHT", -30, 10)
  panelWidth = WIDTH - LIST_WIDTH - 10 - 16 - 30 - 8
  panel = CreateFrame("Frame", nil, scroll)
  panel:SetSize(panelWidth, 10)
  scroll:SetScrollChild(panel)
  window.scroll = scroll

  deleteModal = CreateFrame("Frame", nil, window)
  deleteModal:SetAllPoints(window)
  deleteModal:SetFrameLevel(window:GetFrameLevel() + 50)
  deleteModal.blocker = CreateFrame("Button", nil, deleteModal)
  deleteModal.blocker:SetAllPoints()
  deleteModal.blocker:SetScript("OnClick", function() HideDeleteProfileModal() end)
  deleteModal.shade = deleteModal:CreateTexture(nil, "BACKGROUND")
  deleteModal.shade:SetAllPoints()
  deleteModal.shade:SetColorTexture(0, 0, 0, 0.55)

  local card = CreateFrame("Frame", nil, deleteModal)
  card:SetSize(360, 140)
  card:SetPoint("CENTER")
  local cardEdge = card:CreateTexture(nil, "BACKGROUND", nil, -1)
  cardEdge:SetPoint("TOPLEFT", -1, 1)
  cardEdge:SetPoint("BOTTOMRIGHT", 1, -1)
  cardEdge:SetColorTexture(0.35, 0.35, 0.4, 1)
  local cardBg = card:CreateTexture(nil, "BACKGROUND")
  cardBg:SetAllPoints()
  cardBg:SetColorTexture(0.06, 0.06, 0.09, 0.97)
  local text = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  text:SetPoint("TOP", 0, -24)
  text:SetWidth(320)
  text:SetJustifyH("CENTER")
  deleteModal.text = text

  local yes = NewButton(card, 120, 24)
  yes.text:SetText("Delete")
  yes.text:SetJustifyH("CENTER")
  yes:SetPoint("BOTTOMLEFT", 34, 20)
  local no = NewButton(card, 120, 24)
  no.text:SetText("Cancel")
  no.text:SetJustifyH("CENTER")
  no:SetPoint("BOTTOMRIGHT", -34, 20)
  deleteModal.yes = yes
  deleteModal.no = no
  deleteModal:Hide()

  table.insert(UISpecialFrames, "CombatHUDOptions") -- Escape closes it
  window:Hide()
end

function Options.Refresh()
  if not window or not window:IsShown() or not ns.profile then return end
  ReleaseAll()
  cursorY = 0
  if not viewedName or not CombatHUDDB.profiles[viewedName] then
    viewedName, selected = ns.profileName, "general"
  end
  local profile = CombatHUDDB.profiles[viewedName]
  -- What's selected has to belong to the open profile.
  local valid = selected == "profile" or selected == "power" or selected == "health"
    or selected == "cast" or selected == "swing" or selected == "general"
  for _, bar in ipairs(profile.bars or {}) do
    if bar == selected then valid = true end
  end
  if not valid then selected = "general" end
  if selectedEntry and not (type(selected) == "table" and tContains(selected.buttons or {}, selectedEntry)) then
    selectedEntry = nil
  end

  window.profile:SetText("in use: " .. (ns.profileName or ""))
  if window.editModeButton then
    window.editModeButton.text:SetText(ns.editMode and "Leave Edit Mode" or "Enter Edit Mode")
  end
  RefreshList()
  if selected == "profile" then
    selected = "general"
    GeneralPanel(profile)
  elseif selected == "power" then
    PowerPanel(profile)
  elseif selected == "health" then
    HealthPanel(profile)
  elseif selected == "cast" then
    CastPanel(profile)
  elseif selected == "swing" then
    SwingPanel(profile)
  elseif selected == "general" then
    GeneralPanel(profile)
  elseif selectedEntry then
    ButtonPluginsPanel(selected, selectedEntry, profile)
  else
    BarPanel(selected, profile, "advanced", false)
  end
  panel:SetHeight(math.max(10, -cursorY + 10))
end

-- bar: a bar of the profile in use to show first (optional).
function Options.Open(bar)
  if InCombatLockdown() then
    ns.Print("Settings can't be changed in combat.")
    return
  end
  if not ns.profile then
    ns.Print("The HUD isn't loaded yet.")
    return
  end
  if not window then Create() end
  if bar then
    viewedName, selected, selectedEntry, deleteArmed = ns.profileName, bar, nil, nil
  elseif not viewedName then
    viewedName, selected, selectedEntry = ns.profileName, "general", nil
  end
  window:Show()
  Options.Refresh()
end

-- A button's page (its right-click menu's "Settings..."); with pick, its
-- Plugins tab with the + Add picker open ("Add a plugin..."); with card, that
-- plugin's card shown and open ("Add an alert...").
function Options.OpenButton(bar, entry, pick, card)
  Options.Open(bar)
  if not (window and window:IsShown()) then return end
  selectedEntry = entry
  if card then
    Mark(shownCards, entry, card, true)
    Mark(openCards, entry, card, true)
  end
  Options.Refresh()
  if pick then OpenButtonPicker(CombatHUDDB.profiles[viewedName], bar, entry) end
end

-- Opens a profile's page (after importing one, say).
function Options.View(name)
  viewedName, selected, selectedEntry, deleteArmed = name, "general", nil, nil
  if window and window:IsShown() then Options.Refresh() end
end

function Options.Toggle()
  if window and window:IsShown() then window:Hide() else Options.Open() end
end

function Options.Close()
  ClosePicker()
  if window then window:Hide() end
end
