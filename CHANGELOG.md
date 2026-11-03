# Changelog

All notable changes to CHUDForever. Versions follow the `## Version` line in `CHUDForever.toc`.

## [0.19.0-beta3] - 11/03/2026

### Added

- **Ready pulse**: when a cooldown comes back, its icon fades in big and see-through on your screen, then grows as it fades away. Several at once play one after another. Turn it on for a whole bar or a single button with the new **Ready pulse** behavior, or with **Pulse on screen when ready** in a button's edit-mode menu. Move it in edit mode; its gear (or the profile's settings) sets the size and opacity, with a **Test** button. New profiles have it on for the **Cooldowns** bar.
- **Pick the buff for a Buff With Charges bar**: a **Buff** choice on the bar's settings page, and **Pick the buff** when you right-click it in edit mode. Your class's buffs with charges come first (Lightning Shield, say), and the buff doesn't have to be up. Picking another replaces it.

### Changed

- **New default layout**: your buffs on top, then rotation spells, the power bar, and cooldowns right under it. The bars to each side stand beside the power bar and grow up: items and the shield bar on the right; taunts, missing-buff alerts and weapon enchants on the left, with a charge bar (Lightning Shield, say) centered on top. My Active Buffs shows up to 6 icons, to fit between them. When you turn them on, the cast bar goes low on the screen where the game's own sits, the swing timer just under it, and the health bar right above the power bar. Existing profiles keep their places.
- **Warrior:** Rend, Sunder Armor, Hamstring and Thunder Clap have their own **Debuffs** bar above Rotation, each gray until it's on your target, then showing its time left and stacks. Pummel and Shield Bash share a cooldown, so they're one button.
- **Paladin:** the seal button is dimmed while no seal is up, instead of leaving a gap, so Rotation stays centered.
- **Druid:** new profiles only show the spells your form can use: Moonfire, Wild Growth and the like go away in Cat and Bear Form. Each form's buttons sit centered on the bar by themselves.
- **Racials:** new profiles only get your own race's, including the priest spells only your race has. Other races' used to sit on your bars, hidden in play and faded in edit mode. Read Leyline and Skysight are on the Cooldowns bar for Skyborne.
- **Priest racial spells:** new profiles now have Forever's newer ones. On Cooldowns: Divine Grace (Human), Contingency Plan (Gnome) and Dark Sacrifice (Undead). On Utility: Chastise (Dwarf) and Confounding Flash (Gnome).

Updated for the game's November 2 patch. Changes to the starting buttons apply to new profiles. Existing profiles keep theirs, and a spell the game removed just stays hidden.

- **Hunter traps** now share one cooldown, so they're one button. On an existing profile, the trap buttons on a bar fold into one the first time you log in.
- **Mage:** Rotation has your spec's filler, then the ones you know of Fire Blast, Pyroblast, Ice Lance, Cone of Cold, Arcane Wrath and Blast Wave. Fire Blast and Ice Lance now share a cooldown, on buttons of their own.
- **Rogue:** Shank and Death Mark are on the Rotation bar.
- **Warrior:** Reckless Swings is on the Cooldowns bar.
- **Druid:** Berserk is gone. Primal Bite (Bear) and Shifting Power (Cat), the new final talents, are on the bars instead.
- **Shaman:** Lava Burst is gone. Totemic Projection is now Totemic Call, which brings your totems to you: the yards of reach left now count from where you cast it, instead of disappearing.
- **Paladin:** Blessing of Light and Blessing of Salvation are off the **Missing buffs** list. **Seal of Fury** now counts as a seal: the "no seal" alert stays away while it's up, and the seal button shows it.
- `/chud report` works out your spec from the new final talents.

### Fixed

- Frostbolt, Fireball, Pyroblast and Mind Flay stayed gray until their slow or burn was on your target, as if it were a debuff to keep up. They're in color now, on new profiles.
- **A mage's filler now follows your talents**: Arcane Missiles, Fireball or Frostbolt. Spec detection couldn't read talent points on Forever, so it only worked once you had a tree's final talent. A respec changes the button right away. `/chud debug spec` shows what it read.
- Buttons hidden by your form or by not being stealthed left gaps on Rotation and Utility, pushing the rest off center. Now they take no room, in combat too: a rogue's openers appear beside the row when you stealth.
- New Rogue and Paladin profiles failed with a Lua error (`Defaults.lua: table index is nil`), so the HUD didn't load for those classes. Every earlier build had this.
- **Rebuild From Bars** no longer adds a Target bar, and now keeps the class's shield, charge and missing-buff bars.
- Dropping a spell on a Buff With Charges bar caused a Lua error while you had any buff up.
- A character with the same name and realm as an earlier one of another class (deleted and made again, or on a test server) used the old character's profile and buff list. Each class now gets its own. Your existing characters keep their settings.
- Your buff list and the swing timer's hunter check read your class when the addon loaded, which could be too early.

## [0.19.0-beta2] - 10/27/2026

### Changed

- The addon is now called **CHUDForever**, the same as its CurseForge page: its folder is `CHUDForever` (it was `CombatHUD`). If you installed beta1, delete the old `Interface\AddOns\CombatHUD` folder. Settings are saved per addon folder, so they start fresh; to keep yours, copy `WTF\Account\YOUR_ACCOUNT\SavedVariables\CombatHUD.lua` to `CHUDForever.lua` there (with the game closed).

## [0.19.0-beta1] - 10/26/2026 first public beta

The first build for everyone. See the [README](README.md) for what CHUDForever does.

### Added

- `/chud report`: your version, settings and what the HUD sees from the game, in a box to copy into a bug report.
- `/chud version`, and `/chud debug` for the troubleshooting commands.
- An entry in the game's **Options > AddOns** list, a **minimap button** (drag it around the edge; hide it in the Options entry) and the addon compartment menu, where the game has one. Left-click opens the settings, right-click moves bars and adds spells.
- **Quick setup** for each new character: size, position, and the health bar, cast bar and swing timer, applied as you pick. Open it again from your profile's page or the game's Options > AddOns entry.
- **Edit mode gears.** A gear on each bar's name opens its size, spacing, direction and when it shows, changed as you drag. The power, health, cast and swing bars have one for width and height.
- **Click a button in edit mode** for its menu (hovering shows which one). Click and hold still drags it.
- **Hide this button** in a button's menu: it stays on the bar with its settings, faded in edit mode and out of the way otherwise.
- **Your buffs list** on the "every buff I give myself" bar's settings page: every buff you've given yourself on that class, with icon, duration and the game's tooltip on hover. Hide or show any of them, even when it isn't up; ones longer than the bar's limit are dimmed in place, so changing the limit shows at once what it lets in. Ranks share one row (every Healing Potion is one), and buffs not seen for two months drop off.
- Right-click that bar for **Hide a buff…** (any you've had), **Show a hidden buff**, and **Manage buffs…**. On other bars, **Add → A buff…** lists the buffs up now and every one you've had.

### Default layouts, class by class

Every class's starting HUD was gone through ability by ability, and every spell ID checked against WoW Forever's own data.

- **Bars for each job.** Every class gets a **Utility** bar under Cooldowns (interrupts, stuns, movement, defensives). Warriors and druids get a **Taunts** bar standing on the left, hunters a **Traps** bar, priests a **Target Shield** bar (your shields on your target), and the **Missing buffs** bar warns about Battle Shout, no seal, aura or blessing, Inner Fire, no mage armor, and Thorns.
- **One button for related spells:** a hunter's stings, a warlock's curses (Bane of Doom has its own), fire traps and frost traps, and Heroic Strike with Cleave, which lights up while one is queued for your next swing and is gray while neither is.
- **Buttons that follow what you're doing:** rogue openers (Ambush, Cheap Shot, Garrote, Sap) only while stealthed; druid Cat and Bear abilities only in that form; Power Word: Shield gray while Weakened Soul is on your target (or on you); a warlock's pet ability (Spell Lock, Sacrifice or Seduction) for whichever pet is out; a mage's filler (Frostbolt, Fireball or Arcane Missiles) by spec; Mind Flay once you have it, Smite until then.
- **Buffs on the bars:** the paladin seal you have up, with its time left; Slice and Dice, Ice Barrier and Mana Shield, dimmed while down and with their time left while up. Shadowguard (troll priests) has charges like Lightning Shield.
- **Items bar:** mana gems, Spellstones and Firestones join trinkets, potions, healthstones, runes and grenades; warlocks get their Soulstone on Utility.
- **Where things go:** racials always go on Cooldowns (Shadowmeld's short cooldown put it on Rotation before). Stormstrike, Holy Shock, Holy Strike and Devouring Plague always go on Rotation. Recklessness, Shield Wall and Retaliation are separate buttons (they don't share a cooldown on Forever). Each class's hand-picked cooldowns stay on Cooldowns whatever their length.
- **Forever's spells:** Wyvern Sting and Curse of the Elements use Forever's spell IDs; Faerie Fire (Feral), Curse of Shadow, Blessing of Sanctuary and the old Fire Nova Totem aren't in Forever and are gone; Hurricane has no cooldown there, so it's off the Cooldowns bar.

### Changed

- One profile per character, whatever your talents. Before, each detected spec got its own profile, so a respec made a new one. Your other spec profiles stay in the list.
- New characters start with every tree's spells for their class; the ones you don't know stay hidden.
- `/chud reset` asks first (`/chud reset confirm` does it).
- Settings say "behaviors" instead of "plugins".
- `/chud help` is down to the everyday commands; the rest are under `/chud debug`. Their old names still work.
- Shorter labels on buttons that didn't fit (visibility choices say **Default** instead of spelling out the profile's choice, which is now a line underneath).
- The gear panel and the alert editor can be moved after they open.

### Removed

- `/chud spec` (the spec no longer picks the profile).
- `/chud addbar`, `/chud delbar` and `/chud adddefaults` (the settings window does these).
- `/chud position` and `/chud totemscan` (experiments for Totemic Projection).
- The **In combat or with a target** visibility choice: bars set to it now show **In combat**.

## Closed testing (0.1 - 0.17)

Built and tested on the closed WoW Forever beta. The later builds added, among other things:

- **0.17**: a cast bar for casts and channels, with colors, spell name and time left, that can hide the game's own. A bar texture per power, health and cast bar. Bar pages no longer repeat what their plugin cards set.
- **0.16**: new default layouts (rotation on top, long cooldowns below, items on the right, burst buffs above). Swing timer rows for main hand, off hand and ranged. Number settings can be typed. The power and health bars share one component.
- **0.15**: target debuff tracking set up automatically for damage-over-time and debuff spells, shared cooldowns (shocks, traps) stacked on one button, the swing timer following the game's own, Done/Escape to leave edit mode, totem pulses ending with the totem, totem reach from the listed values.
- **0.14**: proc glow styles and colors, duplicating bars and profiles, exporting and importing bars, and dragging bars between profiles.
