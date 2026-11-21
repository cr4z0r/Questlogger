# Changelog

User-visible changes to Questlogger are recorded here. Released versions should match
the `Version` field in `Questlogger.toc`.

## Unreleased

### Changed

- Shift-clicking tracker entries untracks them, with empty-space dragging preserving entry clicks.
- Shortened target-macro chat confirmations to the target name.
- Added the rested-XP percentage beside the native rested tooltip label in the same color.
- Added world-map quest-marker cards with separate windowed and fullscreen placement.
- Expanded compressed Lua control flow and clarified local names throughout Core, Data, and UI.
- Separated quest-text acquisition from card rendering in `UI/QuestText.lua`.
- Moved session-only tracker movement and resizing into `UI/TrackerGeometry.lua`.
- Simplified event orchestration, bulk-control setup, and quest-row objective layout with focused helpers.
- Documented module responsibilities, load order, and compatibility-sensitive behavior.

### Added

- Green experience-bar preview for the combined XP of completed, unturned-in quests.
- Rested XP displayed after the quest-XP preview, with the full pending total in the tooltip.
- Full-log quest XP scans that restore collapsed headers and the selected quest on legacy clients.
- Automatic interface translations for all eleven WoW client locales, plus English and Portuguese aliases.
- Localized addon-list notes and categories, numeric formatting, and locale-safe client fonts.
- Native name lookups and missing-name safeguards for localized NPC targeting macros.
- NPC-name learning from target and mouseover changes without changing the shared database locale.
- A client compatibility layer for modern quest-ID APIs and legacy quest-log APIs.
- A portable quest window available through `/questlogger` and `/ql`, plus legacy log hover integration.
- Shared interface metadata for Retail, Classic Era, TBC Anniversary, regional Wrath Titan Reforged,
  Mists Classic, and Forever.
- Safe registration of client-specific events and capability-based fallbacks for quest details,
  tracking, rewards, and macro limits.
- Initial project version metadata (`0.1.0`) for WoW Forever.
- README with installation, features, usage, compatibility, and saved-state information.
- MIT license, contribution guidance, and Git ignore rules.
- TOC author, description, optional dependencies, category, icon, and license metadata.
