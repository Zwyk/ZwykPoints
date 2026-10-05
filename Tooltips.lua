local _, FW = ...
local watched = setmetatable({}, {__mode="k"})
local standard = {"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "EmbeddedItemTooltip"}
local refreshing, decorating = false, false

local function safeFrame(tooltip)
    return tooltip and tooltip.AddLine and
        not (tooltip.IsForbidden and tooltip:IsForbidden())
end
local function safeString(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return type(value) == "string" and value or nil
end
local function dataLink(data)
    if type(data) ~= "table" then return nil end
    local link = safeString(data.hyperlink)
    if not link or link == "" then link = safeString(data.itemLink) end
    if link and link ~= "" then return link end
    local guid = safeString(data.guid)
    if guid and C_Item and C_Item.GetItemLinkByGUID then
        local ok, resolved = pcall(C_Item.GetItemLinkByGUID, guid)
        if ok and safeString(resolved) and resolved ~= "" then return resolved end
    end
end
local function comparisonLink(tooltip)
    -- Native comparison data can contain only an item GUID. Keep the exact
    -- equipped variant instead of rebuilding a base link from its item ID.
    local manager = TooltipComparisonManager
    local owner = manager and manager.tooltip
    local shopping = owner and owner.shoppingTooltips
    local info = manager and manager.compareInfo
    if not shopping or not info then return nil end
    if shopping[1] == tooltip then return dataLink(info.item) end
    if shopping[2] == tooltip then
        local items = info.additionalItems
        return dataLink(items and items[manager.comparisonIndex or 1])
    end
end
local function getLink(tooltip, data)
    if tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and safeString(link) and link ~= "" then return link end
    end
    local link = dataLink(data)
    if link then return link end
    local getter = tooltip.GetPrimaryTooltipData or tooltip.GetTooltipData
    if getter then
        local ok, current = pcall(getter, tooltip)
        if ok then link = dataLink(current); if link then return link end end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, displayed = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok and safeString(displayed) and displayed ~= "" then return displayed end
    end
    return comparisonLink(tooltip) or safeString(tooltip.fwSourceLink)
end
local function plainText(text)
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):
        gsub("|T.-|t", ""):gsub("\194\160", " "):gsub("\226\128\175", " "):
        gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Debug marks affect displayed font strings only, never the item data used by
-- the reader. Match by text rather than line number because other addons can
-- insert tooltip rows before us.
function FW:MarkUnknownStats(tooltip, record)
    if not (self.DB.options and self.DB.options.debugUnknownStats) or not record then return end
    local unknown = {}
    for _, entry in ipairs(record.unrecognizedLines or {}) do
        local text = type(entry) == "table" and entry.text or entry
        if type(text) == "string" then unknown[plainText(text)] = true end
    end
    if not next(unknown) then return end
    local function mark(fontString)
        if not fontString or not fontString.GetText or not fontString.SetText then return end
        local text = safeString(fontString:GetText())
        if text and unknown[plainText(text)] and not text:find("[ZV ?]", 1, true) then
            fontString:SetText(text .. " |cffffaa33[ZV ?]|r")
        end
    end
    local name = tooltip.GetName and tooltip:GetName()
    if name and tooltip.NumLines then
        for index = 1, tooltip:NumLines() do
            mark(_G[name .. "TextLeft" .. index])
            mark(_G[name .. "TextRight" .. index])
        end
    elseif tooltip.GetRegions then
        for _, region in ipairs({tooltip:GetRegions()}) do mark(region) end
    end
end
local function formatNumber(value, signed)
    local result = string.format(signed and "%+.2f" or "%.2f", value)
    return result
end
-- Tooltip fonts on some Forever clients have no Unicode arrow glyphs. Use
-- packaged textures so profile fonts cannot turn the indicators into boxes.
local upArrow = "|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t"
local downArrow = "|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:12:12:0:0|t"
local function comparisonText(item, small)
    if item.error then return "|cffb2b2b2? comparison unavailable|r" end
    local equal = item.status == "equal"
    local arrow = equal and "=" or (item.status == "upgrade" and upArrow or downArrow)
    if small and not equal then arrow = arrow:gsub(":12:12:", ":10:10:") end
    local color = equal and "b2b2b2" or (item.status == "upgrade" and "40ff59" or "ff5959")
    local delta = equal and "0.00" or formatNumber(item.delta, true)
    local percent = equal and "+0.0%" or (item.percent and string.format("%+.1f%%", item.percent))
    return "|cff" .. color .. arrow .. delta .. " (" .. (percent or "n/a") .. ")|r"
end
local function restoreBaseFonts(tooltip)
    for fontString, font in pairs(tooltip.fwBaseFonts or {}) do
        fontString:SetFont(font[1], font[2], font[3])
    end
    tooltip.fwBaseFonts = nil
end
local function shrinkBaseLine(tooltip)
    local name = tooltip.GetName and tooltip:GetName()
    local index = tooltip.NumLines and tooltip:NumLines()
    if not index then return end
    for _, side in ipairs({"Left", "Right"}) do
        local key = "Text" .. side .. index
        local getter = tooltip["Get" .. side .. "Line"]
        local fontString
        if getter then
            local ok, line = pcall(getter, tooltip, index)
            if ok then fontString = line end
        end
        fontString = fontString or tooltip[key] or (name and _G[name .. key])
        if fontString and fontString.GetFont and fontString.SetFont then
            tooltip.fwBaseFonts = tooltip.fwBaseFonts or {}
            local font = tooltip.fwBaseFonts[fontString]
            if not font then
                local path, size, flags = fontString:GetFont()
                if path and type(size) == "number" then
                    font = {path, size, flags}
                    tooltip.fwBaseFonts[fontString] = font
                end
            end
            if font then fontString:SetFont(font[1], font[2] * .85, font[3]) end
        end
    end
end
local function hasIssues(record, profile)
    return record and ((FW.ItemHasIssues and FW:ItemHasIssues(record, profile)) or record.partial)
end
local function activeSignature(profiles)
    local parts = {}
    for _, profile in ipairs(profiles) do
        parts[#parts+1] = table.concat({profile.id, profile.revision or 0,
            profile.name, profile.color.r, profile.color.g, profile.color.b}, ":")
    end
    return table.concat(parts, ";") .. ":" .. tostring(FW.equipmentRevision or 0) ..
        ":" .. tostring(FW.DB.options and FW.DB.options.debugUnknownStats) ..
        ":" .. tostring(FW.DB.options and FW.DB.options.showComparisons)
end
local function comparisonTooltip(tooltip)
    local name = tooltip.GetName and tooltip:GetName() or ""
    if name:find("ShoppingTooltip", 1, true) then return true end
    local owner = TooltipComparisonManager and TooltipComparisonManager.tooltip
    local shopping = owner and owner.shoppingTooltips
    return shopping and (shopping[1] == tooltip or shopping[2] == tooltip)
end

function FW:DecorateTooltip(tooltip, data)
    if not self.DB or decorating or not safeFrame(tooltip) or tooltip == self.ScanTooltip then return end
    local link = getLink(tooltip, data)
    if not link then return end
    local profiles = self:GetProfiles(true)
    local debugEnabled = self.DB.options and self.DB.options.debugUnknownStats
    if #profiles == 0 and not debugEnabled then return end
    local signature = link .. activeSignature(profiles)
    if tooltip.fwSignature == signature then return end
    decorating = true
    tooltip.fwSignature = signature
    watched[tooltip] = link
    local issues, notes = false, {}
    if debugEnabled then
        local record = self:GetItem(link)
        self:MarkUnknownStats(tooltip, record)
        issues = hasIssues(record)
    end
    local equipped = false
    if tooltip.IsEquippedItem then
        local ok, value = pcall(tooltip.IsEquippedItem, tooltip)
        equipped = ok and value == true
    end
    local compare = not equipped and not comparisonTooltip(tooltip) and
        not (self.DB.options and self.DB.options.showComparisons == false)
    local displayedProfiles, addedSpacer = 0, false
    for _, profile in ipairs(profiles) do
        local r, g, b = profile.color.r, profile.color.g, profile.color.b
        local function readResult(base)
            if compare then
                if base then return self:CompareBaseItem(link, profile) end
                return self:CompareItem(link, profile)
            end
            local score, record, detail
            if base then score, record, detail = self:GetBaseScore(link, profile)
            else score, record, detail = self:GetScore(link, profile) end
            if score ~= nil then return {score=score, record=record, comparisons={}} end
            if detail == "excluded" then return {excluded=true,record=record,comparisons={}} end
            return nil, record
        end
        local function addResult(result, errorMessage, base)
            if result and result.excluded then return end
            if not addedSpacer then tooltip:AddLine(" "); addedSpacer = true end
            if not base then displayedProfiles = displayedProfiles + 1 end
            local label = base and "  Base" or profile.name
            if result then
                local comparisons = {}
                for _, item in ipairs(result.comparisons) do
                    comparisons[#comparisons+1] = comparisonText(item, base)
                    if item.error then notes[item.error] = true end
                    issues = issues or item.hasIssues
                end
                local values = formatNumber(result.score)
                if #comparisons > 0 then values = values .. "  " .. table.concat(comparisons, " | ") end
                tooltip:AddDoubleLine(label, values, r,g,b, r,g,b)
                if result.note then notes[result.note] = true end
                issues = issues or result.hasIssues or hasIssues(result.record, profile)
            else
                tooltip:AddLine(label .. ": " .. tostring(errorMessage or "Item data loading"), r,g,b, true)
            end
            if base then shrinkBaseLine(tooltip) end
        end
        local result, errorMessage = readResult(false)
        addResult(result, errorMessage, false)
        if not (result and result.excluded) and self.GetBaseScore and self.CompareBaseItem then
            result, errorMessage = readResult(true)
            addResult(result, errorMessage, true)
        end
    end
    for note in pairs(notes) do tooltip:AddLine("  " .. note, .75,.75,.75, true) end
    if issues and (displayedProfiles > 0 or #profiles == 0) then
        tooltip:AddLine("Partial stat data; /zv inspect or /zv exportissues.", 1,.7,.25, true)
    end
    decorating = false
    -- Native post-processing performs sizing after this callback. Legacy
    -- tooltips need Show to update dimensions; signature prevents recursion.
    if not data and tooltip.Show then tooltip:Show() end
end

function FW:RefreshTooltips()
    if refreshing then return end
    refreshing = true
    for tooltip, link in pairs(watched) do
        if safeFrame(tooltip) and tooltip.IsShown and tooltip:IsShown() then
            tooltip.fwSignature = nil
            -- Refresh the original source, preserving bag/inventory tooltip
            -- context. Do not replace a native source with SetHyperlink.
            if tooltip.RefreshData then
                local refreshed = pcall(tooltip.RefreshData, tooltip)
                if refreshed and tooltip:IsShown() then
                    -- RefreshData may clear the source-link field on a frame
                    -- whose modern item data contains only an ID. The watched
                    -- link still identifies this exact unchanged source.
                    tooltip.fwSourceLink = link
                    local ok = pcall(self.DecorateTooltip, self, tooltip)
                    if not ok then decorating = false; tooltip.fwSignature = nil end
                end
            elseif tooltip.Hide then
                tooltip:Hide() -- Older clients rebuild on the next mouse hover.
            end
        end
    end
    refreshing = false
end

function FW:InstallTooltipHooks()
    local modern = TooltipDataProcessor and Enum and Enum.TooltipDataType and
        TooltipDataProcessor.AddTooltipPostCall
    local function clear(tooltip)
        restoreBaseFonts(tooltip)
        tooltip.fwSignature = nil
        tooltip.fwSourceLink = nil
        watched[tooltip] = nil
    end
    local function decorate(tooltip, data)
        local ok, err = pcall(FW.DecorateTooltip, FW, tooltip, data)
        if not ok then
            decorating = false
            tooltip.fwSignature = nil
            if not FW.tooltipErrorReported then
                FW.tooltipErrorReported = true
                if FW.Print then FW:Print("Tooltip error: " .. tostring(err)) end
            end
        end
    end
    local function remember(tooltip, link)
        link = safeString(link)
        if link then
            tooltip.fwSourceLink = link
            decorate(tooltip, {hyperlink=link})
        end
    end
    local function hook(tooltip)
        if not safeFrame(tooltip) or tooltip.fwHooked or tooltip == FW.ScanTooltip then return end
        tooltip.fwHooked = true
        if tooltip.HookScript then
            pcall(tooltip.HookScript, tooltip, "OnTooltipCleared", clear)
            pcall(tooltip.HookScript, tooltip, "OnHide", clear)
            -- Some Classic branches expose TooltipDataProcessor but retain the
            -- legacy item script. Signature suppresses duplicates if both fire.
            if not tooltip.HasScript or tooltip:HasScript("OnTooltipSetItem") then
                pcall(tooltip.HookScript, tooltip, "OnTooltipSetItem", function(t) decorate(t) end)
            end
        end
        -- The item script/GetItem method is absent on some modern frames.
        -- Retain exact source links instead of reconstructing a base item ID.
        if hooksecurefunc then
            if tooltip.SetHyperlink then
                pcall(hooksecurefunc, tooltip, "SetHyperlink", function(t, link) remember(t, link) end)
            end
            if tooltip.SetBagItem then
                pcall(hooksecurefunc, tooltip, "SetBagItem", function(t, bag, slot)
                    local getter = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
                    if getter then local ok, link = pcall(getter, bag, slot); if ok then remember(t, link) end end
                end)
            end
            if tooltip.SetInventoryItem then
                pcall(hooksecurefunc, tooltip, "SetInventoryItem", function(t, unit, slot)
                    if GetInventoryItemLink then
                        local ok, link = pcall(GetInventoryItemLink, unit, slot)
                        if ok then remember(t, link) end
                    end
                end)
            end
            if tooltip.SetCompareItem then
                pcall(hooksecurefunc, tooltip, "SetCompareItem", function(t, other)
                    decorate(t)
                    if safeFrame(other) then decorate(other) end
                end)
            end
            local linkMethods = {
                SetLootItem="GetLootSlotLink", SetLootRollItem="GetLootRollItemLink",
                SetMerchantItem="GetMerchantItemLink", SetQuestItem="GetQuestItemLink",
                SetQuestLogItem="GetQuestLogItemLink", SetInboxItem="GetInboxItemLink",
                SetTradePlayerItem="GetTradePlayerItemLink", SetTradeTargetItem="GetTradeTargetItemLink",
            }
            for method, getterName in pairs(linkMethods) do
                local getter = _G[getterName]
                if tooltip[method] and getter then
                    -- Capture per-iteration values for Lua 5.1 closures.
                    local sourceGetter = getter
                    pcall(hooksecurefunc, tooltip, method, function(t, ...)
                        local ok, link = pcall(sourceGetter, ...)
                        if ok then remember(t, link) end
                    end)
                end
            end
        end
    end
    for _, name in ipairs(standard) do hook(_G[name]) end
    local manager = TooltipComparisonManager
    if hooksecurefunc and manager and manager.SetItemTooltip then
        pcall(hooksecurefunc, manager, "SetItemTooltip", function(m, primary)
            local shopping = m.tooltip and m.tooltip.shoppingTooltips
            local tooltip = shopping and shopping[primary and 1 or 2]
            if safeFrame(tooltip) then hook(tooltip); decorate(tooltip) end
        end)
    end
    if modern then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(t, data)
            hook(t)
            decorate(t, data)
        end)
    end
    self.HookTooltip = hook
end

function FW:GetHoveredItemLink()
    for _, name in ipairs({"GameTooltip", "ItemRefTooltip"}) do
        local tooltip = _G[name]
        if safeFrame(tooltip) and tooltip.IsShown and tooltip:IsShown() then
            local link = getLink(tooltip)
            if link then return link end
        end
    end
end
