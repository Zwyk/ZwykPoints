local _, FW = ...

FW.CACHE_LIMIT = 2000
FW.CACHE_VERSION = 2
local secondaryKeys = { hit = true, crit = true, haste = true, expertise = true, defense = true, dodge = true, parry = true, block = true }
FW.SecondaryStatKeys = secondaryKeys
local upgradeOptions = { upgradeBags = true, upgradeRolls = true, upgradeChat = true }
local defaultColor = { r = 0.35, g = 0.8, b = 1 }
-- Character gear and ammunition; storage and profession slots are excluded.
local gearEquipLocations = {
    INVTYPE_HEAD=true, INVTYPE_NECK=true, INVTYPE_SHOULDER=true, INVTYPE_BODY=true,
    INVTYPE_CHEST=true, INVTYPE_ROBE=true, INVTYPE_WAIST=true, INVTYPE_LEGS=true,
    INVTYPE_FEET=true, INVTYPE_WRIST=true, INVTYPE_HAND=true, INVTYPE_FINGER=true,
    INVTYPE_TRINKET=true, INVTYPE_CLOAK=true, INVTYPE_WEAPON=true,
    INVTYPE_WEAPONMAINHAND=true, INVTYPE_WEAPONOFFHAND=true, INVTYPE_2HWEAPON=true,
    INVTYPE_SHIELD=true, INVTYPE_HOLDABLE=true, INVTYPE_RANGED=true,
    INVTYPE_RANGEDRIGHT=true, INVTYPE_THROWN=true, INVTYPE_RELIC=true, INVTYPE_TABARD=true,
}

function FW:IsGearItem(record)
    if not record then return nil, "Item equipment data is not available yet." end
    if record.classID ~= nil and record.classID ~= 2 and record.classID ~= 4 and record.classID ~= 6 then return false end
    local equipLoc = record.equipLoc
    if (issecretvalue and issecretvalue(equipLoc)) or type(equipLoc) ~= "string" then
        return nil, "Item equipment data is not available yet."
    end
    if equipLoc == "INVTYPE_AMMO" then return record.classID == nil or record.classID == 6 end
    if record.classID == 6 then return false end
    return gearEquipLocations[equipLoc] == true
end

-- Stable client subclass IDs keep saved filters independent of locale.
FW.ItemFilterGroups = {
    {key="weapons", label="Weapon types", classID=2, types={
        {key="0",label="One-handed axes"}, {key="1",label="Two-handed axes"},
        {key="2",label="Bows"}, {key="3",label="Guns"},
        {key="4",label="One-handed maces"}, {key="5",label="Two-handed maces"},
        {key="6",label="Polearms"}, {key="7",label="One-handed swords"},
        {key="8",label="Two-handed swords"}, {key="9",label="Warglaives"},
        {key="10",label="Staves"}, {key="13",label="Fist weapons"},
        {key="14",label="Other weapons"}, {key="15",label="Daggers"},
        {key="16",label="Thrown weapons"}, {key="18",label="Crossbows"},
        {key="19",label="Wands"}, {key="20",label="Fishing poles"},
    }},
    {key="armor", label="Armor types", classID=4, types={
        {key="0",label="Miscellaneous armor / accessories"}, {key="1",label="Cloth"},
        {key="2",label="Leather"}, {key="3",label="Mail"}, {key="4",label="Plate"},
        {key="5",label="Cosmetic armor"}, {key="6",label="Shields"},
        {key="7",label="Librams"}, {key="8",label="Idols"}, {key="9",label="Totems"},
        {key="10",label="Sigils"}, {key="11",label="Relics"},
    }},
}

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function plainObject(value)
    if type(value) ~= "table" or value == FW.JSON.null then return false end
    local meta = getmetatable(value)
    if meta and meta.__jsonType and meta.__jsonType ~= "object" then return false end
    for key in pairs(value) do if type(key) ~= "string" then return false end end
    return true
end

local function cloneItemFilters(source)
    source = type(source) == "table" and source or {}
    local result = {includeOtherClasses=source.includeOtherClasses ~= false}
    for _, group in ipairs(FW.ItemFilterGroups) do
        local values = type(source[group.key]) == "table" and source[group.key] or {}
        result[group.key] = {}
        for _, itemType in ipairs(group.types) do
            result[group.key][itemType.key] = values[itemType.key] ~= false
        end
    end
    return result
end

local function validItemFilters(changes, current)
    if not plainObject(changes) then return nil, "Item filters must be a JSON object." end
    local result = cloneItemFilters(current)
    local groups = {}
    for _, group in ipairs(FW.ItemFilterGroups) do groups[group.key] = group end
    for key, value in pairs(changes) do
        if key == "includeOtherClasses" then
            if type(value) ~= "boolean" then return nil, "Include other classes must be true or false." end
            result[key] = value
        elseif groups[key] then
            if not plainObject(value) then return nil, "Filter types must be a JSON object." end
            for typeKey, checked in pairs(value) do
                if result[key][typeKey] == nil then return nil, "Unknown " .. key .. " type '" .. typeKey .. "'." end
                if type(checked) ~= "boolean" then return nil, "Item type filters must be true or false." end
                result[key][typeKey] = checked
            end
        else
            return nil, "Unknown item filter '" .. key .. "'."
        end
    end
    return result
end

local function itemFiltersEqual(left, right)
    if left.includeOtherClasses ~= right.includeOtherClasses then return false end
    for _, group in ipairs(FW.ItemFilterGroups) do
        for _, itemType in ipairs(group.types) do
            if left[group.key][itemType.key] ~= right[group.key][itemType.key] then return false end
        end
    end
    return true
end

function FW:IsItemAllowed(record, profile)
    local filters = profile.itemFilters
    if not filters then return true end
    local function hasExclusions(group)
        for _, checked in pairs(group or {}) do if checked == false then return true end end
        return false
    end
    local group = record.classID == 2 and filters.weapons or record.classID == 4 and filters.armor
    if record.classID == nil and record.equipLoc ~= "INVTYPE_AMMO"
        and (hasExclusions(filters.weapons) or hasExclusions(filters.armor)) then
        return nil, "Item type data is not available yet."
    end
    if group then
        if record.subclassID == nil and hasExclusions(group) then
            return nil, "Item subtype data is not available yet."
        end
        if group[tostring(record.subclassID)] == false then return false end
    end
    if filters.includeOtherClasses == false then
        local allowed = record.allowedClasses
        if allowed then
            local _, playerClass
            if UnitClass then _, playerClass = UnitClass("player") end
            if issecretvalue and issecretvalue(playerClass) then playerClass = nil end
            if playerClass and allowed[playerClass] then return true end
            if not playerClass then return nil, "Player class data is not available yet." end
            if record.classRestrictionsKnown then return false end
        elseif record.classRestrictionsKnown then return true end
        return nil, "Item class restrictions could not be read yet."
    end
    return true
end

local function cloneWeights(weights)
    local result = {}
    for _, definition in ipairs(FW.StatDefinitions) do result[definition.key] = (weights and weights[definition.key]) or 0 end
    return result
end

local function copySavedTable(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, child in pairs(value) do result[key] = copySavedTable(child, seen) end
    return result
end

local function validWeights(weights)
    if not plainObject(weights) then return nil, "Weights must be a JSON object of stat names and numbers." end
    local unknown = {}
    for key, value in pairs(weights) do
        if not FW.StatByKey[key] then
            unknown[#unknown + 1] = key
        elseif not finite(value) then
            return nil, "Weight for '" .. key .. "' must be a finite number."
        end
    end
    if #unknown > 0 then
        table.sort(unknown)
        return nil, "Unknown stat key(s): " .. table.concat(unknown, ", ") .. "."
    end
    return cloneWeights(weights)
end

local function validName(name)
    if type(name) ~= "string" then return nil, "Profile name must be text." end
    name = name:match("^%s*(.-)%s*$")
    if name == "" then return nil, "Enter a profile name." end
    if #name > 160 then return nil, "Profile names must be at most 160 bytes." end
    if name:find("[%z\1-\31\127]") then return nil, "Profile names cannot contain control characters." end
    return name
end

local function validColor(color)
    if not plainObject(color) then return nil, "Color must contain r, g and b channels." end
    for key in pairs(color) do if key ~= "r" and key ~= "g" and key ~= "b" then return nil, "Unknown color channel '" .. key .. "'." end end
    local result = {}
    for _, channel in ipairs({ "r", "g", "b" }) do
        if not finite(color[channel]) or color[channel] < 0 or color[channel] > 1 then return nil, "Color channels must be numbers between 0 and 1." end
        result[channel] = color[channel]
    end
    return result
end

local function validUnit(unit)
    if unit ~= "percent" and unit ~= "rating" then return nil, "Secondary stat unit must be 'percent' or 'rating'." end
    return unit
end

local function blankCache()
    local order = {}
    return { version = FW.CACHE_VERSION, items = {}, scores = {}, itemOrder = order, order = order }
end

local function trimCache(cache)
    local order, seen = {}, {}
    local oldOrder = type(cache.itemOrder) == "table" and cache.itemOrder or cache.order
    if type(oldOrder) == "table" then
        for _, key in ipairs(oldOrder) do
            if type(key) == "string" and cache.items[key] and not seen[key] then
                order[#order + 1] = key
                seen[key] = true
            end
        end
    end
    local missing = {}
    for key, record in pairs(cache.items) do
        if type(key) ~= "string" or type(record) ~= "table" or record.key ~= key then
            cache.items[key] = nil
            cache.scores[key] = nil
        elseif not seen[key] then
            missing[#missing + 1] = key
        end
    end
    table.sort(missing)
    for _, key in ipairs(missing) do order[#order + 1] = key end
    while #order > FW.CACHE_LIMIT do
        local key = table.remove(order, 1)
        cache.items[key], cache.scores[key] = nil, nil
    end
    for key in pairs(cache.scores) do if not cache.items[key] then cache.scores[key] = nil end end
    cache.itemOrder, cache.order = order, order
end

function FW:Initialize()
    if self.DB then return self.DB end
    -- The old addon's SavedVariables are only available if that addon loaded.
    -- Copy them once so both addons never share mutable profile/cache tables.
    if ZwykValuesDB == nil then
        local legacy = type(_G.ZwykPointsDB) == "table" and _G.ZwykPointsDB or _G.ForeverWeightsDB
        if type(legacy) == "table" then ZwykValuesDB = copySavedTable(legacy) end
    end
    local db = type(ZwykValuesDB) == "table" and ZwykValuesDB or {}
    ZwykValuesDB, self.DB = db, db
    db.schemaVersion = 1
    db.profiles = type(db.profiles) == "table" and db.profiles or {}
    db.profileOrder = type(db.profileOrder) == "table" and db.profileOrder or {}
    db.nextProfileID = finite(db.nextProfileID) and math.max(1, math.floor(db.nextProfileID)) or 1
    db.options = type(db.options) == "table" and db.options or {}
    if db.options.showComparisons == nil then db.options.showComparisons = true end
    for key in pairs(upgradeOptions) do db.options[key] = db.options[key] == true end
    -- Diagnostics have their own lifetime: cache eviction or clearing cached
    -- scores must not discard the problem items the user wants to export.
    db.itemIssues = type(db.itemIssues) == "table" and db.itemIssues or {}
    for key, entry in pairs(db.itemIssues) do
        if type(key) ~= "string" or type(entry) ~= "table" then db.itemIssues[key] = nil end
    end
    local normalized, seen = {}, {}
    local function restore(id, profile)
        if type(id) ~= "string" or type(profile) ~= "table" or seen[id] then return end
        local name = validName(profile.name)
        if not name then db.profiles[id] = nil return end
        local weights = {}
        for _, definition in ipairs(self.StatDefinitions) do
            local value = type(profile.weights) == "table" and profile.weights[definition.key]
            weights[definition.key] = finite(value) and value or 0
        end
        profile.id, profile.name, profile.weights = id, name, weights
        profile.active = profile.active ~= false
        profile.color = validColor(profile.color) or { r = defaultColor.r, g = defaultColor.g, b = defaultColor.b }
        profile.secondaryUnit = validUnit(profile.secondaryUnit) or "percent"
        profile.itemFilters = cloneItemFilters(profile.itemFilters)
        profile.revision = finite(profile.revision) and math.max(1, math.floor(profile.revision)) or 1
        normalized[#normalized + 1], seen[id] = id, true
    end
    for _, id in ipairs(db.profileOrder) do restore(id, db.profiles[id]) end
    local remainder = {}
    for id in pairs(db.profiles) do
        if type(id) == "string" and not seen[id] then remainder[#remainder + 1] = id
        elseif type(id) ~= "string" then db.profiles[id] = nil end
    end
    table.sort(remainder)
    for _, id in ipairs(remainder) do restore(id, db.profiles[id]) end
    db.profileOrder = normalized
    if type(db.options.mainProfileID) ~= "string" or not db.profiles[db.options.mainProfileID] then
        db.options.mainProfileID = nil
    end
    local cache = db.cache
    if type(cache) ~= "table" or cache.version ~= self.CACHE_VERSION then
        db.cache = blankCache()
    else
        cache.items = type(cache.items) == "table" and cache.items or {}
        cache.scores = type(cache.scores) == "table" and cache.scores or {}
        trimCache(cache)
    end
    if #db.profileOrder == 0 then
        -- This is deliberately a zero-weight profile, not a guessed class preset.
        self:CreateProfile("My profile", {})
    end
    return db
end

function FW:GetProfiles(activeOnly)
    self:Initialize()
    local profiles = {}
    for _, id in ipairs(self.DB.profileOrder) do
        local profile = self.DB.profiles[id]
        if profile and (not activeOnly or profile.active) then profiles[#profiles + 1] = profile end
    end
    return profiles
end

function FW:NotifyChanged()
    if self.InvalidateUpgradeComparisons then self:InvalidateUpgradeComparisons() end
    if self.RefreshUI then self:RefreshUI() end
    if self.RefreshTooltips then self:RefreshTooltips() end
    if self.RefreshUpgradeIndicators then self:RefreshUpgradeIndicators() end
end

-- A single main profile drives optional upgrade markers independently of its
-- tooltip visibility. No profile is chosen implicitly on import or deletion.
function FW:GetMainProfile()
    self:Initialize()
    return self.DB.profiles[self.DB.options.mainProfileID]
end

function FW:SetMainProfile(id)
    self:Initialize()
    if id ~= nil and (type(id) ~= "string" or not self.DB.profiles[id]) then
        return nil, "Profile not found."
    end
    if self.DB.options.mainProfileID ~= id then
        self.DB.options.mainProfileID = id
        self:NotifyChanged()
    end
    return true
end

function FW:SetUpgradeOption(key, value)
    self:Initialize()
    if not upgradeOptions[key] then return nil, "Unknown upgrade-arrow option." end
    if type(value) ~= "boolean" then return nil, "Upgrade-arrow options must be true or false." end
    if self.DB.options[key] ~= value then
        self.DB.options[key] = value
        self:NotifyChanged()
    end
    return true
end

function FW:CreateProfile(name, weights)
    self:Initialize()
    local checkedName, errorMessage = validName(name)
    if not checkedName then return nil, errorMessage end
    local checkedWeights
    checkedWeights, errorMessage = validWeights(weights or {})
    if not checkedWeights then return nil, errorMessage end
    local db, id = self.DB
    repeat
        id = "profile" .. db.nextProfileID
        db.nextProfileID = db.nextProfileID + 1
    until not db.profiles[id]
    local profile = {
        id = id, name = checkedName, active = true,
        color = { r = defaultColor.r, g = defaultColor.g, b = defaultColor.b },
        weights = checkedWeights, revision = 1, secondaryUnit = "percent", itemFilters = cloneItemFilters(),
    }
    db.profiles[id] = profile
    db.profileOrder[#db.profileOrder + 1] = id
    self:NotifyChanged()
    return profile
end

local function clearProfileScores(db, id)
    for _, record in pairs(db.cache.items) do
        if type(record.scoreIssues) == "table" then record.scoreIssues[id] = nil end
        if type(record.profileScores) == "table" then record.profileScores[id] = nil end
    end
    for itemKey, scores in pairs(db.cache.scores) do
        if type(scores) == "table" then
            scores[id] = nil
            if not next(scores) then db.cache.scores[itemKey] = nil end
        else
            db.cache.scores[itemKey] = nil
        end
    end
end

function FW:UpdateProfile(id, changes)
    self:Initialize()
    local profile = self.DB.profiles[id]
    if not profile then return nil, "Profile not found." end
    if not plainObject(changes) then return nil, "Profile changes must be a table." end
    local allowed = { name = true, active = true, color = true, weights = true, secondaryUnit = true, itemFilters = true }
    for key in pairs(changes) do if not allowed[key] then return nil, "Unknown profile field '" .. key .. "'." end end
    local replacement, errorMessage = {}
    if changes.name ~= nil then
        replacement.name, errorMessage = validName(changes.name)
        if not replacement.name then return nil, errorMessage end
    end
    if changes.active ~= nil then
        if type(changes.active) ~= "boolean" then return nil, "Active must be true or false." end
        replacement.active = changes.active
    end
    if changes.color ~= nil then
        replacement.color, errorMessage = validColor(changes.color)
        if not replacement.color then return nil, errorMessage end
    end
    if changes.secondaryUnit ~= nil then
        replacement.secondaryUnit, errorMessage = validUnit(changes.secondaryUnit)
        if not replacement.secondaryUnit then return nil, errorMessage end
    end
    if changes.weights ~= nil then
        local checked
        checked, errorMessage = validWeights(changes.weights)
        if not checked then return nil, errorMessage end
        replacement.weights = cloneWeights(profile.weights)
        -- Partial programmatic updates leave unspecified weights unchanged.
        for key in pairs(changes.weights) do replacement.weights[key] = checked[key] end
    end
    if changes.itemFilters ~= nil then
        replacement.itemFilters, errorMessage = validItemFilters(changes.itemFilters, profile.itemFilters)
        if not replacement.itemFilters then return nil, errorMessage end
    end
    local scoreChanged = replacement.secondaryUnit and replacement.secondaryUnit ~= profile.secondaryUnit
    if replacement.itemFilters and not itemFiltersEqual(replacement.itemFilters, profile.itemFilters) then scoreChanged = true end
    if replacement.weights then
        for key, value in pairs(replacement.weights) do if value ~= profile.weights[key] then scoreChanged = true break end end
    end
    for key, value in pairs(replacement) do profile[key] = value end
    if scoreChanged then
        profile.revision = profile.revision + 1
        clearProfileScores(self.DB, id)
    end
    self:NotifyChanged()
    return profile
end

function FW:DeleteProfile(id)
    self:Initialize()
    if not self.DB.profiles[id] then return nil, "Profile not found." end
    self.DB.profiles[id] = nil
    if self.DB.options.mainProfileID == id then self.DB.options.mainProfileID = nil end
    for index = #self.DB.profileOrder, 1, -1 do
        if self.DB.profileOrder[index] == id then table.remove(self.DB.profileOrder, index) end
    end
    clearProfileScores(self.DB, id)
    self:NotifyChanged()
    return true
end

function FW:CopyProfile(id)
    self:Initialize()
    local original = self.DB.profiles[id]
    if not original then return nil, "Profile not found." end
    local suffix, name, occupied = 1, original.name .. " (copy)", {}
    for _, profile in ipairs(self:GetProfiles()) do occupied[profile.name] = true end
    while occupied[name] do suffix = suffix + 1 name = original.name .. " (copy " .. suffix .. ")" end
    -- Keep long imported names within the same name limit.
    if #name > 160 then
        local prefix = original.name:sub(1, 140)
        while #prefix > 0 and not self.JSON.Encode(prefix) do prefix = prefix:sub(1, -2) end
        name = prefix .. " (copy " .. suffix .. ")"
    end
    local profile, errorMessage = self:CreateProfile(name, original.weights)
    if not profile then return nil, errorMessage end
    profile.active = original.active
    profile.color = { r = original.color.r, g = original.color.g, b = original.color.b }
    profile.secondaryUnit = original.secondaryUnit
    profile.itemFilters = cloneItemFilters(original.itemFilters)
    self:NotifyChanged()
    return profile
end

function FW:ImportProfile(source, fallbackName)
    self:Initialize()
    local decoded, errorMessage = self.JSON.Decode(source)
    if decoded == nil then return nil, errorMessage end
    if not plainObject(decoded) then return nil, "Import must be a weight object or a ZwykValues profile object." end
    local weights, name, color, unit, filters
    local warnings = {}
    if decoded.weights ~= nil or decoded.format ~= nil then
        local allowed = { format = true, version = true, name = true, color = true, secondaryUnit = true, weights = true, itemFilters = true }
        for key in pairs(decoded) do if not allowed[key] then return nil, "Unknown profile field '" .. key .. "'." end end
        if decoded.format ~= "ZwykValues" and decoded.format ~= "ZwykPoints" and decoded.format ~= "ForeverWeights" then
            return nil, "Profile format must be 'ZwykValues', 'ZwykPoints' or 'ForeverWeights'."
        end
        if decoded.version ~= 1 then return nil, "Unsupported profile version (expected 1)." end
        weights, errorMessage = validWeights(decoded.weights)
        if not weights then return nil, errorMessage end
        name, errorMessage = validName(decoded.name or fallbackName or "Imported profile")
        if not name then return nil, errorMessage end
        color, errorMessage = validColor(decoded.color or defaultColor)
        if not color then return nil, errorMessage end
        unit, errorMessage = validUnit(decoded.secondaryUnit or "percent")
        if not unit then return nil, errorMessage end
        local importedFilters = decoded.itemFilters
        if importedFilters == nil then importedFilters = {} end
        filters, errorMessage = validItemFilters(importedFilters)
        if not filters then return nil, errorMessage end
    else
        weights, errorMessage = validWeights(decoded)
        if not weights then return nil, errorMessage end
        name, errorMessage = validName(fallbackName or "Imported profile")
        if not name then return nil, errorMessage end
        color = { r = defaultColor.r, g = defaultColor.g, b = defaultColor.b }
        unit = "percent"
        warnings[#warnings + 1] = "Bare weights use percentage points for secondary stats; defense uses defense skill points. Choose rating mode if these weights are per rating point."
    end
    local profile
    profile, errorMessage = self:CreateProfile(name, weights)
    if not profile then return nil, errorMessage end
    profile.color, profile.secondaryUnit = color, unit
    if filters then profile.itemFilters = filters end
    self:NotifyChanged()
    return profile, nil, warnings
end

function FW:ExportProfile(id, bare)
    self:Initialize()
    local profile = self.DB.profiles[id]
    if not profile then return nil, "Profile not found." end
    local weights = cloneWeights(profile.weights)
    if bare then return self.JSON.Encode(weights) end
    return self.JSON.Encode({
        format = "ZwykValues", version = 1, name = profile.name,
        color = { r = profile.color.r, g = profile.color.g, b = profile.color.b },
        secondaryUnit = profile.secondaryUnit, weights = weights, itemFilters = cloneItemFilters(profile.itemFilters),
    })
end

function FW:ScoreStats(profile, stats)
    local total = 0
    for _, definition in ipairs(self.StatDefinitions) do
        local weight = profile.weights[definition.key] or 0
        total = total + weight * (stats[definition.key] or 0)
    end
    return total
end

function FW:ItemHasIssues(record, profile)
    if type(record) ~= "table" then return false end
    if record.partial or #(record.warnings or {}) > 0 or #(record.unrecognizedLines or {}) > 0
        or #(record.unknownAPIStats or {}) > 0 then return true end
    local issues = record.scoreIssues or {}
    if profile then return issues[type(profile) == "table" and profile.id or profile] ~= nil end
    return next(issues) ~= nil
end

function FW:ItemIssueSummary(record, profile)
    if not self:ItemHasIssues(record, profile) then return nil end
    local issue = profile and record.scoreIssues and record.scoreIssues[type(profile) == "table" and profile.id or profile]
    if issue and #issue.warnings > 0 then return table.concat(issue.warnings, " ") end
    if #(record.warnings or {}) > 0 then return table.concat(record.warnings, " ") end
    return "Some item stats could not be read reliably."
end

-- Keep only serializable, non-secret diagnostic data. Item API fields can be
-- protected or non-finite on some clients; preserve that fact as text instead
-- of trying to compare, stringify, or export the protected value itself.
local function diagnosticCopy(value, seen, depth)
    if issecretvalue and issecretvalue(value) then return "[secret value unavailable]" end
    local kind = type(value)
    if kind == "number" then return finite(value) and value or "[non-finite number]" end
    if kind == "string" then
        if FW.JSON.Encode(value) then return value end
        return "[invalid UTF-8 bytes] " .. value:gsub(".", function(byte) return string.format("%02x ", byte:byte()) end)
    end
    if kind == "boolean" or kind == "nil" then return value end
    if kind ~= "table" then return "[" .. kind .. " value unavailable]" end
    seen = seen or {}
    depth = depth or 0
    if depth >= 24 then return "[diagnostic nesting limit]" end
    if seen[value] then return "[circular table]" end
    seen[value] = true
    local result, count, maximum, dense = {}, 0, 0, true
    for key in pairs(value) do
        if (issecretvalue and issecretvalue(key)) or not finite(key) or key < 1 or key ~= math.floor(key) then dense = false
        else count = count + 1; if key > maximum then maximum = key end end
    end
    dense = dense and count > 0 and maximum == count
    for key, child in pairs(value) do
        local copiedKey
        if issecretvalue and issecretvalue(key) then copiedKey = "[secret key unavailable]"
        elseif dense then copiedKey = key
        elseif type(key) == "string" then copiedKey = diagnosticCopy(key)
        elseif type(key) == "number" or type(key) == "boolean" then copiedKey = tostring(key)
        else copiedKey = "[" .. type(key) .. " key unavailable]" end
        result[copiedKey] = diagnosticCopy(child, seen, depth + 1)
    end
    seen[value] = nil
    return result
end

function FW:CopyItemDiagnostic(value)
    return diagnosticCopy(value)
end

function FW:RecordItemIssue(record)
    if not self:ItemHasIssues(record) or type(record.key) ~= "string" then return end
    self:Initialize()
    local old = self.DB.itemIssues[record.key]
    local diagnostic = record.diagnostic or {}
    local entry = diagnosticCopy({
        key = record.key, itemID = record.itemID, name = record.name or diagnostic.name,
        link = record.link, equipLoc = record.equipLoc, parserVersion = record.parserVersion,
        build = diagnostic.build, locale = diagnostic.locale, level = diagnostic.level,
        source = diagnostic.source, apiAvailable = diagnostic.apiAvailable,
        raw = diagnostic.raw or {}, ignoredAPIStats = diagnostic.ignoredKeys or {},
        unknownAPIStats = record.unknownAPIStats or diagnostic.unknownKeys or {},
        tooltipLines = diagnostic.tooltipLines or {}, tooltipSource = diagnostic.tooltipSource,
        tooltipDetails = diagnostic.tooltipDetails or {},
        stats = record.stats, percentStats = record.percentStats, ratingStats = record.ratingStats,
        unresolvedStats = record.unresolvedStats or {}, unrecognizedLines = record.unrecognizedLines or {},
        partial = record.partial == true, warnings = record.warnings or {},
        scoreIssues = record.scoreIssues or {}, profileScores = record.profileScores or {},
    })
    -- A partial item may be re-read once per active profile. Merge the profile
    -- results so the last read does not erase the other profile's diagnostics.
    if old then
        for _, field in ipairs({ "scoreIssues", "profileScores" }) do
            for id, value in pairs(old[field] or {}) do
                local recomputedIssue = field == "scoreIssues" and entry.profileScores[id] ~= nil
                if entry[field][id] == nil and not recomputedIssue then entry[field][id] = diagnosticCopy(value) end
            end
        end
    end
    local now = time and time() or nil
    entry.firstSeen, entry.lastSeen = old and old.firstSeen or now, now
    self.DB.itemIssues[record.key] = entry
end

function FW:GetIssueReport()
    self:Initialize()
    local keys, items = {}, self.JSON.array()
    for key in pairs(self.DB.itemIssues) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do items[#items + 1] = diagnosticCopy(self.DB.itemIssues[key]) end
    return { format = "ZwykValuesIssues", version = 1, addonVersion = self.version,
        generatedAt = time and time() or nil, itemCount = #items, items = items }
end

function FW:ClearItemIssues()
    self:Initialize()
    self.DB.itemIssues = {}
end

function FW:GetScore(link, profile, ignoreFilters)
    self:Initialize()
    if type(profile) == "string" then profile = self.DB.profiles[profile] end
    if type(profile) ~= "table" or not self.DB.profiles[profile.id] then return nil, "Profile not found." end
    local record, errorMessage = self:GetItem(link)
    if not record then return nil, errorMessage or "Item data is not available yet." end
    if type(record.key) ~= "string" or type(record.stats) ~= "table" then return nil, "Item data is incomplete." end
    local gear, gearError = self:IsGearItem(record)
    if gear == nil and self.RefreshItemFilterMetadata then
        self:RefreshItemFilterMetadata(record, true)
        gear, gearError = self:IsGearItem(record)
    end
    if gear == false then return nil, record, "excluded" end
    if gear == nil then return nil, gearError end
    if not ignoreFilters then
        local allowed, reason = self:IsItemAllowed(record, profile)
        if allowed == nil and self.RefreshItemFilterMetadata then
            self:RefreshItemFilterMetadata(record, true)
            allowed, reason = self:IsItemAllowed(record, profile)
        end
        if allowed == false then return nil, record, "excluded" end
        if allowed == nil then return nil, reason end
    end
    local cache = self.DB.cache
    local recent = self.GetRecentItemRead and self:GetRecentItemRead(record.key)
    local subtotal = recent and recent.record == record and recent.scores[profile.id]
    if subtotal and subtotal.revision == profile.revision then return subtotal.score, record, subtotal.detail end
    local scores = cache.scores[record.key]
    local cached = type(scores) == "table" and scores[profile.id]
    if not record.partial and type(cached) == "table" and cached.revision == profile.revision and finite(cached.score) then
        self:RecordItemIssue(record)
        return cached.score, record
    end
    local stats = {}
    for key, value in pairs(record.stats) do stats[key] = value end
    local missingStats, scoreWarnings = {}, {}
    for key in pairs(record.unresolvedStats or {}) do
        if not secondaryKeys[key] and (profile.weights[key] or 0) ~= 0 then
            local label = self.StatByKey[key] and self.StatByKey[key].label or key
            missingStats[key] = true
            scoreWarnings[#scoreWarnings + 1] = label .. " could not be read completely; its known value contributes to this subtotal."
        end
    end
    local selected = profile.secondaryUnit == "rating" and record.ratingStats or record.percentStats
    local other = profile.secondaryUnit == "rating" and record.percentStats or record.ratingStats
    selected, other = selected or {}, other or {}
    for key in pairs(secondaryKeys) do
        local value = selected[key]
        if value == nil then
            if (profile.weights[key] or 0) ~= 0 and (other[key] ~= nil or (record.unresolvedStats and record.unresolvedStats[key])) then
                local label = self.StatByKey[key] and self.StatByKey[key].label or key
                local unit = profile.secondaryUnit == "rating" and "rating points" or (key == "defense" and "defense skill points" or "percentage points")
                missingStats[key] = true
                scoreWarnings[#scoreWarnings + 1] = label .. " is unavailable in " .. unit .. "; its contribution is omitted. Check the profile's secondary stat unit."
            end
            value = 0
        end
        stats[key] = value
    end
    local score = self:ScoreStats(profile, stats)
    if not finite(score) then return nil, "This item's weighted total is not finite; reduce the profile weights." end
    table.sort(scoreWarnings)
    record.scoreIssues, record.profileScores = record.scoreIssues or {}, record.profileScores or {}
    local scorePartial = next(missingStats) ~= nil
    record.scoreIssues[profile.id] = scorePartial and { name = profile.name, secondaryUnit = profile.secondaryUnit,
        revision = profile.revision, missingStats = missingStats, warnings = scoreWarnings } or nil
    record.profileScores[profile.id] = { name = profile.name, revision = profile.revision,
        secondaryUnit = profile.secondaryUnit, score = score, partial = record.partial == true or scorePartial }
    self:RecordItemIssue(record)
    -- A partially loaded tooltip may gain more stats on the next read. It must
    -- never become a persistent item/score entry merely because scoring ran.
    if record.partial or scorePartial then
        local detail = #scoreWarnings > 0 and table.concat(scoreWarnings, " ") or self:ItemIssueSummary(record, profile)
        if self.RememberItemRead then
            recent = recent and recent.record == record and recent or self:RememberItemRead(record)
            if recent then recent.scores[profile.id] = {revision=profile.revision, score=score, detail=detail} end
        end
        return score, record, detail
    end
    scores = type(scores) == "table" and scores or {}
    scores[profile.id] = { revision = profile.revision, score = score }
    cache.scores[record.key] = scores
    -- Items owns the bounded item cache; scores cannot outlive an item record.
    if cache.items[record.key] == nil then
        cache.items[record.key] = record
        cache.itemOrder[#cache.itemOrder + 1] = record.key
    end
    trimCache(cache)
    return score, record
end

function FW:GetCacheCount()
    self:Initialize()
    local count = 0
    for _ in pairs(self.DB.cache.items) do count = count + 1 end
    return count
end

function FW:InvalidateCache()
    self:Initialize()
    self.DB.cache = blankCache()
    self:NotifyChanged()
end

function FW:InvalidateItem(link)
    self:Initialize()
    local key = self.ItemKey and self:ItemKey(link)
    if not key then
        for candidate, record in pairs(self.DB.cache.items) do if record.link == link then key = candidate break end end
    end
    if not key then return false end
    if self.InvalidateRecentItemReads then
        self:InvalidateRecentItemReads(type(link) == "string" and tonumber(link:match("item:(%d+)")))
    end
    local cache = self.DB.cache
    cache.items[key], cache.scores[key] = nil, nil
    if self.InvalidateUpgradeComparisons then self:InvalidateUpgradeComparisons() end
    for index = #cache.itemOrder, 1, -1 do if cache.itemOrder[index] == key then table.remove(cache.itemOrder, index) end end
    cache.order = cache.itemOrder
    return true
end
