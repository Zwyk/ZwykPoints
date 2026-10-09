# ZwykValues 0.1.17

A standalone stat-weight addon written from scratch for WoW Forever. No Pawn code, Pawn dependency, third-party libraries, or online item database is required.

## Installation

1. Close WoW or return to the character selection screen.
2. Extract the `ZwykValues` folder into the Forever client's `Interface/AddOns` folder. The resulting path must be `Interface/AddOns/ZwykValues/ZwykValues.toc`.
3. Enable **ZwykValues** in the AddOns list. If the current beta lists it as out of date, enable **Load out of date AddOns**.
4. Log in and type `/zv`, or click the small **ZV** button beneath the bottom trinket slot on your character sheet.

For a GitHub download, choose **Code → Download ZIP** in the repository, extract it, rename the unpacked repository folder (for example, `ZwykValues-main`) to `ZwykValues`, and copy that folder into `Interface/AddOns`.

The manifest targets interface `16001`, as reported by the Forever 1.60.1 client in the supplied diagnostics. The active interface number can be checked with `/dump select(4, GetBuildInfo())` if a later client lists the addon as out of date.

### Upgrading from ZwykPoints or ForeverWeights

Before removing the old addon folder, export each profile with **Export profile** from ZwykPoints (`/zwykpoints`) or ForeverWeights (`/fw`). Install ZwykValues, open `/zv`, and import those exports. Legacy `ZwykPoints` and `ForeverWeights` profile JSON and bare Sixty Upgrades weights remain accepted; new profile exports identify their format as `ZwykValues`.

WoW stores each addon's SavedVariables in a file named after that addon, so renaming the folder does not automatically load the old saved profiles. If `ZwykPointsDB` is already loaded when ZwykValues first initializes, ZwykValues copies its profiles, options, and compatible cache into an independent database. Otherwise it can copy a loaded `ForeverWeightsDB`. Existing `ZwykValuesDB` data always takes precedence. Export/import is the reliable migration path when the old folder is removed or disabled. After migration, keep only ZwykValues enabled to avoid duplicate tooltip scores. ZwykValues registers only `/zv` and `/zwykvalues`, leaving `/zp` available for ZwykPlus.

## Profiles

Create, copy, rename, or delete profiles in the left column. Set an individual tooltip color and toggle **Active** for every profile you want shown. Multiple profiles can be active together. Click the color square to open the native color picker; selecting a color saves it for that profile, and **Cancel** restores its original color. The hexadecimal field and **Set color** remain available.

Edit weights in the grouped stat editor and apply them. Positive, zero, negative, and fractional weights are supported. The initial **My profile** is empty: it contains no invented class or specialization weights.

Each score is a linear sum:

`score = sum(item_stat_amount * profile_stat_weight)`

For example, 20 Strength at weight 2 and 1% Crit at weight 10 give 50 points in a percentage profile. Stamina is not converted to health, Strength is not converted to attack power, and Agility is not converted to crit: enter weights that already account for their value for your character.

Profiles are account-wide, including their active status, colors and item filters. All changes and the score cache are stored by WoW in the addon's `SavedVariables` on logout or `/reload`.

Click **Item filters** in a profile to choose its weapon and armor types independently. The scrollable dialog provides a checkbox for each supported client subtype, including shields, class relics and miscellaneous armor/accessories. All types start checked for both new and existing profiles. Changes save immediately and apply to the profile's full/base tooltip values and its main-profile upgrade arrows.

Uncheck **Include items restricted to other classes** to exclude items whose explicit **Classes** restriction does not include your current character's class. An item allowing several classes remains included when yours is among them. This setting uses the current character, so a shared profile adapts when you log into another class. If required type or restriction metadata cannot be read, values wait for that data rather than assuming eligibility. Unchecked candidate items show no values for that profile; equipped comparison baselines still retain their complete score.

Copies and full profile exports preserve these choices. Bare weights JSON and older profiles without item filters start with every filter enabled.

## Stat units and JSON

The supplied Sixty Upgrades keys are preserved. **Import** accepts a bare JSON object of stat weights. Missing recognized keys become zero. Unknown keys and invalid numeric values are rejected with a message so typos cannot silently change a profile.

**Export weights** produces the bare stat object. **Export profile** also preserves the profile name, color, secondary-stat unit and item filters. These metadata are lost when exporting only bare weights.

Choose the unit explicitly:

| Key or group | Default percentage profile | Rating profile |
| --- | --- | --- |
| `hit`, `crit`, `haste`, `expertise`, `dodge`, `parry`, `block` | Weight per percentage point; 1% means an amount of 1 | Weight per native rating point reported by the client |
| `defense` | Weight per defense skill point, when explicitly available | Weight per native defense rating point |
| Primary stats, AP, spell/healing power, armor, resistances, health | Weight per stat point | Same |
| `hp5`, `mp5` | Weight per regeneration point per 5 seconds | Same |
| `dps`, `rangedDps` | Weight per damage per second | Same |
| `lowDamage`, `highDamage` | Weight per minimum/maximum weapon damage | Same |
| `weaponDamage` | Weight per explicitly added flat weapon damage | Same |
| `speed`, `rangedSpeed` | Weight per weapon swing second | Same |

Merged melee/ranged/spell hit and crit aliases are counted once. The reader prefers explicit tooltip percentages for percentage profiles and keeps native API rating values separately. It does not apply an assumed rating conversion. If a needed stat or secondary-stat unit is unavailable, the item still shows the subtotal from known values, accompanied by a partial-data warning. Unavailable amounts contribute zero to that subtotal; an actually absent stat also contributes zero. Check the diagnostics before trusting a partial comparison.

The editor labels each secondary weight with its selected unit. A crit weight of 10 means **10 points per 1%** in Percent mode, but **10 points per 1 rating** in Rating mode. For Manascale Treads, 157 armor at 0.05, 7 Strength at 0.2 and 7 Intellect at 0.3 contribute 11.35. Its 0.5% crit contributes 5 in Percent mode (total 16.35); with 7 native crit rating, Rating mode contributes 70 (total 81.35). Changing the unit keeps your numeric weights and recalculates scores; choose the unit those weights were intended to use.

Version 0.1.17 also fixes static wording such as `chance to critically hit with spells`: it counts as critical strike chance and does not add hit chance. Previously parsed item records refresh automatically.

`weaponDamage` is the explicit flat bonus (for example, `+1 Weapon Damage`), not the weapon's average base damage. To value average base damage, use half of the intended average-damage weight for both `lowDamage` and `highDamage`. JSON key compatibility is preserved, but all Sixty Upgrades field semantics have not been independently verified; check the units above when importing existing profiles.

Separate healing/damage effects and compound static enchant lines (for example, `Enchanted: Stamina +2 and Armor +16`) are recognized. Known enchant bonuses are included once; API base stats and the same tooltip stats are not added together.

English and French static tooltip text are supported, with localized Blizzard formats used where available. Other locales can still expose API stats, but unrecognized tooltip-only values need further validation.

Version 0.1.16 reads elemental wand damage ranges and the client's school-damage API aliases. `Your spells pierce N Magical Resistance` contributes to spell penetration. Separate signed Armor lines are bonus armor: Tortoise Armor's `208 Armor` and `+40 Armor` become 208 base armor and 40 bonus armor, counted once. Explicit damage-received reduction and profession skill bonuses are recorded as ignored diagnostics because they have no matching weight in the current stat schema; they do not create an offensive spell-damage value or a partial-data warning.

## Tooltip comparisons

Values use a positive allowlist: supported weapon and armor subtypes in their character equipment slots, plus ammunition in the ammo slot. This includes jewelry, shields/offhands, relics, shirts and tabards. A weapon or armor candidate must have its subtype checked in that profile. Unknown numeric subtypes are excluded; missing class/subtype metadata waits for loading rather than assuming eligibility. Full and instant item-info APIs supply the classification. Equipped baselines bypass profile checkboxes while still requiring supported gear.

Version 0.1.14 applies this classification before reading stat APIs or scanning tooltips. Unchecked candidate types also stop before parsing, without saving an empty record that could affect another profile. Only actual item hyperlinks enter tooltip decoration: recipe, enchant, spell and trade links are skipped, including blacksmithing recipe tooltips. Consumables, quest items, crafting materials, bags/quivers, profession equipment and other non-gear items receive no full/Base values, comparisons, upgrade arrows or stat-debug markers, even if an older cache contains a score.

Ammunition's added damage per second uses the existing **Ranged weapon DPS** weight (`rangedDps`). For example, 7.5 ammo DPS at weight 2 gives 15 points. Ammo compares with the equipped ammunition slot; full/Base values and main-profile upgrade arrows use the same score. Weapon and armor subtype checkboxes do not exclude ammo. Ammunition does not require weapon speed or a damage range, and unreadable DPS remains partial rather than becoming a cached zero.

Every active profile adds one row with its name and score in the profile color. Candidate items show the signed point difference and percentage difference inline, with only the comparison fragment colored green for an increase, red for a decrease, or gray for equality:

`Mageladin    2.56  ↑+1.52 (+146.2%)`

A smaller, indented **Base** subline appears only when its displayed score or any equipped comparison differs from that profile's main row. Identical values are hidden, including differences too small to change the rounded display. It scores the same item without its enchant and compares it against the equipped items with their enchants removed too, so an equipped enchant can make Base relevant even on an unenchanted candidate. The client supplies the unenchanted stats directly; the addon does not subtract guessed enchant bonuses. Intrinsic item variants, including random-suffix stats, remain part of the base value. Equipped and shopping tooltips show the base score alone when it differs. Base loading/errors remain visible when they add different information, and partial-data warnings are retained even when a duplicate numeric row is hidden. The full score above still includes recognized enchants.

A smaller **Average use** subline adds the average gain from readable on-use stat buffs to the unenchanted Base value. Each effect contributes `stat amount × duration / cooldown`, using seconds for both times and limiting uptime to 100%. For example, 120 spell power for 10 seconds on a 2-minute cooldown contributes 10 average spell power; the profile's spell-damage and healing weights determine its value. Each equipped comparison uses its own Base plus average-use value too. The subline appears only when its rounded score or comparisons differ from Base, including a passive candidate compared with an equipped on-use item.

This estimate assumes using the item as soon as its cooldown ends. It needs an explicit flat stat amount, buff duration and total cooldown in the tooltip. It does not use the remaining cooldown, guess rating conversions, or model encounter length, delayed uses, shared trinket cooldowns, stacking, decreasing bonuses, proc chance or direct damage/healing abilities. Unsupported effects or an unavailable weighted secondary-stat unit show **Average use: unavailable** while retaining the ordinary scores. Main-profile bag, roll and chat arrows continue to use the full static score.

Version 0.1.8 accepts Forever's named item-quality colors (`|cnIQ2:`) as well as hexadecimal link colors, fixing **Base: Invalid item link** for those links. Both candidate and equipped item links retain their complete variant data when removing the enchant.

The up/down indicators use packaged arrow textures so they display even when the tooltip font has no Unicode arrow glyphs. Equality uses `=`. Two spaces separate the score from the first comparison. Multiple replacement choices share the same row, in equipped slot order:

`Mageladin    2.56  ↑+1.52 (+146.2%) | =0.00 (+0.0%)`

Percentages use:

`percentage = (candidate_score - equipped_score) / equipped_score * 100`

Rings and trinkets show both replacement choices. A two-handed weapon is compared to the combined equipped main-hand and off-hand score. Generic one-handed weapons show an off-hand comparison only when dual wielding is available and the equipped main hand is compatible. A shield/off-hand item does not receive a misleading comparison against a two-handed main hand.

An empty slot has score zero; a zero or negative baseline displays **percentage n/a** unless the scores are equal, which displays `=0.00 (+0.0%)`. Equipped and native shopping tooltips show their own item scores without recursively repeating candidate comparisons. Comparisons involving a partial candidate or equipped baseline display a warning because the missing stats could change the result. The addon evaluates item stats, not whether your class can equip every item you inspect.

## Optional upgrade arrows

In `/zv`, select a profile and check **Main for upgrade arrows** in the left-hand **Upgrade arrows** panel. Exactly one profile can be main. Choosing another replaces it; clearing the checkbox or deleting that profile leaves no main. Its tooltip **Active** setting is independent. Main selection and location toggles are saved account-wide.

Enable any of the three locations separately (all are off initially):

- **In bags**: a green arrow at the upper-left corner of native carried-bag item icons, including combined bags.
- **Loot rolls**: a green arrow on the item icon in native loot-roll windows.
- **Chat item links**: an arrow immediately after item links in newly received chat messages.

An arrow means the item scores higher than an equipped replacement under the main profile. Rings/trinkets need to beat at least one equipped slot; two-handed weapons use the combined main/off-hand score. Comparisons wait for main-hand compatibility where needed. Parsing or stat-unit issues suppress the affected upgrade decision, while tooltips retain their known subtotal and diagnostic warning.

Bag/roll arrows refresh after item data loads, equipment changes (including enchants), bag changes, and profile/option edits. They clear when an icon is reused or a roll ends. Chat arrows are a snapshot when each message arrives: an uncached item link requests data and stays unmarked in that message; later messages can show its arrow once the data is available. Existing chat history is retained as originally displayed.

Version 0.1.13 fixes repeated hover work: only item-data completions the addon is waiting for invalidate comparisons and refresh icons; unrelated, duplicate and failed notifications do not redraw all bags. A refresh checks each icon once. Partial reads and subtotals share a bounded, unsaved one-second cache across profiles, Full/Base rows and equipped comparisons, and temporary loading decisions retry after expiry. Completed requests, equipment/enchant changes and cache clearing invalidate those reads immediately. Definitive exclusions reuse a false upgrade decision. Automatic metadata retries are throttled; explicit diagnostic refreshes remain available. These caches reduce repeated scans without turning incomplete data into permanently saved scores.

Native Blizzard bags and loot-roll windows are supported. BetterBags 0.5.14 is also supported automatically, including its bank and list-row item icons; it uses the same **Bags** checkbox and main profile, with no additional provider selection. Its arrows update when equipment, profiles or item data change, and clear when a slot is reused. Empty slots and item-browser previews are excluded.

Other third-party bag addons can integrate their buttons explicitly with `ZwykValues:RegisterUpgradeItemButton(button, linkProvider)` and re-register after their own slot updates; `linkProvider(button)` must return the current full item link or nil.

After upgrading to 0.1.17, parser-versioned cache keys automatically refresh item stats, classification and on-use metadata. The report's top-level addon version identifies the exporter; each entry's `parserVersion` and `lastSeen` identify when that issue was collected. Issue exports intentionally preserve historical problems. To collect a fresh report, run `/zv clearissues`, then `/zv clearcache`, hover the affected items again, and run `/zv exportissues`.

## Debugging unrecognized stats

Enable **Mark unrecognized stats in tooltips** in the editor. Static stat lines that the parser cannot recognize receive an orange `[ZV ?]` marker next to their text. This also works with no active profiles. It is off by default and does not change weights or item scores.

The inline marker identifies a specific unrecognized line. A partial-data notice covers all detected issues, including unknown API fields, missing tooltip data and unavailable stat units, which may have no identifiable line to mark. Both indicators can appear for the same item. The partial-data notice is shown once per tooltip, and calculated known values remain visible.

Use **Export issues** in the editor or `/zv exportissues` to copy one JSON report for every encountered item variant with issues. It includes raw client stats, original tooltip lines, parsed stats, warnings and profile-specific score issues. Collection runs even when inline debug markers are disabled. The issue history is separate from the score cache, survives `/reload` and logout, and is retained until `/zv clearissues`; clearing the score cache does not erase it. Repeated reads update a variant's diagnostic entry rather than adding duplicate items. This reports items encountered by the addon, rather than scanning the entire item database.

Diagnostics include those lines, raw client stat keys, and parser warnings. Item descriptions, requirements, use effects, and set/proc descriptions are not marked as missing static stats. The detection is deliberately limited to stat-looking lines; it cannot identify every possible novel tooltip wording before that wording has been observed.

## Persistent cache

Parsed stats and profile scores are stored locally. Cache keys include the full item payload, so suffixes, enchants, gems, and other variants do not collapse to one item ID; build, locale, and character level provide additional separation. Repeated tooltips and equipped comparisons reuse stored totals.

Editing weights or units increments the profile revision and invalidates its scores. Color/name/active changes update display without changing stat values. The item cache is bounded to 2,000 variants. Missing or incomplete item data are not permanently cached as a zero-stat item. Equipment changes update comparisons; level/build/parser changes invalidate incompatible data.

| Command | Action |
| --- | --- |
| `/zv` or `/zwykvalues` | Open or close the profile editor |
| `/zv cache` | Show item and score cache counts |
| `/zv clearcache` | Clear parsed stats and scores |
| `/zv inspect` | Open diagnostics for a hovered item, or the main-hand item |
| `/zv inspect <item link>` | Open diagnostics for a pasted item link |
| `/zv exportissues` | Copy diagnostics for all encountered item variants with issues |
| `/zv clearissues` | Reset the recorded issue history without changing profiles or score caches |
| `/zv help` | Show commands |

## Scope and validation

This release evaluates static item stats and separately estimates the average of supported on-use stat buffs. It does not model procs, set bonuses, stat caps, talent interactions, DPS rotations, class equipment restrictions, or future equipment combinations. Spell-power or attack-power weights should already include their expected value for your build. A higher score is a stat-weight estimate, not a simulated DPS percentage.

The Lua scoring, JSON, cache, parser, comparison, issue export, and tooltip/event logic are covered by mocked API tests included in `tests`. There is no running WoW client in this environment, so the actual UI rendering, the current Forever beta stat vocabulary, and secure tooltip behavior require an in-game check. Use `/zv inspect` for one item or `/zv exportissues` for all recorded issues.

Run the included tests from the addon directory with a Lua interpreter, for example:

```sh
lua tests/test_core.lua
lua tests/test_items.lua
lua tests/test_compare.lua
lua tests/test_base.lua
lua tests/test_on_use_items.lua
lua tests/test_on_use.lua
lua tests/test_report_stats.lua
lua tests/test_report_armor.lua
lua tests/test_weapon_schools.lua
lua tests/test_filters.lua
lua tests/test_item_metadata.lua
lua tests/test_tooltips.lua
lua tests/test_bootstrap.lua
lua tests/test_integration.lua
lua tests/test_ui.lua
lua tests/test_upgrades.lua
lua tests/test_indicators.lua
lua tests/test_betterbags.lua
lua tests/test_hover_performance.lua
```

`luatex --luaonly` can also run the tests when a standalone Lua executable is unavailable. Production modules use Lua 5.1-compatible syntax.

## Files

- `JSON.lua`: strict JSON reader/writer; no executable imports.
- `Stats.lua`: stat schema and native API mappings.
- `Core.lua`: profile management, import/export, scoring, and score-cache invalidation.
- `Items.lua`: item variants, client data loading, normalization, static tooltip parsing and timed on-use stat buffs.
- `Compare.lua`: equipped slot comparisons.
- `Upgrades.lua`: main-profile upgrade decisions and local chat-link decoration.
- `Indicators.lua`: native bag/loot-roll overlays and refresh hooks.
- `Tooltips.lua`: native tooltip hooks and refresh handling.
- `Textures/ArrowUp.tga` and `Textures/ArrowDown.tga`: tooltip comparison indicators.
- `UI.lua`: profile and weight editor.
- `Bootstrap.lua`: saved variables lifecycle, events, diagnostics, and slash commands.

## License

MIT. See `LICENSE`.
