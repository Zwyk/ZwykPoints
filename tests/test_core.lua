-- Run from the addon directory: lua tests/test_core.lua .
local addonPath = (arg and arg[1]) or "."
local FW = {}
assert(loadfile(addonPath .. "/JSON.lua"))("ZwykValues", FW)
assert(loadfile(addonPath .. "/Stats.lua"))("ZwykValues", FW)
assert(loadfile(addonPath .. "/Core.lua"))("ZwykValues", FW)

local passed = 0
local function check(value, message)
    assert(value, message or "assertion failed")
    passed = passed + 1
end
local function equal(actual, expected, message)
    check(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(value, pattern)
    check(type(value) == "string" and value:find(pattern, 1, true), "Expected error containing '" .. pattern .. "', got " .. tostring(value))
end
local function reset()
    ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB, FW.DB = nil, nil, nil, nil
    FW:Initialize()
end

local json = FW.JSON
local decoded, errorMessage = json.Decode('{"text":"Félix \\uD83D\\uDE00","array":[null,false,0],"empty":{}}')
check(decoded, errorMessage)
equal(decoded.text, "Félix " .. string.char(0xF0, 0x9F, 0x98, 0x80))
equal(decoded.array[1], json.null)
equal(decoded.array[2], false)
equal(decoded.array[3], 0)
local encoded = assert(json.Encode(decoded))
local roundtrip = assert(json.Decode(encoded))
equal(#roundtrip.array, 3)
equal(assert(json.Encode(roundtrip.empty)), "{}")
equal(assert(json.Encode(json.array())), "[]")
local malformed = {
    '{"strength":1,"strength":2}', '{"strength":1,}', '[1,]', '01', '-01',
    '1.', '.5', '1e', '1e999', 'NaN', 'true false', '"\\uD800"', '"\\uDC00"',
    '"\\x12"', '"' .. string.char(0xC0, 0xAF) .. '"',
}
for _, source in ipairs(malformed) do
    local value, parseError = json.Decode(source)
    equal(value, nil, "malformed JSON must be rejected: " .. source)
    check(type(parseError) == "string")
end
local circular = {}
circular.self = circular
equal(json.Encode(circular), nil)
equal(json.Encode({ value = math.huge }), nil)

reset()
local default = FW:GetProfiles()[1]
equal(default.name, "My profile")
equal(default.secondaryUnit, "percent")
equal(#FW:GetProfiles(true), 1)
for _, definition in ipairs(FW.StatDefinitions) do equal(default.weights[definition.key], 0) end

local profile = assert(FW:CreateProfile("  My weights  ", { strength = 2, agility = -0.5, hit = 3 }))
equal(profile.name, "My weights")
equal(FW:ScoreStats(profile, { strength = 12, agility = 4, hit = 1 }), 25)
local revision = profile.revision
assert(FW:UpdateProfile(profile.id, { name = "Renamed", color = { r = 1, g = 0, b = 0 } }))
equal(profile.revision, revision, "display edits keep cached scores valid")
assert(FW:UpdateProfile(profile.id, { weights = { strength = 3 } }))
equal(profile.weights.agility, -0.5, "partial weight edits preserve other weights")
equal(profile.revision, revision + 1)
local before = profile.name
local result, updateError = FW:UpdateProfile(profile.id, { name = "Mutation", weights = { unknown = 1 } })
equal(result, nil)
contains(updateError, "Unknown stat")
equal(profile.name, before, "invalid updates are atomic")
equal(FW:CreateProfile("Invalid", { strength = math.huge }), nil)
equal(FW:UpdateProfile(profile.id, { color = { r = 2, g = 0, b = 0 } }), nil)

local bare = assert(FW:ExportProfile(profile.id, true))
local bareObject = assert(json.Decode(bare))
local keyCount = 0
for key in pairs(bareObject) do
    check(FW.StatByKey[key], "export contains only canonical keys")
    keyCount = keyCount + 1
end
equal(keyCount, #FW.StatDefinitions, "exports retain every zero-weight stat")
local imported, importError, warnings = FW:ImportProfile(bare, "Imported")
check(imported, importError)
equal(imported.weights.strength, 3)
equal(imported.name, "Imported")
check(#warnings > 0, "bare imports explain unit assumptions")
assert(FW:UpdateProfile(profile.id, { secondaryUnit = "rating", active = false }))
local envelope = assert(FW:ExportProfile(profile.id))
equal(assert(json.Decode(envelope)).format, "ZwykValues", "new exports use the renamed format")
local restored = assert(FW:ImportProfile(envelope))
equal(restored.name, profile.name)
equal(restored.secondaryUnit, "rating")
equal(restored.color.r, 1)
for _, legacyFormat in ipairs({ "ZwykPoints", "ForeverWeights" }) do
    local legacyEnvelope = envelope:gsub('"format":"ZwykValues"', '"format":"' .. legacyFormat .. '"')
    local legacy = assert(FW:ImportProfile(legacyEnvelope))
    equal(legacy.name, profile.name, "legacy profile names are preserved")
    equal(legacy.weights.strength, 3, "legacy profile weights are preserved")
    equal(legacy.secondaryUnit, "rating", "legacy profile units are preserved")
    equal(legacy.color.r, 1, "legacy profile colors are preserved")
    equal(assert(json.Decode(assert(FW:ExportProfile(legacy.id)))).format, "ZwykValues", "legacy imports re-export with the new format")
end
local empty = assert(FW:ImportProfile("{}", "Empty"))
equal(FW:ScoreStats(empty, { strength = 100 }), 0)
local badImports = {
    '[]', 'null', 'false', '{"spellingMistake":1}', '{"strength":null}', '{"strength":"2"}',
    '{"format":"ZwykValues","version":2,"weights":{}}',
    '{"format":"ZwykValues","version":1,"weights":{},"secondaryUnit":"guessed"}',
}
for _, source in ipairs(badImports) do
    local count = #FW:GetProfiles()
    local value, importFailure = FW:ImportProfile(source)
    equal(value, nil)
    check(type(importFailure) == "string", "invalid imports explain failure")
    equal(#FW:GetProfiles(), count, "invalid imports do not create profiles")
end
local copied = assert(FW:CopyProfile(profile.id))
check(copied.id ~= profile.id)
equal(copied.secondaryUnit, profile.secondaryUnit)
equal(copied.active, false)
copied.weights.strength = 123
equal(profile.weights.strength, 3, "copies own their weight table")
copied.color.g = 1
equal(profile.color.g, 0, "copies own their color table")
assert(FW:DeleteProfile(copied.id))
equal(FW.DB.profiles[copied.id], nil)
local longNamed = assert(FW:CreateProfile("A" .. string.rep("é", 79), {}))
local longCopy = assert(FW:CopyProfile(longNamed.id))
check(FW:ExportProfile(longCopy.id), "copying a long Unicode name does not split its UTF-8 characters")

local legacyDB = FW.DB
legacyDB.options.debugUnknownStats = true
local legacyProfile = legacyDB.profiles[profile.id]
ForeverWeightsDB, ZwykValuesDB, FW.DB = legacyDB, nil, nil
FW:Initialize()
check(FW.DB ~= legacyDB, "legacy migration creates an independent database")
check(FW.DB.profiles[profile.id] ~= legacyProfile, "migrated profiles are independent")
equal(FW.DB.profiles[profile.id].weights.strength, 3, "legacy migration preserves weights")
equal(FW.DB.profiles[profile.id].secondaryUnit, "rating", "legacy migration preserves units")
equal(FW.DB.profiles[profile.id].active, false, "legacy migration preserves activation")
equal(FW.DB.options.debugUnknownStats, true, "legacy migration preserves options")
assert(FW:UpdateProfile(profile.id, { weights = { strength = 42 }, color = { r = 0, g = 1, b = 0 } }))
equal(legacyProfile.weights.strength, 3, "migrated edits do not modify the old weights")
equal(legacyProfile.color.r, 1, "migrated edits do not modify the old colors")
local migratedDB = FW.DB
FW.DB = nil
FW:Initialize()
equal(FW.DB, migratedDB, "an existing ZwykValues database takes precedence over legacy data")
equal(FW.DB.profiles[profile.id].weights.strength, 42, "reinitializing does not reimport legacy weights")

-- The immediately previous addon database takes precedence over the original.
ZwykPointsDB, ZwykValuesDB, FW.DB = migratedDB, nil, nil
FW:Initialize()
check(FW.DB ~= ZwykPointsDB, "ZwykPoints migration creates an independent database")
equal(FW.DB.profiles[profile.id].weights.strength, 42, "ZwykPoints takes precedence over ForeverWeights")
check(FW.DB.options ~= ZwykPointsDB.options, "migrated options are independent")
check(FW.DB.cache ~= ZwykPointsDB.cache, "migrated cache is independent")
assert(FW:UpdateProfile(profile.id, { weights = { strength = 50 } }))
equal(ZwykPointsDB.profiles[profile.id].weights.strength, 42, "migrated edits do not modify ZwykPoints weights")
FW.DB = nil
FW:Initialize()
equal(FW.DB.profiles[profile.id].weights.strength, 50, "existing ZwykValues takes precedence over both legacy databases")

reset()
local records, itemReads, scoreCalls = {}, 0, 0
function FW:ItemKey(link) return link end
function FW:GetItem(link)
    local cached = self.DB.cache.items[link]
    if cached then return cached end
    itemReads = itemReads + 1
    if records[link] then
        records[link].equipLoc = "INVTYPE_HEAD"
        records[link].classID, records[link].subclassID = 4, 4
    end
    return records[link], records[link] and nil or "Item is loading."
end
local baseScoreStats = FW.ScoreStats
function FW:ScoreStats(selectedProfile, stats)
    scoreCalls = scoreCalls + 1
    return baseScoreStats(self, selectedProfile, stats)
end
local weighted = assert(FW:CreateProfile("Test", { strength = 2, hit = 10 }))
records.itemA = { key = "itemA", link = "itemA", stats = { strength = 4 }, percentStats = { hit = 1 }, ratingStats = { hit = 12 }, warnings = {} }
local score, record = FW:GetScore("itemA", weighted)
equal(score, 18)
equal(record, records.itemA)
equal(FW:GetScore("itemA", weighted), 18)
equal(scoreCalls, 1, "repeat tooltip scores use the local cache")
equal(itemReads, 1, "item cache is reused")
assert(FW:UpdateProfile(weighted.id, { color = { r = 0, g = 1, b = 0 } }))
equal(FW:GetScore("itemA", weighted), 18)
equal(scoreCalls, 1, "color edits do not calculate another score")
assert(FW:UpdateProfile(weighted.id, { weights = { strength = 3 } }))
equal(FW:GetScore("itemA", weighted), 22)
equal(scoreCalls, 2, "weight edits invalidate score without reparsing item")
equal(itemReads, 1)
assert(FW:UpdateProfile(weighted.id, { secondaryUnit = "rating" }))
equal(FW:GetScore("itemA", weighted), 132)
local second = assert(FW:CreateProfile("Second", { strength = 1 }))
equal(FW:GetScore("itemA", second), 4)
equal(FW.DB.cache.scores.itemA[weighted.id].score, 132)
equal(FW.DB.cache.scores.itemA[second.id].score, 4, "scores are independent for each profile")

records.noSecondary = { key = "noSecondary", stats = { strength = 2 }, percentStats = {}, ratingStats = {}, warnings = {} }
equal(FW:GetScore("noSecondary", weighted), 6, "a stat absent from an item contributes zero")
records.percentOnly = { key = "percentOnly", stats = {}, percentStats = { hit = 1 }, ratingStats = {}, warnings = {} }
local unavailable, unavailableError = FW:GetScore("percentOnly", weighted)
equal(unavailable, 0, "known subtotal is shown when the selected secondary unit is missing")
contains(FW:ItemIssueSummary(unavailableError, weighted), "rating points")
check(not unavailableError.partial, "a profile unit mismatch does not corrupt the parsed item record")
check(FW:ItemHasIssues(unavailableError, weighted), "the affected profile receives a score-specific warning")
check(not FW:ItemHasIssues(unavailableError, second), "an unweighted unit mismatch does not affect a different profile")
equal(FW.DB.cache.scores.percentOnly, nil, "partial unit calculations are never cached")
records.unresolved = { key = "unresolved", stats = {}, percentStats = {}, ratingStats = {}, unresolvedStats = { hit = true }, partial = true, warnings = { "Unknown hit unit" } }
local unresolvedScore, unresolvedError = FW:GetScore("unresolved", weighted)
equal(unresolvedScore, 0)
contains(FW:ItemIssueSummary(unresolvedError, weighted), "unavailable")
equal(FW:GetScore("unresolved", second), 0, "unweighted unknown secondary stats do not prevent scoring")
records.partial = { key = "partial", stats = { strength = 5 }, percentStats = {}, ratingStats = {}, partial = true, warnings = { "Proc is unweighted" } }
local partialScore, partialRecord = FW:GetScore("partial", second)
equal(partialScore, 5)
check(partialRecord.partial, "item warnings remain available to the tooltip")
equal(FW.DB.cache.items.partial, nil, "partial item reads are not persisted")
equal(FW.DB.cache.scores.partial, nil, "partial scores are not persisted")
local partialReadsBefore, partialCallsBefore = itemReads, scoreCalls
equal(FW:GetScore("partial", second), 5)
equal(itemReads, partialReadsBefore + 1, "partial item data is read again")
equal(scoreCalls, partialCallsBefore + 1, "partial totals are recalculated as data becomes available")
records.unresolvedBase = { key = "unresolvedBase", stats = {}, percentStats = {}, ratingStats = {}, unresolvedStats = { strength = true }, partial = true }
local baseFailure, baseError = FW:GetScore("unresolvedBase", second)
equal(baseFailure, 0, "an unavailable base stat contributes zero to the known subtotal")
contains(FW:ItemIssueSummary(baseError, second), "could not be read completely")
records.knownBase = { key = "knownBase", stats = { strength = 3 }, unresolvedStats = { strength = true }, partial = true }
local knownSubtotal, knownRecord = FW:GetScore("knownBase", second)
equal(knownSubtotal, 3, "reliable API values survive a partially unreadable tooltip for the same stat")
check(knownRecord.scoreIssues[second.id].missingStats.strength)
local report = FW:GetIssueReport()
equal(report.format, "ZwykValuesIssues")
check(report.itemCount >= 5, "all encountered issue variants are journaled")
local knownEntry = FW.DB.itemIssues.knownBase
equal(knownEntry.profileScores[second.id].score, 3, "export contains the calculated known subtotal")
equal(knownEntry.profileScores[second.id].name, second.name)
equal(knownEntry.profileScores[second.id].revision, second.revision)
equal(knownEntry.profileScores[second.id].partial, true)
check(json.Encode(report), "combined diagnostics are valid JSON")
records.resolvedUnit = { key = "resolvedUnit", stats = { strength = 2 }, ratingStats = { hit = 12 },
    percentStats = {}, unresolvedStats = { hit = true }, partial = true, warnings = { "Unknown API field" } }
local unitFixProfile = assert(FW:CreateProfile("Fix units", { strength = 1, hit = 2 }))
equal(FW:GetScore("resolvedUnit", unitFixProfile), 2)
check(FW.DB.itemIssues.resolvedUnit.scoreIssues[unitFixProfile.id], "missing percentage contribution is recorded")
assert(FW:UpdateProfile(unitFixProfile.id, { secondaryUnit = "rating" }))
equal(FW:GetScore("resolvedUnit", unitFixProfile), 26)
equal(FW.DB.itemIssues.resolvedUnit.scoreIssues[unitFixProfile.id], nil, "recomputed successful unit selection removes the old profile warning")
equal(FW.DB.itemIssues.resolvedUnit.profileScores[unitFixProfile.id].score, 26)
local missing, missingError = FW:GetScore("notLoaded", second)
equal(missing, nil)
contains(missingError, "loading")

local savedDB, readsBefore, callsBefore = FW.DB, itemReads, scoreCalls
FW.DB = nil
FW:Initialize()
equal(FW.DB, savedDB)
equal(FW:GetScore("itemA", weighted), 132)
equal(scoreCalls, callsBefore, "persistent scores survive reinitialization")
equal(itemReads, readsBefore)
check(FW:InvalidateItem("itemA"))
equal(FW.DB.cache.items.itemA, nil)
equal(FW.DB.cache.scores.itemA, nil)
equal(FW:GetScore("itemA", weighted), 132)
equal(itemReads, readsBefore + 1)
FW:InvalidateCache()
equal(FW:GetCacheCount(), 0)
equal(next(FW.DB.cache.scores), nil)
equal(FW.DB.itemIssues.knownBase.profileScores[second.id].score, 3, "clearing the normal cache preserves problem items")

for index = 1, FW.CACHE_LIMIT + 5 do
    local key = "bounded" .. index
    records[key] = { key = key, stats = { strength = index }, percentStats = {}, ratingStats = {}, warnings = {} }
    equal(FW:GetScore(key, second), index)
end
equal(FW:GetCacheCount(), FW.CACHE_LIMIT)
equal(#FW.DB.cache.itemOrder, FW.CACHE_LIMIT)
equal(FW.DB.cache.items.bounded1, nil)
equal(FW.DB.cache.scores.bounded1, nil, "evicting an item also evicts its profile scores")
check(FW.DB.cache.items.bounded2005)
check(FW.DB.itemIssues.knownBase, "normal cache eviction preserves diagnostic history")
assert(FW:DeleteProfile(second.id))
for _, scores in pairs(FW.DB.cache.scores) do equal(scores[second.id], nil) end
FW:ClearItemIssues()
equal(FW:GetIssueReport().itemCount, 0)
contains(assert(json.Encode(FW:GetIssueReport())), '"items":[]')

print("Core/JSON: " .. passed .. " checks passed.")
