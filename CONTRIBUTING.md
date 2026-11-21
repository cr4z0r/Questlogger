# Contributing to Questlogger

Bug reports, feature suggestions, and focused pull requests are welcome.

## Reporting an issue

Open a GitHub issue and include:

- The Questlogger version, client edition, and client version/interface number.
- QuestieDB and Questie versions, if installed.
- Steps to reproduce the problem, including the quest ID when relevant.
- What you expected and what actually happened.
- The Lua error text or a screenshot, if useful.

Remove account details, character names, realm names, and other personal information
from reports and screenshots. Do not upload your `WTF` folder or complete saved variables.

## Making changes

1. Keep the change focused and preserve the surrounding Lua style and file organization.
2. Keep addon files listed in `Questlogger.toc` in their required load order.
3. Preserve graceful behavior when QuestieDB is missing or its data is incomplete.
4. Run the existing Lua checks listed in the README when an interpreter is available.
5. Check the affected behavior in each relevant WoW client, including combat restrictions
   and relevant Questie integrations. For interface changes, include a screenshot.
6. Describe the behavior change and the validation performed in the pull request.

Use descriptive local names and small helpers for separate responsibilities. Comments
should explain client restrictions, ownership, lifecycle, or algorithm choices rather
than repeat the code. Preserve nil/false distinctions, multi-value API results,
secret-value guards, pooled-frame cleanup, and macro ownership checks when refactoring.
Keep client API differences in `Core/Compat.lua`; avoid replacing Blizzard's globals.
When a feature depends on a particular UI layout or database, keep the portable quest
window usable and describe the limitation in the README.

## Translating text

Keep complete English phrases as `addon.L` keys, and use `L.Format` for dynamic text.
Add each new phrase to all ten files in `Locales/`, preserving the order and type of
format placeholders. Keep files UTF-8, and use client font objects for rendered text.
Do not translate API identifiers, slash commands, macro commands, or macro ownership markers.

Prefer localized game information for quest and entity names. Do not change QuestieDB's
shared locale to translate one lookup. Keep missing-name safeguards in targeting actions.

Do not include local game state, credentials, generated archives, or unrelated changes.
Add a short entry under `Unreleased` in [CHANGELOG.md](CHANGELOG.md) for user-visible changes.

Contribute only material you have permission to share. Contributions to original
Questlogger content are made under the project's [MIT License](LICENSE).
