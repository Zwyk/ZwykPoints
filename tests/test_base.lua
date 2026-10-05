-- Run from the addon directory: luatex --luaonly tests/test_base.lua
local function equal(actual, expected, message)
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, text)
    assert(type(value) == "string" and value:find(text, 1, true), tostring(value) .. " does not contain " .. text)
end

local items, equipped, statCalls, tooltipCalls, requests = {}, {}, {}, {}, {}
local function payload(link)
    return type(link) == "string" and link:match("(item:[^|%s]+)") or nil
end
local function itemInfo(link)
    local data = items[payload(link)]
    if not data or data.loaded == false then return nil end
    return data.name, link, 2, 18, 13, "Armor", "Mail", 1, data.equipLoc
end
GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", 16001 end
GetLocale = function() return "enUS" end
UnitLevel = function() return 22 end
GetItemInfo = itemInfo
GetInventoryItemLink = function(_, slot) return equipped[slot] end
CanDualWield = function() return true end
C_Item = {
    GetItemInfo = itemInfo,
    IsItemDataCachedByID = function() return true end,
    RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end,
    GetItemStats = function(link)
        local key = payload(link)
        statCalls[key] = (statCalls[key] or 0) + 1
        return items[key] and items[key].raw
    end,
}
C_TooltipInfo = { GetHyperlink = function(link)
    local key = payload(link)
    tooltipCalls[key] = (tooltipCalls[key] or 0) + 1
    local data = items[key]
    if not data then return nil end
    local lines = {}
    for _, text in ipairs(data.lines) do lines[#lines + 1] = { leftText = text } end
    return { lines = lines }
end }
CreateFrame = nil
ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
local function loadAddon()
    local addon = {}
    for _, file in ipairs({ "JSON.lua", "Stats.lua", "Core.lua", "Items.lua", "Compare.lua" }) do
        assert(loadfile(file))("ZwykValues", addon)
    end
    addon:Initialize()
    return addon
end
local FW = loadAddon()

local suffix = ":0:0:0:0:-42:9:22:1486::1:2:12755:13001:1:28:5254:::Player-4618-006D6ADA:"
local fullLink = "item:100:8481" .. suffix
local baseLink = "item:100:0" .. suffix
local hyperlink = "|cff1eff00|H" .. fullLink .. "|h[Ring of the Knight]|h|r"
equal(FW:GetBaseItemLink(fullLink), baseLink, "every field after the enchant is preserved")
equal(FW:GetBaseItemLink(hyperlink), baseLink, "colored item hyperlink")
equal(FW:GetBaseItemLink("|H" .. fullLink .. "|h[Ring of the Knight]|h"), baseLink)
equal(FW:GetBaseItemLink(baseLink), baseLink, "already unenchanted links are stable")
equal(FW:GetBaseItemLink("item:12"), "item:12:0")
equal(FW:GetBaseItemLink("item:12:"), "item:12:0")
equal(FW:GetBaseItemLink("item:12:::-42:"), "item:12:0::-42:")
equal(FW:GetBaseItemLink("item:12:88"), "item:12:0")
equal(FW:GetBaseItemLink(12.0), "item:12:0")
for _, bad in ipairs({ "", "not an item:12", "item:0", "item:-12", "item:12oops",
    "item:12:enchantment", "item:12:8 bad", "item:12:8:0|", "item:12:8:0\n",
    "item:12:8:bad@field", "|cffZZZZZZ|Hitem:12:8|h[Bad]|h|r", {}, false,
    0, -1, 12.5, math.huge, -math.huge, 0 / 0 }) do
    equal(FW:GetBaseItemLink(bad), nil, "malformed item link is rejected safely")
end
equal(FW:GetBaseItemLink(nil), nil)
local secret = setmetatable({}, { __tostring = function() error("secret value must not be stringified") end })
issecretvalue = function(value) return value == secret end
equal(FW:GetBaseItemLink(secret), nil)
local invalidScore, invalidError = FW:GetBaseScore(secret, {})
equal(invalidScore, nil); contains(invalidError, "Invalid item link")
issecretvalue = nil

local function addItem(link, equipLoc, strength, enchant)
    local base = assert(FW:GetBaseItemLink(link))
    local function data(enchantLine)
        local lines = { "Test " .. link, "+" .. strength .. " Strength" }
        if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
            or equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_2HWEAPON" then
            lines[#lines + 1] = "1 - 3 Damage"
            lines[#lines + 1] = "Speed 1.00"
        end
        if enchantLine then lines[#lines + 1] = enchantLine end
        return { name = "Test " .. link, equipLoc = equipLoc,
            raw = { ITEM_MOD_STRENGTH_SHORT = strength }, lines = lines }
    end
    items[base] = data()
    if link ~= base then
        local enchantLine = type(enchant) == "number" and ("Enchanted: Strength +" .. enchant) or enchant
        items[link] = data(enchantLine)
    end
    return base
end

addItem(fullLink, "INVTYPE_FINGER", 10, 5)
local profile = assert(FW:CreateProfile("Base regression", { strength = 1 }))
local fullScore, fullRecord = FW:GetScore(hyperlink, profile)
local baseScore, baseRecord = FW:GetBaseScore(hyperlink, profile)
equal(fullScore, 15, "normal scoring still includes a recognized enchant")
equal(baseScore, 10, "base score is read from the unenchanted variant")
equal(baseRecord.link, baseLink)
equal(baseRecord.partial, false)
assert(fullRecord.key ~= baseRecord.key, "base and full variants need separate cache entries")
equal(baseRecord.parserVersion, 4, "base scoring uses the current item metadata schema")
equal(statCalls[baseLink], 1); equal(tooltipCalls[baseLink], 1)
equal(FW:GetBaseScore("item:100:9999" .. suffix, profile), 10,
    "different enchants reuse the same preserved base variant")
equal(statCalls[baseLink], 1, "persistent item cache skips extraction")
equal(tooltipCalls[baseLink], 1)
assert(FW.DB.cache.scores[baseRecord.key][profile.id])

local differentSuffix = "item:100:8481" .. suffix:gsub("%-42", "-43", 1)
local differentBase = addItem(differentSuffix, "INVTYPE_FINGER", 13, 5)
local otherScore, otherRecord = FW:GetBaseScore(differentSuffix, profile)
equal(otherScore, 13, "random suffix variations keep their distinct stats")
assert(otherRecord.key ~= baseRecord.key)
equal(otherRecord.link, differentBase)

local unknownLink = "item:110:9001" .. suffix
local unknownBase = addItem(unknownLink, "INVTYPE_FINGER", 6, "Enchanted: Grants 10 Mystery Flux")
-- Simulate an API/tooltip exposing a known full total alongside an enchant that
-- cannot be interpreted. Subtracting only recognized enchant stats would fail.
items[unknownLink].raw.ITEM_MOD_STRENGTH_SHORT = 16
items[unknownLink].lines[2] = "+16 Strength"
local unknownScore, unknownRecord = FW:GetScore(unknownLink, profile)
equal(unknownScore, 16); equal(unknownRecord.partial, true)
local cleanScore, cleanRecord = FW:GetBaseScore(unknownLink, profile)
equal(cleanScore, 6, "unknown enchants are removed by reading the base item")
equal(cleanRecord.link, unknownBase)
equal(cleanRecord.partial, false); equal(#cleanRecord.unrecognizedLines, 0)
equal(statCalls[unknownBase], 1)

local ring1, ring2 = "item:101:8481" .. suffix, "item:102:8481" .. suffix
local ring1Base = addItem(ring1, "INVTYPE_FINGER", 8, 12)
local ring2Base = addItem(ring2, "INVTYPE_FINGER", 12, 1)
equipped[11], equipped[12] = ring1, ring2
local result = assert(FW:CompareItem(fullLink, profile))
equal(result.score, 15)
equal(result.comparisons[1].baseline, 20); equal(result.comparisons[1].delta, -5)
equal(result.comparisons[2].baseline, 13); equal(result.comparisons[2].delta, 2)
result = assert(FW:CompareBaseItem(fullLink, profile))
equal(result.score, 10); equal(#result.comparisons, 2)
equal(result.comparisons[1].baseline, 8); equal(result.comparisons[1].delta, 2)
equal(result.comparisons[1].percent, 25)
equal(result.comparisons[2].baseline, 12); equal(result.comparisons[2].delta, -2)
equal(result.comparisons[1].links[1], ring1, "comparison retains the actual equipped link")
equal(result.hasIssues, false)
equal(statCalls[ring1Base], 1); equal(statCalls[ring2Base], 1)
equipped[12] = nil
result = FW:CompareItem(fullLink, profile, true)
equal(result.comparisons[2].baseline, 0); equal(result.comparisons[2].percent, nil)
equal(result.comparisons[2].status, "upgrade", "empty ring slots follow the existing delta rules")

local trinket, trinket1, trinket2 = "item:120:8481", "item:121:8481", "item:122:8481"
addItem(trinket, "INVTYPE_TRINKET", 10, 5)
addItem(trinket1, "INVTYPE_TRINKET", 10, 12)
addItem(trinket2, "INVTYPE_TRINKET", 5, 20)
equipped[13], equipped[14] = trinket1, trinket2
result = FW:CompareBaseItem(trinket, profile)
equal(#result.comparisons, 2)
equal(result.comparisons[1].status, "equal"); equal(result.comparisons[1].percent, 0)
equal(result.comparisons[2].delta, 5); equal(result.comparisons[2].percent, 100)

local sword, shield, twohand = "item:130:8481", "item:131:8481", "item:132:8481"
addItem(sword, "INVTYPE_WEAPON", 18, 5)
addItem(shield, "INVTYPE_SHIELD", 10, 7)
addItem(twohand, "INVTYPE_2HWEAPON", 30, 5)
equipped[16], equipped[17] = sword, shield
result = FW:CompareBaseItem(twohand, profile)
equal(#result.comparisons, 1); equal(result.score, 30)
equal(result.comparisons[1].baseline, 28); equal(result.comparisons[1].delta, 2)
equal(#result.comparisons[1].links, 2, "two-hand baseline combines both unenchanted items")
result = FW:CompareItem(twohand, profile)
equal(result.score, 35); equal(result.comparisons[1].baseline, 40)
equal(result.comparisons[1].delta, -5, "full weapon comparison remains unchanged")
equipped[16], equipped[17] = twohand, nil
result = FW:CompareBaseItem(shield, profile)
equal(#result.comparisons, 0); contains(result.note, "compatible main-hand")
result = FW:CompareBaseItem(sword, profile)
equal(#result.comparisons, 1); contains(result.note, "future off-hand")

local pendingRing = "item:140:8481"
local pendingRingBase = addItem(pendingRing, "INVTYPE_FINGER", 8, 5)
items[pendingRingBase].loaded = false
equipped[11], equipped[12] = pendingRing, nil
result = FW:CompareBaseItem(fullLink, profile)
equal(result.score, 10); equal(result.comparisons[1].delta, nil)
contains(result.comparisons[1].error, "loading")
equal(requests[140], 1)
equal(FW.DB.cache.items[FW:ItemKey(pendingRingBase)], nil, "loading base items are not cached")
items[pendingRingBase].loaded = true
result = FW:CompareBaseItem(fullLink, profile)
equal(result.comparisons[1].baseline, 8); equal(result.comparisons[1].delta, 2)

local pendingMain = "item:141:8481"
local pendingMainBase = addItem(pendingMain, "INVTYPE_WEAPON", 18, 5)
items[pendingMainBase].loaded = false
equipped[16], equipped[17] = pendingMain, nil
result = FW:CompareBaseItem(shield, profile)
equal(result.pending, true); equal(#result.comparisons, 0)
contains(result.note, "main-hand item data is loading")
result = FW:CompareBaseItem(twohand, profile)
equal(result.comparisons[1].delta, nil); contains(result.comparisons[1].error, "loading")

local beforeCalls = statCalls[baseLink]
assert(FW:UpdateProfile(profile.id, { weights = { strength = 2 } }))
equal(FW:GetBaseScore(fullLink, profile), 20, "weight changes invalidate the base score")
equal(FW:GetScore(fullLink, profile), 30, "weight changes also invalidate the normal score")
equal(statCalls[baseLink], beforeCalls, "profile edits reuse extracted base stats")
equal(FW.DB.cache.scores[baseRecord.key][profile.id].revision, profile.revision)
local savedDB = FW.DB
FW = loadAddon()
equal(FW.DB, savedDB, "base item and score caches survive addon reinitialization")
local reloadedProfile = FW.DB.profiles[profile.id]
local reloadedScore, reloadedRecord = FW:GetBaseScore(hyperlink, reloadedProfile)
equal(reloadedScore, 20); equal(reloadedRecord, baseRecord)
equal(statCalls[baseLink], beforeCalls, "reload uses the persistent base cache")
equal(tooltipCalls[baseLink], 1)
equipped[11], equipped[12], equipped[16], equipped[17] = ring1, ring2, nil, nil
result = FW:CompareBaseItem(fullLink, reloadedProfile)
equal(result.comparisons[1].baseline, 16); equal(result.comparisons[1].delta, 4)
equal(result.comparisons[2].baseline, 24); equal(result.comparisons[2].delta, -4)
-- Reconstruct saved data as fresh tables, rather than relying only on retaining
-- object identities in one Lua state, and verify extraction is still skipped.
ZwykValuesDB = assert(FW.JSON.Decode(assert(FW.JSON.Encode(FW.DB))))
FW = loadAddon()
local restoredScore, restoredRecord = FW:GetBaseScore(hyperlink, profile.id)
equal(restoredScore, 20)
assert(restoredRecord ~= baseRecord, "restored cache records are independent tables")
equal(restoredRecord.link, baseLink)
equal(statCalls[baseLink], beforeCalls, "reconstructed saved cache skips base extraction")
equal(tooltipCalls[baseLink], 1)
print("Base item tests passed")
