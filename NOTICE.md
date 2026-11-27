# Quest Rep Forecast notices

Quest Rep Forecast is distributed under the GNU General Public License, version 3. See [LICENSE](LICENSE).

The setup interface adapts Quest XP Forecast by iltGames. Its original MIT notice is included in [LICENSE-QuestXPForecast.txt](LICENSE-QuestXPForecast.txt).

`TurnInData.lua` is an adapted subset of the [Polestar forever-db 2026.11.2 release](https://github.com/fitzforge/polestar/releases/tag/data-v2026.11.2). On November 26, 2026, Quest Rep Forecast extracted quest and faction IDs, minimum levels, repeatability flags, and item IDs and counts for quests with item-only objectives and positive reputation rewards. It also extracted quest IDs for cloth exclusions. The result omits the original quest text and reward amounts. The original credits and notices are included in [Polestar-NOTICE.md](Polestar-NOTICE.md).

To regenerate, download `forever-db-2026.11.2.sqlite.zst` from the source release and run `node scripts/Generate-TurnInData.mjs path/to/forever-db-2026.11.2.sqlite.zst` with Node.js 24 or later. The script checks the database checksum before reading it.

World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. Quest Rep Forecast is an independent addon.
