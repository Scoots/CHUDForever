-- Sounds when a buff or debuff starts or ends (Lightning Shield running out of
-- charges, a shield breaking...). Whether an aura is up is secret in combat,
-- so the game plays them: C_UnitAuras.AddAuraSound registers a sound for a
-- spell ID on a unit, for when it's added or removed. Registrations are
-- redone on every rebuild, from each entry's sound alerts (Alerts.lua).
--
-- A sound can also be a spoken phrase. Nothing can be spoken on the fly when
-- the game plays the sound, so phrases are recorded ahead of time with
-- Windows' voices (tools/make_voices.ps1; the list is in VoiceList.lua).
-- "say:name" says the aura's own name, or a general phrase when that name
-- wasn't recorded; "say:<phrase>" says that phrase.
local _, ns = ...

local Sounds = {}
ns.Sounds = Sounds

local SOUNDS_DIR = ns.MEDIA .. "Sounds\\"
local VOICE_DIR = ns.MEDIA .. "Voice\\"

Sounds.LIST = {
  { "none", "None" },
  { "blip", "Robot blip", SOUNDS_DIR .. "RobotBlip.ogg" },
  { "drop", "Water drop", SOUNDS_DIR .. "WaterDrop.ogg" },
  { "bell", "Temple bell", SOUNDS_DIR .. "TempleBellHuge.ogg" },
  { "heartbeat", "Heartbeat", SOUNDS_DIR .. "HeartbeatSingle.ogg" },
  { "siren", "Warning siren", SOUNDS_DIR .. "WarningSiren.ogg" },
  { "raid", "Raid warning (game)", "Sound\\Interface\\RaidWarning.ogg" },
  { "custom", "My own: Media\\Sounds\\custom.ogg", SOUNDS_DIR .. "custom.ogg" },
}

-- The voices phrases are recorded in (a profile's "voice" setting).
Sounds.VOICES = { { "female", "Zira (female)" }, { "male", "David (male)" } }

local files, labels = {}, {}
for _, sound in ipairs(Sounds.LIST) do
  files[sound[1]], labels[sound[1]] = sound[3], sound[2]
end

-- Spoken phrases ----------------------------------------------------------------------

local VOICE = ns.VOICE or { alerts = {}, spells = {} }
local recordings = {} -- phrase without spaces or punctuation, in lower case -> file name

local function Simplify(text)
  return (text:gsub("[^%w]", ""):lower())
end

for _, phrase in ipairs(VOICE.alerts) do recordings[Simplify(phrase[1])] = phrase[2] end
for phrase, file in pairs(VOICE.spells) do recordings[Simplify(phrase)] = file end

-- The recording of a phrase in a voice ("female" or "male"), or nil.
local function VoiceFile(phrase, voice)
  if ns.issecret(phrase) or type(phrase) ~= "string" then return end
  local file = recordings[Simplify(phrase)]
  if file then return VOICE_DIR .. (voice == "male" and "Male" or "Female") .. "\\" .. file .. ".mp3" end
end

local function SaidPhrase(key)
  if type(key) == "string" and key ~= "say:name" and key:sub(1, 4) == "say:" then return key:sub(5) end
end

-- The phrase "say:name" falls back to when the aura's name wasn't recorded.
-- event: "Added" or "Removed"; kind: the bar's type; unit: the aura's unit.
function Sounds.Fallback(event, kind, unit)
  if event == "Removed" then
    if kind == "charges" then return "Charges gone" end
    return unit == "target" and "Debuff gone" or "Buff gone"
  end
  return unit == "target" and "Debuff up" or "Buff up"
end

-- Sounds ------------------------------------------------------------------------------------

-- The file a sound key plays. name: the aura's (or spell's) name, for
-- "say:name"; fallback: the phrase said instead when that name wasn't
-- recorded; voice: "female" or "male" (the profile in use's, if left out).
function Sounds.File(key, name, fallback, voice)
  voice = voice or (ns.profile and ns.profile.voice)
  if key == "say:name" then return VoiceFile(name, voice) or VoiceFile(fallback, voice) end
  local phrase = SaidPhrase(key)
  if phrase then return VoiceFile(phrase, voice) end
  return files[key]
end

function Sounds.Label(key)
  if key == "say:name" then return "Say its name" end
  local phrase = SaidPhrase(key)
  if phrase then return 'Say "' .. phrase .. '"' end
  return labels[key or "none"] or "None"
end

-- Plays a sound key now (a preview, or a sound the addon triggers itself).
function Sounds.Preview(key, name, fallback, voice)
  local file = Sounds.File(key, name, fallback or "Buff gone", voice)
  if file then PlaySoundFile(file, "Master") end
end

local registered = {}

local function Supported()
  return C_UnitAuras and C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound and Enum.UnitAuraSoundTrigger
end

-- The unit an entry's aura is on, or nil when the entry isn't an aura.
-- kind: the bar's type.
function Sounds.AuraUnit(kind, entry, opts)
  if entry.slot or entry.item or entry.totemSlot then return end
  if kind == "debuffs" then return "target" end
  if kind == "buffs" or kind == "alerts" or kind == "charges" then return "player" end
  if kind == "cooldowns" then
    if entry.aura then return opts.unit or "player" end
    if entry.watchAura then return "player" end
    if opts.targetDebuff then return "target" end
  end
end

-- What an entry's sounds listen for, and the name "Say its name" says. A
-- cooldown can watch its own buff (watchAura = true, the buff learned for
-- the spell) or chosen ones (a list of IDs); with Target debuff, its debuff
-- (every member's, on a shared cooldown).
local function Watched(kind, entry, unit)
  if kind == "cooldowns" and not entry.aura then
    if type(entry.watchAura) == "table" then
      return ns.Aura.SpellIDs({ aura = entry.watchAura }), ns.Aura.SpellName(entry.watchAura[1])
    elseif entry.watchAura then
      return ns.Aura.SpellIDs({ spell = entry.spell }), ns.Aura.SpellName(ns.Aura.IconSpell(entry))
    elseif unit == "target" then
      local spellID, name = ns.Groups.ResolveSpell(entry)
      return ns.Groups.DebuffIDs(entry, spellID), name or ns.Aura.SpellName(ns.Aura.IconSpell(entry))
    end
  end
  return ns.Aura.SpellIDs(entry), ns.Aura.SpellName(ns.Aura.IconSpell(entry))
end

local warned
function Sounds.Apply(profile)
  if Supported() then
    for _, id in ipairs(registered) do pcall(C_UnitAuras.RemoveAuraSound, id) end
  end
  wipe(registered)

  local done = {} -- one sound per event, unit and spell ID
  for _, bar in ipairs(profile.bars or {}) do
    local kind = ns.Bar.Type(bar)
    for _, entry in ipairs(bar.buttons or {}) do
      local opts = ns.Bar.Options(profile, bar, entry)
      local unit = Sounds.AuraUnit(kind, entry, opts)
      local wanted = {}
      for _, alert in ipairs(ns.Alerts.List(opts)) do
        if alert.kind == "sound" and (alert.when == "applied" or alert.when == "removed") then wanted[#wanted + 1] = alert end
      end
      if unit and #wanted > 0 then
        if not Supported() then
          if not warned then
            warned = true
            ns.Print("This client can't play sounds for buffs starting or ending.")
          end
          return
        end
        local ids, name = Watched(kind, entry, unit)
        for _, alert in ipairs(wanted) do
          local event = alert.when == "applied" and "Added" or "Removed"
          local file = Sounds.File(alert.sound, name, Sounds.Fallback(event, kind, unit), profile.voice)
          if file then
            for spellID in pairs(ids) do
              local signature = event .. unit .. spellID
              if not done[signature] then
                done[signature] = true
                local ok, id = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger[event], {
                  unitToken = unit, spellID = spellID, soundFileName = file, outputChannel = "Master",
                })
                if ok and id then registered[#registered + 1] = id end
              end
            end
          end
        end
      end
    end
  end
end

-- Menu items choosing a sound for one of an entry's options; picking one
-- plays it. name: the aura's or spell's name, for "Say its name" (nil for a
-- whole bar); fallback: what's said when that name wasn't recorded.
function Sounds.MenuItems(current, pick, name, fallback)
  current = current or "none"
  fallback = fallback or "Buff gone"
  local function Item(key, text)
    return {
      text = text, checked = current == key,
      func = function()
        pick(key)
        Sounds.Preview(key, name, fallback)
      end,
    }
  end

  local items = {}
  for _, sound in ipairs(Sounds.LIST) do items[#items + 1] = Item(sound[1], sound[2]) end
  items[#items + 1] = { separator = true }
  local sayName = "Say its name"
  if name and VoiceFile(name) then
    sayName = 'Say its name: "' .. name .. '"'
  elseif name then
    sayName = 'Say its name (not recorded: "' .. fallback .. '")'
  end
  items[#items + 1] = Item("say:name", sayName)
  local phrase = SaidPhrase(current)
  items[#items + 1] = {
    text = phrase and Sounds.Label(current) or "Say a phrase", checked = phrase ~= nil, submenu = function()
      local phrases = {}
      for _, alert in ipairs(VOICE.alerts) do phrases[#phrases + 1] = Item("say:" .. alert[1], alert[1]) end
      return phrases
    end,
  }
  return items
end
