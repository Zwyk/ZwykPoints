local _, FW = ...

FW.CACHE_LIMIT = 2000
FW.CACHE_VERSION = 1
local secondaryKeys = { hit = true, crit = true, haste = true, expertise = true, defense = true, dodge = true, parry = true, block = true }
FW.SecondaryStatKeys = secondaryKeys
local defaultColor = { r = 0.35, g = 0.8, b = 1 }

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
    if ZwykPointsDB == nil and type(_G.ForeverWeightsDB) == "table" then
        ZwykPointsDB = copySavedTable(_G.ForeverWeightsDB)
    end
    local db = type(ZwykPointsDB) == "table" and ZwykPointsDB or {}
    ZwykPointsDB, self.DB = db, db
    db.schemaVersion = 1
    db.profiles = type(db.profiles) == "table" and db.profiles or {}
    db.profileOrder = type(db.profileOrder) == "table" and db.profileOrder or {}
    db.nextProfileID = finite(db.nextProfileID) and math.max(1, math.floor(db.nextProfileID)) or 1
    db.options = type(db.options) == "table" and db.options or {}
    if db.options.showComparisons == nil then db.options.showComparisons = true end
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
    if self.RefreshUI then self:RefreshUI() end
    if self.RefreshTooltips then self:RefreshTooltips() end
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
        weights = checkedWeights, revision = 1, secondaryUnit = "percent",
    }
    db.profiles[id] = profile
    db.profileOrder[#db.profileOrder + 1] = id
    self:NotifyChanged()
    return profile
end

local function clearProfileScores(db, id)
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
    local allowed = { name = true, active = true, color = true, weights = true, secondaryUnit = true }
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
    local scoreChanged = replacement.secondaryUnit and replacement.secondaryUnit ~= profile.secondaryUnit
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
    self:NotifyChanged()
    return profile
end

function FW:ImportProfile(source, fallbackName)
    self:Initialize()
    local decoded, errorMessage = self.JSON.Decode(source)
    if decoded == nil then return nil, errorMessage end
    if not plainObject(decoded) then return nil, "Import must be a weight object or a ZwykPoints profile object." end
    local weights, name, color, unit
    local warnings = {}
    if decoded.weights ~= nil or decoded.format ~= nil then
        local allowed = { format = true, version = true, name = true, color = true, secondaryUnit = true, weights = true }
        for key in pairs(decoded) do if not allowed[key] then return nil, "Unknown profile field '" .. key .. "'." end end
        if decoded.format ~= "ZwykPoints" and decoded.format ~= "ForeverWeights" then
            return nil, "Profile format must be 'ZwykPoints' or the legacy 'ForeverWeights'."
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
        format = "ZwykPoints", version = 1, name = profile.name,
        color = { r = profile.color.r, g = profile.color.g, b = profile.color.b },
        secondaryUnit = profile.secondaryUnit, weights = weights,
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

function FW:GetScore(link, profile)
    self:Initialize()
    if type(profile) == "string" then profile = self.DB.profiles[profile] end
    if type(profile) ~= "table" or not self.DB.profiles[profile.id] then return nil, "Profile not found." end
    local record, errorMessage = self:GetItem(link)
    if not record then return nil, errorMessage or "Item data is not available yet." end
    if type(record.key) ~= "string" or type(record.stats) ~= "table" then return nil, "Item data is incomplete." end
    local cache = self.DB.cache
    local scores = cache.scores[record.key]
    local cached = type(scores) == "table" and scores[profile.id]
    if not record.partial and type(cached) == "table" and cached.revision == profile.revision and finite(cached.score) then return cached.score, record end
    local stats = {}
    for key, value in pairs(record.stats) do stats[key] = value end
    for key in pairs(record.unresolvedStats or {}) do
        if not secondaryKeys[key] and (profile.weights[key] or 0) ~= 0 then
            local label = self.StatByKey[key] and self.StatByKey[key].label or key
            return nil, label .. " could not be read reliably for this item."
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
                return nil, label .. " is unavailable in " .. unit .. " for this item; check the profile's secondary stat unit."
            end
            value = 0
        end
        stats[key] = value
    end
    local score = self:ScoreStats(profile, stats)
    if not finite(score) then return nil, "This item's weighted total is not finite; reduce the profile weights." end
    -- A partially loaded tooltip may gain more stats on the next read. It must
    -- never become a persistent item/score entry merely because scoring ran.
    if record.partial then return score, record end
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
    local cache = self.DB.cache
    cache.items[key], cache.scores[key] = nil, nil
    for index = #cache.itemOrder, 1, -1 do if cache.itemOrder[index] == key then table.remove(cache.itemOrder, index) end end
    cache.order = cache.itemOrder
    return true
end
