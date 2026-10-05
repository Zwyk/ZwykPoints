-- Integration checks for profile filtering, using the real score/cache,
-- base-link, comparison, upgrade and tooltip paths. Item-reader metadata is
-- supplied at its record boundary; parser/locale coverage has its own suite.
local FW, records, equipped = {}, {}, {}
local playerClass, scoreCalls = "PALADIN", 0
ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
GetBuildInfo = function() return "1.16.0", "70124", "", 11600 end
GetLocale = function() return "enUS" end
UnitLevel = function() return 60 end
UnitClass = function(unit) assert(unit == "player"); return playerClass, playerClass end
CanDualWield = function() return false end
GetInventoryItemLink = function(unit, slot) assert(unit == "player"); return equipped[slot] end
local function payload(link) return type(link) == "string" and link:match("(item:[^|%s]+)") end
GetItemInfo = function(link)
    local record = records[payload(link)]
    if record then
        return record.name, link, 3, 60, 60, "", "", 1, record.equipLoc, nil, 0, record.classID, record.subclassID
    end
end
C_Item = {GetItemInfo=GetItemInfo}
for _, file in ipairs({"JSON.lua", "Stats.lua", "Core.lua", "Items.lua", "Compare.lua", "Upgrades.lua"}) do
    assert(loadfile(file))("ZwykValues", FW)
end
FW:Initialize()
local passed = 0
local function check(value, message) assert(value, message or "filter check failed"); passed = passed + 1 end
local function equal(actual, expected, message)
    check(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, text)
    check(type(value) == "string" and value:find(text, 1, true), "Expected '" .. text .. "' within " .. tostring(value))
end
local function fixture(link, classID, subclassID, strength, equipLoc, allowedClasses, known)
    local record = {key=FW:ItemKey(link), link=link, name="Fixture " .. link, classID=classID, subclassID=subclassID,
        stats={strength=strength}, percentStats={}, ratingStats={}, equipLoc=equipLoc or "INVTYPE_HEAD",
        allowedClasses=allowedClasses, classRestrictionsKnown=known ~= false, partial=false}
    records[link] = record
    return record
end
function FW:GetItem(link)
    local record = records[payload(link)]
    if not record then return nil, "Item data is still loading." end
    self.DB.cache.items[record.key] = record
    return record
end
local realScoreStats = FW.ScoreStats
function FW:ScoreStats(profile, stats) scoreCalls = scoreCalls + 1; return realScoreStats(self, profile, stats) end
local main = FW:GetProfiles()[1]
assert(FW:UpdateProfile(main.id, {name="Filtered", weights={strength=1}}))
local independent = assert(FW:CreateProfile("Independent", {strength=1}))
local function allOn(profile)
    local filters = {includeOtherClasses=true, weapons={}, armor={}}
    for _, group in ipairs(FW.ItemFilterGroups) do
        for _, itemType in ipairs(group.types) do filters[group.key][itemType.key] = true end
    end
    assert(FW:UpdateProfile(profile.id, {itemFilters=filters}))
end

-- Every declared type is independently switchable and starts checked.
local expected = {
    weapons={"0","1","2","3","4","5","6","7","8","9","10","13","14","15","16","18","19","20"},
    armor={"0","1","2","3","4","5","6","7","8","9","10","11"},
}
for _, group in ipairs(FW.ItemFilterGroups) do
    equal(#group.types, #expected[group.key], "all UI filter types are represented")
    for index, itemType in ipairs(group.types) do
        equal(itemType.key, expected[group.key][index], "stable numeric subclass key")
        equal(main.itemFilters[group.key][itemType.key], true, itemType.label .. " defaults checked")
        local item = {classID=group.classID, subclassID=tonumber(itemType.key), classRestrictionsKnown=true}
        check(FW:IsItemAllowed(item, main), itemType.label .. " starts allowed")
        local revision = main.revision
        assert(FW:UpdateProfile(main.id, {itemFilters={[group.key]={[itemType.key]=false}}}))
        equal(main.revision, revision+1, "filter edits invalidate cached scores")
        equal(FW:IsItemAllowed(item, main), false, itemType.label .. " unchecked excludes that subtype")
        check(FW:IsItemAllowed(item, independent), "another profile retains its independent choices")
        local otherType = tonumber(group.types[index == 1 and 2 or 1].key)
        check(FW:IsItemAllowed({classID=group.classID,subclassID=otherType}, main), "unrelated subtype stays included")
        assert(FW:UpdateProfile(main.id, {itemFilters={[group.key]={[itemType.key]=false}}}))
        equal(main.revision, revision+1, "unchanged checkbox is not a score revision")
        assert(FW:UpdateProfile(main.id, {itemFilters={[group.key]={[itemType.key]=true}}}))
        check(FW:IsItemAllowed(item, main), "reenabling the checkbox restores eligibility")
    end
end
equal(main.itemFilters.includeOtherClasses, true)
check(main.itemFilters ~= independent.itemFilters and main.itemFilters.weapons ~= independent.itemFilters.weapons)
local patch = {armor={["4"]=false}, weapons={["10"]=false}}
assert(FW:UpdateProfile(main.id, {itemFilters=patch}))
patch.armor["4"], patch.weapons["10"] = true, true
equal(main.itemFilters.armor["4"], false, "updates do not retain caller-owned tables")
equal(main.itemFilters.weapons["10"], false)
equal(main.itemFilters.armor["1"], true, "partial updates preserve unspecified types")

-- Invalid mixed patches are atomic, even if valid fields were supplied first.
local badPatches = {
    false, FW.JSON.null, FW.JSON.array(), {includeOtherClasses=1}, {unknown=true},
    {weapons=false}, {weapons=FW.JSON.array()}, {weapons={[7]=false}},
    {weapons={["999"]=false}}, {armor={["4"]="false"}},
    {armor={["1"]=false}, weapons={["7"]=0}},
}
for _, bad in ipairs(badPatches) do
    local before = assert(FW:ExportProfile(main.id))
    local revision = main.revision
    local changed, err = FW:UpdateProfile(main.id, {name="Must not mutate", itemFilters=bad})
    equal(changed, nil); check(type(err) == "string")
    equal(assert(FW:ExportProfile(main.id)), before, "invalid filter update is atomic")
    equal(main.revision, revision)
end

-- Cached totals cannot bypass a newly applied filter or a different character.
allOn(main)
local plate = fixture("item:1000:0", 4, 4, 40)
equal(FW:GetScore(plate.link, main), 40)
local computed = scoreCalls
equal(FW:GetScore(plate.link, main), 40); equal(scoreCalls, computed, "repeat score hits persistent cache")
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["4"]=false}}}))
local score, record, detail = FW:GetScore(plate.link, main)
equal(score, nil); equal(record, plate); equal(detail, "excluded")
equal(FW:CompareItem(plate.link, main).excluded, true)
equal(FW:GetScore(plate.link, independent), 40, "cached exclusion is profile-specific")
equal(FW:GetScore(plate.link, main, true), 40, "equipped-item scoring explicitly bypasses candidate filters")
computed = scoreCalls
equal(FW:GetScore(plate.link, main), nil); equal(scoreCalls, computed, "even bypass-cached totals stay hidden for candidates")
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["4"]=true}}}))
equal(FW:GetScore(plate.link, main), 40, "reenabling a type restores score")
assert(FW:UpdateProfile(main.id, {itemFilters={includeOtherClasses=false}}))
local paladinOnly = fixture("item:1001:0", 4, 0, 70, "INVTYPE_HEAD", {PALADIN=true})
equal(FW:GetScore(paladinOnly.link, main), 70)
computed = scoreCalls
playerClass = "MAGE"
score, record, detail = FW:GetScore(paladinOnly.link, main)
equal(score, nil); equal(detail, "excluded"); equal(scoreCalls, computed, "player-class test precedes score-cache lookup")
playerClass = "PALADIN"
equal(FW:GetScore(paladinOnly.link, main), 70); equal(scoreCalls, computed)
local mixed = fixture("item:1002:0", 4, 0, 55, "INVTYPE_HEAD", {PALADIN=true,WARRIOR=true})
equal(FW:GetScore(mixed.link, main), 55)
playerClass = "WARRIOR"; equal(FW:GetScore(mixed.link, main), 55)
playerClass = "MAGE"; equal(select(3, FW:GetScore(mixed.link, main)), "excluded")
playerClass = "PALADIN"
equal(FW:GetScore(plate.link, main), 40, "unrestricted gear remains allowed")
assert(FW:UpdateProfile(main.id, {itemFilters={includeOtherClasses=true}}))
equal(FW:GetScore(mixed.link, main), 55, "including other classes accepts restricted items")

-- Missing type/class metadata waits and retries without caching a false score.
assert(FW:UpdateProfile(main.id, {itemFilters={weapons={["10"]=false}, includeOtherClasses=false}}))
local missing = fixture("item:1003:0", nil, nil, 25, "INVTYPE_HEAD", nil, false)
computed = scoreCalls
score, detail = FW:GetScore(missing.link, main)
equal(score, nil); contains(detail, "type data"); equal(scoreCalls, computed)
missing.classID, missing.subclassID = 4, 4
score, detail = FW:GetScore(missing.link, main)
equal(score, nil); contains(detail, "class restrictions"); equal(scoreCalls, computed)
missing.classRestrictionsKnown = true
equal(FW:GetScore(missing.link, main), 25, "later metadata completes a pending item")
local missingSubtype = fixture("item:1004:0", 2, nil, 30)
score, detail = FW:GetScore(missingSubtype.link, main)
equal(score, nil); contains(detail, "subtype data")
missingSubtype.subclassID = 7
equal(FW:GetScore(missingSubtype.link, main), 30)
local incompleteClasses = fixture("item:1005:0", 4, 0, 20, nil, {MAGE=true}, false)
score, detail = FW:GetScore(incompleteClasses.link, main)
equal(score, nil); contains(detail, "class restrictions")
incompleteClasses.classRestrictionsKnown = true
incompleteClasses.allowedClasses = {MAGE=true}
equal(select(3, FW:GetScore(incompleteClasses.link, main)), "excluded")
incompleteClasses.allowedClasses.PALADIN = true
equal(FW:GetScore(incompleteClasses.link, main), 20, "positive player membership is recognized")
playerClass = nil
score, detail = FW:GetScore(paladinOnly.link, main)
equal(score, nil); contains(detail, "Player class")
playerClass = "PALADIN"
allOn(main)
local noMetadataNeeded = fixture("item:1006:0", nil, nil, 10, nil, nil, false)
equal(FW:GetScore(noMetadataNeeded.link, main), 10, "all-inclusive defaults do not require optional metadata")

-- Base and enchanted item paths apply the same candidate filters, while the
-- baseline includes equipped gear even when those item types were unchecked.
local sword = fixture("item:2000:42:0", 2, 7, 100, "INVTYPE_WEAPON")
fixture("item:2000:0:0", 2, 7, 80, "INVTYPE_WEAPON")
local shield = fixture("item:2001:42:0", 4, 6, 50, "INVTYPE_SHIELD")
fixture("item:2001:0:0", 4, 6, 40, "INVTYPE_SHIELD")
local twohand = fixture("item:2002:42:0", 2, 8, 140, "INVTYPE_2HWEAPON")
fixture("item:2002:0:0", 2, 8, 110, "INVTYPE_2HWEAPON")
equipped[16], equipped[17] = sword.link, shield.link
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["6"]=false}}}))
equal(select(3, FW:GetScore(shield.link, main)), "excluded")
equal(select(3, FW:GetBaseScore(shield.link, main)), "excluded")
equal(FW:GetBaseScore(shield.link, main, true), 40, "base scorer forwards the baseline bypass")
local result = assert(FW:CompareItem(twohand.link, main))
equal(result.comparisons[1].baseline, 150, "excluded shield remains part of the equipped 2H baseline")
equal(result.comparisons[1].delta, -10); equal(result.comparisons[1].status, "downgrade")
result = assert(FW:CompareBaseItem(twohand.link, main))
equal(result.comparisons[1].baseline, 120); equal(result.comparisons[1].delta, -10)
local oldTwohand = fixture("item:2003:42:0", 2, 8, 200, "INVTYPE_2HWEAPON")
fixture("item:2003:0:0", 2, 8, 170, "INVTYPE_2HWEAPON")
local newSword = fixture("item:2004:42:0", 2, 7, 130, "INVTYPE_WEAPON")
fixture("item:2004:0:0", 2, 7, 110, "INVTYPE_WEAPON")
equipped[16], equipped[17] = oldTwohand.link, nil
assert(FW:UpdateProfile(main.id, {itemFilters={weapons={["8"]=false}}}))
equal(FW:CompareItem(oldTwohand.link, main).excluded, true)
result = assert(FW:CompareItem(newSword.link, main))
equal(result.comparisons[1].baseline, 200, "excluded equipped 2H weapon is never an empty-slot baseline")
equal(result.comparisons[1].delta, -70)
result = assert(FW:CompareBaseItem(newSword.link, main))
equal(result.comparisons[1].baseline, 170); equal(result.comparisons[1].delta, -60)
equipped[16], equipped[17] = nil, nil

-- Copy/import/export/reload own their maps and retain unchecked entries.
local copied = assert(FW:CopyProfile(main.id))
check(copied.itemFilters ~= main.itemFilters and copied.itemFilters.armor ~= main.itemFilters.armor)
equal(copied.itemFilters.armor["6"], false); equal(copied.itemFilters.weapons["8"], false)
assert(FW:UpdateProfile(copied.id, {itemFilters={armor={["6"]=true}}}))
equal(main.itemFilters.armor["6"], false)
local exported = assert(FW:ExportProfile(main.id))
local decoded = assert(FW.JSON.Decode(exported))
equal(decoded.itemFilters.weapons["8"], false)
local imported = assert(FW:ImportProfile(exported))
equal(imported.itemFilters.armor["6"], false)
check(imported.itemFilters.weapons ~= main.itemFilters.weapons)
assert(FW:UpdateProfile(imported.id, {itemFilters={weapons={["8"]=true}}}))
equal(main.itemFilters.weapons["8"], false)
local bare = assert(FW.JSON.Decode(assert(FW:ExportProfile(main.id, true))))
equal(bare.itemFilters, nil, "bare Sixty Upgrades weights retain their original schema")
local bareImport = assert(FW:ImportProfile(assert(FW.JSON.Encode(bare)), "Bare"))
for _, group in ipairs(FW.ItemFilterGroups) do
    for _, itemType in ipairs(group.types) do equal(bareImport.itemFilters[group.key][itemType.key], true) end
end
for _, format in ipairs({"ZwykValues", "ZwykPoints", "ForeverWeights"}) do
    local oldEnvelope = {format=format, version=1, weights={strength=1}}
    local oldImport = assert(FW:ImportProfile(assert(FW.JSON.Encode(oldEnvelope))))
    equal(oldImport.itemFilters.includeOtherClasses, true)
    equal(oldImport.itemFilters.weapons["8"], true)
    equal(oldImport.itemFilters.armor["6"], true)
end
for _, bad in ipairs(badPatches) do
    local invalid = {format="ZwykValues", version=1, weights={strength=1}, itemFilters=bad}
    local profileCount, nextID = #FW:GetProfiles(), FW.DB.nextProfileID
    local source = FW.JSON.Encode(invalid)
    if source then
        local profile, err = FW:ImportProfile(source)
        equal(profile, nil, "invalid envelope filter is rejected"); check(type(err) == "string")
        equal(#FW:GetProfiles(), profileCount); equal(FW.DB.nextProfileID, nextID, "invalid import never allocates a profile")
    else
        -- Numeric Lua table keys cannot be represented by the JSON writer;
        -- their rejection was covered as a programmatic partial patch above.
        check(type(bad) == "table" and bad.weapons and bad.weapons[7] == false)
    end
end
local savedMaps = main.itemFilters
local mainID, independentID = main.id, independent.id
FW.DB = nil; FW:Initialize()
main, independent = FW.DB.profiles[mainID], FW.DB.profiles[independentID]
equal(main.itemFilters.armor["6"], false); equal(main.itemFilters.weapons["8"], false)
check(main.itemFilters ~= savedMaps and main.itemFilters.weapons ~= savedMaps.weapons)
check(main.itemFilters.weapons ~= independent.itemFilters.weapons, "saved profiles reload into independent maps")
local legacySaved = FW.DB.profiles[bareImport.id]
legacySaved.itemFilters = nil; FW.DB = nil; FW:Initialize()
equal(legacySaved.itemFilters.weapons["8"], true, "old saved profiles migrate to inclusive defaults")

-- Arrows use the same filters and recover after re-enabling or delayed data.
assert(FW:SetMainProfile(main.id))
assert(FW:SetUpgradeOption("upgradeChat", true))
local candidate = fixture("item:3000:42:0", 4, 4, 100)
fixture("item:3000:0:0", 4, 4, 80)
local oldHelmet = fixture("item:3001:42:0", 4, 4, 50)
fixture("item:3001:0:0", 4, 4, 40)
equipped[1] = oldHelmet.link
check(FW:IsMainProfileUpgrade(candidate.link))
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["4"]=false}}}))
check(not FW:IsMainProfileUpgrade(candidate.link), "previously cached upgrade disappears after filter change")
local chat = "|H" .. candidate.link .. "|h[Helmet]|h"
equal(FW:DecorateUpgradeChatMessage(chat), chat, "excluded item links receive no upgrade marker")
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["4"]=true}}}))
check(FW:IsMainProfileUpgrade(candidate.link))
contains(FW:DecorateUpgradeChatMessage(chat), "ArrowUp")
candidate.classID = nil
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["1"]=false}}}))
check(not FW:IsMainProfileUpgrade(candidate.link), "missing metadata does not establish an upgrade")
candidate.classID = 4
check(FW:IsMainProfileUpgrade(candidate.link), "loading result is retried without a profile revision")

-- Excluded profiles contribute no score, Base row, spacer, or generic warning.
for _, profile in ipairs(FW:GetProfiles()) do assert(FW:UpdateProfile(profile.id, {active=profile.id==main.id})) end
assert(loadfile("Tooltips.lua"))("ZwykValues", FW)
local function tooltip(link, name)
    local t = {link=link, name=name or "FilterTooltip", lines={{left="Native item line"}}, shown=false}
    function t:GetItem() return "Item", self.link end
    function t:GetName() return self.name end
    function t:IsForbidden() return false end
    function t:IsShown() return self.shown end
    function t:IsEquippedItem() return self.equipped == true end
    function t:AddLine(left) self.lines[#self.lines+1] = {left=left} end
    function t:AddDoubleLine(left, right) self.lines[#self.lines+1] = {left=left,right=right} end
    function t:NumLines() return #self.lines end
    return t
end
assert(FW:UpdateProfile(main.id, {itemFilters={armor={["4"]=false}}}))
FW.DB.options.debugUnknownStats = true
candidate.partial, candidate.unrecognizedLines = true, {{text="Unparsed stat"}}
local t = tooltip(candidate.link)
FW:DecorateTooltip(t, {hyperlink=candidate.link})
equal(#t.lines, 1, "all profiles excluded leaves native tooltip unchanged")
local shopping = tooltip(candidate.link, "ShoppingTooltip1"); shopping.equipped = true
FW:DecorateTooltip(shopping, {hyperlink=candidate.link})
equal(#shopping.lines, 1, "comparison tooltip also filters its own profile scores")
FW.DB.options.showComparisons = false
local noCompare = tooltip(candidate.link)
FW:DecorateTooltip(noCompare, {hyperlink=candidate.link})
equal(#noCompare.lines, 1, "non-comparison score/Base path also excludes cleanly")
candidate.partial, candidate.unrecognizedLines = false, nil
FW.DB.options.debugUnknownStats, FW.DB.options.showComparisons = false, true
assert(FW:UpdateProfile(independent.id, {active=true}))
local mixedTooltip = tooltip(candidate.link)
FW:DecorateTooltip(mixedTooltip, {hyperlink=candidate.link})
equal(#mixedTooltip.lines, 4, "one eligible profile adds exactly spacer, full score and Base")
equal(mixedTooltip.lines[2].left, " ")
equal(mixedTooltip.lines[3].left, independent.name)
equal(mixedTooltip.lines[4].left, "  Base")
contains(mixedTooltip.lines[3].right, "100.00")
contains(mixedTooltip.lines[4].right, "80.00")
for _, line in ipairs(mixedTooltip.lines) do check(line.left ~= main.name, "excluded profile name stays hidden") end

-- Gear eligibility is universal: positive stats, old cached totals and the
-- equipped-baseline filter bypass cannot turn other item types into gear.
allOn(main)
allOn(independent)
FW.DB.options.debugUnknownStats = true
local nonGear = {
    {label="consumable", classID=0, equipLoc=""},
    {label="quest item", classID=12, equipLoc=""},
    {label="equippable quest prop", classID=12, equipLoc="INVTYPE_HOLDABLE"},
    {label="bag", classID=1, equipLoc="INVTYPE_BAG"},
    {label="quiver", classID=11, equipLoc="INVTYPE_QUIVER"},
    {label="projectile in a weapon slot", classID=6, equipLoc="INVTYPE_RANGED"},
    {label="projectile without an ammunition slot", classID=6, equipLoc=""},
    {label="armor in an ammunition slot", classID=4, equipLoc="INVTYPE_AMMO"},
    {label="profession tool", classID=19, equipLoc="INVTYPE_PROFESSION_TOOL"},
    {label="profession accessory", classID=19, equipLoc="INVTYPE_PROFESSION_GEAR"},
    {label="unsupported weapon slot", classID=2, equipLoc="INVTYPE_PROFESSION_TOOL"},
    {label="miscellaneous item", classID=15, equipLoc=""},
    {label="nonwearable armor", classID=4, equipLoc=""},
}
for index, data in ipairs(nonGear) do
    local full = fixture("item:" .. (4000+index) .. ":42:0", data.classID, 0, 99, data.equipLoc)
    local base = fixture("item:" .. (4000+index) .. ":0:0", data.classID, 0, 88, data.equipLoc)
    for _, record in ipairs({full,base}) do
        FW.DB.cache.scores[record.key] = {[main.id]={revision=main.revision,score=999}}
    end
    local before = scoreCalls
    for _, ignoreFilters in ipairs({false,true}) do
        local score, record, detail = FW:GetScore(full.link, main, ignoreFilters)
        equal(score, nil, data.label .. " never receives a full score")
        equal(record, full); equal(detail, "excluded")
        score, record, detail = FW:GetBaseScore(full.link, main, ignoreFilters)
        equal(score, nil, data.label .. " never receives a Base score")
        equal(record, base); equal(detail, "excluded")
    end
    equal(scoreCalls, before, data.label .. " is rejected before calculating or returning cached totals")
    equal(FW:GetScore(full.link, independent), nil, "gear eligibility applies to every profile")
    for _, baseOnly in ipairs({false,true}) do
        local result = assert(FW:CompareItem(full.link, main, baseOnly))
        equal(result.excluded, true); equal(#result.comparisons, 0)
    end
    check(not FW:IsMainProfileUpgrade(full.link), data.label .. " receives no upgrade arrow")
    local chatLink = "|cnIQ2:|H" .. full.link .. "|h[" .. data.label .. "]|h|r"
    equal(FW:DecorateUpgradeChatMessage(chatLink), chatLink, data.label .. " chat link stays unchanged")
    full.partial, full.unrecognizedLines = true, {{text="Native item line"}}
    for _, showComparisons in ipairs({true,false}) do
        FW.DB.options.showComparisons = showComparisons
        local itemTooltip = tooltip(full.link, "NonGearTooltip" .. index)
        local nativeFont = {text="Native item line"}
        function nativeFont:GetText() return self.text end
        function nativeFont:SetText(value) self.text = value end
        _G[itemTooltip.name .. "TextLeft1"] = nativeFont
        FW:DecorateTooltip(itemTooltip, {hyperlink=full.link})
        equal(#itemTooltip.lines, 1, data.label .. " tooltip adds no score, Base row, spacer or warning")
        equal(nativeFont.text, "Native item line", data.label .. " native tooltip receives no stat debug mark")
        _G[itemTooltip.name .. "TextLeft1"] = nil
    end
end
FW.DB.options.showComparisons, FW.DB.options.debugUnknownStats = true, false

-- Accessories and existing character clothing slots are still gear. A known
-- equipment slot also remains sufficient on legacy tuples without class IDs.
for index, data in ipairs({
    {label="ring", equipLoc="INVTYPE_FINGER"},
    {label="offhand", equipLoc="INVTYPE_HOLDABLE"},
    {label="shirt", equipLoc="INVTYPE_BODY"},
    {label="tabard", equipLoc="INVTYPE_TABARD"},
}) do
    local garment = fixture("item:" .. (4100+index) .. ":0", 4, 0, 7, data.equipLoc)
    equal(FW:GetScore(garment.link, main), 7, data.label .. " remains eligible gear")
end
local legacyGear = fixture("item:4110:0", nil, nil, 9, "INVTYPE_HEAD", nil, false)
equal(FW:GetScore(legacyGear.link, main), 9, "known gear slot works without optional class metadata")

-- Ammunition remains eligible and contributes through the existing ranged DPS
-- weight. Weapon/armor subtype choices do not classify projectiles as either.
local ammoProfile = assert(FW:CreateProfile("Ammunition", {rangedDps=2}))
local excludeTypes = {includeOtherClasses=true, weapons={}, armor={}}
for _, group in ipairs(FW.ItemFilterGroups) do
    for _, itemType in ipairs(group.types) do excludeTypes[group.key][itemType.key] = false end
end
assert(FW:UpdateProfile(ammoProfile.id, {itemFilters=excludeTypes}))
local ammunition = fixture("item:4130:42:0", 6, 2, 0, "INVTYPE_AMMO")
local baseAmmunition = fixture("item:4130:0:0", 6, 2, 0, "INVTYPE_AMMO")
ammunition.stats, baseAmmunition.stats = {rangedDps=4}, {rangedDps=2.5}
equal(FW:GetScore(ammunition.link, ammoProfile), 8, "ammunition uses the ranged DPS weight")
equal(FW:GetBaseScore(ammunition.link, ammoProfile), 5, "ammunition Base score uses its unenchanted variant")
local ammoComputed = scoreCalls
equal(FW:GetScore(ammunition.link, ammoProfile), 8)
equal(FW:GetBaseScore(ammunition.link, ammoProfile), 5)
equal(scoreCalls, ammoComputed, "ammunition full and Base totals use the persistent score cache")
equal(FW:GetScore(ammunition.link, ammoProfile, true), 8, "equipped ammunition follows the same ranged DPS scoring")
local legacyAmmo = fixture("item:4131:0", nil, nil, 0, "INVTYPE_AMMO", nil, false)
legacyAmmo.stats = {rangedDps=3}
equal(FW:GetScore(legacyAmmo.link, main), 0, "ammunition is eligible on legacy tuples without class IDs")
equal(FW:GetScore(ammunition.link, main), 0, "zero ranged DPS weight gives eligible ammunition a zero total")

-- Missing or secret equipment metadata waits; completing it restores scoring
-- without changing the profile or preserving an excluded/loading decision.
local pendingGear = fixture("item:4120:0", 4, 4, 25)
pendingGear.equipLoc = nil
local beforePending = scoreCalls
local waitingScore, waitingReason = FW:GetScore(pendingGear.link, main)
equal(waitingScore, nil); contains(waitingReason, "equipment data")
equal(scoreCalls, beforePending)
equal(FW.DB.cache.scores[pendingGear.key], nil, "missing equipment metadata does not cache a total")
local secretEquipLoc = setmetatable({}, {__tostring=function() error("secret equipment must not be stringified") end})
issecretvalue = function(value) return value == secretEquipLoc end
pendingGear.equipLoc = secretEquipLoc
waitingScore, waitingReason = FW:GetScore(pendingGear.link, main, true)
equal(waitingScore, nil); contains(waitingReason, "equipment data")
equal(scoreCalls, beforePending, "baseline bypass also waits for secret equipment metadata")
issecretvalue = nil
pendingGear.equipLoc = "INVTYPE_HEAD"
equal(FW:GetScore(pendingGear.link, main), 25, "later equipment metadata recovers at the same profile revision")

-- Debug-only tooltips must also leave non-gear alone when no profile is active.
for _, profile in ipairs(FW:GetProfiles()) do assert(FW:UpdateProfile(profile.id, {active=false})) end
FW.DB.options.debugUnknownStats = true
local debugItem = records["item:4001:42:0"]
local debugTooltip = tooltip(debugItem.link)
FW:DecorateTooltip(debugTooltip, {hyperlink=debugItem.link})
equal(#debugTooltip.lines, 1, "debug-only non-gear tooltip stays native")
print("Item filters tests passed: " .. passed .. " checks")
