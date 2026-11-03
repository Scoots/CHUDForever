-- Default settings and the starting layout for each spec. A new profile is
-- copied from these; after that everything is changed in game (/chud for
-- settings, /chud edit to arrange). Changing this file only affects new
-- profiles (or /chud reset).
local _, ns = ...

-- Every button option, with its default. Bars can override these in
-- buttonDefaults, and each button can override them again.
ns.BUTTON_DEFAULTS = {
  cooldown = "swipe",     -- "swipe" (clock), "wipe" (left to right) or "none"
  numbers = true,         -- countdown number while on cooldown
  desaturate = true,      -- gray while on cooldown
  gcd = false,            -- light swipe during the global cooldown
  visibility = "always",  -- "always", "cooldown" (only while on cooldown) or "ready" (hidden while on cooldown)
  manaCost = false,       -- mana cost in the corner
  rangeTint = true,       -- red while the target is out of range (the spell must be on an action bar, hidden bars count)
  manaTint = true,        -- blue while you can't afford it
  usableTint = true,      -- darker while unusable for any other reason
  procGlow = true,        -- glowing border while the game highlights the spell
  procStyle = "border",   -- its look: "border" (pulsing edge), "ants" (marching ants and a soft glow) or "both"
  procColor = "gold",     -- its color (Glow.COLORS)
  reactive = "auto",      -- glow while usable: "auto" (Overpower, Revenge, Execute, Riposte...), true or false
  -- Aura buttons
  show = "active",        -- "active" (while up), "missing" (alert while down) or "always" (dimmed while down)
  unit = "player",        -- "player" (my buffs) or "target" (my debuffs)
  auraGlow = false,       -- rotating border while the aura is up
  auraTimer = "spinner",  -- time left: "spinner" (clock swipe), "number" or "both"
  timerRed = 5,           -- time left turns red under this many seconds (0: never)
  -- Charge bars
  pips = 3,               -- segments: the most charges the buff can have
  chargeLook = "bar",     -- "bar" (segments), "orbs", "gems" (art in Media/Charges) or "icon" (the spell's icon)
  chargeOrb = "lightning", -- orbs' theme (Charges.ORBS)
  chargeGem = "red",       -- gems' color (Charges.GEMS)
  chargeGap = 3,          -- pixels between charges
  -- Totem bars
  totemRange = true,      -- red glow while out of range of a totem that buffs you
  totemPulse = true,      -- pulse timer for totems that pulse (Tremor, Earthbind...)
  totemCooldown = true,   -- thin bar for the totem spell's cooldown
  totemDistance = true,   -- yards of reach left, from where you dropped it (open world only)
  totemExtraRange = 0,    -- yards added to every totem's reach (talents the addon hasn't learned yet)
  -- Weapon enchant bars
  weaponShow = "alert",   -- "alert" (only while missing or running out) or "always"
  weaponWarn = 60,        -- seconds left that count as running out
  -- Cooldown buttons
  debuffGray = false,     -- with target debuff: gray until the debuff is on the target
  targetDebuff = false,   -- also show my debuff from the spell on the target (time left along the bottom);
                          -- on a shock: every shock's debuff, and the icon of the last shock cast
  earlyReady = false,     -- glow green when it's ready sooner than its cooldown (Stormstrike resets)
  pulse = false,          -- its icon flashes big on screen when the cooldown is ready (Pulse.lua)
  -- Alerts: sounds and visuals on a trigger (see Alerts.lua); false: none
  alerts = false,
}

-- WoW Forever specs are worked out from the final talent of each tree (every
-- rank listed), or else from the tree with the most points. A mage's also go by
-- its talent spells (talents), since its filler follows its spec. Each class's
-- specs are in talent tree order.
ns.SPECS = {
  { key = "WARRIOR_ARMS", class = "WARRIOR", name = "Arms", spells = { 12294, 21551, 21552, 21553 } },               -- Mortal Strike
  { key = "WARRIOR_FURY", class = "WARRIOR", name = "Fury", spells = { 23881, 23892, 23893, 23894 } },               -- Bloodthirst
  { key = "WARRIOR_PROTECTION", class = "WARRIOR", name = "Protection", spells = { 23922, 23923, 23924, 23925 } },   -- Shield Slam
  { key = "PALADIN_HOLY", class = "PALADIN", name = "Holy", spells = { 1310911, 1311590, 1311595 } },                -- Light's Vigil
  { key = "PALADIN_PROTECTION", class = "PALADIN", name = "Protection", spells = { 1328544 } },                      -- Shieldsworn
  { key = "PALADIN_RETRIBUTION", class = "PALADIN", name = "Retribution", spells = { 1310735 } },                    -- Unsealed Wrath
  { key = "HUNTER_BEAST_MASTERY", class = "HUNTER", name = "Beast Mastery", spells = { 19574 } },                    -- Bestial Wrath
  { key = "HUNTER_MARKSMANSHIP", class = "HUNTER", name = "Marksmanship", spells = { 1310687, 1310785, 1310786 } },  -- Sniper Shot
  { key = "HUNTER_SURVIVAL", class = "HUNTER", name = "Survival", spells = { 1310533 } },                            -- Lacerating Strikes
  { key = "ROGUE_ASSASSINATION", class = "ROGUE", name = "Assassination", spells = { 1310707, 399956, 1241582, 1241584 } },  -- Mutilate
  { key = "ROGUE_COMBAT", class = "ROGUE", name = "Combat", spells = { 13750 } },                                    -- Adrenaline Rush
  { key = "ROGUE_SUBTLETY", class = "ROGUE", name = "Subtlety", spells = { 1316709, 1325756, 1325757, 1325758 } },   -- Death Mark
  { key = "PRIEST_DISCIPLINE", class = "PRIEST", name = "Discipline", spells = { 10060 } },                          -- Power Infusion
  { key = "PRIEST_HOLY", class = "PRIEST", name = "Holy", spells = { 401859, 1240826, 1240827 } },                   -- Prayer of Mending
  { key = "PRIEST_SHADOW", class = "PRIEST", name = "Shadow", spells = { 15473 } },                                  -- Shadowform
  { key = "SHAMAN_ELEMENTAL", class = "SHAMAN", name = "Elemental", spells = {} },                                   -- no active final talent: by points
  { key = "SHAMAN_ENHANCEMENT", class = "SHAMAN", name = "Enhancement", spells = { 425336 } },                       -- Rage of the Farseer
  { key = "SHAMAN_RESTORATION", class = "SHAMAN", name = "Restoration", spells = { 408521, 1239242, 1239243 } },     -- Riptide
  { key = "MAGE_ARCANE", class = "MAGE", name = "Arcane", spells = { 12042 },                                        -- Arcane Power
    talents = { 12043, 400574 } },                                                                                   -- Presence of Mind, Arcane Blast
  { key = "MAGE_FIRE", class = "MAGE", name = "Fire", spells = { 11129 },                                            -- Combustion
    talents = { 11113, 11366 } },                                                                                    -- Blast Wave, Pyroblast
  { key = "MAGE_FROST", class = "MAGE", name = "Frost", spells = { 11426, 13031, 13032, 13033 },                     -- Ice Barrier
    talents = { 11958, 12472, 1312002 } },                                                                           -- Ice Block, Cold Snap, Ice Lance
  { key = "WARLOCK_AFFLICTION", class = "WARLOCK", name = "Affliction", spells = { 1316697 } },                      -- Wrack
  { key = "WARLOCK_DEMONOLOGY", class = "WARLOCK", name = "Demonology", spells = { 425464 } },                       -- Demonic Pact
  { key = "WARLOCK_DESTRUCTION", class = "WARLOCK", name = "Destruction", spells = { 412758, 1293812, 1293813 } },   -- Incinerate
  { key = "DRUID_BALANCE", class = "DRUID", name = "Balance", spells = { 24858 } },                                  -- Moonkin Form
  { key = "DRUID_FERAL_COMBAT", class = "DRUID", name = "Feral Combat", spells = { 407995, 1238069, 1238070, 1238073, 1322605 } },  -- Primal Bite, Shifting Power
  { key = "DRUID_RESTORATION", class = "DRUID", name = "Restoration", spells = { 408120, 1238214, 1238215 } },       -- Wild Growth
}

-- Aura spell IDs (every rank). Rank IDs the player knows are also found by name.
local LIGHTNING_SHIELD = { 324, 325, 905, 945, 8134, 10431, 10432 }
local WATER_SHIELD = { 408510 }
local INNER_FIRE = { 588, 7128, 602, 1006, 10951, 10952 }
local BATTLE_SHOUT = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }
local SLICE_AND_DICE = { 5171, 6774 }
local SHADOWGUARD = { 18137, 19308, 19309, 19310, 19311, 19312 } -- troll priests
local MAGE_ARMORS = { 168, 7300, 7301, 7302, 7320, 10219, 10220, 6117, 22782, 22783 } -- Frost, Ice, Mage Armor
local ICE_BARRIER = { 11426, 13031, 13032, 13033 }
local MANA_SHIELD = { 1463, 8494, 8495, 10191, 10192, 10193 }
local THORNS = { 467, 782, 1075, 8914, 9756, 9910 }

-- Buffs with charges, by class, and the most each holds: offered first when
-- picking a charge bar's buff (EditMenu.lua).
ns.CHARGE_BUFFS = {
  SHAMAN = { { ids = LIGHTNING_SHIELD, charges = 3 }, { ids = WATER_SHIELD, charges = 3 } },
  PRIEST = { { ids = SHADOWGUARD, charges = 3, race = "Troll" }, { ids = INNER_FIRE, charges = 20 } },
  PALADIN = { { ids = { 20925, 20927, 20928 }, charges = 4 } }, -- Holy Shield
}

-- A druid ability usable in one form only: shown only in that form (Button.lua), and
-- each form's are centered on the bar by themselves (Bar.GatedSlots).
local function Cat(id, extra)
  local entry = { spell = id, form = "cat" }
  for key, value in pairs(extra or {}) do entry[key] = value end
  return entry
end
local function Bear(id) return { spell = id, form = "bear" } end
local function Caster(id) return { spell = id, form = "caster" } end
-- Power Word: Shield, gray while Weakened Soul is on whoever it would go on (Button.lua)
local SHIELD = { spell = 17, lockout = 6788, lockoutTime = 15 }
-- Mind Flay once you have it, Smite until then. A filler stays in color: Flay's slow
-- isn't something to keep up, so it doesn't gray out until it's on the target.
local SMITE_OR_FLAY = { spell = { 15407, 585 }, targetDebuff = false }

local function Join(...)
  local all = {}
  for i = 1, select("#", ...) do
    for _, id in ipairs((select(i, ...))) do all[#all + 1] = id end
  end
  return all
end

-- Paladin seals, auras and blessings (every rank; ranks you know are also found by name)
local SEALS = Join(
  { 21084, 20287, 20288, 20289, 20290, 20291, 20292, 20293 }, -- Righteousness
  { 20375, 20915, 20918, 20919, 20920 },                      -- Command
  { 21082, 20162, 20305, 20306, 20307, 20308 },               -- the Crusader
  { 20165, 20347, 20348, 20349 },                             -- Light
  { 20166, 20356, 20357 },                                    -- Wisdom
  { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 },    -- Fury
  { 20164 })                                                  -- Justice
local PALADIN_AURAS = Join(
  { 465, 10290, 643, 10291, 1032, 10292, 10293 },             -- Devotion
  { 7294, 10298, 10299, 10300, 10301 },                       -- Retribution
  { 19746 },                                                  -- Concentration
  { 19876, 19895, 19896 }, { 19888, 19897, 19898 }, { 19891, 19899, 19900 }, -- Shadow, Frost, Fire Resistance
  { 20218 })                                                  -- Sanctity
local BLESSINGS = Join(
  { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 }, -- Might (and Greater)
  { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 },        -- Wisdom
  { 20217, 25898 })                                                  -- Kings

-- Default layouts ----------------------------------------------------------------------------------
-- Every new profile starts with the same bars, filled for its class (and spec):
--   My buffs:     every buff you cast on yourself, while up (on top)
--   Rotation:     spells with a cooldown of 12 seconds or less, and fillers (just above the power bar)
--   Cooldowns:    spells with a longer one (just below the power bar)
--   Items:        trinkets, potions, healthstones, runes, grenades; only while on cooldown (right)
--   Left side:    a charge bar on top, and what's missing below it (buffs, armors, weapon enchants)
--   Absorb:       shields on you, anyone's
-- plus totems and shield charges for shamans, Inner Fire charges for priests,
-- and weapon enchants for
-- shamans and rogues. Spells you don't know (another spec's, not trained
-- yet) stay hidden until you do; another race's aren't added at all. A spell
-- is an ID, or a button entry for one with options.

local SHOCKS = { spell = 8042, group = { 8050, 8056 } } -- one button, every shock's debuff (the bar's "auto")
-- Heroic Strike and Cleave: one button, showing the one queued for your next swing (Button.lua).
local HEROIC_CLEAVE = { spell = 78, group = { 845 }, queue = true }

-- Burst cooldowns: their buffs are left off cooldown bars and shown naturally
-- on the My buffs bar while active.
ns.BURST = {
  20572,                               -- Blood Fury
  20554,                               -- Berserking
  425336,                              -- Rage of the Farseer
  16166,                               -- Lightning Mastery
  1719, 12292, 12328,                  -- Recklessness, Sweeping Strikes, Death Wish
  3045,                                -- Rapid Fire
  13750, 13877, 14177,                 -- Adrenaline Rush, Blade Flurry, Cold Blood
  10060, 14751,                        -- Power Infusion, Inner Focus
  12042, 11129, 12043,                 -- Arcane Power, Combustion, Presence of Mind
}

-- The Items bar: trinkets, and consumables that share a cooldown as one
-- button each (showing the one you used last).
ns.DEFAULT_ITEMS = {
  { slot = 13 }, { slot = 14 },
  -- Potions: healing, mana, Free Action, Limited Invulnerability, Restorative, Mighty Rage
  { item = 13446, group = { 3928, 1710, 929, 858, 118, 13444, 13443, 6149, 3827, 3385, 2455,
    5634, 3387, 9030, 13442 } },
  -- Healthstones, every rank and talent version
  { item = 9421, group = { 19012, 19013, 5510, 19010, 19011, 5509, 19008, 19009, 5511, 19006, 19007,
    5512, 19004, 19005 } },
  { item = 20520, group = { 12662 } }, -- Dark Rune, Demonic Rune
  -- Grenades and bombs: Thorium, Iron, Dense Dynamite, Big Iron Bomb, EZ-Thro Dynamite II, Big Bronze Bomb
  { item = 15993, group = { 4390, 18641, 4394, 18588, 4380 } },
  -- Mana gems: Ruby, Citrine, Jade, Agate
  { item = 8008, group = { 8007, 5513, 5514 } },
  -- Spellstones and Firestones, every rank
  { item = 13603, group = { 13602, 5522 } },
  { item = 13701, group = { 13700, 13699, 1254 } },
}

-- Cooldowns this long or shorter go on the Rotation bar, longer ones on Cooldowns.
ns.ROTATION_COOLDOWN = 12

local function FirstSpell(entry)
  return type(entry.spell) == "table" and entry.spell[1] or entry.spell
end

-- An entry's spell's base cooldown in seconds; nil when it isn't known.
function ns.EntryCooldown(entry)
  return ns.BaseCooldown(FirstSpell(entry))
end

-- Burst spells by name (any rank).
local burstNames
function ns.IsBurst(spellID)
  if not burstNames then
    burstNames = {}
    for _, item in ipairs(ns.BURST) do
      local ids = type(item) == "table" and item.spell or item
      for _, id in ipairs(type(ids) == "table" and ids or { ids }) do
        local name = C_Spell.GetSpellName(id)
        if name and not ns.issecret(name) then burstNames[name] = true end
      end
    end
  end
  local name = type(spellID) == "number" and C_Spell.GetSpellName(spellID)
  return name ~= nil and not ns.issecret(name) and burstNames[name] == true
end

-- Each race's racials, by UnitRace's file name. New profiles only get their own.
local RACIALS = {
  Orc = { 20572 },                  -- Blood Fury
  Troll = { 20554 },                -- Berserking
  Tauren = { 20549 },               -- War Stomp
  Scourge = { 7744, 20577 },        -- Will of the Forsaken, Cannibalize
  Dwarf = { 20594 },                -- Stoneform
  Gnome = { 20589 },                -- Escape Artist
  Human = { 20600 },                -- Perception
  NightElf = { 20580 },             -- Shadowmeld
  Skyborne = { 1259705, 1259686 },  -- Read Leyline, Skysight
}

-- Spells on a class's cooldown and utility lists that only one race has.
local RACE_ONLY = {
  [13908] = "Dwarf",    -- Desperate Prayer
  [13896] = "Human",    -- Feedback
  [10797] = "NightElf", -- Starshards
  [2651] = "NightElf",  -- Elune's Grace
  [2652] = "Scourge",   -- Touch of Weakness
  [9035] = "Troll",     -- Hex of Weakness
  [1277370] = "Human",  -- Divine Grace
  [1277331] = "Dwarf",  -- Chastise
  [1277455] = "Gnome",  -- Confounding Flash
  [1277462] = "Gnome",  -- Contingency Plan
  [1277324] = "Scourge", -- Dark Sacrifice
}

-- Whether a race (nil: any) is yours. If the game won't say, it counts as yours:
-- a spell you don't know stays hidden anyway.
function ns.IsMyRace(race)
  if not race then return true end
  local _, mine = UnitRace("player")
  if ns.issecret(mine) or not mine then return true end
  return mine == race
end

ns.CLASS_DEFAULTS = {
  WARRIOR = {
    -- Mortal Strike, Bloodthirst, Shield Slam, Whirlwind, Overpower, Revenge, Execute,
    -- Shield Block, and Heroic Strike / Cleave on one button showing the one queued
    -- for your next swing
    main = { 12294, 23881, 23922, 1680, 7384, 6572, 5308, 2565, HEROIC_CLEAVE },
    specs = {
      WARRIOR_ARMS = { 12294, 7384, 5308, 1680, HEROIC_CLEAVE },
      WARRIOR_FURY = { 23881, 1680, 5308, 7384, HEROIC_CLEAVE },
      WARRIOR_PROTECTION = { 23922, 6572, 2565, HEROIC_CLEAVE },
    },
    -- Rend, Sunder Armor, Hamstring, Thunder Clap: their own bar above Rotation
    debuffs = { 772, 7386, 1715, 6343 },
    -- Recklessness, Shield Wall, Retaliation (separate cooldowns on Forever), Sweeping
    -- Strikes, Bloodrage, Berserker Rage, Death Wish, Last Stand, Reckless Swings
    cooldowns = { 1719, 871, 20230, 12292, 2687, 18499, 12328, 12975, 1329555 },
    -- Charge, Intercept, Pummel / Shield Bash (one shared cooldown; which one you can
    -- use depends on your stance, so the button doesn't darken for it), Concussion
    -- Blow, Disarm, Intimidating Shout
    utility = { 100, 20252, { spell = 6552, group = { 72 }, usableTint = false }, 12809, 676, 5246 },
    -- Taunt, Mocking Blow, Challenging Shout
    taunts = { 355, 694, 1161 },
    missing = { BATTLE_SHOUT },
    hideBuffs = BATTLE_SHOUT, -- not on My Active Buffs: it has its own alert
  },
  PALADIN = {
    -- Judgement, Holy Shock, Exorcism, Hammer of Wrath, Consecration, Holy Shield,
    -- Holy Wrath, Holy Strike (Forever), and the seal you have up (its time left;
    -- dimmed while there's none, so it always holds its place and the row stays centered)
    main = { 20271, 20473, 879, 24275, 26573, 20925, 2812, 679, { aura = SEALS, show = "always" } },
    specs = {
      PALADIN_HOLY = { 20473, 20271, 26573 },
      PALADIN_PROTECTION = { 20925, 26573, 20271, 2812 },
      PALADIN_RETRIBUTION = { 20271, 679, 879, 24275, 26573 },
    },
    -- An alert for each: no seal, no aura, no blessing
    missing = { SEALS, PALADIN_AURAS, BLESSINGS },
    -- Divine Favor, Divine Shield, Divine Protection, Lay on Hands
    cooldowns = { 20216, 642, 498, 633 },
    -- Hammer of Justice, Blessing of Protection, Blessing of Freedom
    utility = { 853, 1022, 1044 },
  },
  HUNTER = {
    -- The stings (one button: the one on the target, or the last cast), Hunter's Mark,
    -- Aimed Shot, Arcane Shot, Multi-Shot, Raptor Strike, Mongoose Bite, Counterattack
    main = { { spell = 1978, group = { 3034, 3043 } }, 1130, 19434, 3044, 2643, 2973, 1495, 19306 },
    -- Rapid Fire, Bestial Wrath
    cooldowns = { 3045, 19574 },
    -- Scatter Shot, Wyvern Sting, Intimidation, Feign Death, Disengage, Deterrence,
    -- Concussive Shot, Wing Clip, Tranquilizing Shot, Flare
    utility = { 19503, 1215753, 19577, 5384, 781, 19263, 5116, 2974, 19801, 1543 },
    -- Every trap on one button (one shared cooldown): the trap used last, or the
    -- one whose debuff on the target ends first, with its time left
    traps = { { spell = 13795, group = { 13813, 1499, 13809 } } },
  },
  ROGUE = {
    -- Sinister Strike, Backstab, Hemorrhage, Shank, Slice and Dice (dimmed while it's
    -- down, its time left while it's up), Rupture, Death Mark, Riposte, Ghostly Strike,
    -- and the openers, shown only while stealthed: Ambush, Cheap Shot, Garrote
    main = { 1752, 53, 16511, 1329283, { aura = SLICE_AND_DICE, show = "always" }, 1943, 1316709, 14251, 14278,
      { spell = 8676, stealthOnly = true }, { spell = 1833, stealthOnly = true }, { spell = 703, stealthOnly = true } },
    -- Adrenaline Rush, Blade Flurry, Cold Blood, Preparation
    cooldowns = { 13750, 13877, 14177, 14185 },
    -- Kick, Gouge, Kidney Shot, Blind, Sap (while stealthed), Distract, Sprint, Vanish, Evasion, Feint
    utility = { 1766, 1776, 408, 2094, { spell = 6770, stealthOnly = true }, 1725, 2983, 1856, 5277, 1966 },
  },
  PRIEST = {
    -- Shadow Word: Pain, Devouring Plague (next to it), Mind Blast, Mind Flay or
    -- Smite, Power Word: Shield
    main = { 589, 2944, 8092, SMITE_OR_FLAY, SHIELD },
    specs = {
      PRIEST_HOLY = { 401859, SHIELD, SMITE_OR_FLAY, 8092 }, -- with Prayer of Mending
      PRIEST_SHADOW = { 589, 2944, 15286, 8092, SMITE_OR_FLAY, SHIELD }, -- with Vampiric Embrace
    },
    -- Inner Focus, Power Infusion, and the racial priest spells (only your race's,
    -- RACE_ONLY): Desperate Prayer, Starshards, Elune's Grace, Feedback, Touch of
    -- Weakness, Hex of Weakness, Divine Grace, Contingency Plan, Dark Sacrifice
    cooldowns = { 14751, 10060, 13908, 10797, 2651, 13896, 2652, 9035, 1277370, 1277462, 1277324 },
    -- Psychic Scream, Silence, Fade, Fear Ward, and the racial Chastise and Confounding Flash
    utility = { 8122, 15487, 586, 6346, 1277331, 1277455 },
    missing = { INNER_FIRE },
    targetShield = true, -- your shields on your target, as a bar
  },
  SHAMAN = {
    -- Stormstrike (glowing on a reset), the shocks, Fire Nova, Chain Lightning, Lightning Bolt
    main = { { spell = 17364, earlyReady = true }, SHOCKS, 408341, 421, 403 },
    specs = {
      SHAMAN_ELEMENTAL = { SHOCKS, 421, 403, 408341 },
      SHAMAN_RESTORATION = { 408521, SHOCKS, 421 }, -- with Riptide
    },
    -- Rage of the Farseer, Lightning Mastery, Nature's Swiftness, Mana Tide Totem
    cooldowns = { 425336, 16166, 16188, 16190 },
    -- Grounding Totem, Earthbind Totem, Stoneclaw Totem, Totemic Call
    utility = { 8177, 2484, 5730, 437009 },
  },
  MAGE = {
    -- The filler for your spec (Frostbolt, Fireball or Arcane Missiles), Fire Blast,
    -- Pyroblast, Ice Lance (shares Fire Blast's cooldown, on a button of its own), Cone
    -- of Cold, Arcane Wrath, Blast Wave. The filler and Pyroblast stay in color: Frostbolt's
    -- slow and their burns aren't things to keep up, so they don't gray out until they're on.
    main = { { spell = { 116, 133, 5143 }, bySpec = { MAGE_FROST = 116, MAGE_FIRE = 133, MAGE_ARCANE = 5143 }, targetDebuff = false },
      2136, { spell = 11366, targetDebuff = false }, 1312002, 120, 1326079, 11113 },
    -- Arcane Power, Presence of Mind, Combustion, Evocation, Cold Snap, and Ice Barrier
    -- and Mana Shield: dimmed while down, their time left while up
    cooldowns = { 12042, 12043, 11129, 12051, 12472,
      { aura = ICE_BARRIER, show = "always" }, { aura = MANA_SHIELD, show = "always" } },
    -- Frost Nova, Counterspell, Blink, Ice Block, Polymorph, Fire Ward / Frost Ward (one shared cooldown)
    utility = { 122, 2139, 1953, 11958, 118, { spell = 543, group = { 6143 } } },
    missing = { MAGE_ARMORS },
  },
  WARLOCK = {
    -- Corruption, your curse on the target (one button for every curse but Doom),
    -- Immolate, Siphon Life, Shadow Bolt, Conflagrate
    main = { 172, { spell = 980, group = { 702, 704, 1714, 1311676, 18223 } }, 348, 18265, 686, 17962 },
    -- Amplify Curse, Fel Domination, Inferno, Shadowburn, Bane of Doom, and your
    -- pet's main ability (Spell Lock, Sacrifice or Seduction: whichever pet is out)
    cooldowns = { 18288, 18708, 1122, 17877, 603, { spell = 19244, group = { 7812, 6358 } } },
    -- Fear, Banish, Death Coil, Howl of Terror, Shadow Ward, and your Soulstone (the item)
    utility = { 5782, 710, 6789, 5484, 6229, { item = 16896, group = { 16895, 16893, 16892, 5232 } } },
  },
  DRUID = {
    -- Out of a form: Moonfire, Insect Swarm, Faerie Fire, Swiftmend, Wild Growth; in Cat
    -- Form: Claw, Shred, Rake, Rip, Ferocious Bite, Shifting Power, and Ravage and Pounce
    -- while prowling; in Bear Form: Maul, Swipe, Demoralizing Roar, Primal Bite
    main = { Caster(8921), Caster(5570), Caster(770),
      Cat(1082), Cat(5221), Cat(1822), Cat(1079), Cat(22568), Cat(1322605),
      Cat(6785, { stealthOnly = true }), Cat(9005, { stealthOnly = true }),
      Bear(6807), Bear(779), Bear(99), Bear(407995), Caster(18562), Caster(408120) },
    specs = {
      DRUID_BALANCE = { Caster(8921), Caster(5570), Caster(770) },
      DRUID_RESTORATION = { Caster(18562), Caster(408120) },
    },
    -- Innervate, Nature's Swiftness, Tranquility, and by form: Frenzied
    -- Regeneration and Enrage (Bear), Tiger's Fury (Cat)
    cooldowns = { 29166, 17116, 740, Bear(22842), Bear(5229), Cat(5217) },
    -- Bash and Feral Charge (Bear), Barkskin, Dash (Cat), Rebirth
    utility = { Bear(5211), Bear(16979), 22812, Cat(1850), 20484 },
    -- Growl, Challenging Roar (Bear)
    taunts = { Bear(6795), Bear(5209) },
    missing = { THORNS },
  },
}

local function Copy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, inner in pairs(value) do copy[key] = Copy(inner) end
  return copy
end

local function Entries(list)
  local entries = {}
  for _, item in ipairs(list or {}) do
    entries[#entries + 1] = type(item) == "number" and { spell = item } or Copy(item)
  end
  return entries
end

-- x/y are offsets from the center of the screen.
local function NewBar(name, kind, y, size, extra)
  local bar = {
    name = name, type = kind, orientation = "HORIZONTAL", grow = "CENTER",
    size = size, spacing = 4, scale = 1, x = 0, y = y, buttons = {},
  }
  for key, value in pairs(extra or {}) do bar[key] = value end
  return bar
end

-- The bars beside the power bar (250 wide, y -152) stand on its bottom edge and
-- grow up, just past the ends of Rotation: 7 of its buttons fit between them, and
-- so does My Active Buffs (6 icons at most).
local BESIDE_X, BESIDE_Y = 186, -159

-- On the left: taunts if the class has them, a column of what's missing (buffs,
-- armors, weapon enchants), and a charge bar centered over it, above Rotation.
local COLUMN_X, COLUMN_PAST_TAUNTS, CHARGES_Y = -190, -226, -63

local function ChargeBar(auras)
  return NewBar("Buff With Charges", "charges", CHARGES_Y, 30, { x = COLUMN_X, buttons = { { aura = auras } } })
end

local function MissingColumn(name, kind, x, extra)
  local column = NewBar(name, kind, BESIDE_Y, 36, { x = x, orientation = "VERTICAL", grow = "UP" })
  for key, value in pairs(extra or {}) do column[key] = value end
  return column
end

-- Racials are never part of a rotation, however short their cooldown
-- (Shadowmeld's is 10 seconds): they go on Cooldowns.
local RACIAL_IDS = {}
for _, ids in pairs(RACIALS) do
  for _, id in ipairs(ids) do RACIAL_IDS[#RACIAL_IDS + 1] = id end
end

-- Your race's racials; all of them if the game won't say which race you are.
local function MyRacials()
  local _, race = UnitRace("player")
  if ns.issecret(race) or not race then return RACIAL_IDS end
  return RACIALS[race] or {}
end

-- A cooldown or utility list's entries, without the spells only another race has.
local function MyEntries(list)
  local entries = {}
  for _, entry in ipairs(Entries(list)) do
    if ns.IsMyRace(RACE_ONLY[FirstSpell(entry)]) then entries[#entries + 1] = entry end
  end
  return entries
end

local function IsRacial(entry)
  local name = ns.SpellName(FirstSpell(entry))
  return name ~= nil and ns.NameSet(RACIAL_IDS)[name] == true
end

-- Rotation spells with a longer cooldown than the rotation cutoff.
local ALWAYS_ROTATION = {
  17364, -- Stormstrike (6 sec on Forever; kept here in case that changes)
  20473, -- Holy Shock (10 sec on Forever)
  2944,  -- Devouring Plague (24 sec), next to Shadow Word: Pain
  679,   -- Holy Strike
  11113, -- Blast Wave (45 sec)
}

local function IsRotation(entry)
  local name = ns.SpellName(FirstSpell(entry))
  return name ~= nil and ns.NameSet(ALWAYS_ROTATION)[name] == true
end

-- Puts spell entries on the Rotation or Cooldowns list by their cooldown.
-- An entry whose cooldown isn't known goes on fallback.
function ns.SortByCooldown(entries, rotation, long, fallback)
  for _, entry in ipairs(entries) do
    local cooldown = ns.EntryCooldown(entry)
    local list = fallback
    if cooldown and cooldown > 0 then list = cooldown <= ns.ROTATION_COOLDOWN and rotation or long end
    if IsRacial(entry) then list = long end
    if IsRotation(entry) then list = rotation end
    list[#list + 1] = entry
  end
end

-- The bars every new profile has, close around the power bar (y -152): Active
-- Buffs on top, Rotation just above the bar, with room for the health bar in
-- between, Cooldowns just below it, and Items beside it.
function ns.StandardBars(rotation, long)
  ns.Groups.Collapse(rotation)
  ns.Groups.Collapse(long)
  return {
    NewBar("My Active Buffs", "allbuffs", -57, 40, { dynamic = true, unit = "player", mine = true, maxIcons = 6,
      maxDuration = 60, buttonDefaults = { auraGlow = false, auraTimer = "spinner" } }),
    -- Spells that leave a debuff set themselves up ("auto", Debuff.lua).
    NewBar("Rotation", "cooldowns", -103, 44, { buttonDefaults = { gcd = true, targetDebuff = "auto" }, buttons = rotation }),
    -- The big cooldowns flash on screen when they're back (Pulse.lua).
    NewBar("Cooldowns", "cooldowns", -181, 36, { buttonDefaults = { targetDebuff = "auto", pulse = true }, buttons = long }),
    NewBar("Items", "cooldowns", BESIDE_Y, 32, { x = BESIDE_X, grow = "UP", orientation = "VERTICAL", buttons = Entries(ns.DEFAULT_ITEMS),
      buttonDefaults = { visibility = "cooldown" } }),
  }
end

-- The cast bar starts low on the screen, where the game's own goes (about 190
-- up from the bottom edge), but never up onto the HUD above it.
local function CastBarY()
  return math.min(-290, math.floor(190 - UIParent:GetHeight() / 2))
end

-- The power, health and swing bars' settings for a new profile.
function ns.DefaultMeters()
  local castY = CastBarY()
  return {
    -- Health right above power, the swing timer just under the cast bar. Only power starts on.
    health = { enabled = false, width = 250, height = 14, x = 0, y = -134, text = "value" },
    power = { enabled = true, width = 250, height = 14, x = 0, y = -152, text = "value" },
    cast = {
      enabled = false, width = 250, height = 16, x = 0, y = castY, showName = true, showTime = true,
      castColor = "gold", channelColor = "green", hideGame = true,
    },
    swing = {
      enabled = false, mode = "auto", modeVersion = 2, width = 250, height = 14, x = 0, y = castY - 28,
      fill = "down", gap = 1, bgColor = "dark", containerAlpha = 0.8,
    },
  }
end

-- A new profile's layout for a class (UnitClass's file name) and spec key.
-- Every spell in a class's lists, its specs' too, each once (in talent tree
-- order): with hybrid talents any of them may be yours, and the ones you
-- don't know stay hidden until you do.
local function ClassMain(class, data)
  local list, seen = {}, {}
  local function Add(items)
    for _, item in ipairs(items or {}) do
      local first = type(item) == "table" and item.spell or item
      -- A button for an aura has no spell (Slice and Dice, a seal): it only matches itself.
      if type(first) == "table" then first = first[1] or item end
      if not seen[first] then
        seen[first] = true
        list[#list + 1] = item
      end
    end
  end
  Add(data.main)
  for _, spec in ipairs(ns.SPECS) do
    if spec.class == class then Add(data.specs and data.specs[spec.key]) end
  end
  return list
end

-- The bars a class has whatever fills its cooldown bars: shields, totems, a
-- charge bar, weapon enchants, alerts for missing buffs (one button each), and
-- the buffs kept off My Active Buffs. totemsY: under the bars above the totems.
-- columnX: where the left column goes, when something else is beside the power bar.
function ns.AddClassBars(bars, class, totemsY, columnX)
  local data = ns.CLASS_DEFAULTS[class] or {}
  columnX = columnX or COLUMN_X
  -- Ends level with the top of the power bar, so its amount shows beside that bar.
  bars[#bars + 1] = NewBar("Absorb", "absorb", -75, 18, { x = 224, unit = "player", look = "segments",
    orientation = "VERTICAL", width = 140, segments = 14 })
  if class == "SHAMAN" then
    bars[#bars + 1] = NewBar("Totems", "totems", totemsY, 30)
    bars[#bars + 1] = ChargeBar(Join(LIGHTNING_SHIELD, WATER_SHIELD))
  end
  if class == "PRIEST" and ns.IsMyRace("Troll") then
    -- Shadowguard (troll priests) has charges, like Lightning Shield.
    bars[#bars + 1] = ChargeBar(SHADOWGUARD)
  end
  if data.targetShield then
    -- On the far side of the left column, and past a troll's charge bar.
    bars[#bars + 1] = NewBar("Target Shield", "absorb", -75, 18, { x = ns.IsMyRace("Troll") and -260 or -226,
      unit = "target", look = "segments", orientation = "VERTICAL", width = 140, segments = 14 })
  end
  if class == "SHAMAN" or class == "ROGUE" then
    bars[#bars + 1] = MissingColumn("Weapons", "weapons", columnX)
  end
  if data.missing then
    local alerts = {}
    for _, auras in ipairs(data.missing) do alerts[#alerts + 1] = { aura = auras } end
    bars[#bars + 1] = MissingColumn("Missing buffs", "alerts", columnX, { buttonDefaults = { show = "missing" }, buttons = alerts })
  end
  if data.hideBuffs then
    -- Kept by ID; Learn.lua turns them into names (every rank) at the next login.
    local exclude = {}
    for _, id in ipairs(data.hideBuffs) do exclude[id] = true end
    bars[1].exclude = exclude
  end
end

-- specKey: a spec's own layout; left out, the whole class's.
function ns.DefaultProfile(class, specKey)
  local data = ns.CLASS_DEFAULTS[class] or {}
  local main
  if specKey == nil then
    main = ClassMain(class, data)
  else
    main = (data.specs and data.specs[specKey]) or data.main
  end
  local rotation, long = {}, {}
  ns.SortByCooldown(Entries(main), rotation, long, rotation)
  for _, entry in ipairs(MyEntries(data.cooldowns)) do long[#long + 1] = entry end
  ns.SortByCooldown(Entries(MyRacials()), rotation, long, long)

  local bars = ns.StandardBars(rotation, long)
  ns.AddClassBars(bars, class, -255, data.taunts and COLUMN_PAST_TAUNTS)
  -- Debuffs to keep up: their own bar above Rotation, each gray until it's on the
  -- target. My Active Buffs moves up to make room.
  if data.debuffs then
    bars[1].y = -17
    table.insert(bars, 2, NewBar("Debuffs", "cooldowns", -59, 36, {
      buttonDefaults = { gcd = true, targetDebuff = true, debuffGray = true }, buttons = Entries(data.debuffs) }))
  end
  -- A second cooldown bar (utility), a hunter's traps, and taunts beside the power bar.
  if data.utility then
    bars[#bars + 1] = NewBar("Utility", "cooldowns", -219, 32, { buttonDefaults = { targetDebuff = "auto" },
      buttons = MyEntries(data.utility) })
  end
  if data.traps then
    bars[#bars + 1] = NewBar("Traps", "cooldowns", -255, 32, { buttonDefaults = { targetDebuff = true },
      buttons = Entries(data.traps) })
  end
  if data.taunts then
    bars[#bars + 1] = NewBar("Taunts", "cooldowns", BESIDE_Y, 32, { x = -BESIDE_X, grow = "UP", orientation = "VERTICAL",
      buttons = Entries(data.taunts) })
  end
  local profile = ns.DefaultMeters()
  profile.bars = bars
  return profile
end

ns.NewBarConfig = NewBar
