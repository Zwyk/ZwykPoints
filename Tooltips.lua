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
local function getLink(tooltip, data)
    if tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and safeString(link) then return link end
    end
    if data then
        local link = safeString(data.hyperlink) or safeString(data.itemLink)
        if link then return link end
    end
    if tooltip.GetTooltipData then
        local ok, current = pcall(tooltip.GetTooltipData, tooltip)
        if ok and current then
            local link = safeString(current.hyperlink) or safeString(current.itemLink)
            if link then return link end
        end
    end
    return safeString(tooltip.fwSourceLink)
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
        if text and unknown[plainText(text)] and not text:find("[ZP ?]", 1, true) then
            fontString:SetText(text .. " |cffffaa33[ZP ?]|r")
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
    return name:find("ShoppingTooltip", 1, true) ~= nil
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
    if debugEnabled then
        local record = self:GetItem(link)
        self:MarkUnknownStats(tooltip, record)
    end
    local equipped = false
    if tooltip.IsEquippedItem then
        local ok, value = pcall(tooltip.IsEquippedItem, tooltip)
        equipped = ok and value == true
    end
    local compare = not equipped and not comparisonTooltip(tooltip) and
        not (self.DB.options and self.DB.options.showComparisons == false)
    if #profiles > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("ZwykPoints", 0.5, 0.8, 1)
    end
    for _, profile in ipairs(profiles) do
        local r, g, b = profile.color.r, profile.color.g, profile.color.b
        local result, errorMessage
        if compare then
            result, errorMessage = self:CompareItem(link, profile)
        else
            local score, record = self:GetScore(link, profile)
            if score ~= nil then result = {score=score, record=record, comparisons={}}
            else errorMessage = record end
        end
        if result then
            tooltip:AddDoubleLine(profile.name, formatNumber(result.score), r,g,b, r,g,b)
            for _, item in ipairs(result.comparisons) do
                if item.error then
                    tooltip:AddLine("  " .. item.label .. ": " .. item.error, .75,.75,.75, true)
                else
                    local text = "  " .. item.label .. ": " .. formatNumber(item.delta, true)
                    if item.percent then text = text .. " (" .. string.format("%+.1f%%", item.percent) .. ")"
                    elseif item.baseline <= 0 then text = text .. " (percentage n/a)" end
                    text = text .. " " .. item.status
                    local color = item.status == "upgrade" and {.25,1,.35} or
                        (item.status == "downgrade" and {1,.35,.35} or {.7,.7,.7})
                    tooltip:AddLine(text, color[1],color[2],color[3], true)
                end
            end
            if result.note then tooltip:AddLine("  " .. result.note, .75,.75,.75, true) end
            if result.record.partial then
                tooltip:AddLine("  Partial stat data; use /zp inspect for details.", 1,.7,.25, true)
            end
        else
            tooltip:AddLine(profile.name .. ": " .. tostring(errorMessage or "Item data loading"), r,g,b, true)
        end
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
