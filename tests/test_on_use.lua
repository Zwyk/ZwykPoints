-- Run from the addon directory: luatex --luaonly tests/test_on_use.lua
-- Exercise scoring and equipped comparisons using the parser's normalized
-- on-use contract. Reader text/locale regressions live in the item tests.
local FW, checks = {}, 0
local function check(value, message)
    assert(value, message or "assertion failed")
    checks = checks + 1
end
local function equal(actual, expected, message)
    check(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function approx(actual, expected, message)
    check(type(actual) == "number" and math.abs(actual - expected) < 0.000001, message or (tostring(actual) .. " ~= " .. expected))
end
local function contains(value, text)
    check(type(value) == "string" and value:find(text, 1, true), tostring(value) .. " does not contain " .. text)
end
local function copy(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local clock, inventory, records, reads, weightedCalls = 10, {}, {}, {}, 0
GetTime = function() return clock end
GetBuildInfo = function() return "1.60.1", "70205", "Oct 2026", 16001 end
GetLocale = function() return "enUS" end
UnitLevel = function() return 60 end
UnitClass = function() return "Paladin", "PALADIN" end
GetInventoryItemLink = function(_, slot) return inventory[slot] end
CanDualWield = function() return true end
CreateFrame = nil
ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
for _, file in ipairs({"JSON.lua", "Stats.lua", "Core.lua", "Items.lua", "Compare.lua", "Upgrades.lua"}) do
    assert(loadfile(file))("ZwykValues", FW)
end
FW:Initialize()
local function payload(link)
    return type(link) == "string" and link:match("(item:[^|%s]+)") or nil
end
local function fixture(link, options)
    options = options or {}
    local record = {
        key = assert(FW:ItemKey(link)), link = link, itemID = tonumber(link:match("item:(%d+)")),
        name = "On-use fixture " .. link, equipLoc = options.equipLoc or "INVTYPE_TRINKET",
        classID = options.classID or 4, subclassID = options.subclassID or 0,
        classRestrictionsKnown = true, stats = copy(options.stats),
        percentStats = copy(options.percentStats), ratingStats = copy(options.ratingStats),
        onUseStats = copy(options.onUseStats), onUsePercentStats = copy(options.onUsePercentStats),
        onUseRatingStats = copy(options.onUseRatingStats), onUseEffects = options.effects or {},
        onUseUnsupported = options.unsupported or {}, warnings = {}, unresolvedStats = {},
        unrecognizedLines = {}, partial = options.partial or false,
    }
    records[link] = record
    return record
end
function FW:GetItem(link)
    local key = self:ItemKey(link)
    if self.DB.cache.items[key] then return self.DB.cache.items[key] end
    local recent = self:GetRecentItemRead(key)
    if recent then return recent.record end
    local item = payload(link)
    reads[item] = (reads[item] or 0) + 1
    local record = records[item]
    if record and record.partial then self:RememberItemRead(record) end
    return record, record and nil or "Item data is still loading."
end
GetItemInfo = function(link)
    local record = records[payload(link)]
    if not record then return nil end
    return record.name, link, 3, 60, 60, "", "", 1, record.equipLoc, 12345, 100, record.classID, record.subclassID
end
C_Item = {GetItemInfo = GetItemInfo}
local realScoreStats = FW.ScoreStats
function FW:ScoreStats(profile, stats)
    weightedCalls = weightedCalls + 1
    return realScoreStats(self, profile, stats)
end
local function effect(stats)
    -- The raw strength amount is 100; the parser's aggregate is already 5.
    return {text="Use: +100 Strength for 6 sec. (2 Min Cooldown)", index=3,
        amount=100, duration=6, cooldown=120, uptime=.05, stats=stats or {strength=100},
        percentStats={}, ratingStats={}}
end
local profile = assert(FW:CreateProfile("Average", {strength=2, crit=10}))
local second = assert(FW:CreateProfile("Negative", {strength=-1}))
local full = fixture("item:100:8481", {stats={strength=20}, onUseStats={strength=5}, effects={effect()}})
local base = fixture("item:100:0", {stats={strength=10}, onUseStats={strength=5}, effects={effect()}})
local staticSnapshot = assert(FW.JSON.Encode(base.stats))
equal(FW:GetScore(full.link, profile), 40, "full static score retains enchants")
equal(FW:GetBaseScore(full.link, profile), 20)
local score, record, detail, metadata = FW:GetAverageUseScore(full.link, profile)
equal(score, 30, "average adds the already-averaged buff to the unenchanted base")
equal(record, base); equal(detail, nil)
equal(metadata.averageUseGain, 10)
check(metadata.hasAverageUse and not metadata.averageUseIncomplete)
equal(#metadata.averageUseWarnings, 0)
equal(assert(FW.JSON.Encode(base.stats)), staticSnapshot, "average scoring never mutates static stats")
equal(FW:GetScore(full.link, profile), 40)
equal(FW:GetBaseScore(full.link, profile), 20)
equal(FW.DB.cache.scores[base.key][profile.id].score, 20, "static score cache must not receive an average total")
local beforeCalls, beforeReads = weightedCalls, reads[base.link]
local again, _, _, againMetadata = FW:GetAverageUseScore(full.link, profile.id)
equal(again, 30); equal(againMetadata, metadata)
equal(weightedCalls, beforeCalls, "repeat averages reuse the weighted result")
equal(reads[base.link], beforeReads, "repeat averages reuse the parsed base variant")
equal(FW:GetAverageUseScore(full.link, second), -15, "negative weights retain signed average contributions")
equal(base.averageUseScores[profile.id].score, 30, "profiles own independent average totals")
assert(FW:UpdateProfile(profile.id, {weights={strength=3}}))
score, _, _, metadata = FW:GetAverageUseScore(full.link, profile)
equal(score, 45); equal(metadata.averageUseGain, 15, "weight revisions invalidate average totals")
equal(reads[base.link], beforeReads, "weight changes reuse parsed effect amounts")
assert(FW:UpdateProfile(profile.id, {weights={strength=2}}))

local rating = fixture("item:101:0", {stats={strength=4}, onUseRatingStats={crit=12}, effects={effect({})}})
score, record, _, metadata = FW:GetAverageUseScore(rating.link, profile)
equal(score, 8); equal(metadata.averageUseGain, 0)
check(metadata.averageUseIncomplete, "rating amounts cannot silently become percentages")
contains(table.concat(metadata.averageUseWarnings, " "), "percentage points")
check(not record.partial and not FW:ItemHasIssues(record, profile), "average unit errors do not change static issues")
equal(FW:GetScore(rating.link, profile), 8)
assert(FW:UpdateProfile(profile.id, {secondaryUnit="rating"}))
score, _, _, metadata = FW:GetAverageUseScore(rating.link, profile)
equal(score, 128); equal(metadata.averageUseGain, 120)
check(not metadata.averageUseIncomplete, "requested rating units recover at the new revision")
local percentage = fixture("item:102:0", {onUsePercentStats={crit=.5}, effects={effect({})}})
score, _, _, metadata = FW:GetAverageUseScore(percentage.link, profile)
equal(score, 0); check(metadata.averageUseIncomplete)
contains(table.concat(metadata.averageUseWarnings, " "), "rating points")
assert(FW:UpdateProfile(profile.id, {weights={crit=0}}))
score, _, _, metadata = FW:GetAverageUseScore(percentage.link, profile)
equal(score, 0); check(not metadata.averageUseIncomplete, "an unweighted missing unit does not make the average incomplete")
local defense = fixture("item:103:0", {onUsePercentStats={defense=2.5}, effects={effect({})}})
local defenseProfile = assert(FW:CreateProfile("Defense skill", {defense=4}))
equal(FW:GetAverageUseScore(defense.link, defenseProfile), 10, "percentage mode retains defense skill points")
assert(FW:UpdateProfile(profile.id, {weights={crit=10}, secondaryUnit="percent"}))
local mixedUnits = fixture("item:114:0", {onUsePercentStats={crit=.5}, onUseRatingStats={crit=12},
    effects={effect({}), effect({})}})
score, _, _, metadata = FW:GetAverageUseScore(mixedUnits.link, profile)
equal(score, 5); check(metadata.averageUseIncomplete, "one readable effect cannot conceal another effect in the wrong unit")
assert(FW:UpdateProfile(profile.id, {secondaryUnit="rating"}))
score, _, _, metadata = FW:GetAverageUseScore(mixedUnits.link, profile)
equal(score, 120); check(metadata.averageUseIncomplete, "the other unit also remains incomplete for mixed-unit effects")
assert(FW:UpdateProfile(profile.id, {secondaryUnit="percent"}))
local temporaryArmor = fixture("item:116:0", {stats={armor=100}, onUseStats={armorBonus=10},
    effects={{amount=120,duration=10,cooldown=120,uptime=1/12,stats={armorBonus=120},percentStats={},ratingStats={}}}})
local armorProfile = assert(FW:CreateProfile("Armor bonus", {armor=2,armorBonus=3}))
equal(FW:GetScore(temporaryArmor.link, armorProfile), 200)
score, _, _, metadata = FW:GetAverageUseScore(temporaryArmor.link, armorProfile)
equal(score, 230, "temporary armor uses the bonus-armor weight rather than the intrinsic armor weight")
equal(metadata.averageUseGain, 30)
local temporaryBlock = fixture("item:117:0", {stats={blockValue=5}, onUseStats={blockValueBonus=2}, effects={effect({blockValueBonus=40})}})
local blockProfile = assert(FW:CreateProfile("Block bonus", {blockValue=4,blockValueBonus=7}))
equal(FW:GetScore(temporaryBlock.link, blockProfile), 20)
equal(FW:GetAverageUseScore(temporaryBlock.link, blockProfile), 34, "temporary block value uses its bonus weight")

local passive = fixture("item:104:0", {stats={strength=8}})
score, _, _, metadata = FW:GetAverageUseScore(passive.link, profile)
equal(score, 16); check(not metadata.hasAverageUse and not metadata.averageUseIncomplete)
local unsupported = fixture("item:105:0", {stats={strength=12},
    unsupported={{text="Use: Grants a changing stat bonus.", index=3, reason="changing bonuses are not supported"}}})
score, record, _, metadata = FW:GetAverageUseScore(unsupported.link, profile)
equal(score, 24); check(metadata.hasAverageUse and metadata.averageUseIncomplete)
contains(table.concat(metadata.averageUseWarnings, " "), "changing bonuses")
check(not record.partial and not FW:ItemHasIssues(record, profile))
equal(FW:GetScore(unsupported.link, profile), 24, "unsupported uses leave the ordinary static score readable")
assert(FW:SetMainProfile(profile.id))
inventory[13], inventory[14] = passive.link, nil
check(FW:IsMainProfileUpgrade(unsupported.link), "unsupported uses never disable a proven static upgrade marker")
local staticComparison = assert(FW:CompareItem(unsupported.link, profile))
equal(staticComparison.comparisons[1].delta, 8)
check(not staticComparison.hasIssues)
local uncertain = assert(FW:CompareAverageUseItem(unsupported.link, profile))
check(uncertain.averageUseIncomplete)
equal(uncertain.comparisons[1].delta, nil); equal(uncertain.comparisons[1].status, nil)

local strongUse = fixture("item:106:0", {stats={strength=8}, onUseStats={strength=10}, effects={effect()}})
inventory[13], inventory[14] = strongUse.link, passive.link
local replacements = assert(FW:CompareAverageUseItem(base.link, profile))
equal(#replacements.comparisons, 2)
equal(replacements.score, 30)
equal(replacements.comparisons[1].baseline, 36); equal(replacements.comparisons[1].delta, -6)
equal(replacements.comparisons[2].baseline, 16); equal(replacements.comparisons[2].delta, 14)
check(replacements.hasAverageUse and not replacements.averageUseIncomplete)
equal(replacements.averageUseGain, 10, "candidate gain is not replaced with equipped effect gains")
local passiveCandidate = fixture("item:107:0", {stats={strength=20}})
replacements = assert(FW:CompareAverageUseItem(passiveCandidate.link, profile))
check(replacements.hasAverageUse, "equipped on-use effects make the average comparison relevant for a passive candidate")
equal(replacements.averageUseGain, 0)
equal(replacements.comparisons[1].delta, 4)
inventory[13], inventory[14] = unsupported.link, passive.link
replacements = assert(FW:CompareAverageUseItem(passiveCandidate.link, profile))
check(replacements.averageUseIncomplete, "an unsupported equipped effect reaches the candidate result")
check(replacements.comparisons[1].averageUseIncomplete)
equal(replacements.comparisons[1].delta, nil)
equal(replacements.comparisons[2].delta, 24, "a different complete replacement retains its correct calculation")
check(#replacements.averageUseWarnings > 0)
inventory[13], inventory[14] = "item:999:8481", nil
replacements = assert(FW:CompareAverageUseItem(passiveCandidate.link, profile))
contains(replacements.comparisons[1].error, "loading"); equal(replacements.comparisons[1].delta, nil)

local sword = fixture("item:108:0", {classID=2, subclassID=7, equipLoc="INVTYPE_WEAPON",
    stats={strength=18}, onUseStats={strength=5}, effects={effect()}})
local shield = fixture("item:109:0", {classID=4, subclassID=6, equipLoc="INVTYPE_SHIELD", stats={strength=10}})
local twoHand = fixture("item:110:0", {classID=2, subclassID=8, equipLoc="INVTYPE_2HWEAPON",
    stats={strength=30}, onUseStats={strength=10}, effects={effect()}})
inventory[16], inventory[17] = sword.link, shield.link
assert(FW:UpdateProfile(profile.id, {itemFilters={weapons={["7"]=false}, armor={["6"]=false}}}))
local excludedScore, excludedRecord, excludedStatus = FW:GetAverageUseScore(sword.link, profile)
equal(excludedScore, nil); equal(excludedRecord, sword); equal(excludedStatus, "excluded")
equal(FW:CompareAverageUseItem(shield.link, profile).excluded, true)
replacements = assert(FW:CompareAverageUseItem(twoHand.link, profile))
equal(#replacements.comparisons, 1)
equal(replacements.score, 80)
equal(replacements.comparisons[1].baseline, 66, "equipped unchecked types still contribute their full average value")
equal(replacements.comparisons[1].delta, 14)
equal(#replacements.comparisons[1].links, 2)
equal(FW:GetAverageUseScore(sword.link, profile, true), 46)
assert(FW:UpdateProfile(profile.id, {itemFilters={weapons={["7"]=true}, armor={["6"]=true}}}))
inventory[16], inventory[17] = twoHand.link, nil
replacements = assert(FW:CompareAverageUseItem(shield.link, profile))
equal(#replacements.comparisons, 0); contains(replacements.note, "compatible main-hand")
local nonGear = fixture("item:111:0", {classID=0, stats={strength=100}, onUseStats={strength=100}, effects={effect()}})
equal(select(3, FW:GetAverageUseScore(nonGear.link, profile, true)), "excluded", "baseline bypass never permits non-gear")
equal(FW:CompareAverageUseItem(nonGear.link, profile).excluded, true)

local partial = fixture("item:112:0", {stats={strength=3}, onUseStats={strength=5}, effects={effect()}, partial=true})
score, record, _, metadata = FW:GetAverageUseScore(partial.link, profile)
equal(score, 16); check(record.partial and metadata.hasAverageUse)
check(not FW.DB.cache.items[partial.key] and not FW.DB.cache.scores[partial.key], "average scoring does not persist a partial static record")
beforeCalls = weightedCalls
equal(FW:GetAverageUseScore(partial.link, profile), 16)
equal(weightedCalls, beforeCalls, "temporary partial values reuse their static and average totals")

local overflow = fixture("item:113:0", {onUseStats={strength=2}, effects={effect()}})
local extreme = assert(FW:CreateProfile("Extreme", {strength=1e308}))
local invalidAverage, invalidError, _, invalidMetadata = FW:GetAverageUseScore(overflow.link, extreme)
equal(invalidAverage, nil); contains(invalidError, "not finite")
check(invalidMetadata.hasAverageUse and invalidMetadata.averageUseIncomplete)
equal(FW:GetScore(overflow.link, extreme), 0, "an overflowing average does not poison the finite static total")
local overflowAddition = fixture("item:115:0", {stats={strength=1e308}, onUseStats={strength=1e308}, effects={effect()}})
local large = assert(FW:CreateProfile("Large values", {strength=1}))
equal(FW:GetBaseScore(overflowAddition.link, large), 1e308, "base total remains finite before adding the average gain")
invalidAverage, invalidError, _, invalidMetadata = FW:GetAverageUseScore(overflowAddition.link, large)
equal(invalidAverage, nil); contains(invalidError, "not finite")
check(invalidMetadata.hasAverageUse and invalidMetadata.averageUseIncomplete)
equal(invalidMetadata.averageUseGain, 1e308)
local invalidComparison, comparisonError, comparisonMetadata = FW:CompareAverageUseItem(overflowAddition.link, large)
equal(invalidComparison, nil); contains(comparisonError, "not finite")
check(comparisonMetadata.hasAverageUse and comparisonMetadata.averageUseIncomplete, "candidate overflow metadata reaches the tooltip caller")
inventory[13], inventory[14] = overflowAddition.link, nil
local failedBaseline = assert(FW:CompareAverageUseItem(passiveCandidate.link, large))
check(failedBaseline.hasAverageUse and failedBaseline.averageUseIncomplete, "equipped overflow metadata reaches the candidate result")
contains(failedBaseline.comparisons[1].error, "not finite")
equal(failedBaseline.comparisons[1].delta, nil)
local invalidProfile, invalidProfileError = FW:GetAverageUseScore(base.link, "missing profile")
equal(invalidProfile, nil); contains(invalidProfileError, "Profile not found")
local invalidItem, invalidItemError = FW:GetAverageUseScore("enchant:9968", profile)
equal(invalidItem, nil); contains(invalidItemError, "Invalid item link")

print("On-use scoring/comparison: " .. checks .. " checks passed.")
