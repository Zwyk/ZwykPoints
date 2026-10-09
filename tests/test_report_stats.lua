-- Run from the addon directory: luatex --luaonly tests/test_report_stats.lua
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local current, statCalls, tooltipCalls
local function reader(fixture)
    current, statCalls, tooltipCalls = fixture, 0, 0
    GetLocale = function() return current.locale or "enUS" end
    GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", 16001 end
    UnitLevel = function() return 60 end
    UnitClass = function() return "Paladin", "PALADIN", 2 end
    GetTime = nil
    GetItemInfo = function(link)
        return current.name or "Report Item", link, 3, 60, 60, "Armor", "Miscellaneous", 1,
            current.equipLoc or "INVTYPE_TRINKET", 123, 0, 4, current.subclassID or 0
    end
    GetItemInfoInstant, GetItemStats, CreateFrame = nil, nil, nil
    ITEM_CLASSES_ALLOWED, ITEM_CLASSES_ALLOWED_MULTIPLE = "Classes: %s", nil
    LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = {PALADIN="Paladin"}, {PALADIN="Paladin"}
    C_Item = {
        IsItemDataCachedByID = function() return true end,
        GetItemStats = function() statCalls = statCalls + 1; return current.raw or {} end,
    }
    C_TooltipInfo = { GetHyperlink = function()
        tooltipCalls = tooltipCalls + 1
        local lines = { {leftText=current.name or "Report Item", type=22} }
        for _, text in ipairs(current.lines or {"Binds when equipped"}) do
            lines[#lines + 1] = {leftText=text, type=0}
        end
        return {lines=lines}
    end }
    ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
    local addon = {}
    for _, file in ipairs({"JSON.lua", "Stats.lua", "Core.lua", "Items.lua"}) do
        assert(loadfile(file))("ZwykValues", addon)
    end
    addon:Initialize()
    return addon
end
local function complete(record)
    equal(record.partial, false, "recognized item is complete")
    equal(next(record.unresolvedStats), nil, "recognized item has no unresolved stats")
    equal(#record.unrecognizedLines, 0)
    equal(#record.warnings, 0)
    equal(next(record.unknownAPIStats or {}), nil)
end

-- The current report's defensive line must never become offensive spell damage.
local reducedLine = "Equip: Spell Damage received is reduced by 5."
local FW = reader({name="Tortoise Armor", equipLoc="INVTYPE_CHEST", subclassID=2,
    raw={RESISTANCE0_NAME=248}, lines={"208 Armor", "+40 Armor", reducedLine}})
local item = assert(FW:GetItem("item:6907"))
complete(item)
equal(item.stats.spellDamage, nil)
equal(item.unresolvedStats.spellDamage, nil)
equal(#item.ignoredTooltipStats, 1)
equal(item.ignoredTooltipStats[1].text, reducedLine)
equal(item.ignoredTooltipStats[1].index, 4)
equal(item.ignoredTooltipStats[1].reason, "Spell damage received reduction has no stat in the weight schema.")
local spellProfile = assert(FW:CreateProfile("Offensive spell weight", {spellDamage=100}))
local score, _, status = FW:GetScore("item:6907", spellProfile)
equal(score, 0); equal(status, nil, "ignored defensive effect is not a score failure")
equal(FW:GetIssueReport().itemCount, 0, "deliberately ignored effects do not create issue history")
equal(FW:GetItem("item:6907"), item)
equal(statCalls, 1); equal(tooltipCalls, 1, "ignored effects do not prevent persistent caching")

-- Independent offensive stats still contribute when a defensive line is ignored.
FW = reader({raw={ITEM_MOD_SPELL_DAMAGE_DONE_SHORT=7}, lines={reducedLine,
    "Equip: Increases damage done by magical spells and effects by up to 7."}})
item = assert(FW:GetItem("item:20001"))
complete(item); equal(item.stats.spellDamage, 7); equal(#item.ignoredTooltipStats, 1)
spellProfile = assert(FW:CreateProfile("Offensive spell weight", {spellDamage=2}))
equal(FW:GetScore("item:20001", spellProfile), 14)

-- Unknown trailing clauses stay unknown; recognized words must not hide them.
for _, line in ipairs({
    "Equip: Spell Damage received is reduced by 5 and Mystery Flux by 2.",
    "Equip: Spell Damage received is reduced by 5%.",
    "Equip: Spell Damage received is reduced by an unknown amount of 5.",
}) do
    FW = reader({lines={line}})
    item = assert(FW:GetItem("item:20002"))
    equal(item.partial, true, line); equal(#item.unrecognizedLines, 1)
    equal(#item.ignoredTooltipStats, 0); equal(item.stats.spellDamage, nil)
end

-- Reported spell penetration is one stat even when both APIs expose it.
for _, raw in ipairs({{}, {ITEM_MOD_SPELL_PENETRATION_SHORT=2}}) do
    FW = reader({name="Vest of Elements", equipLoc="INVTYPE_CHEST", subclassID=3,
        raw=raw, lines={"Equip: Your spells pierce 2 Magical Resistance."}})
    item = assert(FW:GetItem("item:16666"))
    complete(item); equal(item.stats.spellPen, 2)
    equal(item.stats.spellDamage, nil); equal(item.stats.arcaneResist, nil)
    local profile = assert(FW:CreateProfile("Spell penetration", {spellPen=3}))
    equal(FW:GetScore("item:16666", profile), 6)
end
FW = reader({raw={ITEM_MOD_SPELL_PENETRATION_SHORT=3}, lines={
    "Equip: Your spells pierce 3 Magical Resistance."}})
item = assert(FW:GetItem("item:16700")); complete(item); equal(item.stats.spellPen, 3)
FW = reader({lines={"Equip: Your spells pierce 2 Magical Resistance and add Mystery Flux."}})
item = assert(FW:GetItem("item:20003"))
equal(item.partial, true); equal(item.stats.spellPen, nil); equal(#item.unrecognizedLines, 1)

-- Herbalism on the reported gloves is outside the scoring schema, not an unknown stat.
local herbalismLine = "Equip: Increased Herbalism +2."
FW = reader({name="Apothecary Gloves", equipLoc="INVTYPE_HAND", subclassID=1,
    raw={ITEM_MOD_HERBALISM_SHORT=2, ITEM_MOD_SPELL_POWER_SHORT=4, RESISTANCE0_NAME=21},
    lines={"21 Armor", "Equip: Increases damage and healing done by magical spells and effects by up to 4.", herbalismLine}})
item = assert(FW:GetItem("item:20004")); complete(item)
equal(item.stats.spellDamage, 4); equal(item.stats.healing, 4); equal(item.stats.herbalism, nil)
equal(#item.diagnostic.ignoredKeys, 1); equal(item.diagnostic.ignoredKeys[1], "ITEM_MOD_HERBALISM_SHORT")
equal(#item.ignoredTooltipStats, 1); equal(item.ignoredTooltipStats[1].text, herbalismLine)
equal(item.ignoredTooltipStats[1].reason, "Profession skill bonuses have no stat in the weight schema.")
local profile = assert(FW:CreateProfile("Glove spells", {spellDamage=2, healing=3}))
equal(FW:GetScore("item:20004", profile), 20)
equal(FW:GetIssueReport().itemCount, 0)

for _, profession in ipairs({"HERBALISM", "MINING", "SKINNING", "FISHING", "ALCHEMY", "BLACKSMITHING",
    "ENCHANTING", "ENGINEERING", "LEATHERWORKING", "TAILORING", "COOKING", "FIRST_AID"}) do
    for _, suffix in ipairs({"_SHORT", ""}) do
        local key = "ITEM_MOD_" .. profession .. suffix
        local name = profession:lower():gsub("_", " ")
        FW = reader({raw={[key]=2}, lines={"Equip: Increased " .. name .. " +2."}})
        item = assert(FW:GetItem("item:20005")); complete(item)
        equal(next(item.stats), nil); equal(#item.ignoredTooltipStats, 1)
        equal(item.diagnostic.ignoredKeys[1], key)
    end
end
for _, line in ipairs({"Équipé : Herboristerie +2.", "Équipé : +2 Pêche.", "Équipé : Augmente minage de 2."}) do
    FW = reader({locale="frFR", lines={line}})
    item = assert(FW:GetItem("item:20006")); complete(item); equal(#item.ignoredTooltipStats, 1)
end
ITEM_MOD_HERBALISM_SHORT = "Native Gathering Label"
FW = reader({lines={"Equip: Increased Native Gathering Label +2."}})
item = assert(FW:GetItem("item:20007")); complete(item); equal(#item.ignoredTooltipStats, 1)
ITEM_MOD_HERBALISM_SHORT = nil

FW = reader({raw={ITEM_MOD_HERBALISM_POWER_SHORT=2}, lines={herbalismLine}})
item = assert(FW:GetItem("item:20008"))
equal(item.partial, true); equal(item.unknownAPIStats[1], "ITEM_MOD_HERBALISM_POWER_SHORT")
equal(#item.ignoredTooltipStats, 1, "a known ignored line cannot hide a separate unknown API field")
FW = reader({raw={ITEM_MOD_HERBALISM_SHORT=2}, lines={herbalismLine, "Equip: Increased Mystery Flux +3."}})
item = assert(FW:GetItem("item:20014"))
equal(item.partial, true); equal(#item.ignoredTooltipStats, 1); equal(#item.unrecognizedLines, 1)
equal(item.unrecognizedLines[1].text, "Equip: Increased Mystery Flux +3.")
local report = assert(FW.JSON.Decode(assert(FW.JSON.Encode(FW:GetIssueReport()))))
equal(report.itemCount, 1)
equal(report.items[1].ignoredTooltipStats[1].text, herbalismLine)
equal(report.items[1].ignoredTooltipStats[1].reason, "Profession skill bonuses have no stat in the weight schema.")
equal(report.items[1].ignoredAPIStats[1], "ITEM_MOD_HERBALISM_SHORT")
for _, line in ipairs({"Equip: Increased Herbalism +2 and spell damage +4.", "Equip: Increased Dragon Taming +2."}) do
    FW = reader({lines={line}})
    item = assert(FW:GetItem("item:20009"))
    equal(item.partial, true); equal(#item.ignoredTooltipStats, 0); equal(#item.unrecognizedLines, 1)
end

-- All six native school-damage API aliases are supported, including older unsuffixed names.
local schools = {"ARCANE", "FIRE", "NATURE", "FROST", "SHADOW", "HOLY"}
for _, school in ipairs(schools) do
    for _, suffix in ipairs({"_SHORT", ""}) do
        local key, stat = "ITEM_MOD_" .. school .. "_DAMAGE_DONE" .. suffix, school:lower() .. "Damage"
        FW = reader({raw={[key]=7}})
        item = assert(FW:GetItem("item:20010")); complete(item)
        equal(item.stats[stat], 7); equal(item.stats.spellDamage, nil); equal(item.stats.healing, nil)
        local weights = {spellDamage=100, healing=100}; weights[stat]=2
        profile = assert(FW:CreateProfile("School weight", weights))
        equal(FW:GetScore("item:20010", profile), 14)
        equal(FW:GetItem("item:20010"), item); equal(statCalls, 1); equal(tooltipCalls, 1)
    end
    local stat, prefix = school:lower() .. "Damage", "ITEM_MOD_" .. school
    FW = reader({raw={[prefix .. "_DAMAGE_DONE_SHORT"]=7, [prefix .. "_DAMAGE_DONE"]=7,
        [prefix .. "_DAMAGE_SHORT"]=7, [prefix .. "_DAMAGE"]=7}, lines={
        "Equip: Increases damage done by " .. school .. " spells and effects by up to 7."}})
    item = assert(FW:GetItem("item:20011")); complete(item)
    equal(item.stats[stat], 7, "API aliases and explicit tooltip do not multiply school damage")
    equal(item.stats.spellDamage, nil); equal(item.stats.healing, nil)
end
FW = reader({raw={ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT=37}, lines={
    "Equip: Increases damage done by Shadow spells and effects by up to 37."}})
item = assert(FW:GetItem("item:20012")); complete(item); equal(item.stats.shadowDamage, 37)
FW = reader({raw={ITEM_MOD_SHADOW_DAMAGE_TAKEN_SHORT=5}, lines={reducedLine}})
item = assert(FW:GetItem("item:20013"))
equal(item.partial, true); equal(item.stats.shadowDamage, nil); equal(item.stats.spellDamage, nil)
equal(item.unknownAPIStats[1], "ITEM_MOD_SHADOW_DAMAGE_TAKEN_SHORT")

print("Report stat regressions passed (" .. checks .. " checks).")
