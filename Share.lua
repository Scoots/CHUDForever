-- Sharing profiles as text: export gives a string to copy (to back up or
-- share); import turns one back into a new profile.
--
-- The profile is written in a small data-only format (length-prefixed
-- strings, numbers, booleans, tables) and read back by a parser that only
-- builds tables, so an imported string can never run code. It's compressed
-- when the client can, and always base64-encoded so it survives copy and paste.
local _, ns = ...

local Share = {}
ns.Share = Share

local PREFIX, PREFIX_PACKED = "CHUD1:", "CHUD1z:"
local BAR_PREFIX, BAR_PREFIX_PACKED = "CHUDBAR1:", "CHUDBAR1z:"
local MAX_DEPTH = 20

-- Writing ----------------------------------------------------------------------------

local function KeyOrder(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  return a < b
end

local function Write(value, out)
  local kind = type(value)
  if kind == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for key in pairs(value) do
      if type(key) == "string" or type(key) == "number" then keys[#keys + 1] = key end
    end
    table.sort(keys, KeyOrder)
    for _, key in ipairs(keys) do
      Write(key, out)
      out[#out + 1] = "="
      Write(value[key], out)
      out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
  elseif kind == "string" then
    out[#out + 1] = "s" .. #value .. ":" .. value
  elseif kind == "number" then
    out[#out + 1] = "n" .. string.format("%.17g", value) .. ":"
  elseif kind == "boolean" then
    out[#out + 1] = value and "T" or "F"
  else
    out[#out + 1] = "F" -- functions and the like: not part of a profile
  end
end

-- Reading ------------------------------------------------------------------------------

local function Read(text, position, depth)
  if depth > MAX_DEPTH then error("too deeply nested") end
  local kind = text:sub(position, position)
  if kind == "{" then
    local result = {}
    position = position + 1
    while text:sub(position, position) ~= "}" do
      if position > #text then error("cut off") end
      local key, value
      key, position = Read(text, position, depth + 1)
      if type(key) ~= "string" and type(key) ~= "number" then error("bad key") end
      if text:sub(position, position) ~= "=" then error("expected =") end
      value, position = Read(text, position + 1, depth + 1)
      if text:sub(position, position) ~= ";" then error("expected ;") end
      position = position + 1
      result[key] = value
    end
    return result, position + 1
  elseif kind == "s" then
    local colon = text:find(":", position, true)
    local length = colon and tonumber(text:sub(position + 1, colon - 1))
    if not length then error("bad text") end
    return text:sub(colon + 1, colon + length), colon + length + 1
  elseif kind == "n" then
    local colon = text:find(":", position, true)
    local number = colon and tonumber(text:sub(position + 1, colon - 1))
    if not number then error("bad number") end
    return number, colon + 1
  elseif kind == "T" then
    return true, position + 1
  elseif kind == "F" then
    return false, position + 1
  end
  error("unexpected data")
end

-- Base64 ------------------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local decodeMap = {}
for index = 1, #ALPHABET do decodeMap[ALPHABET:sub(index, index)] = index - 1 end

local function ToBase64(data)
  local out = {}
  for index = 1, #data, 3 do
    local a, b, c = data:byte(index, index + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local chars = {}
    for shift = 3, 0, -1 do
      local sixBits = math.floor(n / 64 ^ shift) % 64
      chars[#chars + 1] = ALPHABET:sub(sixBits + 1, sixBits + 1)
    end
    if not b then chars[3], chars[4] = "=", "=" elseif not c then chars[4] = "=" end
    out[#out + 1] = table.concat(chars)
  end
  return table.concat(out)
end

local function FromBase64(text)
  text = text:gsub("[^%w%+/=]", "")
  local out = {}
  for index = 1, #text, 4 do
    local chunk = text:sub(index, index + 3)
    local n, pad = 0, 0
    for offset = 1, 4 do
      local char = chunk:sub(offset, offset)
      if char == "=" or char == "" then
        pad = pad + 1
        n = n * 64
      else
        local value = decodeMap[char]
        if not value then error("bad characters") end
        n = n * 64 + value
      end
    end
    local bytes = { math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256 }
    for byte = 1, 3 - pad do out[#out + 1] = string.char(bytes[byte]) end
  end
  return table.concat(out)
end

-- Encoding --------------------------------------------------------------------------------

local function Packer()
  local util = C_EncodingUtil
  if util and util.CompressString and util.DecompressString then return util end
end

local function Pack(value, prefix, packedPrefix)
  local out = {}
  Write(value, out)
  local data = table.concat(out)
  local packer = Packer()
  if packer then
    local ok, packed = pcall(packer.CompressString, data)
    if ok and type(packed) == "string" then return packedPrefix .. ToBase64(packed) end
  end
  return prefix .. ToBase64(data)
end

-- The table in a string with one of these prefixes; or nil, false when it
-- doesn't start with either; or nil and what's wrong with it.
local function Unpack(text, prefix, packedPrefix)
  text = strtrim(text or "")
  local packed = text:sub(1, #packedPrefix) == packedPrefix
  if not packed and text:sub(1, #prefix) ~= prefix then return nil, false end
  local ok, result = pcall(function()
    local data = FromBase64(text:sub(packed and #packedPrefix + 1 or #prefix + 1))
    if packed then
      local packer = Packer()
      if not packer then error("this client can't unpack it") end
      data = packer.DecompressString(data)
    end
    local value, position = Read(data, 1, 0)
    if position <= #data then error("extra data at the end") end
    return value
  end)
  if not ok then return nil, "The string is damaged or incomplete (" .. tostring(result) .. ")." end
  return result
end

function Share.Encode(profile)
  return Pack(profile, PREFIX, PREFIX_PACKED)
end

function Share.EncodeBar(bar)
  return Pack(bar, BAR_PREFIX, BAR_PREFIX_PACKED)
end

-- A bar in a string, or nil and what's wrong with it.
function Share.DecodeBar(text)
  local bar, problem = Unpack(text, BAR_PREFIX, BAR_PREFIX_PACKED)
  if problem == false then
    return nil, "That isn't a CombatHUD bar string (a profile string goes in \"Import a profile\")."
  end
  if not bar then return nil, problem end
  if type(bar) ~= "table" then return nil, "That string has no bar in it." end
  bar.buttons = type(bar.buttons) == "table" and bar.buttons or {}
  -- Made by an older version: shared cooldowns and alerts as they are now.
  local wrapper = { bars = { bar } }
  ns.Groups.MigrateProfile(wrapper)
  ns.Alerts.MigrateProfile(wrapper)
  return bar
end

-- The profile in a string, or nil and what's wrong with it.
function Share.Decode(text)
  local result, problem = Unpack(text, PREFIX, PREFIX_PACKED)
  if problem == false then return nil, "That isn't a CombatHUD profile string." end
  if not result then return nil, problem end
  if type(result) ~= "table" or type(result.bars) ~= "table" then return nil, "That string has no bars in it." end
  for _, bar in ipairs(result.bars) do
    if type(bar) ~= "table" then return nil, "That string has a broken bar in it." end
    bar.buttons = type(bar.buttons) == "table" and bar.buttons or {}
  end
  return result
end

-- The window ------------------------------------------------------------------------------

local popup

local function NewButton(parent, text)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(200, 22)
  local bg = button:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.18, 0.18, 0.22, 1)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetColorTexture(1, 1, 1, 0.1)
  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  button.text:SetPoint("CENTER")
  button.text:SetText(text)
  return button
end

local function Create()
  popup = CreateFrame("Frame", "CombatHUDShare", UIParent)
  popup:SetSize(480, 300)
  popup:SetPoint("CENTER")
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:EnableMouse(true)
  popup:SetMovable(true)
  popup:RegisterForDrag("LeftButton")
  popup:SetScript("OnDragStart", popup.StartMoving)
  popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
  local border = popup:CreateTexture(nil, "BACKGROUND", nil, -1)
  border:SetColorTexture(0.35, 0.35, 0.4, 1)
  border:SetPoint("TOPLEFT", -1, 1)
  border:SetPoint("BOTTOMRIGHT", 1, -1)
  local bg = popup:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0.06, 0.06, 0.09, 0.97)
  bg:SetAllPoints()
  popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  popup.title:SetPoint("TOPLEFT", 12, -10)
  popup.hint = popup:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  popup.hint:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -4)

  local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  if not ok then scroll = CreateFrame("ScrollFrame", nil, popup) end
  scroll:SetPoint("TOPLEFT", 12, -46)
  scroll:SetPoint("BOTTOMRIGHT", -30, 42)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetMaxLetters(0)
  box:SetFontObject("ChatFontNormal")
  box:SetWidth(430)
  box:SetScript("OnEscapePressed", function() popup:Hide() end)
  scroll:SetScrollChild(box)
  popup.box = box

  popup.action = NewButton(popup, "")
  popup.action:SetPoint("BOTTOMLEFT", 12, 12)
  local close = NewButton(popup, "Close")
  close:SetWidth(100)
  close:SetPoint("BOTTOMRIGHT", -12, 12)
  close:SetScript("OnClick", function() popup:Hide() end)

  table.insert(UISpecialFrames, "CombatHUDShare") -- Escape closes it
  popup:Hide()
end

-- profile, name: which one (the one in use if left out).
function Share.ShowExport(profile, name)
  profile, name = profile or ns.profile, name or ns.profileName
  if not profile then return end
  if not popup then Create() end
  popup.title:SetText("Export: " .. tostring(name))
  popup.hint:SetText("Press Ctrl+C to copy, then paste it wherever you keep it.")
  popup.action:Hide()
  popup:Show()
  popup.box:SetText(Share.Encode(profile))
  popup.box:SetFocus()
  popup.box:HighlightText()
end

-- Any text to copy (the bug report).
function Share.ShowText(title, hint, text)
  if not popup then Create() end
  popup.title:SetText(title)
  popup.hint:SetText(hint)
  popup.action:Hide()
  popup:Show()
  popup.box:SetText(text)
  popup.box:SetFocus()
  popup.box:HighlightText()
end

function Share.ShowExportBar(bar)
  if not popup then Create() end
  popup.title:SetText("Export bar: " .. tostring(bar.name or "Bar"))
  popup.hint:SetText("Press Ctrl+C to copy. Import it on any profile's page (\"Import a bar\").")
  popup.action:Hide()
  popup:Show()
  popup.box:SetText(Share.EncodeBar(bar))
  popup.box:SetFocus()
  popup.box:HighlightText()
end

-- profileName: the profile the bar is added to.
function Share.ShowImportBar(profileName)
  if not popup then Create() end
  popup.title:SetText("Import a bar into " .. tostring(profileName))
  popup.hint:SetText("Paste a CombatHUD bar string (Ctrl+V), then import it.")
  popup.action.text:SetText("Add it to " .. tostring(profileName))
  popup.action:SetScript("OnClick", function()
    local bar, problem = Share.DecodeBar(popup.box:GetText())
    if not bar then
      ns.Print(problem)
      return
    end
    local profile = CombatHUDDB.profiles[profileName]
    if not profile then return end
    ns.AddBarConfig(bar, profile)
    popup:Hide()
    ns.Print(("Added the bar %s to %s."):format(bar.name, profileName))
    ns.Options.Refresh()
  end)
  popup.action:Show()
  popup:Show()
  popup.box:SetText("")
  popup.box:SetFocus()
end

function Share.ShowImport()
  if not popup then Create() end
  popup.title:SetText("Import a profile")
  popup.hint:SetText("Paste a CombatHUD profile string (Ctrl+V), then import it.")
  popup.action.text:SetText("Import as a new profile")
  popup.action:SetScript("OnClick", function()
    local profile, problem = Share.Decode(popup.box:GetText())
    if not profile then
      ns.Print(problem)
      return
    end
    -- Made by an older version: shared cooldowns and alerts as they are now.
    ns.Groups.MigrateProfile(profile)
    ns.Alerts.MigrateProfile(profile)
    local name = ns.AddProfile("Imported", profile)
    popup:Hide()
    ns.Print("Imported as " .. name .. ", and now in use.")
    ns.Options.View(name)
  end)
  popup.action:Show()
  popup:Show()
  popup.box:SetText("")
  popup.box:SetFocus()
end
