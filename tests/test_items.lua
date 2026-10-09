-- Plain Lua 5.1+ tests; execute from the ZwykValues project directory.
local source = "./"
if not io.open("Stats.lua", "r") then source = "../" end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function approx(actual, expected)
    assert(actual and math.abs(actual - expected) < 0.00001, tostring(actual) .. " ~= " .. expected)
end
local current, locale, cached, modernCalls, legacyCalls, loads, tooltipCalls
local weaponSlots = { INVTYPE_WEAPON=true, INVTYPE_WEAPONMAINHAND=true, INVTYPE_WEAPONOFFHAND=true,
    INVTYPE_2HWEAPON=true, INVTYPE_RANGED=true, INVTYPE_RANGEDRIGHT=true, INVTYPE_THROWN=true }
local function newReader(item)
    current, locale, cached, modernCalls, legacyCalls, loads, tooltipCalls = item, "enUS", true, 0, 0, 0, 0
    GetBuildInfo = function() return "1.60.0", "12345", "today", 16000 end
    UnitLevel = function() return 60 end
    GetLocale = function() return locale end
    GetItemInfo = function(link)
        if not cached then return nil end
        local equipLoc = current.equipLoc or "INVTYPE_HEAD"
        local classID = current.classID or (weaponSlots[equipLoc] and 2 or 4)
        local subclassID = current.subclassID or (classID == 2 and 7 or 4)
        return current.name or "Test Item", link, 4, 60, 60, classID == 2 and "Weapon" or "Armor",
            classID == 2 and "Sword" or "Plate", 1, equipLoc, nil, nil, classID, subclassID
    end
    GetItemInfoInstant = nil
    GetItemStats = function() legacyCalls = legacyCalls + 1; return current.legacy end
    C_Item = {
        IsItemDataCachedByID = function() return cached end,
        RequestLoadItemDataByID = function() loads = loads + 1 end,
        GetItemStats = function() modernCalls = modernCalls + 1; return current.raw end,
    }
    C_TooltipInfo = {
        GetHyperlink = function()
            tooltipCalls = tooltipCalls + 1
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
    equal(item.parserVersion, 8, "old persisted parser results receive a new key")
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

-- Ammunition is an explicit scoring exception and contributes ranged DPS,
-- without requiring a weapon's damage range or attack speed.
local originalAmmoFormat = ITEM_AMMO_DAMAGE_TEMPLATE
for index, sample in ipairs({
    {raw={},line="Adds 7.5 damage per second",expected=7.5},
    {raw={},line="Ajoute 7,5 points de dégâts par seconde",locale="frFR",expected=7.5},
    {raw={},line="Ajoute 8 dégâts par seconde",locale="frFR",expected=8},
    {raw={},line="Projectile DPS: 9.5",format="Projectile DPS: %1$.1f",expected=9.5},
    {raw={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=7.5,ITEM_MOD_DAMAGE_PER_SECOND=7.5},
        line="Adds 7.5 damage per second",expected=7.5},
    {raw={ITEM_MOD_DAMAGE_PER_SECOND=0},line="Arrow",expected=0},
    {raw={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=6},line="Bullet",expected=6},
}) do
    ITEM_AMMO_DAMAGE_TEMPLATE = sample.format
    FW = newReader({raw=sample.raw,classID=6,subclassID=2,equipLoc="INVTYPE_AMMO",lines={"Test Arrow",sample.line}})
    locale = sample.locale or "enUS"
    item = assert(FW:GetItem("item:" .. (500+index)))
    equal(item.stats.rangedDps,sample.expected)
    equal(item.stats.dps,nil,"ammo DPS is never melee DPS")
    equal(item.stats.rangedSpeed,nil); equal(item.stats.lowDamage,nil); equal(item.stats.highDamage,nil)
    equal(item.partial,false,"ammo does not need weapon speed or damage range")
    equal(next(item.unresolvedStats),nil); equal(#item.warnings,0)
    local weights = assert(FW:CreateProfile("Ammo",{rangedDps=2,dps=100}))
    equal(FW:GetScore(item.link,weights),sample.expected*2,"only the ranged DPS weight applies")
    equal(FW:GetBaseScore(item.link,weights),sample.expected*2)
end
ITEM_AMMO_DAMAGE_TEMPLATE = originalAmmoFormat

FW = newReader({raw={},classID=6,subclassID=3,equipLoc="INVTYPE_AMMO",lines={"Unreadable Bullet","Bullet"}})
item = assert(FW:GetItem("item:510"))
equal(item.partial,true); equal(item.unresolvedStats.rangedDps,true)
equal(FW.DB.cache.items[item.key],nil,"missing ammo DPS is never cached as a complete zero")

FW = newReader({raw={},classID=6,subclassID=2,equipLoc="INVTYPE_AMMO",lines={"Arrow","Adds 7.5 damage per second"}})
local ammoProfile = assert(FW:CreateProfile("Cache migration",{rangedDps=2,dps=100}))
local oldAmmoKey = FW:ItemKey("item:511"):gsub("^8|","4|")
FW.DB.cache.items[oldAmmoKey] = {key=oldAmmoKey,stats={dps=7.5},equipLoc="INVTYPE_AMMO"}
FW.DB.cache.scores[oldAmmoKey] = {[ammoProfile.id]={revision=ammoProfile.revision,score=750}}
equal(FW:GetScore("item:511",ammoProfile),15,"parser update ignores ammo previously cached as melee DPS")
equal(modernCalls,1,"stale ammo stats are read again")

FW = newReader({raw={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=7.5},classID=6,subclassID=2,equipLoc="INVTYPE_AMMO"})
item = assert(FW:GetItem("item:512"))
equal(item.stats.rangedDps,7.5)
for _, key in ipairs({"dps","lowDamage","highDamage","weaponDamage","speed","rangedSpeed"}) do
    equal(item.unresolvedStats[key],nil,"ammo never requires weapon fields, even without a tooltip")
end
local apiAmmoProfile = assert(FW:CreateProfile("API ammo",{rangedDps=2,rangedSpeed=10,dps=100}))
local apiAmmoScore, _, apiAmmoNote = FW:GetScore(item.link,apiAmmoProfile)
equal(apiAmmoScore,15)
assert(not apiAmmoNote:find("speed",1,true),"missing ammo tooltip must not invent a speed warning")

-- Excluded item types stop at metadata. Positive API/tooltip stats on a recipe,
-- crafting output or malformed equipment category must never trigger parsing.
for index, sample in ipairs({
    {name="Recipe: Mithril Shield Spike",classID=9,subclassID=4,equipLoc=""},
    {name="Mithril Shield Spike",classID=7,subclassID=1,equipLoc=""},
    {name="Flint and Tinder",classID=15,subclassID=0,equipLoc=""},
    {name="Strength Potion",classID=0,subclassID=1,equipLoc=""},
    {name="Quest Prop",classID=12,subclassID=0,equipLoc="INVTYPE_HOLDABLE"},
    {name="Unsupported Armor",classID=4,subclassID=99,equipLoc="INVTYPE_HEAD"},
    {name="Unsupported Weapon",classID=2,subclassID=99,equipLoc="INVTYPE_WEAPON"},
    {name="Armor With Invalid Slot",classID=4,subclassID=4,equipLoc="INVTYPE_UNKNOWN"},
    {name="Bag",classID=1,subclassID=0,equipLoc="INVTYPE_BAG"},
}) do
    sample.raw = {ITEM_MOD_STRENGTH_SHORT=99}
    sample.lines = {sample.name,"+99 Strength","Equip: Grants 3 Mystery Flux."}
    FW = newReader(sample)
    local link = "item:" .. (600+index) .. ":42:0"
    local raw = assert(FW:GetRawItemStats(link))
    equal(raw.ready,true); equal(raw.excluded,true,sample.name .. " is excluded from the raw reader")
    equal(next(raw.raw),nil); equal(#raw.tooltipLines,0); equal(#raw.tooltipDetails,0)
    equal(modernCalls,0); equal(legacyCalls,0); equal(tooltipCalls,0,
        sample.name .. " never scans a tooltip")
    item = assert(FW:GetItem(link))
    equal(next(item.stats),nil); equal(item.partial,false); equal(#item.warnings,0)
    local profile = assert(FW:CreateProfile("No non-gear values",{strength=1}))
    local total, record, status = FW:GetScore(link,profile)
    equal(total,nil); equal(record.name,sample.name); equal(status,"excluded")
    -- Simulate a validly keyed SavedVariables record from earlier code that
    -- already contains a positive score; classification still wins over it.
    item.stats = {strength=99}
    FW.DB.cache.items[item.key] = item
    FW.DB.cache.scores[item.key] = {[profile.id]={revision=profile.revision,score=99}}
    total, record, status = FW:GetScore(link,profile,true)
    equal(total,nil); equal(record,item); equal(status,"excluded",
        "cached non-gear cannot score through the equipped-baseline bypass")
    equal(FW:GetBaseScore(link,profile),nil,"non-gear Base scores stay excluded")
    equal(modernCalls,0); equal(legacyCalls,0); equal(tooltipCalls,0,
        sample.name .. " never reads API stats or tooltips, including cached/Base paths")
end

-- Profile exclusions also stop unread candidates before stat/tooltip APIs,
-- without placing an empty record in the shared item cache. Other profiles and
-- equipped baselines must still read the real stats from the same variants.
FW = newReader({name="Unread plate helmet",classID=4,subclassID=4,equipLoc="INVTYPE_HEAD",
    raw={ITEM_MOD_STRENGTH_SHORT=99},lines={"Unread plate helmet","+99 Strength"}})
local unchecked = assert(FW:CreateProfile("Plate unchecked",{strength=1}))
local included = assert(FW:CreateProfile("Plate included",{strength=1}))
assert(FW:UpdateProfile(unchecked.id,{itemFilters={armor={["4"]=false}}}))
local unreadLink, unreadBase = "item:790:42:0", "item:790:0:0"
local total, metadata, status = FW:GetScore(unreadLink,unchecked)
equal(total,nil); equal(status,"excluded"); equal(next(metadata.stats),nil)
equal(modernCalls,0); equal(legacyCalls,0); equal(tooltipCalls,0,
    "unchecked unread candidates avoid stat APIs and tooltip scans")
equal(FW.DB.cache.items[FW:ItemKey(unreadLink)],nil,"profile-excluded metadata is never cached as an empty shared item")
equal(FW.DB.cache.scores[FW:ItemKey(unreadLink)],nil)
total, metadata, status = FW:GetBaseScore(unreadLink,unchecked)
equal(total,nil); equal(status,"excluded")
equal(modernCalls,0); equal(tooltipCalls,0,"unchecked fresh Base variant also stops before parsing")
equal(FW.DB.cache.items[FW:ItemKey(unreadBase)],nil)
equal(FW:GetScore(unreadLink,included),99,"another profile reads actual stats after an unread exclusion")
equal(modernCalls,1); equal(tooltipCalls,1)
equal(FW.DB.cache.items[FW:ItemKey(unreadLink)].stats.strength,99)
equal(FW:GetScore(unreadLink,unchecked,true),99,"equipped baseline bypass uses the real shared item stats")
local freshBaselineLink = "item:791:43:0"
equal(FW:GetScore(freshBaselineLink,unchecked,true),99,"uncached equipped baseline bypass also reads real stats")
equal(modernCalls,2); equal(tooltipCalls,2)
equal(FW:GetBaseScore(freshBaselineLink,unchecked),nil)
equal(modernCalls,2); equal(tooltipCalls,2,"unchecked second Base variant does not scan")
equal(FW.DB.cache.items[FW:ItemKey("item:791:0:0")],nil)
equal(FW:GetBaseScore(freshBaselineLink,included),99,"included profile can later parse a previously excluded Base variant")
equal(modernCalls,3); equal(tooltipCalls,3)

print("Items tests passed")
