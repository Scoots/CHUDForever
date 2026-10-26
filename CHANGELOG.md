# Changelog

All notable changes to CombatHUD. Versions follow the `## Version` line in `CombatHUD.toc`.

## [0.19.0-beta1] - 10/26/2026 first public beta

The first build for everyone. See the [README](README.md) for what CombatHUD does.

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

### Changed

- One profile per character, whatever your talents. Before, each detected spec got its own profile, so a respec made a new one. Your other spec profiles stay in the list.
- New characters start with every tree's spells for their class; the ones you don't know stay hidden.
- `/chud reset` asks first (`/chud reset confirm` does it).
- Settings say "behaviors" instead of "plugins".
- `/chud help` is down to the everyday commands; the rest are under `/chud debug`. Their old names still work.

### Removed

- `/chud spec` (the spec no longer picks the profile).
- `/chud addbar`, `/chud delbar` and `/chud adddefaults` (the settings window does these).
- `/chud position` and `/chud totemscan` (experiments for Totemic Projection).

## Closed testing (0.1 - 0.17)

Built and tested on the closed WoW Forever beta. The later builds added, among other things:

- **0.17**: a cast bar for casts and channels, with colors, spell name and time left, that can hide the game's own. A bar texture per power, health and cast bar. Bar pages no longer repeat what their plugin cards set.
- **0.16**: new default layouts (rotation on top, long cooldowns below, items on the right, burst buffs above). Swing timer rows for main hand, off hand and ranged. Number settings can be typed. The power and health bars share one component.
- **0.15**: target debuff tracking set up automatically for damage-over-time and debuff spells, shared cooldowns (shocks, traps) stacked on one button, the swing timer following the game's own, Done/Escape to leave edit mode, totem pulses ending with the totem, totem reach from the listed values.
- **0.14**: proc glow styles and colors, duplicating bars and profiles, exporting and importing bars, and dragging bars between profiles.
