local _, FW = ...
local MAX_ITEMS, PARSER_VERSION = 2000, 5

local function number(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then return value end
        return nil
    end
    if type(value) ~= "string" then return nil end
    value = value:gsub("%s", "")
    local locale = GetLocale and GetLocale() or "enUS"
    if locale == "enUS" or locale == "enGB" then value = value:gsub(",", "")
    else value = value:gsub(",", ".") end
    return tonumber(value)
end

local function clean(text)
    if issecretvalue and issecretvalue(text) then return "" end
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("%s+", " "):gsub("(%d) (%d%d%d)", "%1%2"):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function escape(text) return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")) end
local function lower(text)
    return (text:lower():gsub("É", "é"):gsub("À", "à"):gsub("È", "è")
        :gsub("Ê", "ê"):gsub("Î", "î"):gsub("Ô", "ô"):gsub("Û", "û"):gsub("Ç", "ç"))
end
local function itemPayload(link)
    if issecretvalue and issecretvalue(link) then return nil end
    if type(link) == "number" and link > 0 then return "item:" .. math.floor(link) end
    if type(link) ~= "string" then return nil end
    return link:match("(item:[^|%s]+)")
end

local function rangedItem(record)
    return record.equipLoc == "INVTYPE_RANGED" or record.equipLoc == "INVTYPE_RANGEDRIGHT"
        or record.equipLoc == "INVTYPE_THROWN" or record.equipLoc == "INVTYPE_AMMO"
end

function FW:GetBaseItemLink(link)
    if issecretvalue and issecretvalue(link) then return nil end
    local payload
    if type(link) == "number" then
        if link ~= link or link == math.huge or link <= 0 or link ~= math.floor(link) then return nil end
        payload = "item:" .. math.floor(link)
    elseif type(link) == "string" then
        if link:match("^item:[^|%s]+$") then payload = link
        else
            -- Forever also uses named quality colors (for example |cnIQ2:).
            -- Color markup is outside the item payload and carries no stats.
            local hyperlink = link:gsub("^|c%x%x%x%x%x%x%x%x", ""):
                gsub("^|cn[%w_]+:", ""):gsub("|r$", "")
            payload = hyperlink:match("^|H(item:[^|%s]+)|h.-|h$")
        end
    end
    if not payload then return nil end
    local itemID, tail = payload:match("^item:(%d+)(.*)$")
    local id = tonumber(itemID)
    if not id or id == math.huge or id <= 0 then return nil end
    if tail == "" then return "item:" .. itemID .. ":0" end
    local enchant, remaining = tail:match("^:([^:]*)(.*)$")
    if not enchant or (enchant ~= "" and (not enchant:match("^%d+$") or tonumber(enchant) == math.huge))
        or (remaining ~= "" and not remaining:match("^:[%w:%-]*$")) then return nil end
    -- Keep suffixes, bonus IDs, creator GUIDs and trailing empty fields intact.
    return "item:" .. itemID .. ":0" .. remaining
end

function FW:GetBaseScore(link, profile, ignoreFilters)
    local baseLink = self:GetBaseItemLink(link)
    if not baseLink then return nil, "Invalid item link." end
    return self:GetScore(baseLink, profile, ignoreFilters)
end

function FW:ItemKey(link)
    local payload = itemPayload(link)
    if not payload or not tonumber(payload:match("^item:(%d+)")) then return nil end
    local version, build, _, interface = "unknown", "unknown", nil, "unknown"
    if GetBuildInfo then version, build, _, interface = GetBuildInfo() end
    local level = UnitLevel and UnitLevel("player") or 0
    local locale = GetLocale and GetLocale() or "enUS"
    return table.concat({ tostring(PARSER_VERSION), payload, tostring(level), tostring(version),
        tostring(build), tostring(interface), locale }, "|")
end

local absolute = {
    ITEM_MOD_STRENGTH_SHORT = "strength", ITEM_MOD_AGILITY_SHORT = "agility",
    ITEM_MOD_STAMINA_SHORT = "stamina", ITEM_MOD_INTELLECT_SHORT = "intellect",
    ITEM_MOD_SPIRIT_SHORT = "spirit", ITEM_MOD_HEALTH_SHORT = "health",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5", ITEM_MOD_HEALTH_REGEN_SHORT = "hp5",
    ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_MANA_REGEN_SHORT = "mp5",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spellDamage", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healing",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "spellPen", ITEM_MOD_ATTACK_POWER_SHORT = "attackPower",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feralAttackPower",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rangedAttackPower",
    RESISTANCE0_NAME = "armor", ITEM_MOD_ARMOR_SHORT = "armor",
    ITEM_MOD_EXTRA_ARMOR_SHORT = "armorBonus", ITEM_MOD_BONUS_ARMOR_SHORT = "armorBonus",
    ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue", ITEM_MOD_BLOCK_VALUE_BONUS_SHORT = "blockValueBonus",
    RESISTANCE2_NAME = "fireResist", RESISTANCE3_NAME = "natureResist",
    RESISTANCE4_NAME = "frostResist", RESISTANCE5_NAME = "shadowResist", RESISTANCE6_NAME = "arcaneResist",
}
local ratings, untyped = {}, {}
for _, school in ipairs({ "ARCANE", "FIRE", "NATURE", "FROST", "SHADOW", "HOLY" }) do
    absolute["ITEM_MOD_" .. school .. "_DAMAGE_SHORT"] = school:lower() .. "Damage"
    if school ~= "HOLY" then absolute["ITEM_MOD_" .. school .. "_RESISTANCE_SHORT"] = school:lower() .. "Resist" end
end
local secondaryAliases = {
    hit = { "HIT", "HIT_MELEE", "HIT_RANGED", "HIT_SPELL" },
    crit = { "CRIT", "CRIT_MELEE", "CRIT_RANGED", "CRIT_SPELL" },
    haste = { "HASTE", "HASTE_MELEE", "HASTE_RANGED", "HASTE_SPELL" },
    expertise = { "EXPERTISE" }, dodge = { "DODGE" }, parry = { "PARRY" },
    block = { "BLOCK" }, defense = { "DEFENSE_SKILL", "DEFENSE" },
}
for key, aliases in pairs(secondaryAliases) do
    for _, alias in ipairs(aliases) do
        ratings["ITEM_MOD_" .. alias .. "_RATING_SHORT"] = key
        untyped["ITEM_MOD_" .. alias .. "_SHORT"] = key
    end
end
for _, mapping in ipairs({ absolute, ratings, untyped }) do
    local extras = {}
    for key, value in pairs(mapping) do
        if key:match("_SHORT$") then extras[(key:gsub("_SHORT$", ""))] = value end
    end
    for key, value in pairs(extras) do mapping[key] = value end
end
-- Known, deliberately out-of-schema values are reported separately, not
-- treated as an unknown Forever field. They cannot acquire an accidental weight.
local ignored = {
    ITEM_MOD_MANA_SHORT = true, ITEM_MOD_RESILIENCE_RATING_SHORT = true,
    ITEM_MOD_MASTERY_RATING_SHORT = true, ITEM_MOD_VERSATILITY = true,
    ITEM_MOD_VERSATILITY_RATING_SHORT = true, ITEM_MOD_CR_AVOIDANCE_SHORT = true,
    ITEM_MOD_CR_LIFESTEAL_SHORT = true, ITEM_MOD_CR_SPEED_SHORT = true,
    ITEM_MOD_INDESTRUCTIBLE_SHORT = true,
}

local function maximum(map, key, value)
    if value ~= nil and (map[key] == nil or value > map[key]) then map[key] = value end
end
local function add(map, key, value)
    if value ~= nil then map[key] = (map[key] or 0) + value end
end
local function warn(record, message)
    record.warnings[#record.warnings + 1] = message
end
local function apiKeyText(key)
    if issecretvalue and issecretvalue(key) then return "[secret API key unavailable]" end
    if type(key) == "string" or type(key) == "number" or type(key) == "boolean" then return tostring(key) end
    return "[" .. type(key) .. " API key unavailable]"
end

local scanner
local function tooltipLines(link)
    local lines, details, readable = {}, {}, true
    local function readableText(value)
        return not (issecretvalue and issecretvalue(value)) and (value == nil or type(value) == "string")
    end
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and type(data) == "table" and type(data.lines) == "table" then
            for index, line in ipairs(data.lines) do
                if not readableText(line.leftText) or not readableText(line.rightText) then readable = false end
                local left, right = clean(line.leftText), clean(line.rightText)
                details[#details + 1] = { index = index, leftText = line.leftText,
                    rightText = line.rightText, type = line.type, requirementType = line.requirementType }
                if left ~= "" then lines[#lines + 1] = left end
                if right ~= "" and right ~= left then lines[#lines + 1] = right end
            end
            if #lines > 0 then return lines, "C_TooltipInfo", details, readable end
        end
    end
    if not CreateFrame then return lines, nil, details end
    if not scanner then
        local ok, frame = pcall(CreateFrame, "GameTooltip", "ZwykValuesScanTooltip", UIParent, "GameTooltipTemplate")
        if ok then scanner = frame; FW.ScanTooltip = frame end
    end
    if not scanner then return lines, nil, details end
    scanner:SetOwner(UIParent, "ANCHOR_NONE")
    scanner:ClearLines()
    local ok = pcall(scanner.SetHyperlink, scanner, link)
    if ok then
        for i = 1, scanner:NumLines() do
            local left = _G["ZwykValuesScanTooltipTextLeft" .. i]
            local right = _G["ZwykValuesScanTooltipTextRight" .. i]
            local rawLeft, rawRight = left and left:GetText(), right and right:GetText()
            if not readableText(rawLeft) or not readableText(rawRight) then readable = false end
            local leftText, rightText = clean(rawLeft), clean(rawRight)
            details[#details + 1] = { index = i, leftText = rawLeft, rightText = rawRight }
            if leftText ~= "" then lines[#lines + 1] = leftText end
            if rightText ~= "" and rightText ~= leftText then lines[#lines + 1] = rightText end
        end
    end
    scanner:Hide()
    return lines, #lines > 0 and "GameTooltip" or nil, details, readable
end

local function identifier(value)
    value = number(value)
    return value and value >= 0 and value == math.floor(value) and value or nil
end

local function itemClassification(link, info)
    local classID, subclassID = info and identifier(info[13]), info and identifier(info[14])
    local function equipmentType(value)
        if issecretvalue and issecretvalue(value) then return nil end
        return type(value) == "string" and value or nil
    end
    local equipLoc = info and equipmentType(info[10])
    local modern = C_Item and C_Item.GetItemInfoInstant
    local previous
    for _, getter in ipairs({ modern or false, GetItemInfoInstant or false }) do
        if classID ~= nil and subclassID ~= nil and equipLoc ~= nil then break end
        if getter and getter ~= previous then
            previous = getter
            local instant = { pcall(getter, link) }
            if instant[1] then
                classID, subclassID = classID or identifier(instant[7]), subclassID or identifier(instant[8])
                equipLoc = equipLoc or equipmentType(instant[5])
            end
        end
    end
    return classID, subclassID, equipLoc
end

local restrictionFormats
local function getRestrictionFormats()
    if restrictionFormats then return restrictionFormats end
    restrictionFormats = {}
    local function addFormat(value, kind)
        local text = lower(clean(value))
        local first, last = text:find("%%[%d%$]*s")
        if not first then return end
        local separators, finish = {}, last
        while true do
            local nextFirst, nextLast = text:find("%%[%d%$]*s", finish + 1)
            if not nextFirst then break end
            local separator = text:sub(finish + 1, nextFirst - 1)
            if separator ~= "" then separators[#separators + 1] = separator end
            finish = nextLast
        end
        local prefix, suffix = text:sub(1, first - 1), text:sub(finish + 1)
        if clean(prefix) == "" and clean(suffix) == "" then return end
        local function pattern(part) return escape(clean(part)):gsub(" ", "%%s*") end
        restrictionFormats[#restrictionFormats + 1] = { kind = kind, separators = separators,
            pattern = "^" .. pattern(prefix) .. "%s*(.-)%s*" .. pattern(suffix) .. "$" }
    end
    for name, value in pairs(_G) do
        if type(name) == "string" and type(value) == "string" then
            if name == "ITEM_CLASSES_ALLOWED" or name:match("^ITEM_CLASSES_ALLOWED_") then addFormat(value, "class")
            elseif name == "ITEM_RACES_ALLOWED" or name:match("^ITEM_RACES_ALLOWED_") then addFormat(value, "race") end
        end
    end
    local locale = GetLocale and GetLocale() or "enUS"
    if locale == "enUS" or locale == "enGB" or locale == "frFR" then
        addFormat("Classes: %s", "class"); addFormat("Races: %s", "race")
    end
    return restrictionFormats
end

local function classNames()
    local names = {}
    local function addName(token, name)
        if (issecretvalue and (issecretvalue(token) or issecretvalue(name))) then return end
        if type(token) == "string" and token:match("^[A-Z]+$") and type(name) == "string" and clean(name) ~= "" then
            names[lower(clean(name))], names[lower(token)] = token, token
        end
    end
    for _, list in ipairs({ LOCALIZED_CLASS_NAMES_MALE or {}, LOCALIZED_CLASS_NAMES_FEMALE or {} }) do
        if type(list) == "table" then for token, name in pairs(list) do addName(token, name) end end
    end
    local locale = GetLocale and GetLocale() or "enUS"
    if locale == "enUS" or locale == "enGB" then
        for _, token in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
            addName(token, token)
        end
    end
    if UnitClass then
        local ok, name, token = pcall(UnitClass, "player")
        if ok then addName(token, name) end
    end
    return names
end

local function classRestrictions(details, readable)
    local formats, names = getRestrictionFormats(), classNames()
    local hasClassFormat = false
    for _, format in ipairs(formats) do if format.kind == "class" then hasClassFormat = true; break end end
    local contentRows = 0
    for _, line in ipairs(details) do
        if clean(line.leftText) ~= "" or clean(line.rightText) ~= "" then contentRows = contentRows + 1 end
    end
    local known, allowed, unknown = readable == true and contentRows > 1 and hasClassFormat, nil, {}
    local function retrieving(text)
        if text == "" then return false end
        return text == lower(clean(_G.RETRIEVING_ITEM_INFO)) or text == lower(clean(_G.RETRIEVING_DATA))
            or text:find("^retrieving item information") or text:find("^retrieving data")
            or text:find("^récupération des informations") or text:find("^récupération des données")
    end
    for index, line in ipairs(details) do
        if index > 1 then
            local left, right = lower(clean(line.leftText)), lower(clean(line.rightText))
            if retrieving(left) or retrieving(right) then known = false end
            local format, list
            local candidates = left ~= right and { left .. " " .. right, left, right } or { left }
            for _, candidate in ipairs(candidates) do
                candidate = clean(candidate)
                for _, entry in ipairs(formats) do
                    list = candidate:match(entry.pattern)
                    if list ~= nil then format = entry; break end
                end
                if format then break end
            end
            if format and format.kind == "class" then
                allowed = allowed or {}
                list = list:gsub("，", ","):gsub("、", ","):gsub("；", ","):gsub("[;/]", ",")
                for _, separator in ipairs(format.separators) do list = list:gsub(escape(separator), ",") end
                local locale = GetLocale and GetLocale() or "enUS"
                if locale == "enUS" or locale == "enGB" then list = list:gsub(" and ", ",")
                elseif locale == "frFR" then list = list:gsub(" et ", ",") end
                for name in (list .. ","):gmatch("(.-),") do
                    name = clean(name)
                    local token = names[name]
                    if token then allowed[token] = true
                    else known = false; unknown[#unknown + 1] = name end
                end
            elseif not format and identifier(line.type) == 43 and identifier(line.requirementType) == 0 then
                -- RaceClass requirements without readable native Classes/Races
                -- text cannot safely establish that this item is unrestricted.
                known = false; unknown[#unknown + 1] = clean(left .. " " .. right)
            end
        end
    end
    return allowed, known, #unknown > 0 and unknown or nil
end

local function requestItem(itemID)
    FW.PendingItems = FW.PendingItems or {}
    if FW.PendingItems[itemID] then return end
    FW.PendingItems[itemID] = true
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
end

function FW:GetRawItemStats(link)
    local payload = itemPayload(link)
    local itemID = payload and tonumber(payload:match("^item:(%d+)"))
    if not itemID then return nil, "Invalid item link." end
    local result = { itemID = itemID, raw = {}, unknownKeys = {}, ignoredKeys = {}, warnings = {}, ready = false }
    local version, build, buildDate, interface = "unknown", "unknown", "unknown", "unknown"
    if GetBuildInfo then version, build, buildDate, interface = GetBuildInfo() end
    result.build = { version = version, build = build, date = buildDate, interface = interface }
    result.locale = GetLocale and GetLocale() or "enUS"
    result.level = UnitLevel and UnitLevel("player") or 0
    if C_Item and C_Item.IsItemDataCachedByID then
        local ok, cached = pcall(C_Item.IsItemDataCachedByID, itemID)
        if ok and not cached then requestItem(itemID); return result end
    end
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if getInfo then
        local info = { pcall(getInfo, link) }
        if (not info[1] or not info[2]) and GetItemInfo and getInfo ~= GetItemInfo then
            info = { pcall(GetItemInfo, link) }
        end
        if info[1] and info[2] then
            result.name, result.link = info[2], info[3] or link
            result.classID, result.subclassID, result.equipLoc = itemClassification(link, info)
        end
    end
    if not result.name then requestItem(itemID); return result end
    local raw
    if C_Item and C_Item.GetItemStats then
        local ok, stats = pcall(C_Item.GetItemStats, link)
        if ok and type(stats) == "table" then raw, result.source = stats, "C_Item.GetItemStats" end
    end
    if not raw and GetItemStats then
        local ok, stats = pcall(GetItemStats, link)
        if ok and type(stats) == "table" then raw, result.source = stats, "GetItemStats" end
    end
    result.raw = raw or {}
    result.apiAvailable = raw ~= nil
    for key in pairs(result.raw) do
        if issecretvalue and issecretvalue(key) then result.unknownKeys[#result.unknownKeys + 1] = apiKeyText(key)
        elseif ignored[key] then result.ignoredKeys[#result.ignoredKeys + 1] = apiKeyText(key)
        elseif not absolute[key] and not ratings[key] and not untyped[key]
            and key ~= "ITEM_MOD_SPELL_POWER_SHORT" and key ~= "ITEM_MOD_SPELL_POWER"
            and key ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" and key ~= "ITEM_MOD_DAMAGE_PER_SECOND" then
            result.unknownKeys[#result.unknownKeys + 1] = apiKeyText(key)
        end
    end
    table.sort(result.unknownKeys)
    table.sort(result.ignoredKeys)
    result.tooltipLines, result.tooltipSource, result.tooltipDetails, result.tooltipReadable = tooltipLines(link)
    result.allowedClasses, result.classRestrictionsKnown, result.classRestrictionUnknownNames =
        classRestrictions(result.tooltipDetails, result.tooltipReadable)
    result.ready = result.apiAvailable or #result.tooltipLines > 0
    for _, line in ipairs(result.tooltipLines) do
        local text = lower(clean(line))
        if text == lower(clean(_G.RETRIEVING_ITEM_INFO)) or text == lower(clean(_G.RETRIEVING_DATA))
            or text:find("^retrieving item information") or text:find("^retrieving data")
            or text:find("^récupération des informations") or text:find("^récupération des données") then
            result.ready = false
        end
    end
    if not result.ready then requestItem(itemID) end
    return result
end

function FW:RefreshItemFilterMetadata(record)
    if type(record) ~= "table" or type(record.link) ~= "string" then return end
    local diagnostic = record.diagnostic or {}
    local knownEquipLoc = record.equipLoc
    if (issecretvalue and issecretvalue(knownEquipLoc)) or type(knownEquipLoc) ~= "string" then knownEquipLoc = nil end
    if record.classID == nil or record.subclassID == nil or knownEquipLoc == nil then
        local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
        local info = getter and { pcall(getter, record.link) } or nil
        if (not info or not info[1] or not info[2]) and GetItemInfo and getter ~= GetItemInfo then
            info = { pcall(GetItemInfo, record.link) }
        end
        if info and not info[1] then info = nil end
        local classID, subclassID, equipLoc = itemClassification(record.link, info)
        record.classID, record.subclassID = record.classID or classID, record.subclassID or subclassID
        record.equipLoc = knownEquipLoc or equipLoc
        diagnostic.classID, diagnostic.subclassID = record.classID, record.subclassID
        diagnostic.equipLoc = record.equipLoc
    end
    if record.classRestrictionsKnown ~= true then
        restrictionFormats = nil -- Native locale/class globals may have loaded since the first read.
        local lines, source, details, readable = tooltipLines(record.link)
        record.allowedClasses, record.classRestrictionsKnown, record.classRestrictionUnknownNames = classRestrictions(details, readable)
        diagnostic.tooltipLines, diagnostic.tooltipSource, diagnostic.tooltipDetails, diagnostic.tooltipReadable = lines, source, details, readable
        diagnostic.allowedClasses, diagnostic.classRestrictionsKnown, diagnostic.classRestrictionUnknownNames =
            record.allowedClasses, record.classRestrictionsKnown, record.classRestrictionUnknownNames
    end
    record.diagnostic = diagnostic
end

local labels = {
    strength = { "strength", "force" }, agility = { "agility", "agilité" },
    stamina = { "stamina", "endurance" }, intellect = { "intellect", "intelligence" },
    spirit = { "spirit", "esprit" }, health = { "health", "points de vie", "vie" },
    spellDamage = { "spell damage", "dégâts des sorts" }, healing = { "healing", "soins" },
    spellPen = { "spell penetration", "pénétration des sorts" },
    attackPower = { "attack power", "puissance d'attaque" },
    rangedAttackPower = { "ranged attack power", "puissance d'attaque à distance" },
    feralAttackPower = { "feral attack power", "puissance d'attaque farouche" },
    weaponDamage = { "weapon damage", "dégâts de l'arme", "dégâts de l’arme" },
    armor = { "armor", "armure" }, armorBonus = { "bonus armor", "armure supplémentaire" },
    blockValue = { "block value", "valeur de blocage", "block", "blocage" }, blockValueBonus = { "bonus block value", "bonus à la valeur de blocage" },
    hit = { "hit", "hit chance", "hit rating", "toucher", "chances de toucher", "score de toucher" },
    crit = { "crit", "critical strike", "critical strike chance", "critical strike rating", "critical hit", "critique", "coup critique", "chances de coup critique", "score de coup critique" },
    haste = { "haste", "haste rating", "hâte", "score de hâte" },
    expertise = { "expertise", "expertise rating", "score d'expertise" },
    defense = { "defense", "defense skill", "défense", "compétence de défense" },
    dodge = { "dodge", "dodge chance", "dodge rating", "esquive", "score d'esquive" },
    parry = { "parry", "parry chance", "parry rating", "parade", "score de parade" },
    block = { "block chance", "block rating", "chances de blocage", "score de blocage" },
}
local schools = { arcane = "arcanes", fire = "feu", nature = "nature", frost = "givre", shadow = "ombre", holy = "sacré" }
for school, french in pairs(schools) do
    labels[school .. "Damage"] = { school .. " damage", "dégâts de " .. french }
    if school ~= "holy" then
        labels[school .. "Resist"] = { school .. " resistance", "résistance au " .. french, "résistance à " .. french, "résistance aux " .. french }
    end
end

local localizedLabels
local function getLabels()
    if localizedLabels then return localizedLabels end
    localizedLabels = {}
    for key, list in pairs(labels) do
        localizedLabels[key] = {}
        for _, label in ipairs(list) do localizedLabels[key][#localizedLabels[key] + 1] = label end
    end
    for global, key in pairs(absolute) do
        local label = _G[global]
        if type(label) == "string" and not label:find("%%") then
            localizedLabels[key] = localizedLabels[key] or {}
            localizedLabels[key][#localizedLabels[key] + 1] = lower(clean(label))
        end
    end
    return localizedLabels
end

local function directValue(text, label, percent)
    label = escape(label)
    local suffix = percent and "%s*%%" or ""
    return number(text:match("^([%+%-]?[%d%.,]+)" .. suffix .. "%s+" .. label .. "$"))
        or number(text:match("^" .. label .. "%s*%+?%s*([%+%-]?[%d%.,]+)" .. suffix .. "$"))
end

local function enchantValues(content)
    local values, unknown = {}, {}
    -- Split only explicit enchant conjunctions. Each clause must still match a
    -- complete stat label/value; a known clause cannot hide an unknown effect.
    content = content:gsub(" and ", "\n"):gsub(" et ", "\n")
    for clause in (content .. "\n"):gmatch("(.-)\n") do
        local handled = false
        for key, list in pairs(getLabels()) do
            if not FW.StatByKey[key].secondary then
                for _, label in ipairs(list) do
                    local value = directValue(clause, label, false)
                    if value then add(values, key, value); handled = true; break end
                end
            end
        end
        local allStats = number(clause:match("^%+([%d%.,]+) all stats$"))
            or number(clause:match("^all stats %+(%d+)$"))
            or number(clause:match("^%+([%d%.,]+) à toutes les caractéristiques$"))
        if allStats then
            for _, key in ipairs({ "strength", "agility", "stamina", "intellect", "spirit" }) do add(values, key, allStats) end
            handled = true
        end
        if not handled then unknown[#unknown + 1] = clause end
    end
    return values, #unknown == 0, table.concat(unknown, " and ")
end

local function conditional(text)
    return text:find("^use:") or text:find("^utiliser%s*:") or text:find("^utilisation%s*:")
        or text:find("^chance on hit:") or text:find("^chances quand vous touchez")
        or text:find("^set:") or text:find("^ensemble%s*:") or text:find("^socket bonus:")
        or text:find("^bonus de sertissage%s*:") or text:find("^%(%d+%) set:")
        or text:find("^%(%d+%) ensemble%s*:")
        or text:find("when ") or text:find("whenever ") or text:find("while ")
        or text:find("has a chance to ") or text:find("gives a chance to ") or text:find("chance on ")
        or text:find("for [%d%.,]+ sec") or text:find("pendant [%d%.,]+ sec")
        or text:find("lorsque ") or text:find("quand ") or text:find("chaque fois ")
        or text:find("si vous ") or text:find("en forme ")
end

local function scope(text)
    local spell = text:find("spell") or text:find("sort")
    local melee = text:find("melee") or text:find("mêlée")
    local ranged = text:find("ranged") or text:find("distance")
    if spell and (melee or ranged) then return "generic" end
    if spell then return "spell" end
    if ranged then return "ranged" end
    if melee then return "melee" end
    return "generic"
end

function FW:IsPotentialStatLine(line)
    local text = lower(clean(line))
    if text == "" or conditional(text) or text:find("%(%d+/%d+%)") then return false end
    if text:find("^requires ") or text:find("^requiert ") or text:find("^durability ")
        or text:find("^durabilité ") or text:find("^item level ") or text:find("^niveau d'objet ") then return false end
    if text:find("^[%+%-][%d%.,]+%s*") then return true end
    if text:find("%s[%+%-][%d%.,]+%s*%%?$") then return true end
    local equip = text:find("^equip:") or text:find("^équipé%s*:") or text:find("^équipement%s*:")
    if equip and text:find("%d") then return true end
    if (text:find("^enchanted%s*:") or text:find("^enchanté%s*:")) and text:find("%d") then return true end
    return false
end

local function unrecognized(record, line, index, reason)
    record.unrecognizedLines[#record.unrecognizedLines + 1] = { text = line, index = index, side = "left", reason = reason }
    warn(record, reason .. ": " .. line)
    record.partial = true
end

local function ammoDps(content)
    local format = lower(clean(_G.ITEM_AMMO_DAMAGE_TEMPLATE)):gsub("%.$", "")
    local first, last = format:find("%%[%d%$%.]*[dfgs]")
    local value
    if first then
        value = number(content:match("^" .. escape(format:sub(1, first-1))
            .. "([%+%-]?[%d%.,]+)" .. escape(format:sub(last+1)) .. "$"))
    end
    return value or number(content:match("^adds ([%d%.,]+) damage per second$"))
        or number(content:match("^ajoute ([%d%.,]+) points de dégâts par seconde$"))
        or number(content:match("^ajoute ([%d%.,]+) dégâts par seconde$"))
end

local function scan(record, lines)
    local parsed, enchants, percentages, weapon = {}, {}, {}, {}
    local ammo = record.equipLoc == "INVTYPE_AMMO"
    local locale = GetLocale and GetLocale() or "enUS"
    local supportedLocale = locale == "enUS" or locale == "enGB" or locale == "frFR"
    if not supportedLocale then
        warn(record, "Tooltip parsing is limited on " .. locale .. "; inspect raw item stats before using tooltip-only weights.")
        record.partial = true
    end
    local setSection = false
    for lineIndex, line in ipairs(lines) do
        local text = lower(clean(line))
        if text:find("%(%d+/%d+%)") then setSection = true end
        -- Never parse the item name, set sections, use effects or triggered bonuses.
        if lineIndex > 1 and not setSection and not conditional(text) then
            local content = text:gsub("^equip:%s*", ""):gsub("^équipé%s*:%s*", "")
                :gsub("^équipement%s*:%s*", ""):gsub("%.$", "")
            local handled = false
            local enchant = content:match("^enchanted%s*:%s*(.+)$") or content:match("^enchanté%s*:%s*(.+)$")
            local unresolvedContent
            if enchant then
                local values
                values, handled, unresolvedContent = enchantValues(enchant)
                for key, value in pairs(values) do add(enchants, key, value) end
            end
            for key, list in pairs(getLabels()) do
                for _, label in ipairs(list) do
                    local definition = FW.StatByKey[key]
                    local isSecondary = definition and definition.secondary
                    local isRating = label:find("rating", 1, true) or label:find("score", 1, true)
                    local value = directValue(content, label, isSecondary and key ~= "defense" and not isRating)
                    if value then
                        if isSecondary and isRating then
                            maximum(record.ratingStats, key, value)
                            if value ~= 0 then record.unresolvedStats[key] = true end
                        elseif isSecondary then
                            percentages[key] = percentages[key] or {}
                            add(percentages[key], scope(content), value)
                        else add(parsed, key, value) end
                        handled = true; break
                    end
                end
            end
            local allStats = number(content:match("^%+([%d%.,]+) all stats$")) or number(content:match("^%+([%d%.,]+) à toutes les caractéristiques$"))
            if allStats then
                for _, key in ipairs({ "strength", "agility", "stamina", "intellect", "spirit" }) do add(parsed, key, allStats) end
                handled = true
            end
            local low, high = content:match("^([%d%.,]+)%s*%-%s*([%d%.,]+)%s+damage$")
            if not low then low, high = content:match("^([%d%.,]+)%s*%-%s*([%d%.,]+)%s+dégâts$") end
            if low then add(weapon, "low", number(low)); add(weapon, "high", number(high)); handled = true end
            local speed = number(content:match("^speed%s+([%d%.,]+)$")) or number(content:match("^vitesse%s+([%d%.,]+)$"))
            if speed then weapon.speed, handled = speed, true end
            local dps = number(content:match("^%(([%d%.,]+) damage per second%)$"))
                or number(content:match("^%(([%d%.,]+) dégâts par seconde%)$"))
            if ammo then dps = dps or ammoDps(content) end
            if dps then weapon.dps, handled = dps, true end

            -- Expertise's explicitly displayed dodge-and-parry reduction is
            -- already a percentage. A lone dodge/parry bonus is not expertise.
            local expertise = number(content:match("^reduces the chance for your attacks to be dodged or parried by ([%d%.,]+)%%$"))
                or number(content:match("^%-([%d%.,]+)%%%s+chance to be dodged or parried$"))
                or number(content:match("^réduit les chances que vos attaques soient esquivées ou parées de ([%d%.,]+)%%$"))
                or number(content:match("^%-([%d%.,]+)%%%s+de chances d'être esquivé ou paré$"))
            if expertise then
                percentages.expertise = percentages.expertise or {}
                add(percentages.expertise, "generic", expertise)
                handled = true
            end

            -- Static classic tooltip sentences. The effect must match the whole
            -- line's stat wording and pass the conditional-effect filter above.
            local pct = number(content:match("([%d%.,]+)%s*%%"))
            local _, percentCount = content:gsub("%%", "")
            if not handled and pct and percentCount == 1 then
                local key
                if content:find("hit") or content:find("toucher") then key = "hit"
                elseif content:find("critical") or content:find("critique") then key = "crit"
                elseif content:find("haste") or content:find("hâte") or content:find("attack speed") or content:find("vitesse d'attaque") then key = "haste"
                elseif content:find("expertise") then key = "expertise"
                elseif content:find("dodge") or content:find("esquive") then key = "dodge"
                elseif content:find("parry") or content:find("parade") then key = "parry"
                elseif content:find("block") or content:find("blocage") then key = "block" end
                if key and (content:find("^increases ") or content:find("^improves ") or content:find("^augmente ") or content:find("^améliore ")) then
                    percentages[key] = percentages[key] or {}; add(percentages[key], scope(content), pct); handled = true
                end
            end
            if not handled then
                for secondary in pairs(secondaryAliases) do
                    local name = secondary == "crit" and "critical strike" or secondary
                    local value = number(content:match("^increases your " .. name .. " rating by ([%d%.,]+)$"))
                        or number(content:match("^increases " .. name .. " rating by ([%d%.,]+)$"))
                    if value then
                        maximum(record.ratingStats, secondary, value)
                        if value ~= 0 then record.unresolvedStats[secondary] = true end
                        handled = true
                    end
                end
                local frenchRatings = { hit = "toucher", crit = "coup critique", haste = "hâte", expertise = "expertise", dodge = "esquive", parry = "parade", block = "blocage", defense = "défense" }
                for secondary, name in pairs(frenchRatings) do
                    local value = number(content:match("^augmente votre score de " .. name .. " de ([%d%.,]+)$"))
                        or number(content:match("^augmente le score de " .. name .. " de ([%d%.,]+)$"))
                        or number(content:match("^augmente votre score d'" .. name .. " de ([%d%.,]+)$"))
                    if value then
                        maximum(record.ratingStats, secondary, value)
                        if value ~= 0 then record.unresolvedStats[secondary] = true end
                        handled = true
                    end
                end
            end
            if not handled then
                local value = number(content:match("^restores ([%d%.,]+) mana per 5 sec"))
                    or number(content:match("^rend ([%d%.,]+) points de mana toutes les 5 sec"))
                if value then add(parsed, "mp5", value); handled = true end
                value = number(content:match("^restores ([%d%.,]+) health per 5 sec"))
                    or number(content:match("^rend ([%d%.,]+) points de vie toutes les 5 sec"))
                if value then add(parsed, "hp5", value); handled = true end
            end
            if not handled then
                local value = number(content:match("^increases attack power by ([%d%.,]+)$"))
                    or number(content:match("^augmente la puissance d'attaque de ([%d%.,]+)$"))
                if value then add(parsed, "attackPower", value); handled = true end
                value = number(content:match("^increases ranged attack power by ([%d%.,]+)$"))
                    or number(content:match("^augmente la puissance d'attaque à distance de ([%d%.,]+)$"))
                if value then add(parsed, "rangedAttackPower", value); handled = true end
                value = number(content:match("^increases the block value of your shield by ([%d%.,]+)$"))
                    or number(content:match("^augmente la valeur de blocage de votre bouclier de ([%d%.,]+)$"))
                if value then add(parsed, "blockValueBonus", value); handled = true end
                value = number(content:match("^increased defense %+(%d+)$"))
                    or number(content:match("^increases defense skill by (%d+)$"))
                    or number(content:match("^augmente la compétence de défense de (%d+)$"))
                if value then percentages.defense = percentages.defense or {}; add(percentages.defense, "generic", value); handled = true end
            end
            if not handled then
                local healing, damage = content:match("^increases healing done by up to ([%d%.,]+) and damage done by up to ([%d%.,]+) for all magical spells and effects$")
                if healing and damage then
                    add(parsed, "healing", number(healing)); add(parsed, "spellDamage", number(damage)); handled = true
                end
                local value = number(content:match("^increases damage and healing done by magical spells and effects by up to ([%d%.,]+)$"))
                    or number(content:match("^augmente les dégâts et les soins produits par les sorts et effets magiques de ([%d%.,]+) au maximum$"))
                if value then add(parsed, "spellDamage", value); add(parsed, "healing", value); handled = true end
                value = number(content:match("^increases healing done by spells and effects by up to ([%d%.,]+)$"))
                    or number(content:match("^augmente les soins prodigués par les sorts et effets de ([%d%.,]+) au maximum$"))
                if value then add(parsed, "healing", value); handled = true end
                value = number(content:match("^increases damage done by magical spells and effects by up to ([%d%.,]+)$"))
                if value then add(parsed, "spellDamage", value); handled = true end
                for school, french in pairs(schools) do
                    value = number(content:match("^increases damage done by " .. school .. " spells and effects by up to ([%d%.,]+)$"))
                        or number(content:match("^increases " .. school .. " spell damage by up to ([%d%.,]+)$"))
                        or number(content:match("^augmente les dégâts infligés par les sorts et effets de " .. french .. " de ([%d%.,]+) au maximum$"))
                        or number(content:match("^augmente les dégâts des sorts de " .. french .. " de ([%d%.,]+) au maximum$"))
                    if value then add(parsed, school .. "Damage", value); handled = true end
                end
            end
            if not handled and (text:find("^equip:") or text:find("^équipé%s*:") or text:find("^équipement%s*:")) then
                -- Surface a known static stat that could not be read. Arbitrary
                -- procs and flavor text are excluded and do not create warnings.
                for key, list in pairs(getLabels()) do
                    for _, label in ipairs(list) do
                        if (unresolvedContent or content):find(label, 1, true) then
                            record.unresolvedStats[key] = true
                            break
                        end
                    end
                end
            end
            if not handled and FW:IsPotentialStatLine(line) then
                for key, list in pairs(getLabels()) do
                    for _, label in ipairs(list) do
                        if (unresolvedContent or content):find(label, 1, true) then record.unresolvedStats[key] = true; break end
                    end
                end
                unrecognized(record, line, lineIndex, "Unrecognized static item stat")
            end
        end
    end
    local apiArmor = record.stats.armor
    for key, value in pairs(parsed) do record.stats[key] = value end
    if parsed.blockValueBonus and parsed.blockValue == nil and record.stats.blockValue == parsed.blockValueBonus then
        record.stats.blockValue = nil
    end
    -- Some classic clients expose school-only spell damage in the generic API
    -- slot. An explicit school-only tooltip is more specific than that alias.
    local schoolTotal = 0
    for school in pairs(schools) do schoolTotal = schoolTotal + (parsed[school .. "Damage"] or 0) end
    if schoolTotal > 0 and parsed.spellDamage == nil and record.stats.spellDamage == schoolTotal then
        record.stats.spellDamage = nil
        if parsed.healing == nil and record.stats.healing == schoolTotal then record.stats.healing = nil end
    end
    for key, value in pairs(enchants) do
        -- The API exposes base item stats. Some tooltips fold armor enchants
        -- into the armor line; that displayed total must not gain it twice.
        if key ~= "armor" or not apiArmor or not parsed.armor or parsed.armor < apiArmor + value then
            add(record.stats, key, value)
        end
    end
    for key, values in pairs(percentages) do
        record.percentStats[key] = math.max(values.generic or 0, values.melee or 0, values.ranged or 0, values.spell or 0)
        record.unresolvedStats[key] = nil
    end
    if weapon.low and weapon.high then
        record.stats.lowDamage, record.stats.highDamage = weapon.low, weapon.high
        if weapon.speed and weapon.speed > 0 then weapon.dps = weapon.dps or (weapon.low + weapon.high) / 2 / weapon.speed end
    end
    local ranged = rangedItem(record)
    if weapon.speed then record.stats[ranged and "rangedSpeed" or "speed"] = weapon.speed end
    if weapon.dps then record.stats[ranged and "rangedDps" or "dps"] = weapon.dps end
    local weaponItem = (ranged and not ammo) or record.equipLoc == "INVTYPE_WEAPON" or record.equipLoc == "INVTYPE_2HWEAPON"
        or record.equipLoc == "INVTYPE_WEAPONMAINHAND" or record.equipLoc == "INVTYPE_WEAPONOFFHAND"
    if weaponItem and (not weapon.low or not weapon.high or not weapon.speed) then
        for _, key in ipairs({ "lowDamage", "highDamage", ranged and "rangedSpeed" or "speed", ranged and "rangedDps" or "dps" }) do
            if record.stats[key] == nil then record.unresolvedStats[key] = true end
        end
        warn(record, "Weapon damage or speed was not available from the tooltip.")
        record.partial = true
    end
    if ammo and record.stats.rangedDps == nil then
        record.unresolvedStats.rangedDps = true
        warn(record, "Ammunition DPS was not available from the item data or tooltip.")
        record.partial = true
    end
end

function FW:GetItem(link)
    local key = self:ItemKey(link)
    if not key then return nil, "Invalid item link." end
    self.DB.cache.items = self.DB.cache.items or {}
    self.DB.cache.itemOrder = self.DB.cache.itemOrder or {}
    local cached = self.DB.cache.items[key]
    if cached then return cached end
    local diagnostic, err = self:GetRawItemStats(link)
    if not diagnostic then return nil, err end
    if not diagnostic.ready then return nil, "Item data is still loading." end
    local record = { key = key, link = diagnostic.link or link, itemID = diagnostic.itemID,
        equipLoc = diagnostic.equipLoc, stats = {}, percentStats = {}, ratingStats = {},
        classID = diagnostic.classID, subclassID = diagnostic.subclassID,
        allowedClasses = diagnostic.allowedClasses, classRestrictionsKnown = diagnostic.classRestrictionsKnown,
        classRestrictionUnknownNames = diagnostic.classRestrictionUnknownNames,
        unresolvedStats = {}, unrecognizedLines = {}, warnings = {}, partial = false,
        name = diagnostic.name, parserVersion = PARSER_VERSION,
        diagnostic = self.CopyItemDiagnostic and self:CopyItemDiagnostic(diagnostic) or diagnostic }
    local gear, gearError = self:IsGearItem(record)
    if gear == false then return record end
    if gear == nil then return nil, gearError end
    for rawKey, rawValue in pairs(diagnostic.raw) do
        if issecretvalue and issecretvalue(rawKey) then rawKey = nil end
        local value = number(rawValue)
        if value == nil and (absolute[rawKey] or ratings[rawKey] or untyped[rawKey]) then
            local stat = absolute[rawKey] or ratings[rawKey] or untyped[rawKey]
            record.unresolvedStats[stat] = true
            warn(record, "Item API value unavailable for " .. rawKey)
            record.partial = true
        end
        if absolute[rawKey] then maximum(record.stats, absolute[rawKey], value)
        elseif ratings[rawKey] then
            maximum(record.ratingStats, ratings[rawKey], value)
            if value and value ~= 0 then record.unresolvedStats[ratings[rawKey]] = true end
        elseif untyped[rawKey] then
            if value and value ~= 0 then record.unresolvedStats[untyped[rawKey]] = true end
        elseif rawKey == "ITEM_MOD_SPELL_POWER_SHORT" or rawKey == "ITEM_MOD_SPELL_POWER" then
            maximum(record.stats, "spellDamage", value); maximum(record.stats, "healing", value)
            if value == nil then
                record.unresolvedStats.spellDamage, record.unresolvedStats.healing = true, true
                warn(record, "Item API spell power value was not available."); record.partial = true
            end
        elseif rawKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" or rawKey == "ITEM_MOD_DAMAGE_PER_SECOND" then
            local ranged = rangedItem(record)
            maximum(record.stats, ranged and "rangedDps" or "dps", value)
            if value == nil then
                record.unresolvedStats[ranged and "rangedDps" or "dps"] = true
                warn(record, "Item API weapon DPS value was not available."); record.partial = true
            end
        end
    end
    if #diagnostic.unknownKeys > 0 then
        record.unknownAPIStats = diagnostic.unknownKeys
        warn(record, "Unrecognized item API stats: " .. table.concat(diagnostic.unknownKeys, ", "))
        record.partial = true
    end
    if #diagnostic.tooltipLines == 0 then
        warn(record, "Item tooltip data was not available; tooltip-only stats may be missing.")
        record.partial = true
        local ammo = record.equipLoc == "INVTYPE_AMMO"
        local weaponOnly = {dps=true,lowDamage=true,highDamage=true,weaponDamage=true,speed=true,rangedSpeed=true}
        for _, stat in ipairs({ "hp5", "mp5", "arcaneDamage", "fireDamage", "natureDamage", "frostDamage", "shadowDamage", "holyDamage",
            "feralAttackPower", "dps", "lowDamage", "highDamage", "weaponDamage", "speed", "rangedDps", "rangedSpeed", "armorBonus", "blockValueBonus" }) do
            if record.stats[stat] == nil and not (ammo and weaponOnly[stat]) then record.unresolvedStats[stat] = true end
        end
    else scan(record, diagnostic.tooltipLines) end
    for _, rawKey in ipairs(diagnostic.unknownKeys) do
        local label = _G[rawKey]
        if type(label) == "string" and not label:find("%%") then
            local labelText = lower(clean(label))
            for index, line in ipairs(diagnostic.tooltipLines) do
                if index > 1 and self:IsPotentialStatLine(line) and lower(line):find(labelText, 1, true) then
                    local alreadyPresent = false
                    for _, entry in ipairs(record.unrecognizedLines) do
                        if entry.text == line then alreadyPresent = true; break end
                    end
                    if not alreadyPresent then unrecognized(record, line, index, "Unrecognized item API stat " .. rawKey) end
                end
            end
        end
    end
    if next(record.stats) == nil and next(record.percentStats) == nil and next(record.ratingStats) == nil
        and #diagnostic.tooltipLines <= 1 then
        warn(record, "No item stats or complete tooltip were available.")
        record.partial = true
    end
    -- RESISTANCE0_NAME/the armor tooltip reports total armor. Keep the explicit
    -- bonus portion separate so base+bonus profiles do not count it twice.
    if record.stats.armor and record.stats.armorBonus then
        record.stats.armor = math.max(0, record.stats.armor - record.stats.armorBonus)
    end
    if self.RecordItemIssue then self:RecordItemIssue(record) end
    if not record.partial then
        self.DB.cache.items[key] = record
        local order = self.DB.cache.itemOrder
        order[#order + 1] = key
        while #order > MAX_ITEMS do
            local removed = table.remove(order, 1)
            self.DB.cache.items[removed] = nil
            if self.DB.cache.scores then self.DB.cache.scores[removed] = nil end
        end
    end
    return record
end
