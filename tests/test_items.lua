-- Plain Lua 5.1+ tests; execute from the ZwykPoints project directory.
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
    local FW = { DB = { cache = { items = {}, itemOrder = {}, scores = {} } } }
    assert(loadfile(source .. "Stats.lua"))("ZwykPoints", FW)
    assert(loadfile(source .. "Items.lua"))("ZwykPoints", FW)
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

print("Items tests passed")
