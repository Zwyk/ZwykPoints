-- Plain Lua 5.1+ tests; execute from the ZwykValues project directory.
local source = "./"
if not io.open("Stats.lua", "r") then source = "../" end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function approx(actual, expected)
    assert(actual and math.abs(actual - expected) < 0.00001, tostring(actual) .. " ~= " .. expected)
end
local current, locale, cached, modernCalls, legacyCalls, loads
local function newReader(item)
    current, locale, cached, modernCalls, legacyCalls, loads = item, "enUS", true, 0, 0, 0
    GetBuildInfo = function() return "1.60.0", "12345", "today", 16000 end
    UnitLevel = function() return 60 end
    GetLocale = function() return locale end
    GetItemInfo = function(link)
        if not cached then return nil end
        return current.name or "Test Item", link, 4, 60, 60, "Armor", "Plate", 1, current.equipLoc or "INVTYPE_HEAD"
    end
    GetItemStats = function() legacyCalls = legacyCalls + 1; return current.legacy end
    C_Item = {
        IsItemDataCachedByID = function() return cached end,
        RequestLoadItemDataByID = function() loads = loads + 1 end,
        GetItemStats = function() modernCalls = modernCalls + 1; return current.raw end,
    }
    C_TooltipInfo = {
        GetHyperlink = function()
            if not current.lines then return nil end
            local lines = {}
            for _, text in ipairs(current.lines) do lines[#lines + 1] = { leftText = text } end
            return { lines = lines }
        end,
    }
    CreateFrame = nil
    RETRIEVING_ITEM_INFO, RETRIEVING_DATA = "Retrieving item information", "Retrieving data"
    ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
    local FW = {}
    assert(loadfile(source .. "JSON.lua"))("ZwykValues", FW)
    assert(loadfile(source .. "Stats.lua"))("ZwykValues", FW)
    assert(loadfile(source .. "Core.lua"))("ZwykValues", FW)
    assert(loadfile(source .. "Items.lua"))("ZwykValues", FW)
    FW:Initialize()
    return FW
end

local FW = newReader({ raw = {
    ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_HIT_MELEE_RATING_SHORT = 14,
    ITEM_MOD_HIT_SPELL_RATING_SHORT = 14, ITEM_MOD_HIT_RANGED_RATING_SHORT = 14,
    ITEM_MOD_CRIT_RATING_SHORT = 8,
}, lines = { "Test Item", "+20 Strength", "Equip: Increases your chance to hit with melee attacks by 1%.",
    "Equip: Increases your chance to hit with spells by 1%.", "Critical Strike +0.5%" } })
local item = assert(FW:GetItem("item:100:0:0:0:0:0:7:99"))
equal(item.stats.strength, 20)
equal(item.ratingStats.hit, 14, "merged hit counted once")
equal(item.percentStats.hit, 1, "merged percentage counted once")
equal(item.percentStats.crit, 0.5)
equal(item.partial, false)
equal(item.unresolvedStats.hit, nil)
local cachedItem = FW:GetItem("item:100:0:0:0:0:0:7:99")
equal(cachedItem, item, "persisted record reused")
equal(modernCalls, 1, "cache skips item extraction")
local second = assert(FW:GetItem("item:100:3:0:0:0:0:7:99"))
assert(second.key ~= item.key, "enchant variants need distinct keys")
assert(FW:ItemKey("item:100:3:4:0:0:0:7:99") ~= second.key, "gem variants need distinct keys")
local before = FW:ItemKey("item:100")
locale = "frFR"
assert(FW:ItemKey("item:100") ~= before, "locale affects item key")
locale = "enUS"
UnitLevel = function() return 59 end
assert(FW:ItemKey("item:100") ~= before, "level affects item key")

FW = newReader({ raw = nil, legacy = { ITEM_MOD_AGILITY_SHORT = 11 }, lines = { "Test Item", "+11 Agility" } })
item = assert(FW:GetItem("item:101"))
equal(item.stats.agility, 11)
equal(legacyCalls, 1, "nil modern API falls back")

FW = newReader({ raw = {}, lines = { "Test Item", "Binds when picked up" } })
cached = false
local missing, message = FW:GetItem("item:102")
equal(missing, nil)
assert(message:find("loading"))
equal(loads, 1)
equal(next(FW.DB.cache.items), nil, "unloaded data is never cached")
FW:GetItem("item:102")
equal(loads, 1, "load request is deduplicated")
cached = true
item = assert(FW:GetItem("item:102"))
equal(item.partial, false, "loaded statless items remain valid")
assert(FW.DB.cache.items[item.key], "statless item caches once loaded")

FW = newReader({ raw = {}, equipLoc = "INVTYPE_WEAPON", lines = {
    "Test Sword", "20 - 40 Damage", "Speed 2.00", "(15.0 damage per second)",
    "Equip: Increases damage done by Holy spells and effects by up to 12.",
    "Equip: Restores 4 mana per 5 sec.",
} })
item = assert(FW:GetItem("item:103"))
equal(item.stats.lowDamage, 20); equal(item.stats.highDamage, 40)
equal(item.stats.weaponDamage, nil, "base weapon average is not a flat damage bonus"); equal(item.stats.speed, 2)
equal(item.stats.dps, 15); equal(item.stats.holyDamage, 12); equal(item.stats.mp5, 4)
equal(item.stats.spellDamage, nil, "school damage doesn't become generic damage")

FW = newReader({ raw = {}, equipLoc = "INVTYPE_RANGEDRIGHT", lines = {
    "Test Bow", "10 - 20 Damage", "Speed 1.50",
} })
item = assert(FW:GetItem("item:104"))
equal(item.stats.rangedSpeed, 1.5); equal(item.stats.rangedDps, 10)
equal(item.stats.dps, nil, "ranged DPS kept distinct")

FW = newReader({ raw = { ITEM_MOD_SPELL_POWER_SHORT = 30 }, lines = {
    "Test Wand", "Équipé : Augmente les dégâts et les soins produits par les sorts et effets magiques de 30 au maximum.",
    "+10 Intelligence", "Équipé : Augmente vos chances d'infliger un coup critique de 1,5%.",
    "Équipé : Rend 6 points de mana toutes les 5 sec.",
    "Équipé : Augmente la compétence de défense de 5.",
} })
locale = "frFR"
item = assert(FW:GetItem("item:105"))
equal(item.stats.intellect, 10); equal(item.stats.spellDamage, 30); equal(item.stats.healing, 30)
equal(item.stats.mp5, 6); equal(item.percentStats.defense, 5)
approx(item.percentStats.crit, 1.5); equal(item.partial, false)

FW = newReader({ raw = { ITEM_MOD_HASTE_RATING_SHORT = 12 }, lines = {
    "Test Item", "Equip: Increases your haste rating by 12.",
} })
item = assert(FW:GetItem("item:106"))
equal(item.ratingStats.haste, 12); equal(item.percentStats.haste, nil)
equal(item.unresolvedStats.haste, true, "no guessed rating conversion")
equal(item.partial, false, "valid raw rating can be cached")

FW = newReader({ raw = {}, lines = { "Test Item", "+8 Strength",
    "Use: Increases Strength by 100 for 20 sec.",
    "Equip: Has a chance to increase your attack power by 200.",
    "Equip: Increases your critical strike chance by 10% while in Bear Form.",
    "(2) Set: Increases your chance to hit by 2%.",
} })
item = assert(FW:GetItem("item:107"))
equal(item.stats.strength, 8); equal(item.stats.attackPower, nil)
equal(item.percentStats.crit, nil); equal(item.percentStats.hit, nil)
equal(#item.unrecognizedLines, 0, "procs and conditional effects don't become debug stat warnings")

FW = newReader({ raw = { ITEM_MOD_STRENGTH_SHORT = 5 }, lines = {
    "Test Item", "+5 Strength", "Magister's Regalia (2/8)", "Equip: Increases your chance to hit by 2%.",
} })
item = assert(FW:GetItem("item:108"))
equal(item.percentStats.hit, nil, "set section excluded")

FW = newReader({ raw = { ITEM_MOD_STRENGTH_SHORT = 3, ITEM_MOD_FUTURE_SHORT = 10 }, lines = {
    "Test Item", "+3 Strength and +1% Dodge", "+10 Weapon Skill", "+5 Mana", "Requires Level 60", "Durability 10 / 10",
} })
item = assert(FW:GetItem("item:109"))
equal(item.partial, true)
equal(#item.unrecognizedLines, 3)
equal(item.unrecognizedLines[1].text, "+3 Strength and +1% Dodge")
equal(next(FW.DB.cache.items), nil, "incomplete extraction is not persisted")
equal(FW:GetIssueReport().itemCount, 1, "issue item is persisted independently of the normal cache")
local journal = FW:GetIssueReport().items[1]
equal(journal.name, "Test Item")
equal(journal.raw.ITEM_MOD_FUTURE_SHORT, 10)
equal(journal.tooltipLines[2], "+3 Strength and +1% Dodge")
equal(journal.tooltipDetails[2].leftText, "+3 Strength and +1% Dodge")
equal(journal.tooltipSource, "C_TooltipInfo")
equal(journal.source, "C_Item.GetItemStats")
equal(journal.build.build, "12345")
equal(journal.locale, "enUS")
equal(journal.stats.strength, 3)
FW:GetItem("item:109")
equal(FW:GetIssueReport().itemCount, 1, "repeated reads update one diagnostic entry per variant")
FW:GetItem("item:109:1")
equal(FW:GetIssueReport().itemCount, 2, "item variants receive distinct diagnostic entries")
local diagnostic = assert(FW:GetRawItemStats("item:109"))
equal(diagnostic.unknownKeys[1], "ITEM_MOD_FUTURE_SHORT")
assert(FW:IsPotentialStatLine("+4 Unknown stat"))
equal(FW:IsPotentialStatLine("Use: +4 Strength for 20 sec."), false)

FW = newReader({ raw = { ITEM_MOD_STAMINA_SHORT = 20, RESISTANCE0_NAME = 300, ITEM_MOD_EXTRA_ARMOR_SHORT = 50 },
    lines = { "Test Item", "+20 Stamina", "300 Armor" } })
item = assert(FW:GetItem("item:110"))
equal(item.stats.armor, 250); equal(item.stats.armorBonus, 50)
equal(item.stats.health, nil, "derived stamina health is not counted")

FW = newReader({ raw = {}, lines = { "Test Item" } })
item = assert(FW:GetItem("item:111"))
equal(item.partial, true)
equal(next(FW.DB.cache.items), nil, "empty incomplete tooltip is not cached")

FW = newReader({ raw = { ITEM_MOD_STRENGTH_SHORT = 1 }, lines = { "Test Item", "+1 Strength" } })
for id = 1, 2002 do assert(FW:GetItem("item:" .. (1000 + id))) end
equal(#FW.DB.cache.itemOrder, 2000, "cache is bounded")
equal(FW.DB.cache.items[FW:ItemKey("item:1001")], nil, "oldest cache entry evicted")
assert(FW.DB.cache.items[FW:ItemKey("item:3002")])

FW = newReader({ raw = { ITEM_MOD_CRIT_RATING_SHORT = 14 }, lines = {
    "Test Item", "Critical Strike +1%", "Equip: Increases your chance to critically hit with spells by 1%.",
} })
item = assert(FW:GetItem("item:112"))
equal(item.percentStats.crit, 1, "generic and legacy percentage aliases counted once")

FW = newReader({ raw = { ITEM_MOD_SPELL_DAMAGE_DONE = 20, ITEM_MOD_POWER_REGEN0_SHORT = 4 }, lines = {
    "Test Item", "Equip: Increases Fire spell damage by up to 20.", "Equip: Restores 4 mana per 5 sec.",
} })
item = assert(FW:GetItem("item:113"))
equal(item.stats.fireDamage, 20); equal(item.stats.spellDamage, nil)
equal(item.stats.mp5, 4, "POWER_REGEN0 API maps to mana per five")

FW = newReader({ raw = {}, lines = { "Test Item", "Retrieving item information" } })
missing = FW:GetItem("item:114")
equal(missing, nil, "tooltip placeholder is still loading")
equal(next(FW.DB.cache.items), nil)
equal(loads, 1)

FW = newReader({ raw = {}, equipLoc = "INVTYPE_WEAPON", lines = { "Test Item", "20 - 40 Damage", "Speed 2.00", "+5 Weapon Damage" } })
item = assert(FW:GetItem("item:115"))
equal(item.stats.weaponDamage, 5, "flat damage bonus parsed separately from ranges")
equal(item.stats.dps, 15)

FW = newReader({ raw = {}, lines = { "Test Item", "1,234 Armor" } })
item = assert(FW:GetItem("item:116"))
equal(item.stats.armor, 1234, "English thousands separators")

FW = newReader({ raw = {}, lines = { "Test Item", "1\194\160234 Armure", "Critique +1,5%" } })
locale = "frFR"
item = assert(FW:GetItem("item:117"))
equal(item.stats.armor, 1234, "French thousands separators")
equal(item.percentStats.crit, 1.5, "French decimal separators")

FW = newReader({ raw = {}, lines = { "Test Item", "Equip: Reduces the chance for your attacks to be dodged or parried by 1%." } })
item = assert(FW:GetItem("item:118"))
equal(item.percentStats.expertise, 1)
equal(item.percentStats.dodge, nil); equal(item.percentStats.parry, nil)

FW = newReader({ raw = {}, lines = { "Test Item", "Équipé : Réduit les chances que vos attaques soient esquivées ou parées de 1,5%." } })
locale = "frFR"
item = assert(FW:GetItem("item:119"))
equal(item.percentStats.expertise, 1.5)

FW = newReader({ raw = { ITEM_MOD_STRENGTH_SHORT = 0 / 0,
    ITEM_MOD_FUTURE_SHORT = function() end, [1] = math.huge, [false] = "Unexpected key" }, lines = { "Test Item", "+2 Strength" } })
item = assert(FW:GetItem("item:120"))
local badAPIProfile = assert(FW:CreateProfile("Known subtotal", { strength = 2 }))
equal(FW:GetScore("item:120", badAPIProfile), 4, "known tooltip values remain usable after an invalid API value")
local exported = assert(FW.JSON.Encode(FW:GetIssueReport()))
local exportedReport = assert(FW.JSON.Decode(exported))
equal(exportedReport.items[1].raw.ITEM_MOD_STRENGTH_SHORT, "[non-finite number]", "invalid raw values cannot break combined export")
equal(exportedReport.items[1].raw.ITEM_MOD_FUTURE_SHORT, "[function value unavailable]")
equal(exportedReport.items[1].raw["1"], "[non-finite number]")
equal(exportedReport.items[1].raw["false"], "Unexpected key", "unexpected API key types are still exportable")
equal(exportedReport.items[1].profileScores[badAPIProfile.id].score, 4)
equal(FW:GetIssueReport().itemCount, 1)
FW:InvalidateCache()
equal(FW:GetIssueReport().itemCount, 1, "debug export survives explicit score-cache clearing")
local preservedDB = FW.DB
FW.DB = nil
FW:Initialize()
equal(FW.DB, preservedDB)
equal(FW:GetIssueReport().itemCount, 1, "diagnostics persist through reinitialization")

FW = newReader({ raw = { ITEM_MOD_HIT_RATING_SHORT = 12 }, lines = { "Test Item", "Hit Rating +12" } })
local mismatchProfile = assert(FW:CreateProfile("Percent", { hit = 5 }))
item = assert(FW:GetItem("item:121"))
equal(item.partial, false, "native rating extraction remains valid")
equal(FW:GetIssueReport().itemCount, 0, "valid native ratings are not automatically parser failures")
local mismatchScore, mismatchRecord, mismatchWarning = FW:GetScore("item:121", mismatchProfile)
equal(mismatchScore, 0)
assert(mismatchWarning:find("percentage points", 1, true))
equal(mismatchRecord.partial, false)
assert(FW:ItemHasIssues(mismatchRecord, mismatchProfile))
equal(FW:GetIssueReport().itemCount, 1, "unit-specific scoring failures are also exportable")
assert(FW.JSON.Encode(FW:GetIssueReport()))

local protected = setmetatable({}, { __tostring = function() error("secret value must not be stringified") end })
issecretvalue = function(value) return value == protected end
FW = newReader({ raw = { ITEM_MOD_STRENGTH_SHORT = protected, [protected] = 8 },
    lines = { "Test Item", "+5 Strength" } })
item = assert(FW:GetItem("item:122"))
local secretReport = assert(FW.JSON.Decode(assert(FW.JSON.Encode(FW:GetIssueReport()))))
equal(secretReport.items[1].raw.ITEM_MOD_STRENGTH_SHORT, "[secret value unavailable]")
equal(secretReport.items[1].raw["[secret key unavailable]"], 8)
issecretvalue = nil

-- Regression cases taken from the six-item Forever 1.60.1 issue export.
local foreverCases = {
    { id = 15493, name = "Bloodspattered Loincloth of the Knight", equipLoc = "INVTYPE_LEGS",
        raw = { ITEM_MOD_SPELL_POWER_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 4, ITEM_MOD_STRENGTH_SHORT = 2, RESISTANCE0_NAME = 141 },
        lines = { "141 Armor", "+2 Strength", "+4 Stamina",
            "Equip: Increases damage and healing done by magical spells and effects by up to 2.",
            "Enchanted: Stamina +2 and Armor +16" },
        expected = { armor = 157, strength = 2, stamina = 6, spellDamage = 2, healing = 2 } },
    { id = 15509, name = "Grunt's Handwraps of Magic", equipLoc = "INVTYPE_HAND",
        raw = { ITEM_MOD_SPELL_POWER_SHORT = 6, RESISTANCE0_NAME = 107 },
        lines = { "107 Armor", "Equip: Increases damage and healing done by magical spells and effects by up to 6.",
            "Enchanted: Stamina +2 and Armor +16" },
        expected = { armor = 123, stamina = 2, spellDamage = 6, healing = 6 } },
    { id = 15510, name = "Grunt's Belt of the Physician", equipLoc = "INVTYPE_WAIST",
        raw = { ITEM_MOD_INTELLECT_SHORT = 4, ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1,
            ITEM_MOD_SPELL_HEALING_DONE_SHORT = 4, ITEM_MOD_SPIRIT_SHORT = 2, RESISTANCE0_NAME = 94 },
        lines = { "94 Armor", "+4 Intellect", "+2 Spirit",
            "Equip: Increases healing done by up to 4 and damage done by up to 1 for all magical spells and effects." },
        expected = { armor = 94, intellect = 4, spirit = 2, spellDamage = 1, healing = 4 } },
    { id = 250621, name = "Strange Copper Boots", equipLoc = "INVTYPE_FEET",
        raw = { ITEM_MOD_SPELL_POWER_SHORT = 5, ITEM_MOD_STAMINA_SHORT = 4, RESISTANCE0_NAME = 109 },
        lines = { "109 Armor", "+4 Stamina", "Equip: Increases damage and healing done by magical spells and effects by up to 5.",
            "Enchanted: Stamina +2 and Armor +16", "<Made by Zwyk Zw>" },
        expected = { armor = 125, stamina = 6, spellDamage = 5, healing = 5 } },
    { id = 270023, name = "Tanned Shoulderpads", equipLoc = "INVTYPE_SHOULDER",
        raw = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 3, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 9,
            ITEM_MOD_STAMINA_SHORT = 9, RESISTANCE0_NAME = 73 },
        lines = { "73 Armor", "+9 Stamina",
            "Equip: Increases healing done by up to 9 and damage done by up to 3 for all magical spells and effects." },
        expected = { armor = 73, stamina = 9, spellDamage = 3, healing = 9 } },
    { id = 9779, name = "Bandit Cloak of the Hierophant", equipLoc = "INVTYPE_CLOAK",
        raw = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 1, ITEM_MOD_SPELL_HEALING_DONE_SHORT = 2,
            ITEM_MOD_SPIRIT_SHORT = 1, ITEM_MOD_STAMINA_SHORT = 2, RESISTANCE0_NAME = 16 },
        lines = { "16 Armor", "+2 Stamina", "+1 Spirit",
            "Equip: Increases healing done by up to 2 and damage done by up to 1 for all magical spells and effects." },
        expected = { armor = 16, stamina = 2, spirit = 1, spellDamage = 1, healing = 2 } },
}
for _, sample in ipairs(foreverCases) do
    table.insert(sample.lines, 1, sample.name)
    FW = newReader(sample)
    item = assert(FW:GetItem("item:" .. sample.id .. ":8481"))
    for key, value in pairs(sample.expected) do equal(item.stats[key], value, sample.name .. " " .. key) end
    for key, value in pairs(item.stats) do equal(value, sample.expected[key], sample.name .. " unexpected " .. key) end
    equal(item.partial, false, sample.name .. " resolves without warnings")
    equal(#item.unrecognizedLines, 0)
    equal(next(item.unresolvedStats), nil)
    equal(FW:GetIssueReport().itemCount, 0)
    equal(FW:GetItem("item:" .. sample.id .. ":8481"), item, "resolved item caches")
    equal(item.parserVersion, 3, "old persisted parser results receive a new key")
end

FW = newReader({ raw = { RESISTANCE0_NAME = 141, ITEM_MOD_STAMINA_SHORT = 4 },
    lines = { "Test Item", "157 Armor", "+4 Stamina", "Enchanted: Stamina +2 and Armor +16" } })
item = assert(FW:GetItem("item:123:8481"))
equal(item.stats.armor, 157, "a displayed total that includes an armor enchant is not increased twice")
equal(item.stats.stamina, 6)

FW = newReader({ raw = { ITEM_MOD_STAMINA_SHORT = 4 },
    lines = { "Test Item", "Enchanted: Stamina +2" } })
item = assert(FW:GetItem("item:124:8481"))
equal(item.stats.stamina, 6, "an enchant supplements API base stats even without a normal stat line")

FW = newReader({ raw = {}, lines = { "Test Item",
    "Equip: Increases healing done by up to 9 and damage done by up to 3 for all magical spells and effects." } })
item = assert(FW:GetItem("item:125"))
equal(item.stats.healing, 9); equal(item.stats.spellDamage, 3)
equal(item.partial, false, "combined healing and spell damage can be read without API values")

FW = newReader({ raw = { ITEM_MOD_STAMINA_SHORT = 4 },
    lines = { "Test Item", "+4 Stamina", "Enchanted: Stamina +2 and Armor +16 and Mystery Flux +7" } })
item = assert(FW:GetItem("item:126:8481"))
equal(item.stats.stamina, 6); equal(item.stats.armor, 16)
equal(item.partial, true, "recognized enchant clauses cannot hide an unknown clause")
equal(#item.unrecognizedLines, 1)
equal(item.unresolvedStats.stamina, nil, "a fully recognized clause is not marked unresolved")
equal(next(FW.DB.cache.items), nil)
assert(FW:IsPotentialStatLine("Enchanted: Grants 7 Mystery Flux"))

FW = newReader({ raw = {}, lines = { "Test Item",
    "Equip: Increases healing done by up to 9 and damage done by up to 3 for all magical spells and effects and grants 7 Mystery Flux." } })
item = assert(FW:GetItem("item:127"))
equal(item.partial, true, "combined spell wording must match the entire effect")
equal(item.stats.healing, nil); equal(item.stats.spellDamage, nil)

FW = newReader({ raw = { ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = 20 }, lines = { "Test Item",
    "Equip: Increases Fire spell damage by up to 20.", "Enchanted: Spell Damage +5" } })
item = assert(FW:GetItem("item:128:1"))
equal(item.stats.fireDamage, 20)
equal(item.stats.spellDamage, 5, "an enchant cannot preserve a false generic alias for school-only damage")
equal(item.partial, false)

print("Items tests passed")
