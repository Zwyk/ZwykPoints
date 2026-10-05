-- Run from the addon directory: luatex --luaonly tests/test_item_metadata.lua
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local current, statsCalls, tooltipCalls, modernInstantCalls, legacyInstantCalls
local function newReader(item, locale)
    current, statsCalls, tooltipCalls, modernInstantCalls, legacyInstantCalls = item, 0, 0, 0, 0
    GetLocale = function() return locale or "enUS" end
    GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", 16001 end
    UnitLevel = function() return 22 end
    UnitClass = function() return "Paladin", "PALADIN", 2 end
    ITEM_CLASSES_ALLOWED, ITEM_CLASSES_ALLOWED_MULTIPLE = "Classes: %s", nil
    ITEM_RACES_ALLOWED = "Races: %s"
    LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", MAGE = "Mage", PRIEST = "Priest" }
    LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Warrior", PALADIN = "Paladin", MAGE = "Mage", PRIEST = "Priest" }
    local function equipLoc(instant)
        if instant and current.instantEquipLoc ~= nil then return current.instantEquipLoc end
        if current.missingEquipLoc then return nil end
        return current.equipLoc or "INVTYPE_HEAD"
    end
    GetItemInfo = function(link)
        if current.loading then return nil end
        if current.oldInfo then return "Test Item", link, 2, 18, 60, "Armor", "Plate", 1, equipLoc() end
        return "Test Item", link, 2, 18, 60, "Armor", "Plate", 1,
            equipLoc(), 12345, 100, current.classID, current.subclassID
    end
    local function instant()
        return 100, "Weapon", "Sword", equipLoc(true), 12345,
            current.instantClassID, current.instantSubclassID
    end
    GetItemInfoInstant = current.legacyInstant and function()
        legacyInstantCalls = legacyInstantCalls + 1
        return instant()
    end or nil
    C_Item = {
        IsItemDataCachedByID = function() return not current.loading end,
        GetItemStats = function()
            statsCalls = statsCalls + 1
            if current.raw then return current.raw end
            return { ITEM_MOD_STRENGTH_SHORT = 5 }
        end,
        GetItemInfoInstant = current.modernInstant and function()
            modernInstantCalls = modernInstantCalls + 1
            if current.modernInstantError then error("instant data unavailable") end
            return instant()
        end or nil,
    }
    C_TooltipInfo = { GetHyperlink = function()
        tooltipCalls = tooltipCalls + 1
        if current.noTooltip then return nil end
        local details = current.details
        if not details then
            details = {}
            for _, text in ipairs(current.lines or { "Test Item", "+5 Strength" }) do
                details[#details + 1] = { leftText = text }
            end
        end
        return { lines = details }
    end }
    CreateFrame, GetItemStats = nil, nil
    IsUsableItem = function() error("level/skill usability must not infer class restrictions") end
    C_Item.IsUsableItem = IsUsableItem
    RETRIEVING_ITEM_INFO, RETRIEVING_DATA = "Retrieving item information", "Retrieving data"
    ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
    local addon = {}
    for _, file in ipairs({ "JSON.lua", "Stats.lua", "Core.lua", "Items.lua" }) do
        assert(loadfile(file))("ZwykValues", addon)
    end
    addon:Initialize()
    return addon
end

local FW = newReader({ classID = 4, subclassID = 4, modernInstant = true })
local item = assert(FW:GetItem("item:100"))
equal(item.classID, 4); equal(item.subclassID, 4)
equal(modernInstantCalls, 0, "complete GetItemInfo metadata needs no instant fallback")
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses, nil)
equal(item.parserVersion, 4)
equal(FW:GetItem("item:100"), item, "complete metadata remains in the persistent item cache")
equal(statsCalls, 1); equal(tooltipCalls, 1)

FW = newReader({ oldInfo = true, modernInstant = true, instantClassID = 2, instantSubclassID = 8 })
item = assert(FW:GetItem("item:101"))
equal(item.classID, 2); equal(item.subclassID, 8)
equal(modernInstantCalls, 1, "older GetItemInfo tuples use the modern instant API")

FW = newReader({ oldInfo = true, legacyInstant = true, instantClassID = 2, instantSubclassID = 0 })
item = assert(FW:GetItem("item:102"))
equal(item.classID, 2); equal(item.subclassID, 0, "subclass zero is a valid category")
equal(legacyInstantCalls, 1)

FW = newReader({ oldInfo = true, modernInstant = true, modernInstantError = true,
    legacyInstant = true, instantClassID = 4, instantSubclassID = 6 })
item = assert(FW:GetItem("item:103"))
equal(item.classID, 4); equal(item.subclassID, 6)
equal(modernInstantCalls, 1); equal(legacyInstantCalls, 1, "failing modern instant API falls back to the legacy API")

FW = newReader({ oldInfo = true, legacyInstant = true, instantClassID = 4, instantSubclassID = 1 })
C_Item.GetItemInfoInstant = GetItemInfoInstant
item = assert(FW:GetItem("item:104"))
equal(item.classID, 4); equal(item.subclassID, 1)
equal(legacyInstantCalls, 1, "the same instant function is not called twice")

FW = newReader({ classID = 4, subclassID = nil })
item = assert(FW:GetItem("item:105"))
equal(item.classID, 4); equal(item.subclassID, nil)
equal(item.partial, false, "missing filter metadata is not a missing stat")
current.classID, current.subclassID = nil, nil
FW:RefreshItemFilterMetadata(item)
equal(item.classID, 4, "refresh cannot erase a previously known class ID")
current.classID, current.subclassID = 4, 4
FW:RefreshItemFilterMetadata(item)
equal(item.subclassID, 4)
equal(statsCalls, 1); equal(tooltipCalls, 1, "category refresh reuses complete restriction metadata")
equal(item.diagnostic.classID, 4); equal(item.diagnostic.subclassID, 4)

FW = newReader({classID=2,subclassID=2,missingEquipLoc=true,raw={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=5},
    lines={"Test Item","10 - 20 Damage","Speed 3.00"}})
local profile = assert(FW:CreateProfile("Gear metadata", {rangedDps=1}))
local score, reason = FW:GetScore("item:117", profile)
equal(score, nil); assert(reason:find("equipment data",1,true))
equal(FW.DB.cache.items[FW:ItemKey("item:117")], nil, "missing slot data cannot cache stats in the wrong weapon group")
equal(FW.DB.cache.scores[FW:ItemKey("item:117")], nil, "missing slot data cannot create a score")
current.missingEquipLoc = false
current.equipLoc = "INVTYPE_RANGED"
equal(FW:GetScore("item:117", profile), 5, "later slot data scores ranged DPS in the correct group")
item = assert(FW:GetItem("item:117"))
equal(item.equipLoc, "INVTYPE_RANGED"); equal(item.diagnostic.equipLoc, "INVTYPE_RANGED")
equal(item.stats.dps, nil); equal(item.stats.rangedDps, 5)
equal(statsCalls, 2, "pending data is reread once the slot becomes known")
item.equipLoc = nil -- A previously parsed record can still need metadata recovery.
FW:RefreshItemFilterMetadata(item)
equal(item.equipLoc, "INVTYPE_RANGED"); equal(item.diagnostic.equipLoc, "INVTYPE_RANGED")
equal(statsCalls, 2, "metadata recovery reuses parsed stats")

FW = newReader({classID=4,subclassID=4,missingEquipLoc=true,modernInstant=true,instantEquipLoc="INVTYPE_FINGER"})
item = assert(FW:GetItem("item:118"))
equal(item.equipLoc, "INVTYPE_FINGER", "instant metadata can complete a missing equipment slot")
equal(modernInstantCalls, 1, "slot fallback works even when both category IDs are already known")

FW = newReader({ classID = 4, subclassID = 4, lines = {
    "Test Item", "+5 Strength", "Classes: |cffc79c6eWarrior|r, Paladin",
    "Requires Level 60", "Requires Blacksmithing (300)",
} })
item = assert(FW:GetItem("item:106"))
equal(item.classRestrictionsKnown, true)
equal(item.allowedClasses.WARRIOR, true); equal(item.allowedClasses.PALADIN, true)
equal(item.allowedClasses.MAGE, nil); equal(item.partial, false)
equal(#item.warnings, 0)

FW = newReader({ classID = 4, subclassID = 4, details = {
    { leftText = "Test Item", type = 22 }, { leftText = "+5 Strength" },
    { leftText = "Classes:", rightText = "Warrior, Mage", type = 43, requirementType = 0 },
} })
item = assert(FW:GetItem("item:107"))
equal(item.classRestrictionsKnown, true)
equal(item.allowedClasses.WARRIOR, true); equal(item.allowedClasses.MAGE, true)
equal(item.diagnostic.tooltipDetails[3].requirementType, 0, "native race/class requirement metadata is retained")

current.details[3].leftText, current.details[3].rightText = "Classes: Warrior", "Classes: Warrior"
item.classRestrictionsKnown = false
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses.WARRIOR, true,
    "duplicated left/right class text is read once")

FW = newReader({ classID = 4, subclassID = 4, lines = { "Test Item", "+5 Force", "Classes : Prêtresse, Guerrière" } }, "frFR")
ITEM_CLASSES_ALLOWED = "Classes : %s"
LOCALIZED_CLASS_NAMES_MALE = { PRIEST = "Prêtre", WARRIOR = "Guerrier" }
LOCALIZED_CLASS_NAMES_FEMALE = { PRIEST = "Prêtresse", WARRIOR = "Guerrière" }
item = assert(FW:GetItem("item:108"))
equal(item.classRestrictionsKnown, true)
equal(item.allowedClasses.PRIEST, true); equal(item.allowedClasses.WARRIOR, true)

FW = newReader({ classID = 4, subclassID = 4, lines = { "Test Item", "+5 Strength", "Zulässig: Krieger und Druide" } }, "deDE")
ITEM_CLASSES_ALLOWED, ITEM_CLASSES_ALLOWED_MULTIPLE = "Klassen: %s", "Zulässig: %s und %s"
LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Krieger", DRUID = "Druide" }, {}
item = assert(FW:GetItem("item:109"))
equal(item.classRestrictionsKnown, true)
equal(item.allowedClasses.WARRIOR, true); equal(item.allowedClasses.DRUID, true,
    "localized ITEM_CLASSES_ALLOWED variants supply their native list separator")

FW = newReader({ classID = 4, subclassID = 4, lines = { "Test Item", "+5 Strength", "Классы: Паладинка" } }, "ruRU")
ITEM_CLASSES_ALLOWED = "Классы: %s"
LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = {}, {}
UnitClass = function() return "Паладинка", "PALADIN", 2 end
item = assert(FW:GetItem("item:110"))
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses.PALADIN, true,
    "UnitClass supplies the player's localized name when class tables are absent")

FW = newReader({ classID = 4, subclassID = 4, lines = { "Test Item", "+5 Strength", "Classes: Mage, Necromancer" } })
item = assert(FW:GetItem("item:111"))
equal(item.allowedClasses.MAGE, true); equal(item.classRestrictionsKnown, false)
equal(item.classRestrictionUnknownNames[1], "necromancer")
equal(item.partial, false); equal(#item.warnings, 0, "unknown class names do not become stat parser warnings")
LOCALIZED_CLASS_NAMES_MALE.NECROMANCER = "Necromancer"
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses.NECROMANCER, true)
equal(item.classRestrictionUnknownNames, nil)
equal(statsCalls, 1); equal(tooltipCalls, 2, "unknown class lists can recover without stat extraction")

FW = newReader({ classID = 4, subclassID = 4, details = {
    { leftText = "Test Item" }, { leftText = "+5 Strength" },
    { leftText = "Races: Human, Dwarf", type = 43, requirementType = 0 },
    { leftText = "Requires Level 60", type = 43, requirementType = 5 },
    { leftText = "Requires Blacksmithing (300)", type = 43, requirementType = 2 },
} })
item = assert(FW:GetItem("item:112"))
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses, nil,
    "race, level and skill requirements are not explicit class restrictions")

FW = newReader({ classID = 4, subclassID = 4, details = {
    { leftText = "Test Item" }, { leftText = "+5 Strength" },
    { leftText = "Unidentified requirement", type = 43, requirementType = 0 },
} })
item = assert(FW:GetItem("item:113"))
equal(item.classRestrictionsKnown, false); equal(item.allowedClasses, nil)
equal(item.partial, false)

FW = newReader({ classID = 4, subclassID = 4, lines = { "Test Item" } })
item = assert(FW:GetItem("item:114"))
equal(item.classRestrictionsKnown, false, "a name-only tooltip cannot establish unrestricted classes")
current.details = { { leftText = "Test Item", type = 22 }, { leftText = "", type = 11 } }
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, false, "empty sell/blank rows do not complete a name-only tooltip")
current.details = nil
current.lines = { "Test Item", "+5 Strength", "Classes: Warrior" }
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses.WARRIOR, true)
equal(statsCalls, 1)

FW = newReader({ classID = 4, subclassID = 4, noTooltip = true })
item = assert(FW:GetItem("item:115"))
equal(item.classRestrictionsKnown, false, "missing tooltip text remains unknown")

local secret = setmetatable({}, { __tostring = function() error("secret values must not be stringified") end })
issecretvalue = function(value) return value == secret end
FW = newReader({ classID = secret, subclassID = secret, modernInstant = true,
    instantClassID = 4, instantSubclassID = 4, details = {
        { leftText = "Test Item" }, { leftText = "+5 Strength" },
        { leftText = secret, type = 43, requirementType = 0 },
    } })
item = assert(FW:GetItem("item:116"))
equal(item.classID, 4); equal(item.subclassID, 4)
equal(item.classRestrictionsKnown, false); equal(item.allowedClasses, nil)
equal(item.partial, false); equal(item.diagnostic.tooltipReadable, false)
current.details[3].leftText = "Classes: Paladin"
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, true); equal(item.allowedClasses.PALADIN, true)
equal(item.diagnostic.tooltipReadable, true); equal(statsCalls, 1)
item.equipLoc = secret
FW:RefreshItemFilterMetadata(item)
equal(item.equipLoc, "INVTYPE_HEAD", "unreadable cached slot data recovers from readable native metadata")
equal(item.diagnostic.equipLoc, "INVTYPE_HEAD"); equal(statsCalls, 1)
issecretvalue = nil

current.details[3].leftText = "Retrieving item information"
item.classRestrictionsKnown = false
FW:RefreshItemFilterMetadata(item)
equal(item.classRestrictionsKnown, false, "a loading tooltip does not replace unknown classes with unrestricted")
print("Item metadata tests passed")
