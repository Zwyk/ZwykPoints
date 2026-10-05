-- Count work in the real item -> score -> comparison -> tooltip/marker pipeline.
-- Fake time makes retry limits deterministic; this is not an FPS benchmark.
-- Run from the addon directory: luatex --luaonly tests/test_hover_performance.lua
local FW, checks = {}, 0
local function check(value, message)
    assert(value, message or "assertion failed")
    checks = checks + 1
end
local function equal(actual, expected, message)
    check(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local clock, timers, frames = 10, {}, {}
GetTime = function() return clock end
GetTimePreciseSec = GetTime
C_Timer = { After = function(delay, callback) timers[#timers+1] = { at = clock + delay, callback = callback } end }
local function pump()
    for _ = 1, 100 do
        local pending, ran = timers, false
        timers = {}
        for _, timer in ipairs(pending) do
            if timer.at <= clock then timer.callback(); ran = true
            else timers[#timers+1] = timer end
        end
        if not ran then return end
    end
    error("timer callbacks did not settle")
end

local function object(name, parent)
    local frame = { name = name, parent = parent, shown = true, events = {}, scripts = {}, hooks = {}, id = 0, lines = {} }
    frames[#frames+1] = frame
    if name then _G[name] = frame end
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetID() return self.id end
    function frame:SetID(id) self.id = id end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:IsForbidden() return false end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:HasScript() return true end
    function frame:HookScript(event, callback)
        self.hooks[event] = self.hooks[event] or {}
        self.hooks[event][#self.hooks[event]+1] = callback
    end
    function frame:Fire(event, ...)
        if self.scripts[event] then self.scripts[event](self, ...) end
        for _, callback in ipairs(self.hooks[event] or {}) do callback(self, ...) end
    end
    function frame:Show() self.shown = true; self:Fire("OnShow") end
    function frame:Hide() self.shown = false; self:Fire("OnHide") end
    function frame:CreateTexture()
        local texture = { shown = false }
        function texture:SetTexture(value) self.path = value end
        function texture:SetSize() end
        function texture:SetPoint() end
        function texture:Show() self.shown = true end
        function texture:Hide() self.shown = false end
        return texture
    end
    return frame
end
UIParent = object("UIParent")
CreateFrame = function(_, name, parent) return object(name, parent) end
hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then callback, method, target = method, target, _G end
    local original = assert(target[method])
    target[method] = function(...)
        local values = { original(...) }
        callback(...)
        return (unpack or table.unpack)(values)
    end
end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
local function event(kind, ...)
    local recipients = {}
    for _, frame in ipairs(frames) do if frame.events[kind] then recipients[#recipients+1] = frame end end
    for _, frame in ipairs(recipients) do frame:Fire("OnEvent", kind, ...) end
end

local definitions, inventory = {}, {}
local work = { reads = {}, scans = {}, requests = {}, scores = 0, compares = 0, deltas = 0, indicatorRefreshes = 0, tooltipRefreshes = 0, invalidations = 0 }
local function increment(map, id) map[id] = (map[id] or 0) + 1 end
local function total(map) local count = 0 for _, value in pairs(map) do count = count + value end return count end
local function link(id) return "item:" .. id .. ":0:0:0:0:0:0:0:60" end
local function definition(itemLink)
    local id = type(itemLink) == "string" and tonumber(itemLink:match("item:(%d+)"))
    return definitions[id], id
end
local function addItem(id, strength, options)
    local item = options or {}
    item.name, item.strength = "Performance item " .. id, strength
    if item.equipLoc == nil then item.equipLoc = "INVTYPE_HEAD" end
    if item.classID == nil then item.classID = 4 end
    if item.subclassID == nil then item.subclassID = 4 end
    if item.ready == nil then item.ready = true end
    definitions[id] = item
    return link(id)
end
local function sourceLines(itemLink)
    local item = assert(definition(itemLink), "unknown test item")
    if not item.ready or item.placeholder then return { "Retrieving item information" } end
    local lines = { item.name, "+" .. item.strength .. " Strength" }
    if item.partial then lines[#lines+1] = "+3 Mystic Focus" end
    return lines
end
GetBuildInfo = function() return "16.0.0", "65000", "Oct 2026", 160000 end
GetLocale = function() return "enUS" end
local level = 60
UnitLevel = function() return level end
UnitClass = function() return "Paladin", "PALADIN" end
GetInventoryItemLink = function(_, slot) return inventory[slot] end
GetItemInfo = function(itemLink)
    local item = definition(itemLink)
    if not item or not item.ready then return nil end
    return item.name, itemLink, 3, 60, 60, "Armor", "Plate", 1, item.equipLoc, nil, nil,
        not item.metadataMissing and item.classID or nil, not item.metadataMissing and item.subclassID or nil
end
C_Item = {
    GetItemInfo = GetItemInfo,
    IsItemDataCachedByID = function(id) return definitions[id] and definitions[id].ready == true end,
    RequestLoadItemDataByID = function(id)
        increment(work.requests, id)
        if definitions[id] and definitions[id].feedback then
            event("GET_ITEM_INFO_RECEIVED", id, true)
            event("ITEM_DATA_LOAD_RESULT", id, true)
        end
    end,
    GetItemStats = function(itemLink)
        local item, id = definition(itemLink)
        increment(work.reads, id)
        local stats = { ITEM_MOD_STRENGTH_SHORT = item.strength }
        if item.partial then stats.ITEM_MOD_FOREVER_FOCUS_SHORT = 3 end
        return stats
    end,
}
C_TooltipInfo = { GetHyperlink = function(itemLink)
    local _, id = definition(itemLink)
    increment(work.scans, id)
    local lines = {}
    for _, text in ipairs(sourceLines(itemLink)) do lines[#lines+1] = { leftText = text } end
    return { lines = lines }
end }
RETRIEVING_ITEM_INFO, RETRIEVING_DATA = "Retrieving item information", "Retrieving data"
Enum = { TooltipDataType = { Item = 1 } }
local postCall
TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) postCall = callback end }
GameTooltip = object("GameTooltip", UIParent)
GameTooltip.shown = false
function GameTooltip:AddLine(text) self.lines[#self.lines+1] = { left = text } end
function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines+1] = { left = left, right = right } end
function GameTooltip:NumLines() return #self.lines end
function GameTooltip:GetItem() local item = definition(self.link) return item and item.name, self.link end
function GameTooltip:IsEquippedItem() return false end
function GameTooltip:ClearLines() self.lines = {}; self:Fire("OnTooltipCleared") end
function GameTooltip:SetHyperlink(itemLink)
    self:ClearLines(); self.link = itemLink; self.shown = true
    for _, text in ipairs(sourceLines(itemLink)) do self:AddLine(text) end
    if postCall then postCall(self, { hyperlink = itemLink }) end
    self:Fire("OnTooltipSetItem")
end
function GameTooltip:RefreshData() self:SetHyperlink(self.link) end
local function profileLine()
    for _, line in ipairs(GameTooltip.lines) do if line.left == "Main" then return line.right end end
end
local function warningLine()
    for _, line in ipairs(GameTooltip.lines) do if line.left:find("Partial stat data", 1, true) then return true end end
    return false
end

NUM_CONTAINER_FRAMES, NUM_BAG_SLOTS = 1, 4
local bag = object("ContainerFrame1", UIParent)
bag.Items = {}
function bag:EnumerateValidItems() return ipairs(self.Items) end
function bag:UpdateItems() end
function bag:UpdateItemSlots() end
local bagLinks = {}
for index = 1, 20 do
    local options = index == 19 and { classID = 0, subclassID = 0, equipLoc = "" } or
        index == 20 and { classID = 1, subclassID = 0, equipLoc = "INVTYPE_BAG" } or nil
    bagLinks[index] = addItem(1000 + index, 10 + index, options)
    local button = object(nil, bag)
    button.id, button.icon = index, {}
    function button:GetBagID() return 0 end
    bag.Items[index] = button
end
ContainerFrameContainer = { ContainerFrames = { bag } }
C_Container = { GetContainerItemLink = function(bagID, slot) if bagID == 0 then return bagLinks[slot] end end }
local normalBaseline = addItem(2000, 8)
inventory[1] = normalBaseline
for _, file in ipairs({ "JSON.lua", "Stats.lua", "Core.lua", "Items.lua", "Compare.lua", "Upgrades.lua", "Tooltips.lua", "Indicators.lua", "Bootstrap.lua" }) do
    assert(loadfile(file))("ZwykValues", FW)
end
local actualScore, actualCompare, actualDelta = FW.ScoreStats, FW.CompareItem, FW.CalculateDelta
function FW:ScoreStats(...) work.scores = work.scores + 1; return actualScore(self, ...) end
function FW:CompareItem(...) work.compares = work.compares + 1; return actualCompare(self, ...) end
function FW:CalculateDelta(...) work.deltas = work.deltas + 1; return actualDelta(self, ...) end
local actualIndicatorRefresh, actualTooltipRefresh, actualInvalidate = FW.RefreshUpgradeIndicators, FW.RefreshTooltips, FW.InvalidateUpgradeComparisons
function FW:RefreshUpgradeIndicators(...) work.indicatorRefreshes = work.indicatorRefreshes + 1; return actualIndicatorRefresh(self, ...) end
function FW:RefreshTooltips(...) work.tooltipRefreshes = work.tooltipRefreshes + 1; return actualTooltipRefresh(self, ...) end
function FW:InvalidateUpgradeComparisons(...) work.invalidations = work.invalidations + 1; return actualInvalidate(self, ...) end
event("ADDON_LOADED", "ZwykValues")
local profile = FW:GetProfiles()[1]
assert(FW:UpdateProfile(profile.id, { name = "Main", active = false, weights = { strength = 2 } }))
assert(FW:SetMainProfile(profile.id))
assert(FW:SetUpgradeOption("upgradeBags", true))
pump()
equal(#FW:GetProfiles(true), 0, "main markers work independently of active tooltip profiles")
for index = 1, 18 do check(bag.Items[index].zvUpgradeArrow and bag.Items[index].zvUpgradeArrow.shown, "eligible bag upgrades receive arrows") end
check(not bag.Items[19].zvUpgradeArrow and not bag.Items[20].zvUpgradeArrow, "consumables and bags remain excluded")
local warmedReads, warmedScans, warmedCompares = total(work.reads), total(work.scans), work.compares
for _ = 1, 10 do FW:RefreshUpgradeIndicators(); pump() end
equal(total(work.reads), warmedReads, "warm bag repaints do not re-extract even excluded nongear")
equal(total(work.scans), warmedScans, "warm bag repaints do not rescan tooltips")
equal(work.compares, warmedCompares, "warm upgrade and excluded decisions reuse marker comparisons")

local beforeEvents = { refresh = work.indicatorRefreshes, invalidate = work.invalidations, reads = total(work.reads), scans = total(work.scans), compare = work.compares }
for id = 9001, 9020 do event("GET_ITEM_INFO_RECEIVED", id, true); event("ITEM_DATA_LOAD_RESULT", id, true); pump() end
equal(work.indicatorRefreshes, beforeEvents.refresh, "unrelated successful loads do not repaint 20 visible bag items")
equal(work.invalidations, beforeEvents.invalidate, "unrelated item loads do not invalidate upgrade comparisons")
equal(total(work.reads), beforeEvents.reads, "unrelated item loads do not extract visible bag items")
equal(total(work.scans), beforeEvents.scans, "unrelated item loads do not rescan visible bag items")
equal(work.compares, beforeEvents.compare, "unrelated item loads do not reconstruct warm comparisons")

bag:Hide()
local partialCandidate = addItem(2101, 35, { partial = true })
local partialBaseline = addItem(2102, 30, { partial = true })
inventory[1] = partialBaseline
event("PLAYER_EQUIPMENT_CHANGED", 1); pump()
equal(FW:GetScore(partialCandidate, profile), 70, "partial candidate retains its known subtotal")
equal(FW:GetScore(partialBaseline, profile), 60, "partial baseline retains its known subtotal")
local partialComparison = assert(FW:CompareItem(partialCandidate, profile))
check(partialComparison.hasIssues and partialComparison.comparisons[1].hasIssues, "partial baseline issues reach comparisons")
assert(FW:CompareBaseItem(partialCandidate, profile))
check(not FW:IsMainProfileUpgrade(partialCandidate), "partial candidates cannot establish an upgrade arrow")
local partialWork = { reads = total(work.reads), scans = total(work.scans), scores = work.scores }
for _ = 1, 40 do
    equal(FW:GetScore(partialCandidate, profile), 70)
    equal(FW:GetScore(partialBaseline, profile), 60)
    assert(FW:CompareItem(partialCandidate, profile))
    assert(FW:CompareBaseItem(partialCandidate, profile))
    check(not FW:IsMainProfileUpgrade(partialCandidate))
end
equal(total(work.reads), partialWork.reads, "rapid partial reads share temporary item extraction")
equal(total(work.scans), partialWork.scans, "rapid partial reads share temporary tooltip scans")
equal(work.scores, partialWork.scores, "rapid partial scores share temporary weighted totals")
check(not FW.DB.cache.items[FW:ItemKey(partialCandidate)] and not FW.DB.cache.scores[FW:ItemKey(partialCandidate)], "partial temporary results never enter persistent caches")

assert(FW:UpdateProfile(profile.id, { active = true }))
GameTooltip:SetHyperlink(partialCandidate)
check(warningLine(), "temporary partial tooltip still shows its diagnostic warning")
local beforeClears = { reads = total(work.reads), scans = total(work.scans), scores = work.scores }
definitions[2101].partial, definitions[2101].strength = false, 45
definitions[2102].partial = false
for _ = 1, 20 do GameTooltip:SetHyperlink(partialCandidate) end
equal(total(work.reads), beforeClears.reads, "rapid native tooltip clears reuse transient extraction")
equal(total(work.scans), beforeClears.scans, "rapid native tooltip clears reuse transient scans")
equal(work.scores, beforeClears.scores, "rapid native tooltip clears reuse transient scores")
clock = clock + 1.1; pump()
GameTooltip:SetHyperlink(partialCandidate)
check(profileLine() and profileLine():find("90.00", 1, true), "bounded retry recovers changed candidate stats without a load event")
check(not warningLine(), "bounded retry clears recovered partial warnings")
check(FW.DB.cache.items[FW:ItemKey(partialCandidate)] and FW.DB.cache.scores[FW:ItemKey(partialCandidate)], "recovered complete results enter persistent caches")

local pendingCandidate = addItem(2201, 40, { ready = false })
inventory[1] = normalBaseline
event("PLAYER_EQUIPMENT_CHANGED", 1); pump()
GameTooltip:SetHyperlink(pendingCandidate)
for _ = 1, 15 do GameTooltip:SetHyperlink(pendingCandidate) end
equal(work.requests[2201], 1, "repeated pending tooltips issue one loading request")
check(FW.PendingItems and FW.PendingItems[2201], "requested pending item remains tracked")
definitions[2201].ready = true
local beforeLoadedRefresh = work.tooltipRefreshes
event("ITEM_DATA_LOAD_RESULT", 2201, true); pump()
check(work.tooltipRefreshes > beforeLoadedRefresh, "successful requested item loading refreshes the pending tooltip")
check(profileLine() and profileLine():find("80.00", 1, true), "loaded candidate replaces the pending tooltip with a score")
check(not FW.PendingItems[2201], "successful item loading clears the request")

local pendingBaseline = addItem(2202, 20, { ready = false })
inventory[1] = pendingBaseline
event("PLAYER_EQUIPMENT_CHANGED", 1); pump()
GameTooltip:SetHyperlink(pendingCandidate)
check(profileLine() and profileLine():find("comparison unavailable", 1, true), "pending equipped baseline preserves candidate scores")
check(not FW:IsMainProfileUpgrade(pendingCandidate), "pending baseline does not establish an upgrade marker")
equal(work.requests[2202], 1, "pending equipped baseline loading request is deduplicated")
definitions[2202].ready = true
beforeLoadedRefresh = work.tooltipRefreshes
event("GET_ITEM_INFO_RECEIVED", 2202, true); pump()
check(work.tooltipRefreshes > beforeLoadedRefresh, "successful requested equipped baseline loading refreshes the hovered comparison")
check(profileLine() and profileLine():find("+40.00 (+100.0%)", 1, true), "loaded equipped baseline unblocks the comparison")
check(FW:IsMainProfileUpgrade(pendingCandidate), "loaded baseline unblocks the upgrade marker")

-- A cached tooltip placeholder can synchronously emit two successful load
-- callbacks without becoming readable. That feedback must not create a scan /
-- request / repaint loop during repeated native clears in the same frame.
local feedbackCandidate = addItem(2401, 42, { placeholder = true, feedback = true })
GameTooltip:SetHyperlink(feedbackCandidate)
local feedbackRequests, feedbackRefreshes = work.requests[2401] or 0, work.tooltipRefreshes
for _ = 1, 30 do GameTooltip:SetHyperlink(feedbackCandidate) end
equal(work.requests[2401] or 0, feedbackRequests, "same-frame successful placeholder feedback does not repeat load requests")
equal(work.tooltipRefreshes, feedbackRefreshes, "same-frame successful placeholder feedback does not repeat tooltip rebuilds")
check(feedbackRequests <= 1, "cached placeholder sends at most one request in a retry interval")
definitions[2401].placeholder = false
clock = clock + 1.1; pump()
GameTooltip:SetHyperlink(feedbackCandidate)
check(profileLine() and profileLine():find("84.00", 1, true), "bounded retries recover a placeholder after its real stats arrive")

local beforeWeights = total(work.reads)
assert(FW:UpdateProfile(profile.id, { weights = { strength = 3 } }))
equal(FW:GetScore(pendingCandidate, profile), 120, "profile changes invalidate weighted totals")
equal(total(work.reads), beforeWeights, "profile changes retain complete item extractions")
local heavierBaseline = addItem(2301, 60)
inventory[1] = heavierBaseline
event("PLAYER_EQUIPMENT_CHANGED", 1); pump()
local equipmentChanged = assert(FW:CompareItem(pendingCandidate, profile))
equal(equipmentChanged.comparisons[1].delta, -60, "equipment changes invalidate baseline comparisons")
check(not FW:IsMainProfileUpgrade(pendingCandidate), "equipment changes invalidate cached upgrade decisions")
definitions[2201].strength = 45
local beforeCacheClear = work.reads[2201]
FW:InvalidateCache(); pump()
equal(FW:GetScore(pendingCandidate, profile), 135, "cache clearing invalidates stored and temporary totals")
check(work.reads[2201] > beforeCacheClear, "cache clearing forces fresh candidate extraction")
definitions[2201].strength = 50
assert(FW:InvalidateItem(pendingCandidate))
equal(FW:GetScore(pendingCandidate, profile), 150, "targeted item invalidation clears transient and persistent results")
local previousKey = FW:ItemKey(pendingCandidate)
level = 61
event("PLAYER_LEVEL_UP", 61); pump()
check(FW:ItemKey(pendingCandidate) ~= previousKey, "level changes do not reuse another level's item identity")
equal(FW:GetScore(pendingCandidate, profile), 150, "level invalidation rebuilds the current score")

-- Numerically readable items may still be awaiting class/subclass metadata.
-- The type-filter path must register that wait and recover on its completion.
assert(FW:UpdateProfile(profile.id, { itemFilters = { armor = { ["1"] = false } } }))
local metadataCandidate = addItem(2501, 80, { metadataMissing = true })
GameTooltip:SetHyperlink(metadataCandidate)
check(not profileLine(), "missing type metadata does not bypass profile exclusions")
check(FW.PendingItems and FW.PendingItems[2501], "unknown filter metadata registers an awaited item")
local metadataRequests = work.requests[2501]
for _ = 1, 20 do GameTooltip:SetHyperlink(metadataCandidate) end
equal(work.requests[2501], metadataRequests, "repeated metadata waits do not request data every hover")
definitions[2501].metadataMissing = false
local metadataRefreshes = work.tooltipRefreshes
event("ITEM_DATA_LOAD_RESULT", 2501, true); pump()
check(work.tooltipRefreshes > metadataRefreshes, "metadata completion refreshes the waiting tooltip")
check(profileLine() and profileLine():find("240.00", 1, true), "recovered type metadata resumes profile scoring")
check(FW:IsMainProfileUpgrade(metadataCandidate), "recovered type metadata resumes upgrade markers")

print("Hover performance: " .. checks .. " checks passed (deterministic pipeline work counts).")
