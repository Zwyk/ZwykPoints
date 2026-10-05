-- BetterBags 0.5.14 message/lifecycle integration, without loading its UI.
local FW = { DB = { options = { upgradeBags = false, upgradeRolls = false } } }
local verdicts, scored, timers = {}, {}, {}
function FW:IsMainProfileUpgrade(link) scored[#scored + 1] = link; return verdicts[link] == true end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function pump()
    local pending = timers; timers = {}
    for _, callback in ipairs(pending) do callback() end
end
local function frame(parent)
    local result = { parent = parent, shown = true, hooks = {}, scripts = {}, textures = {}, events = {} }
    function result:IsForbidden() return false end
    function result:IsShown() return self.shown end
    function result:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function result:HookScript(name, callback)
        self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], callback)
    end
    function result:SetScript(name, callback) self.scripts[name] = callback end
    function result:Fire(name, ...)
        if self.scripts[name] then self.scripts[name](self, ...) end
        for _, callback in ipairs(self.hooks[name] or {}) do callback(self, ...) end
    end
    function result:Show() self.shown = true; self:Fire("OnShow") end
    function result:Hide() self.shown = false; self:Fire("OnHide") end
    function result:RegisterEvent(event) self.events[event] = true end
    function result:CreateTexture(_, layer, _, sublayer)
        assert(layer == "OVERLAY" and sublayer == 7)
        local texture = { shown = false }
        function texture:Hide() self.shown = false end
        function texture:Show() self.shown = true end
        function texture:SetTexture(path) self.path = path end
        function texture:SetSize(w, h) self.w, self.h = w, h end
        function texture:SetPoint(...) self.anchor = {...} end
        self.textures[#self.textures + 1] = texture
        return texture
    end
    return result
end
CreateFrame = function() return frame() end
NUM_BAG_SLOTS, NUM_CONTAINER_FRAMES = 4, 0
assert(loadfile("Indicators.lua"))("ZwykValues", FW)
FW:InstallUpgradeIndicators(); pump()
local indicator = FW.UpgradeIndicatorFrame

-- BetterBags can load before its modules initialize, or after ZwykValues.
local events = { callbacks = {}, registrations = {} }
function events:RegisterMessage(message, callback)
    assert(self._messageMap, "events are not initialized")
    self.callbacks[message] = callback
    self.registrations[message] = (self.registrations[message] or 0) + 1
end
function events:Send(message, item, decoration) self.callbacks[message]({}, item, decoration) end
local items, context = {}, {}
function context:New() return {} end
local getterCalls, themes = 0, {}
function themes:GetItemButton(ctx, item)
    assert(ctx and item.frame:IsVisible(), "only visible live items need theme lookup")
    getterCalls = getterCalls + 1
    return item.decoration
end
local modules = { Events = events, ItemFrame = items, Context = context, Themes = themes,
    Constants = { BANK_BAGS = { [-1] = -1, [7] = 7 }, ACCOUNT_BANK_BAGS = { [15] = 15 } } }
local addon = {}
function addon:GetModule(name, silent) assert(silent); return modules[name] end
local ace = {}
function ace:GetAddon(name, silent) assert(name == "BetterBags" and silent); return addon end
LibStub = function(name, silent) assert(name == "AceAddon-3.0" and silent); return ace end
indicator:Fire("OnEvent", "ADDON_LOADED", "BetterBags"); pump()
assert(not next(events.registrations))
events._messageMap, items.buttonsBySlotkey, items.activeItems = {}, {}, {}
indicator:Fire("OnEvent", "PLAYER_LOGIN"); pump()
assert(events.registrations["item/Updated"] == 1 and events.registrations["item/Clearing"] == 1)
assert(#scored == 0)

local bag = frame()
local function item(link, bagid, slotid, parent)
    local value = { frame = frame(parent or bag) }
    value.button = frame(value.frame) -- Native interaction button has hidden artwork.
    value.decoration = frame(value.frame); value.decoration.IconTexture = {}
    value.currentData = { bagid = bagid, slotid = slotid, itemInfo = { itemLink = link } }
    function value:GetItemData() return self.currentData or self.staticData end
    return value
end
local existing = item("item:100", 0, 1)
items.buttonsBySlotkey["0_1"], items.activeItems[existing] = existing, true
verdicts["item:100"], verdicts["item:102"] = true, true
FW.DB.options.upgradeBags = true
FW:RefreshUpgradeIndicators(); pump()
assert(existing.decoration.zvUpgradeArrow.shown and not existing.button.zvUpgradeArrow)
assert(existing.decoration.zvUpgradeArrow.anchor[2] == existing.decoration.IconTexture)
assert(getterCalls == 1, "slot map and active item set are deduplicated")
assert(events.registrations["item/Updated"] == 1)

-- Updated is emitted before owner Show; defer scoring until drawing settles.
local added = item("item:102", 1, 1); added.frame:Hide()
local onClick = function() end; added.button.scripts.OnClick = onClick
events:Send("item/Updated", added, added.decoration)
assert(not added.decoration.zvUpgradeArrow)
added.frame:Show(); pump()
assert(added.decoration.zvUpgradeArrow.shown and added.button.scripts.OnClick == onClick)
assert(added.decoration.zvUpgradeArrow.w == 16 and added.decoration.zvUpgradeArrow.h == 16)
added.decoration.UpgradeIcon = { shown = false } -- BetterBags runs its own provider afterward.
assert(added.decoration.zvUpgradeArrow.shown)

-- List rows update their inner Item through the same messages.
local row = frame(bag); row:Hide()
local rowItem = item("item:102", 0, 2, row)
events:Send("item/Updated", rowItem, rowItem.decoration)
row:Show(); pump(); assert(rowItem.decoration.zvUpgradeArrow.shown)

-- Reusing a slot and changing themes never resurrects the previous overlay.
added.currentData.itemInfo.itemLink = "item:101"
events:Send("item/Updated", added, added.decoration)
assert(not added.decoration.zvUpgradeArrow.shown); pump()
added.currentData.itemInfo.itemLink = "item:102"
local oldDecoration = added.decoration
added.decoration = frame(added.frame); added.decoration.icon = {}
events:Send("item/Updated", added, added.decoration); pump()
assert(not oldDecoration.zvUpgradeArrow.shown and added.decoration.zvUpgradeArrow.shown)
oldDecoration:Show(); assert(not oldDecoration.zvUpgradeArrow.shown)
assert(#added.decoration.textures == 1)

-- Clearing occurs before currentData is reset; hide now, not after a refresh.
events:Send("item/Clearing", added, added.decoration)
assert(added.currentData and not added.decoration.zvUpgradeArrow.shown)
added.decoration:Show(); assert(not added.decoration.zvUpgradeArrow.shown)
added.currentData = nil
FW:RefreshUpgradeIndicators(); pump(); assert(not added.decoration.zvUpgradeArrow.shown)

-- Empty/free/gap slots, previews and unknown container IDs never score.
local scoreCount = #scored
for _, invalid in ipairs({
    { isFreeSlot = true }, { isItemEmpty = true }, { isItemGap = true },
}) do
    local preview = item("item:100", 0, 3)
    for key, value in pairs(invalid) do preview.currentData[key] = value end
    events:Send("item/Updated", preview, preview.decoration)
    assert(not preview.decoration.zvUpgradeArrow)
end
local preview = item("item:100", 0, 3); preview.staticData = preview.currentData
events:Send("item/Updated", preview, preview.decoration)
local bank = item("item:100", -3, 1)
events:Send("item/Updated", bank, bank.decoration)
bank.currentData.bagid = 99; events:Send("item/Updated", bank, bank.decoration)
assert(not preview.decoration.zvUpgradeArrow and not bank.decoration.zvUpgradeArrow and #scored == scoreCount)
pump()

-- BetterBags' numeric bank IDs are supported without widening native bag limits.
for _, bagid in ipairs({ -1, 7, 15 }) do
    local stored = item("item:100", bagid, 1)
    events:Send("item/Updated", stored, stored.decoration)
    assert(stored.decoration.zvUpgradeArrow.shown)
end
pump()

-- The selected-profile decision remains authoritative for gear/filter changes.
verdicts["item:100"], verdicts["item:102"] = false, false
indicator:Fire("OnEvent", "PLAYER_EQUIPMENT_CHANGED", 1); pump()
assert(not existing.decoration.zvUpgradeArrow.shown and not rowItem.decoration.zvUpgradeArrow.shown)
verdicts["item:100"] = true
indicator:Fire("OnEvent", "ITEM_DATA_LOAD_RESULT", 100, true); pump()
assert(existing.decoration.zvUpgradeArrow.shown)
FW.DB.options.upgradeBags = false
scoreCount = #scored
FW:RefreshUpgradeIndicators(); assert(not existing.decoration.zvUpgradeArrow.shown)
pump(); assert(#scored == scoreCount)
assert(events.registrations["item/Updated"] == 1 and events.registrations["item/Clearing"] == 1)
print("BetterBags upgrade indicator tests passed")
