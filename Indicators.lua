local _, FW = ...

-- Audited against Gethe/wow-ui-source's Forever UI (e3ecc27): the native
-- containers own pooled Items and UpdateItems/UpdateItemSlots; loot roll
-- frames own rollID and an IconFrame. No global frame-discovery walk is used.
local buttons, containers, hookTargets = {}, {}, {}
local arrowTexture = "Interface\\AddOns\\ZwykValues\\Textures\\ArrowUp"
local refreshPending = false
local betterBagsItems = setmetatable({}, { __mode = "k" })
local betterBagsEvents, betterBagsMessages
local betterBagsBankBags = {}

local function usable(frame)
    if not frame then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden then return false end
    end
    return true
end

local function visible(frame)
    if not usable(frame) then return false end
    local method = frame.IsVisible or frame.IsShown
    if type(method) ~= "function" then return false end
    local ok, shown = pcall(method, frame)
    return ok and shown == true
end

local function enabled(option)
    return FW.DB and FW.DB.options and FW.DB.options[option] == true
end

local function hide(entry)
    if entry and entry.texture then entry.texture:Hide() end
end

local function paint(button, entry)
    if not enabled(entry.option) or not visible(button) or
        (entry.owner and not visible(entry.owner)) then hide(entry); return end
    local ok, link = pcall(entry.provider, button)
    if not ok or (issecretvalue and issecretvalue(link)) or type(link) ~= "string" or not link:find("item:", 1, true) or
        type(FW.IsMainProfileUpgrade) ~= "function" or not FW:IsMainProfileUpgrade(link) then
        hide(entry); return
    end
    if not entry.texture then
        if type(button.CreateTexture) ~= "function" then return end
        local success, texture = pcall(button.CreateTexture, button, nil, "OVERLAY", nil, 7)
        if not success or not texture then return end
        entry.texture = texture
        texture:SetTexture(arrowTexture)
        texture:SetSize(16, 16)
        texture:SetPoint("TOPLEFT", entry.anchor or button, "TOPLEFT", 0, 0)
        button.zvUpgradeArrow = texture
    end
    entry.texture:Show()
end

local function hookMethod(target, method, callback)
    if not usable(target) or type(target[method]) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    local methods = hookTargets[target]
    if not methods then methods = {}; hookTargets[target] = methods end
    if methods[method] then return end
    local ok = pcall(hooksecurefunc, target, method, callback)
    if ok then methods[method] = true end
end

local function register(button, provider, option, owner, anchor, deferPaint)
    if not usable(button) or type(provider) ~= "function" then return end
    local entry = buttons[button]
    if not entry then
        entry = {}; buttons[button] = entry
        if type(button.HookScript) == "function" then
            pcall(button.HookScript, button, "OnHide", function() hide(entry) end)
            pcall(button.HookScript, button, "OnShow", function() paint(button, entry) end)
        end
        -- Clear old decoration at the moment a recycled button changes its
        -- slot. The native Initialize hook repaints after bag AND slot settle.
        hookMethod(button, "SetID", function()
            hide(entry)
            FW:RefreshUpgradeIndicators()
        end)
        hookMethod(button, "Initialize", function() paint(button, entry) end)
        hookMethod(button, "SetBagID", function() hide(entry) end)
    end
    entry.provider, entry.option, entry.owner, entry.anchor = provider, option, owner, anchor
    if not deferPaint then paint(button, entry) end
    return entry
end

local function bagLink(button)
    local bag
    if type(button.GetBagID) == "function" then bag = button:GetBagID() end
    if bag == nil and type(button.GetParent) == "function" then
        local parent = button:GetParent()
        if usable(parent) and type(parent.GetID) == "function" then bag = parent:GetID() end
    end
    local slot = type(button.GetID) == "function" and button:GetID()
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4
    if type(bag) ~= "number" or bag < 0 or bag > lastBag or type(slot) ~= "number" or slot < 1 then return end
    if C_Container and type(C_Container.GetContainerItemLink) == "function" then
        return C_Container.GetContainerItemLink(bag, slot)
    elseif type(GetContainerItemLink) == "function" then
        return GetContainerItemLink(bag, slot)
    end
end

local function scanContainer(container, deferPaint)
    if not usable(container) or not enabled("upgradeBags") or not visible(container) then return end
    local function visit(button)
        if usable(button) then
            register(button, bagLink, "upgradeBags", container, button.icon or button.Icon, deferPaint)
        end
    end
    if type(container.EnumerateValidItems) == "function" then
        -- Native Forever's iterator yields index, button (not pool keys).
        for _, button in container:EnumerateValidItems() do visit(button) end
    elseif type(container.Items) == "table" then
        for _, button in ipairs(container.Items) do visit(button) end
    else
        local name = type(container.GetName) == "function" and container:GetName()
        if type(name) == "string" and type(container.size) == "number" then
            for index = 1, container.size do visit(_G[name .. "Item" .. index]) end
        end
    end
end

local function hookContainer(container)
    if not usable(container) or containers[container] then return end
    containers[container] = true
    if type(container.HookScript) == "function" then
        pcall(container.HookScript, container, "OnShow", function() scanContainer(container) end)
        pcall(container.HookScript, container, "OnHide", function()
            for _, entry in pairs(buttons) do if entry.owner == container then hide(entry) end end
        end)
    end
    hookMethod(container, "UpdateItems", function() scanContainer(container) end)
    hookMethod(container, "UpdateItemSlots", function() scanContainer(container) end)
end

local function visitNativeContainers(callback)
    local seen = {}
    local function visit(frame)
        if frame and not seen[frame] then seen[frame] = true; callback(frame) end
    end
    visit(ContainerFrameCombinedBags)
    local owner = ContainerFrameContainer or UIParent
    if owner and type(owner.ContainerFrames) == "table" then
        for _, container in ipairs(owner.ContainerFrames) do visit(container) end
    end
    for index = 1, NUM_CONTAINER_FRAMES or 13 do visit(_G["ContainerFrame" .. index]) end
end

local function registerRollFrame(frame, deferPaint)
    if not usable(frame) then return end
    local name = type(frame.GetName) == "function" and frame:GetName()
    local icon = frame.IconFrame or (type(name) == "string" and _G[name .. "IconFrame"])
    if not usable(icon) then return end
    local entry = buttons[icon]
    entry = register(icon, function()
        local rollID = frame.rollID
        if rollID == nil or (entry and entry.cancelledRollID == rollID) or type(GetLootRollItemLink) ~= "function" then return end
        return GetLootRollItemLink(rollID)
    end, "upgradeRolls", frame, icon.Icon or icon.icon, deferPaint)
    if entry and not entry.ownerHideHook then
        entry.ownerHideHook = true
        if type(frame.HookScript) == "function" then
            pcall(frame.HookScript, frame, "OnHide", function() hide(entry) end)
            pcall(frame.HookScript, frame, "OnShow", function() paint(icon, entry) end)
        end
    end
end

local globalHooks = {}
local function hookGlobal(name, callback)
    if globalHooks[name] or type(_G[name]) ~= "function" or type(hooksecurefunc) ~= "function" then return end
    if pcall(hooksecurefunc, name, callback) then globalHooks[name] = true end
end

local function installNativeHooks()
    visitNativeContainers(hookContainer)
    hookGlobal("ContainerFrame_Update", function(frame) hookContainer(frame); scanContainer(frame) end)
    hookGlobal("ContainerFrame_GenerateFrame", function(frame) hookContainer(frame); scanContainer(frame) end)
    hookGlobal("GroupLootFrame_SetupItemDisplay", function(frame) registerRollFrame(frame) end)
    hookGlobal("GroupLootFrame_OnShow", function(frame) registerRollFrame(frame) end)
    hookGlobal("GroupLootContainer_OpenNewFrame", function() FW:RefreshUpgradeIndicators() end)
    for index = 1, 4 do registerRollFrame(_G["GroupLootFrame" .. index]) end
end

local function betterBagsLink(item)
    if type(item) ~= "table" or item.staticData or item.isFreeSlot or
        type(item.GetItemData) ~= "function" then return end
    local ok, data = pcall(item.GetItemData, item)
    if not ok or type(data) ~= "table" or data.isItemEmpty or data.isFreeSlot or data.isItemGap then return end
    local bag, slot = data.bagid, data.slotid
    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_TOTAL_BAG_FRAMES or NUM_BAG_SLOTS or 4
    if (issecretvalue and (issecretvalue(bag) or issecretvalue(slot))) or
        type(bag) ~= "number" or bag ~= math.floor(bag) or
        (not betterBagsBankBags[bag] and (bag < 0 or bag > lastBag)) or
        type(slot) ~= "number" or slot < 1 or slot ~= math.floor(slot) then return end
    local link = data.itemInfo and data.itemInfo.itemLink
    if (issecretvalue and issecretvalue(link)) or type(link) ~= "string" or not link:find("item:", 1, true) then return end
    return link
end

local function updateBetterBagsItem(_, item, decoration, deferPaint)
    local record = betterBagsItems[item]
    if not betterBagsLink(item) or not usable(decoration) then
        if record then record.cleared = true; hide(buttons[record.button]) end
        return
    end
    if not record then record = {}; betterBagsItems[item] = record end
    if record.button and record.button ~= decoration then hide(buttons[record.button]) end
    record.button, record.cleared = decoration, false
    register(decoration, function(button)
        if record.cleared or record.button ~= button then return end
        return betterBagsLink(item)
    end, "upgradeBags", item.frame, decoration.IconTexture or decoration.icon or decoration.Icon, deferPaint)
end

local function clearBetterBagsItem(_, item, decoration)
    -- Clearing is sent before BetterBags resets its live data.
    local record = betterBagsItems[item]
    if record then record.cleared = true; hide(buttons[record.button]) end
    if buttons[decoration] then hide(buttons[decoration]) end
end

local function refreshBetterBags(deferPaint)
    if not LibStub then return end
    local ok, ace = pcall(function() return LibStub("AceAddon-3.0", true) end)
    if not ok or not ace or type(ace.GetAddon) ~= "function" then return end
    local loaded, addon = pcall(ace.GetAddon, ace, "BetterBags", true)
    if not loaded or not addon or type(addon.GetModule) ~= "function" then return end
    local function module(name)
        local found, value = pcall(addon.GetModule, addon, name, true)
        if found then return value end
    end
    local events, items, themes, context = module("Events"), module("ItemFrame"), module("Themes"), module("Context")
    -- Modules exist before OnInitialize; RegisterMessage needs initialized maps.
    if not events or type(events._messageMap) ~= "table" or type(events.RegisterMessage) ~= "function" or
        not items or type(items.buttonsBySlotkey) ~= "table" or not themes or
        type(themes.GetItemButton) ~= "function" or not context or type(context.New) ~= "function" then return end
    local constants = module("Constants")
    betterBagsBankBags = {}
    for _, name in ipairs({ "BANK_BAGS", "ACCOUNT_BANK_BAGS" }) do
        for _, bag in pairs(constants and constants[name] or {}) do
            if type(bag) == "number" and bag == math.floor(bag) then betterBagsBankBags[bag] = true end
        end
    end
    if betterBagsEvents ~= events then betterBagsEvents, betterBagsMessages = events, {} end
    local function subscribe(message, callback)
        if not betterBagsMessages[message] and pcall(events.RegisterMessage, events, message, callback) then
            betterBagsMessages[message] = true
        end
    end
    subscribe("item/Updated", function(ctx, item, decoration)
        updateBetterBagsItem(ctx, item, decoration)
        -- Updated precedes the item's Show, including list-row icons.
        FW:RefreshUpgradeIndicators()
    end)
    subscribe("item/Clearing", clearBetterBagsItem)
    if not enabled("upgradeBags") then return end
    local created, ctx = pcall(context.New, context, "ZwykValuesUpgradeIndicators")
    if not created or not ctx then return end
    local seen = {}
    local function visit(item)
        if type(item) ~= "table" or seen[item] then return end
        seen[item] = true
        if betterBagsLink(item) and visible(item.frame) then
            local themed, decoration = pcall(themes.GetItemButton, themes, ctx, item)
            if themed then updateBetterBagsItem(ctx, item, decoration, deferPaint) end
        end
    end
    for _, item in pairs(items.buttonsBySlotkey) do visit(item) end
    for item in pairs(items.activeItems or {}) do visit(item) end
end

function FW:RegisterUpgradeItemButton(button, linkProvider)
    -- Third-party bags can register their item buttons with a live provider
    -- and call this again after their own updates. They share the bags toggle.
    return register(button, linkProvider, "upgradeBags") ~= nil
end

function FW:RefreshBagUpgradeIndicators()
    -- Discovery updates live providers first; paint each registered button
    -- once below. Native update/show hooks keep their immediate decoration.
    refreshBetterBags(true)
    if enabled("upgradeBags") then
        visitNativeContainers(function(frame) hookContainer(frame); scanContainer(frame, true) end)
    end
    for button, entry in pairs(buttons) do
        if entry.option == "upgradeBags" then paint(button, entry) end
    end
end

function FW:RefreshRollUpgradeIndicators()
    if enabled("upgradeRolls") then
        for index = 1, 4 do registerRollFrame(_G["GroupLootFrame" .. index], true) end
    end
    for button, entry in pairs(buttons) do
        if entry.option == "upgradeRolls" then paint(button, entry) end
    end
end

function FW:RefreshUpgradeIndicators()
    -- Disabled locations disappear immediately; scoring waits until the next
    -- tick so the equipment event's revision and native slot updates settle.
    for _, entry in pairs(buttons) do if not enabled(entry.option) then hide(entry) end end
    if refreshPending then return end
    refreshPending = true
    local function refresh()
        refreshPending = false
        FW:RefreshBagUpgradeIndicators()
        FW:RefreshRollUpgradeIndicators()
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, refresh)
    elseif self.UpgradeIndicatorFrame then
        self.UpgradeIndicatorFrame:SetScript("OnUpdate", function(frame)
            frame:SetScript("OnUpdate", nil)
            refresh()
        end)
    else
        refresh()
    end
end

function FW:InstallUpgradeIndicators()
    if self.UpgradeIndicatorFrame or type(CreateFrame) ~= "function" then return end
    local frame = CreateFrame("Frame")
    self.UpgradeIndicatorFrame = frame
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
        if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then installNativeHooks() end
        if event == "CANCEL_LOOT_ROLL" or event == "CANCEL_ALL_LOOT_ROLLS" then
            for _, entry in pairs(buttons) do
                if entry.option == "upgradeRolls" and entry.owner and
                    (event == "CANCEL_ALL_LOOT_ROLLS" or entry.owner.rollID == arg1) then
                    entry.cancelledRollID = entry.owner.rollID
                    hide(entry)
                end
            end
        elseif event == "START_LOOT_ROLL" then
            for _, entry in pairs(buttons) do
                if entry.option == "upgradeRolls" and entry.cancelledRollID == arg1 then entry.cancelledRollID = nil end
            end
        end
        FW:RefreshUpgradeIndicators()
    end)
    for _, event in ipairs({
        "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ADDON_LOADED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED",
        "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BAG_OPEN", "BAG_CLOSED", "BAG_CONTAINER_UPDATE", "USE_COMBINED_BAGS_CHANGED",
        -- Bootstrap coordinates successful pending-item completions. Listening
        -- independently would redraw all bags for unsolicited cache events.
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
    }) do pcall(frame.RegisterEvent, frame, event) end
    installNativeHooks()
    self:RefreshUpgradeIndicators()
end
