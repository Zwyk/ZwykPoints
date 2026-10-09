-- Run from the addon directory: luatex --luaonly tests/test_crit_units.lua
-- The screenshot shows a 0.5% crit tooltip and a score of 81.35. Its raw API
-- table was not supplied: 7 rating is the value inferred from that score.
-- These fixtures verify unit selection and caching, not live client conversion.
local checks = 0
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function approx(actual, expected, message)
    checks = checks + 1
    assert(actual and math.abs(actual - expected) < 0.000001,
        (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local candidate, baseline = "item:273042", "item:200001"
local fixtures = {
    [candidate] = {
        name = "Manascale Treads", raw = {
            RESISTANCE0_NAME = 157, ITEM_MOD_STRENGTH_SHORT = 7, ITEM_MOD_INTELLECT_SHORT = 7,
            ITEM_MOD_CRIT_RATING_SHORT = 7, ITEM_MOD_CRIT_RATING = 7,
            ITEM_MOD_CRIT_MELEE_RATING_SHORT = 7, ITEM_MOD_CRIT_SPELL_RATING_SHORT = 7,
            ITEM_MOD_CRIT_RANGED_RATING_SHORT = 7,
        }, lines = {
            "157 Armor", "+7 Strength", "+7 Intellect",
            "Equip: Improves your chance to get a critical strike by 0.5%.",
        },
    },
    [baseline] = {
        name = "Equipped caster boots", raw = {ITEM_MOD_SPELL_POWER_SHORT = 20},
        lines = {"Equip: Increases damage and healing done by magical spells and effects by up to 20."},
    },
}
local reads, scans, scoreCalls = 0, 0, 0
GetBuildInfo = function() return "1.60.1", "70291", "Oct 7 2026", 16001 end
GetLocale = function() return "enUS" end
UnitLevel = function() return 30 end
UnitClass = function() return "Paladin", "PALADIN", 2 end
GetTime, GetItemInfoInstant, GetItemStats, CreateFrame = nil, nil, nil, nil
local function fixture(link)
    return assert(fixtures[link], "Unexpected item " .. tostring(link))
end
GetItemInfo = function(link)
    local item = fixture(link)
    return item.name, link, 3, 33, 28, "Armor", "Mail", 1, "INVTYPE_FEET", 123, 0, 4, 3
end
GetInventoryItemLink = function(_, slot) if slot == 8 then return baseline end end
C_Item = {
    GetItemInfo = GetItemInfo,
    IsItemDataCachedByID = function() return true end,
    GetItemStats = function(link) reads = reads + 1; return fixture(link).raw end,
}
C_TooltipInfo = {GetHyperlink = function(link)
    scans = scans + 1
    local item = fixture(link)
    local lines = {{leftText = item.name, type = 22}}
    for _, text in ipairs(item.lines) do lines[#lines + 1] = {leftText = text, type = 0} end
    return {lines = lines}
end}
ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
local FW = {}
for _, file in ipairs({"JSON.lua", "Stats.lua", "Core.lua", "Items.lua", "Compare.lua", "Upgrades.lua"}) do
    assert(loadfile(file))("ZwykValues", FW)
end
FW:Initialize()
local scoreStats = FW.ScoreStats
function FW:ScoreStats(profile, stats)
    scoreCalls = scoreCalls + 1
    return scoreStats(self, profile, stats)
end
local profile = assert(FW:CreateProfile("Mageladin", {
    agility = 0.01, armor = 0.05, armorBonus = 0.05, attackPower = 0.1,
    block = 0.01, blockValue = 0.1, blockValueBonus = 0.1, crit = 10,
    defense = 0.01, dodge = 0.01, dps = 1, expertise = 10, haste = 10, hit = 10,
    holyDamage = 1, intellect = 0.3, parry = 0.01, spellDamage = 1,
    spellPen = 0.1, spirit = 0.01, stamina = 0.01, strength = 0.2,
}))
assert(FW:UpdateProfile(profile.id, {secondaryUnit = "rating"}))
assert(FW:SetMainProfile(profile.id))
local score, item, detail = FW:GetScore(candidate, profile)
equal(detail, nil)
equal(item.partial, false)
equal(item.ratingStats.crit, 7, "generic, scoped and unsuffixed aliases count once")
equal(item.percentStats.crit, 0.5, "tooltip percentage stays separate from native rating")
equal(item.percentStats.hit, nil, "critical strike does not supply hit chance")
equal(item.stats.crit, nil)
approx(score, 81.35, "rating mode: 11.35 static + 7 rating times 10")
approx(FW:GetScore(candidate, profile), 81.35)
equal(reads, 1); equal(scans, 1); equal(scoreCalls, 1, "repeated score is cached")
local comparison = assert(FW:CompareItem(candidate, profile))
approx(comparison.comparisons[1].baseline, 20)
approx(comparison.comparisons[1].delta, 61.35)
equal(comparison.comparisons[1].status, "upgrade")
equal(FW:IsMainProfileUpgrade(candidate), true)
equal(FW:IsMainProfileUpgrade(candidate), true)
equal(reads, 2); equal(scans, 2); equal(scoreCalls, 2)

-- Changing units retains the weight, invalidates only calculated totals and
-- refreshes the memoized upgrade decision without reading either item again.
local oldRevision = profile.revision
assert(FW:UpdateProfile(profile.id, {secondaryUnit = "percent"}))
equal(profile.revision, oldRevision + 1)
equal(profile.weights.crit, 10, "unit changes never rewrite profile weights")
equal((FW.DB.cache.scores[item.key] or {})[profile.id], nil)
approx(FW:GetScore(candidate, profile), 16.35, "percentage mode: 11.35 static + 0.5 percentage point times 10")
comparison = assert(FW:CompareItem(candidate, profile))
approx(comparison.comparisons[1].baseline, 20)
approx(comparison.comparisons[1].delta, -3.65)
equal(comparison.comparisons[1].status, "downgrade")
equal(FW:IsMainProfileUpgrade(candidate), false, "previous rating-mode upgrade memo is invalidated")
equal(FW:IsMainProfileUpgrade(candidate), false)
equal(reads, 2); equal(scans, 2); equal(scoreCalls, 4)
equal(FW.DB.cache.scores[item.key][profile.id].revision, profile.revision)
equal(FW:GetIssueReport().itemCount, 0)

assert(FW:UpdateProfile(profile.id, {secondaryUnit = "rating"}))
approx(FW:GetScore(candidate, profile), 81.35)
equal(FW:IsMainProfileUpgrade(candidate), true)
equal(reads, 2); equal(scans, 2); equal(scoreCalls, 6)
print("Crit unit tests passed (" .. checks .. " checks)")
