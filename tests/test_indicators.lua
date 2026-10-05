local FW = { DB = { options = { upgradeBags = false, upgradeRolls = false } } }
local verdicts, scored, timers = {}, {}, {}
function FW:IsMainProfileUpgrade(link)
    scored[#scored + 1] = link
    return verdicts[link] == true
end
local function pump()
    local pending = timers; timers = {}
    for _, callback in ipairs(pending) do callback() end
end
C_Timer = { After = function(delay, callback) assert(delay == 0); timers[#timers+1] = callback end }

local function object(name, parent)
    local frame = { name = name, parent = parent, shown = true, scripts = {}, hooks = {}, events = {}, textures = {}, id = 1 }
    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:GetID() return self.id end
    function frame:SetID(id) self.id = id end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function frame:HookScript(name, callback)
        self.hooks[name] = self.hooks[name] or {}; table.insert(self.hooks[name], callback)
    end
    function frame:SetScript(name, callback) self.scripts[name] = callback end
    function frame:Fire(name, ...)
        if self.scripts[name] then self.scripts[name](self, ...) end
        for _, callback in ipairs(self.hooks[name] or {}) do callback(self, ...) end
    end
    function frame:Show() self.shown = true; self:Fire("OnShow") end
    function frame:Hide() self.shown = false; self:Fire("OnHide") end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:CreateTexture(_, layer, _, sublayer)
        assert(not self.forbidden and layer == "OVERLAY" and sublayer == 7)
        local texture = { shown = false }
        function texture:Hide() self.shown = false end
        function texture:Show() self.shown = true end
        function texture:SetTexture(path) self.path = path end
        function texture:SetSize(w, h) self.w, self.h = w, h end
        function texture:SetPoint(...) self.anchor = {...} end
        self.textures[#self.textures+1] = texture
        return texture
    end
    return frame
end
CreateFrame = function() return object() end
hooksecurefunc = function(target, method, callback)
    if type(target) == "string" then callback, method, target = method, target, _G end
    local original = assert(target[method])
    target[method] = function(...)
        local result = {original(...)}
        callback(...)
        return (unpack or table.unpack)(result)
    end
end
NUM_CONTAINER_FRAMES, NUM_BAG_SLOTS = 2, 4
local inventory = { [0] = {"item:100", "item:101", "item:102"}, [1] = {"item:103"} }
C_Container = { GetContainerItemLink = function(bag, slot) return inventory[bag] and inventory[bag][slot] end }
local bag = object("NativeBag"); bag.id = 0
local first = object(nil, bag); first.icon = {}
function first:GetBagID() return self.bagID or self.parent:GetID() end
function first:SetBagID(id) self.bagID = id end
function first:Initialize(bagID, slot) self:SetBagID(bagID); self:SetID(slot); self:Show() end
local second = object(nil, bag); second.id = 2
function second:GetBagID() return self.parent:GetID() end
bag.Items = {first, second}
function bag:EnumerateValidItems() return ipairs(self.Items) end
function bag:UpdateItems() end
function bag:UpdateItemSlots() end
ContainerFrameContainer = {ContainerFrames={bag}}
ContainerFrame1 = bag
local combined = object("CombinedBag"); combined.Items = {}
function combined:EnumerateValidItems() return ipairs(self.Items) end
function combined:UpdateItems() end
function combined:UpdateItemSlots() end
ContainerFrameCombinedBags = combined
local legacy = object("ContainerFrame2"); legacy.id, legacy.size = 1, 1
local legacyItem = object("ContainerFrame2Item1", legacy)
ContainerFrame2, ContainerFrame2Item1 = legacy, legacyItem
ContainerFrame_Update = function() end
ContainerFrame_GenerateFrame = function() end
local roll = object("GroupLootFrame1"); roll.rollID = 10
roll.IconFrame = object(nil, roll); roll.IconFrame.Icon = {}
GroupLootFrame1 = roll
local rolls = {[10]="item:104",[11]="item:105"}
GetLootRollItemLink = function(id) return rolls[id] end
GroupLootFrame_SetupItemDisplay = function() end
GroupLootFrame_OnShow = function() end
GroupLootContainer_OpenNewFrame = function() end

assert(loadfile("Indicators.lua"))("ZwykValues", FW)
FW:InstallUpgradeIndicators(); pump()
assert(FW.UpgradeIndicatorFrame.events.BAG_UPDATE and FW.UpgradeIndicatorFrame.events.START_LOOT_ROLL)
assert(not FW.UpgradeIndicatorFrame.events.GET_ITEM_INFO_RECEIVED and not FW.UpgradeIndicatorFrame.events.ITEM_DATA_LOAD_RESULT,
    "item-data completions are coordinated centrally, not subscribed to independently")
assert(#scored == 0 and #first.textures == 0 and #roll.IconFrame.textures == 0)
local eventFrame = FW.UpgradeIndicatorFrame
FW:InstallUpgradeIndicators(); assert(FW.UpgradeIndicatorFrame == eventFrame)

-- Only upgrades get an overlay, at the icon corner, without native click changes.
local onClick = function() end; first.scripts.OnClick = onClick
verdicts["item:100"], verdicts["item:103"], verdicts["item:104"] = true, true, true
FW.DB.options.upgradeBags, FW.DB.options.upgradeRolls = true, true
FW:RefreshUpgradeIndicators(); assert(#timers == 1); pump()
assert(#scored == 4, "a full refresh checks each of three bag buttons and one roll icon exactly once")
local onePass = {}
for _, link in ipairs(scored) do onePass[link] = (onePass[link] or 0) + 1 end
for _, link in ipairs({"item:100", "item:101", "item:103", "item:104"}) do
    assert(onePass[link] == 1, "discovery must not score again before the registry paint: " .. link)
end
assert(first.zvUpgradeArrow.shown and not second.zvUpgradeArrow)
assert(legacyItem.zvUpgradeArrow.shown and roll.IconFrame.zvUpgradeArrow.shown)
assert(first.scripts.OnClick == onClick and first.zvUpgradeArrow.w == 16 and first.zvUpgradeArrow.h == 16)
assert(first.zvUpgradeArrow.anchor[2] == first.icon)
assert(first.zvUpgradeArrow.path == "Interface\\AddOns\\ZwykValues\\Textures\\ArrowUp")
assert(roll.IconFrame.zvUpgradeArrow.anchor[2] == roll.IconFrame.Icon)

-- Recycled native slot is cleared immediately and repainted after Initialize.
first:SetID(2); assert(not first.zvUpgradeArrow.shown); pump()
first:Initialize(1, 1); assert(first.zvUpgradeArrow.shown); pump()
assert(#first.textures == 1)
first:Initialize(0, 1); assert(first.zvUpgradeArrow.shown); pump()
inventory[0][1] = "item:101"
bag:UpdateItems(); assert(not first.zvUpgradeArrow.shown)
inventory[0][1] = "item:100"
eventFrame:Fire("OnEvent", "BAG_UPDATE", 0); pump(); assert(first.zvUpgradeArrow.shown)

-- Equipment/profile invalidations use the current decision next tick and debounce.
verdicts["item:100"] = false
eventFrame:Fire("OnEvent", "PLAYER_EQUIPMENT_CHANGED", 1)
eventFrame:Fire("OnEvent", "BAG_UPDATE_DELAYED")
assert(#timers == 1); pump(); assert(not first.zvUpgradeArrow.shown)
verdicts["item:100"] = true
FW:RefreshUpgradeIndicators(); pump(); assert(first.zvUpgradeArrow.shown)
local callCount = #scored
eventFrame:Fire("OnEvent", "UNIT_INVENTORY_CHANGED", "target")
assert(#timers == 0 and #scored == callCount)

-- Opening bags discovers pooled, unnamed buttons without scanning arbitrary frames.
bag:Hide(); assert(not first.zvUpgradeArrow.shown)
callCount = #scored; FW:RefreshUpgradeIndicators(); pump(); assert(#scored >= callCount)
bag:Show(); assert(first.zvUpgradeArrow.shown)
local pooled = object(nil, combined); pooled.id, pooled.bagID = 3, 0
function pooled:GetBagID() return self.bagID end
combined.Items = {pooled}
verdicts["item:102"] = true
combined:UpdateItemSlots(); assert(pooled.zvUpgradeArrow.shown)
combined:Hide(); assert(not pooled.zvUpgradeArrow.shown)
combined:Show(); assert(pooled.zvUpgradeArrow.shown)
-- Bank bag reuse does not accidentally mark bank content as a carried item.
legacy.id = 7; ContainerFrame_Update(legacy); assert(not legacyItem.zvUpgradeArrow.shown)
legacy.id = 1; ContainerFrame_GenerateFrame(legacy); assert(legacyItem.zvUpgradeArrow.shown)

-- Roll frames are recycled, cancel immediately, and may wait for item data.
roll.rollID = 11; GroupLootFrame_SetupItemDisplay(roll); assert(not roll.IconFrame.zvUpgradeArrow.shown)
verdicts["item:105"] = true
roll.IconFrame.zvUpgradeArrow:Hide()
GroupLootFrame_SetupItemDisplay(roll, true)
assert(roll.IconFrame.zvUpgradeArrow.shown, "extra native setup arguments must not become discovery deferPaint")
roll.IconFrame.zvUpgradeArrow:Hide()
GroupLootFrame_OnShow(roll, true)
assert(roll.IconFrame.zvUpgradeArrow.shown, "extra native show arguments must retain immediate paint")
FW:RefreshUpgradeIndicators(); pump(); assert(roll.IconFrame.zvUpgradeArrow.shown)
eventFrame:Fire("OnEvent", "CANCEL_LOOT_ROLL", 11)
assert(not roll.IconFrame.zvUpgradeArrow.shown); pump(); assert(not roll.IconFrame.zvUpgradeArrow.shown)
eventFrame:Fire("OnEvent", "START_LOOT_ROLL", 11); pump(); assert(roll.IconFrame.zvUpgradeArrow.shown)
roll:Hide(); assert(not roll.IconFrame.zvUpgradeArrow.shown)
roll.rollID = 10; roll:Show(); assert(roll.IconFrame.zvUpgradeArrow.shown)
eventFrame:Fire("OnEvent", "CANCEL_ALL_LOOT_ROLLS"); pump(); assert(not roll.IconFrame.zvUpgradeArrow.shown)
roll.rollID = 12; rolls[12] = nil; GroupLootFrame_SetupItemDisplay(roll)
assert(not roll.IconFrame.zvUpgradeArrow.shown)
rolls[12], verdicts["item:106"] = "item:106", true
FW:RefreshUpgradeIndicators(); pump(); assert(roll.IconFrame.zvUpgradeArrow.shown)

-- Third-party integration is explicit; providers are live and may return no data.
local custom = object("CustomBagItem")
custom.currentLink = "item:100"
assert(FW:RegisterUpgradeItemButton(custom, function(button) return button.currentLink end))
assert(custom.zvUpgradeArrow.shown)
custom.currentLink = nil
FW:RefreshUpgradeIndicators(); pump(); assert(not custom.zvUpgradeArrow.shown)
custom.currentLink = "item:100"
custom:Hide(); custom:Show(); assert(custom.zvUpgradeArrow.shown)
local forbidden = object("Forbidden"); forbidden.forbidden = true
assert(not FW:RegisterUpgradeItemButton(forbidden, function() error("never called") end))
assert(not FW:RegisterUpgradeItemButton(custom, nil))
assert(FW:RegisterUpgradeItemButton(custom, function() error("unavailable custom data") end))
assert(not custom.zvUpgradeArrow.shown)

-- Disabling toggles clears existing arrows before the timer and does zero scoring.
FW.DB.options.upgradeBags, FW.DB.options.upgradeRolls = false, false
callCount = #scored
FW:RefreshUpgradeIndicators()
assert(not first.zvUpgradeArrow.shown and not pooled.zvUpgradeArrow.shown and not roll.IconFrame.zvUpgradeArrow.shown)
pump(); assert(#scored == callCount)
bag:UpdateItems(); roll:Hide(); roll:Show(); assert(#scored == callCount)

-- Blizzard UI may load later; its update hooks and fixed roll frames are retried.
local late = object("GroupLootFrame2"); late.rollID = 10; late.IconFrame = object(nil, late)
GroupLootFrame2 = late
FW.DB.options.upgradeRolls = true
eventFrame:Fire("OnEvent", "ADDON_LOADED", "Blizzard_UIPanels_Game"); pump()
assert(late.IconFrame.zvUpgradeArrow.shown)

-- The one-shot frame fallback never installs a continuous poll.
C_Timer = nil
verdicts["item:104"] = false
FW:RefreshUpgradeIndicators(); assert(eventFrame.scripts.OnUpdate)
eventFrame:Fire("OnUpdate"); assert(not eventFrame.scripts.OnUpdate and not late.IconFrame.zvUpgradeArrow.shown)
print("upgrade indicators tests passed")
