# ZwykValues 0.1.2

A standalone stat-weight addon written from scratch for WoW Forever. No Pawn code, Pawn dependency, third-party libraries, or online item database is required.

## Installation

1. Close WoW or return to the character selection screen.
2. Extract the `ZwykValues` folder into the Forever client's `Interface/AddOns` folder. The resulting path must be `Interface/AddOns/ZwykValues/ZwykValues.toc`.
3. Enable **ZwykValues** in the AddOns list. If the current beta lists it as out of date, enable **Load out of date AddOns**.
4. Log in and type `/zv`.

For a GitHub download, choose **Code → Download ZIP** in the repository, extract it, rename the unpacked repository folder (for example, `ZwykPoints-main`) to `ZwykValues`, and copy that folder into `Interface/AddOns`.

The manifest targets interface `16000` (the 1.60 client family). This has not been confirmed against a running Forever client here. The active interface number can be checked with `/dump select(4, GetBuildInfo())` and substituted into the TOC if necessary.

### Upgrading from ZwykPoints or ForeverWeights

Before removing the old addon folder, export each profile with **Export profile** from ZwykPoints (`/zwykpoints`) or ForeverWeights (`/fw`). Install ZwykValues, open `/zv`, and import those exports. Legacy `ZwykPoints` and `ForeverWeights` profile JSON and bare Sixty Upgrades weights remain accepted; new profile exports identify their format as `ZwykValues`.

WoW stores each addon's SavedVariables in a file named after that addon, so renaming the folder does not automatically load the old saved profiles. If `ZwykPointsDB` is already loaded when ZwykValues first initializes, ZwykValues copies its profiles, options, and compatible cache into an independent database. Otherwise it can copy a loaded `ForeverWeightsDB`. Existing `ZwykValuesDB` data always takes precedence. Export/import is the reliable migration path when the old folder is removed or disabled. After migration, keep only ZwykValues enabled to avoid duplicate tooltip scores. ZwykValues registers only `/zv` and `/zwykvalues`, leaving `/zp` available for ZwykPlus.

## Profiles

Create, copy, rename, or delete profiles in the left column. Set an individual tooltip color and toggle **Active** for every profile you want shown. Multiple profiles can be active together.

Edit weights in the grouped stat editor and apply them. Positive, zero, negative, and fractional weights are supported. The initial **My profile** is empty: it contains no invented class or specialization weights.

Each score is a linear sum:

`score = sum(item_stat_amount * profile_stat_weight)`

For example, 20 Strength at weight 2 and 1% Crit at weight 10 give 50 points in a percentage profile. Stamina is not converted to health, Strength is not converted to attack power, and Agility is not converted to crit: enter weights that already account for their value for your character.

Profiles are account-wide, including their active status and colors. All changes and the score cache are stored by WoW in the addon's `SavedVariables` on logout or `/reload`.

## Stat units and JSON

The supplied Sixty Upgrades keys are preserved. **Import** accepts a bare JSON object of stat weights. Missing recognized keys become zero. Unknown keys and invalid numeric values are rejected with a message so typos cannot silently change a profile.

**Export weights** produces the bare stat object. **Export profile** also preserves the profile name, color, and secondary-stat unit. These metadata are lost when exporting only bare weights.

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

Merged melee/ranged/spell hit and crit aliases are counted once. The reader prefers explicit tooltip percentages for percentage profiles and keeps native API rating values separately. It does not apply an assumed rating conversion. A profile is marked unavailable when it needs a present secondary stat in a unit that the client did not expose. An actually absent stat contributes zero.

`weaponDamage` is the explicit flat bonus (for example, `+1 Weapon Damage`), not the weapon's average base damage. To value average base damage, use half of the intended average-damage weight for both `lowDamage` and `highDamage`. JSON key compatibility is preserved, but all Sixty Upgrades field semantics have not been independently verified; check the units above when importing existing profiles.

English and French static tooltip text are supported, with localized Blizzard formats used where available. Other locales can still expose API stats, but unrecognized tooltip-only values need further validation.

## Tooltip comparisons

Every active profile adds a colored score. Candidate items also show the signed point difference and percentage difference against equipped items:

`percentage = (candidate_score - equipped_score) / equipped_score * 100`

Rings and trinkets show both replacement choices. A two-handed weapon is compared to the combined equipped main-hand and off-hand score. Generic one-handed weapons show an off-hand comparison only when dual wielding is available and the equipped main hand is compatible. A shield/off-hand item does not receive a misleading comparison against a two-handed main hand.

An empty slot has score zero; a zero or negative baseline displays **percentage n/a**. Equipped and native shopping tooltips show the item score without recursively repeating candidate comparisons. The addon evaluates item stats, not whether your class can equip every item you inspect.

## Debugging unrecognized stats

Enable **Mark unrecognized stats in tooltips** in the editor. Static stat lines that the parser cannot recognize receive an orange `[ZV ?]` marker next to their text. This also works with no active profiles. It is off by default and does not change weights or item scores.

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
| `/zv help` | Show commands |

## Scope and validation

This release evaluates static item stats. It does not model procs, on-use effects, set bonuses, stat caps, talent interactions, DPS rotations, class equipment restrictions, or future equipment combinations. Spell-power or attack-power weights should already include their expected value for your build. A higher score is a stat-weight estimate, not a simulated DPS percentage.

The Lua scoring, JSON, cache, parser, comparison, and tooltip/event logic are covered by mocked API tests included in `tests`. There is no running WoW client in this environment, so the actual UI rendering, the current Forever beta stat vocabulary, and secure tooltip behavior require an in-game check. Use `/zv inspect` to collect the raw keys and tooltip lines if an item is missing a stat or has an unavailable unit.

Run the included tests from the addon directory with a Lua interpreter, for example:

```sh
lua tests/test_core.lua
lua tests/test_items.lua
lua tests/test_compare.lua
lua tests/test_tooltips.lua
lua tests/test_bootstrap.lua
lua tests/test_integration.lua
lua tests/test_ui.lua
```

`luatex --luaonly` can also run the tests when a standalone Lua executable is unavailable. Production modules use Lua 5.1-compatible syntax.

## Files

- `JSON.lua`: strict JSON reader/writer; no executable imports.
- `Stats.lua`: stat schema and native API mappings.
- `Core.lua`: profile management, import/export, scoring, and score-cache invalidation.
- `Items.lua`: item variants, client data loading, normalization, and static tooltip parsing.
- `Compare.lua`: equipped slot comparisons.
- `Tooltips.lua`: native tooltip hooks and refresh handling.
- `UI.lua`: profile and weight editor.
- `Bootstrap.lua`: saved variables lifecycle, events, diagnostics, and slash commands.

## License

MIT. See `LICENSE`.
