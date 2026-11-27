# Quest Rep Forecast

Preview turn-ins and track session reputation gains on WoW Forever’s default reputation bar. In the character window’s **Reputation** tab, select a faction and enable **Show as Experience Bar**.

- Bright gold shows estimated rep from quests ready to turn in.
- Teal shows estimated rep from complete item turn-ins you can make with the items in your bags.
- Muted gold shows estimated rep from quests in progress.
- Hover over the bar for the totals and the rep still needed to reach the next standing.
- The tooltip also shows **Session rep per hour**, **Avg rep per kill**, and **Time to next standing** at your current session rate. The hourly rate includes standing gains from all sources while watching that faction. The kill average uses up to 20 recent reputation-awarding kills the client lets the addon match, from the last 20 minutes. Session stats reset on login or `/reload`.
- Enable **Tracked quests only** to limit the quest totals to quests on your objective tracker. Bag turn-ins remain available.
- Enable **Always show rep bar text** to keep the totals and session rep per hour visible. The rate updates when you gain reputation and every 30 seconds out of combat.
- Set each fill’s color and opacity and the font size in **Options > AddOns > Quest Rep Forecast**. Use `/qrfconfig` to reopen first-time setup. During combat, the setup window opens when combat ends.

The preview follows your watched faction and includes your active Legacy **Diplomat** bonus through Questie. It skips cloth hand-ins, counts carried bags, and reserves items for quests already in the forecast. The bar preview ends at the next standing. Questie must be enabled.

Bag turn-ins are estimated from item quantities in [Polestar forever-db 2026.11.2](https://github.com/fitzforge/polestar/releases/tag/data-v2026.11.2), checked against Questie for reward amounts and availability. Coverage depends on both datasets. If several turn-ins use the same stack, the forecast allocates the items toward higher reputation per item first.

## Installation

Install [Questie](https://www.curseforge.com/wow/addons/questie), then download the ZIP from [GitHub Releases](https://github.com/iltGames/QuestRepForecast/releases) and extract `ForeverQuestRep` into `_forever_/Interface/AddOns`.

## License

GNU General Public License v3. See [LICENSE](LICENSE) and [data and code notices](NOTICE.md).
