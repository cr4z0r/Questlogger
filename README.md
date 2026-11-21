# Questlogger

Quest log and tracker enhancements for World of Warcraft, by **cr4z0r**.

Questlogger extends the existing quest interface with chain progress, XP summaries,
reward previews, and controls for managing tracked quests.

## Features

- Quest-chain position, current quest XP, and remaining chain XP.
- A green preview of completed, unturned-in quest XP on the native experience bar, followed by rested XP.
- Follow-up quests, prerequisite information, and dungeon or raid indicators.
- Reward cards with items, spells, currencies, money, and reputation where available.
- Quest giver, turn-in, and objective locations, with NPC or object previews and map waypoints.
- Controls to collapse or expand regions and quests, and track or untrack quests in bulk.
- Native tracker scrolling, movement, and resizing, with optional Questie integration.
- An account-wide targeting macro for selected quest objectives.
- A portable quest window, opened with `/questlogger` (or `/ql` when that alias is free), for all targeted clients.

## Requirements

- One of the current official WoW clients listed in the compatibility table below.
- On Classic and Forever, optional [QuestieDB](https://github.com/Questie/QuestieDB) data for
  chain, location, and objective information.

QuestieDB is a soft dependency: Questlogger can load without it and still display
available native quest information, such as current quest XP. Missing or incomplete
database information is shown as unavailable. QuestieDB does not provide a Retail
database; Retail uses native quest details and rewards. The full
[Questie addon](https://github.com/Questie/Questie) is optional.

## Languages

The interface automatically follows the WoW client's language:

| Locale | Language |
| --- | --- |
| `enUS` | English |
| `deDE` | German |
| `frFR` | French |
| `esES` | Spanish (Spain) |
| `esMX` | Spanish (Latin America) |
| `itIT` | Italian |
| `ptBR` | Portuguese (Brazil) |
| `ruRU` | Russian |
| `koKR` | Korean |
| `zhCN` | Simplified Chinese |
| `zhTW` | Traditional Chinese |

British English uses the English catalog; `enGB` and `ptPT` aliases resolve to `enUS`
and `ptBR`. Labels, cards, help, warnings, and addon-list descriptions are translated.
Numbers use the client's formatting, and fonts come from the client so Cyrillic and
CJK text retain the required glyphs. Missing addon translations safely fall back to English.

Quest and entity names come from the game or QuestieDB, whose translation coverage is
separate from the addon interface. In particular,
[QuestieDB's built-in entity translations do not include Italian](https://github.com/Questie/QuestieDB/blob/master/docs/api.md#localization).
Accepted quest titles and cached item names prefer native client information. If an NPC
name cannot be verified in the client language, Questlogger keeps the macro unchanged
and explains how to target or mouse over the NPC to learn its localized name. Game-object
macros still clear the target as usual. Questlogger does not change QuestieDB's shared locale.

## Installation

1. Download the project and extract it.
2. Rename the extracted addon folder to exactly `Questlogger`.
3. Place it inside your chosen client's `Interface/AddOns/` directory. Install a copy
   into each client you play; the same addon folder is used for every edition.
4. On Classic or Forever, install and enable a matching QuestieDB version for the
   database-backed features.
5. Enable Questlogger in the character selection screen's AddOns list, then log in.
   If you updated files while playing, restart the client to refresh addon metadata.

The final layout must look like this, without an extra nested project folder:

```text
Interface/AddOns/Questlogger/
    Questlogger.toc
    Assets/
    Core/
    Data/
    UI/
```

## Usage

- Open the quest log and hover a quest or tracker entry for its detail card.
- Hover a quest marker on the world map to show its card. On the windowed map,
  the card appears beside the quest-log list; on the fullscreen map, it appears
  at the right edge of the screen.
- Type `/questlogger` or `/ql` to open the portable quest window. Hover its quest rows
  for the same cards, or use its buttons to change tracking and region expansion.
  This window provides access when the client's native quest log has a different layout.
  If another addon uses `/ql`, use the full `/questlogger` command.
- Use the quest-log and tracker buttons to expand, collapse, or change quest tracking.
  On modern clients, bulk tracking applies across the log, including collapsed regions
  and search results. On legacy quest logs, expand region headers first to include their quests.
- Shift-click a tracked quest, profession recipe, or achievement entry to untrack it.
- Use location links in a quest card to open the map or place a waypoint where supported.
- Click a blue objective or endpoint target to create or update the general macro named
  `Questlogger`. Open WoW's macro window with `/macro` and drag the macro onto your action bar.
  NPC targets use `/targetexact`; object targets cannot be targeted in the same way.
  The chat confirmation shows only the target name: `Questlogger - Target macro: 'Name'`.
- Hold Shift to drag empty space in the native tracker or resize its edges. Its custom
  position and size last for the current session.

Questlogger has no separate settings panel. Actions that
the client restricts during combat are disabled until combat ends.

### Completed quest XP on the experience bar

The native experience bar shows current XP first, then a green segment for the combined
XP rewards of accepted quests that are ready to turn in. Rested XP is displayed after
the green segment. Untracked quests and quests under collapsed quest-log headers are included.
The selected quest and the header states are restored after legacy-client scans.

This is a preview: quests grant their actual XP only when turned in, and quest rewards
do not consume or multiply the rested bonus. Both preview segments are clipped at the
end of the current level's bar; hover the bar to see the full completed-quest XP total.
Unknown rewards and database estimates are identified in the tooltip.
The native rested label includes the stored bonus as a percentage of one level,
for example `Rested (37.5%)`, in the label's own color. Percentages follow the client
language and can exceed 100% when the stored bonus spans more than one level.

The display refreshes when quests, player XP, level, or rested XP change. It hides when
the native XP bar is unavailable, XP gain is disabled, or the player is at the level cap.
During combat it uses the last safe quest total until the quest log can be read again.
Third-party replacement XP bars require their own integration.

## Compatibility and limitations

Compatibility targets, with live interface metadata checked on November 19, 2026:

| Client | Interface | Quest information |
| --- | --- | --- |
| [Retail (12.1.5)](https://github.com/Gethe/wow-ui-source/blob/live/version.txt) | `120105` | Native quest details and rewards |
| [Classic Era, Hardcore, and seasonal realms (1.15.9)](https://github.com/Gethe/wow-ui-source/blob/classic_era/version.txt) | `11509` | Native details; optional QuestieDB data |
| [Burning Crusade Classic Anniversary (2.5.6)](https://github.com/Gethe/wow-ui-source/blob/classic_anniversary/version.txt) | `20506` | Native details; optional QuestieDB data |
| [Wrath Classic Titan Reforged, regional client (3.80.2)](https://github.com/Gethe/wow-ui-source/blob/classic_titan/version.txt) | `38002` | Native details; optional QuestieDB data |
| [Mists of Pandaria Classic (5.5.4)](https://github.com/Gethe/wow-ui-source/blob/classic/version.txt) | `50504` | Native details; optional QuestieDB data |
| [Forever (1.60.1)](https://github.com/Gethe/wow-ui-source/blob/forever/version.txt) | `16001` | Native details; optional QuestieDB data |

Client APIs are selected by capability, including modern quest-ID APIs and older
quest-log-index or selected-quest APIs. The portable quest window is available on
every target; native log and tracker enhancements activate where the expected frames
exist. These paths are checked with mocks; live validation in every client is still needed.

- Full feature parity depends on the client's UI and available quest data. Chain,
  future-quest, NPC, and location information require a matching database.
- Legacy reward APIs need accepted quests in expanded regions. Questlogger preserves the selected
  quest when using those APIs; unavailable future rewards remain unknown.
- Map waypoints require client support. Opening a known map remains separate from
  placing a waypoint, and unsupported actions are explained in the card.
- Chain accuracy depends on QuestieDB coverage. Branching, parallel prerequisites,
  or missing data can produce ranges or unknown values.
- Database-derived XP and reputation values may be estimates; live quest rewards
  are used when the client exposes them.
- Questlogger prefers Blizzard's tracker when a supported Questie version is present.
  This can disable Questie's tracker setting. Older versions may use the Questie
  tracker adapter instead. You can restore your preference in Questie's settings
  after disabling Questlogger.
- Other addons that change the same quest-log or tracker frames may affect the layout.

## Privacy and saved state

Questlogger contains no telemetry or external reporting code. It reads quest data
and relevant character information, such as race, class, and level, through game APIs.
It does not declare its own `SavedVariables` database.

The targeting macro is saved by WoW and remains after the addon is disabled or removed.
Tracking and waypoint actions use the game's own systems, and Questie integration can
update Questie's saved tracker, collapse, and tracking preferences. Remove the macro
manually or restore those settings if desired.

Use GitHub issues for support. Remove character names, realm names, account information,
and other personal details from screenshots and error reports before posting them.

## Development

- `Core/`: quest-chain calculations and event handling.
- `Locales/`: translations for the ten non-English client locales.
- `Data/`: game API wrappers, database access, rewards, locations, and targets.
- `UI/`: quest rows, cards, previews, controls, and tracker integration.
- `Assets/`: addon textures.
- `tests/`: existing Lua checks with mocked game APIs.

Modules share WoW's private addon table through `...`; `Questlogger.toc` defines their
load order. The main responsibilities are:

| Concern | Modules |
| --- | --- |
| Client-language selection, English fallback, and number formatting | `Core/Locale.lua`, `Locales/` |
| Client API differences, safe event registration, and legacy quest selection | `Core/Compat.lua` |
| Quest graph, route traversal, and XP summaries | `Core/Chains.lua` |
| Safe client/database access, locations, rewards, and target macros | `Data/` |
| Completed-quest XP totals, full quest-log scans, and change detection | `Data/Experience.lua`, `Core/Compat.lua` |
| Reward icons, row layout, and shared popup styling | `UI/RewardIcons.lua`, `UI/QuestRows.lua`, `UI/TooltipStyle.lua` |
| Native quest text and database text fallbacks | `UI/QuestText.lua` |
| Card layout, interaction, and entity previews | `UI/QuestCard.lua`, `UI/EntityPreview.lua` |
| World-map quest marker hover and map card placement | `UI/MapQuestCards.lua`, `UI/QuestCard.lua` |
| Quest-log expansion and tracking controls | `UI/BulkControls.lua` |
| Native and Questie tracker integration | `UI/Trackers.lua` |
| Session-only tracker movement, resizing, and Edit Mode restoration | `UI/TrackerGeometry.lua` |
| Portable quest window and legacy quest-log hover hooks | `UI/ClientQuestLog.lua` |
| Green quest-XP preview and shifted rested-XP display | `UI/ExperienceBar.lua` |
| Summary caching, asynchronous graph loading, and live event hooks | `Core/Main.lua` |

Load `Core/Locale.lua` and the locale files before other modules cache display labels.
Load `Core/Compat.lua` before the data modules, then `Data/Api.lua` before the other data modules and
`UI/RewardIcons.lua` before the other UI modules: these create the shared namespaces. `QuestText.lua` must precede
`QuestCard.lua`, and `TrackerGeometry.lua` must precede `Trackers.lua`. Keep
`Core/Main.lua` last so event handlers see fully initialized modules.

There is no build step. Run the existing checks from the project root using a
standalone Lua interpreter with `table.unpack` support (Lua 5.2 or later):

```sh
lua tests/smoke.lua
lua tests/dependencies.lua
lua tests/targets.lua
lua tests/controls.lua
lua tests/ui.lua
lua tests/trackers.lua
```

These checks use mock APIs. Validate changes in the affected clients as well, including
login, quest-log cards, tracking, combat transitions, and optional Questie integration.
Check longer translated labels and Cyrillic/CJK fonts in the relevant client languages.
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidance and
[CHANGELOG.md](CHANGELOG.md) for release notes.

## Addon metadata

`Questlogger.toc` declares the client interface, display title, author, addon version,
description, optional dependencies, category, icon, license identifier, and Lua load order.
The initial addon version is `0.1.0`.

The shared TOC lists all targeted interface values. Version references come from
[WoW UI source client branches](https://github.com/Gethe/wow-ui-source/branches),
[Questie's client manifests](https://github.com/Questie/Questie), and
[APR's Retail/Forever manifest](https://github.com/Azeroth-Pilot-Reloaded/azeroth-pilot-reloaded/blob/main/APR.toc).
QuestieDB's supported database flavors are listed in its
[client configuration](https://github.com/Questie/QuestieDB/blob/master/src/config.lua).
To check your installed client's value, run `/dump select(4, GetBuildInfo())` in game.
Update the TOC when supporting a different client interface, after checking compatibility.

## Author, license, and acknowledgments

Created by **cr4z0r**. No email address or other personal contact information is
required to use or contribute to this project.

Original Questlogger code and project content are licensed under the [MIT License](LICENSE).
Questie and QuestieDB are separate projects with their own licenses. Game-provided
fonts, icons, and other World of Warcraft assets remain subject to their owners' terms.

Thanks to the Questie and QuestieDB contributors for the database and integration APIs.
World of Warcraft and Blizzard Entertainment are trademarks of their respective owners.
Questlogger is an independent community addon and is not affiliated with Blizzard Entertainment.
