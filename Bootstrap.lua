local addonName, FW = ...
_G.ZwykValues = FW
FW.version = "0.1.2"

function FW:Print(message)
    local text = "|cff80ccffZwykValues:|r " .. tostring(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) else print(text) end
end

local function countEntries(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

local function inspect(link)
    link = link or FW:GetHoveredItemLink() or (GetInventoryItemLink and GetInventoryItemLink("player", 16))
    if not link then FW:Print("Hover an item or type /zv inspect <item link>."); return end
    local record, err = FW:GetItem(link)
    if not record then FW:Print(tostring(err)); return end
    local raw = FW.GetRawItemStats and FW:GetRawItemStats(link) or {}
    local data = {item=link, build=GetBuildInfo and ({GetBuildInfo()}) or {},
        locale=GetLocale and GetLocale() or "unknown", stats=record.stats,
        percentStats=record.percentStats, ratingStats=record.ratingStats,
        unresolvedStats=record.unresolvedStats, unrecognizedLines=record.unrecognizedLines,
        warnings=record.warnings, raw=raw}
    local json, encodeError = FW.JSON.Encode(data)
    if FW.ShowTextDialog then FW:ShowTextDialog("Item diagnostics", json or tostring(encodeError), false)
    elseif FW.ShowTransferDialog then FW:ShowTransferDialog("Item diagnostics", json or tostring(encodeError), false)
    else FW:Print(json or tostring(encodeError)) end
end

SLASH_ZWYKVALUES1 = "/zv"
SLASH_ZWYKVALUES2 = "/zwykvalues"
SlashCmdList.ZWYKVALUES = function(message)
    local command, rest = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "cache" then
        FW:Print(countEntries(FW.DB.cache.items) .. " cached item variants; " ..
            countEntries(FW.DB.cache.scores) .. " scored variants.")
    elseif command == "clearcache" then
        FW:InvalidateCache(); FW:Print("Item and score caches cleared.")
    elseif command == "inspect" then
        inspect(rest ~= "" and rest or nil)
    elseif command == "help" then
        FW:Print("/zv opens profiles. /zv cache, /zv clearcache, /zv inspect [item link].")
    else FW:ToggleUI() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_DATA_LOAD_RESULT")
eventFrame:SetScript("OnEvent", function(_, event, arg1, success)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            FW:Initialize()
            FW:InstallTooltipHooks()
        elseif FW.DB and FW.HookTooltip then
            for _, name in ipairs({"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2"}) do
                FW.HookTooltip(_G[name])
            end
        end
    elseif not FW.DB then return
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        FW.equipmentRevision = (FW.equipmentRevision or 0) + 1
        FW:RefreshTooltips()
    elseif event == "PLAYER_LEVEL_UP" then
        FW:InvalidateCache()
    else
        if FW.PendingItems then FW.PendingItems[arg1] = nil end
        if success == false then return end
        if FW.OnItemDataLoaded then FW:OnItemDataLoaded(arg1, success) end
        -- Only refresh a hovered loading item. Do not redraw on each unrelated
        -- item load; scanner APIs may themselves trigger data events.
        local hovered = FW:GetHoveredItemLink()
        local id = hovered and tonumber(hovered:match("item:(%d+)"))
        local relevant = id and id == arg1
        if hovered and not relevant and GetInventoryItemLink then
            for slot = 1, 19 do
                local equipped = GetInventoryItemLink("player", slot)
                if equipped and tonumber(equipped:match("item:(%d+)")) == arg1 then
                    relevant = true; break
                end
            end
        end
        if relevant then FW:RefreshTooltips() end
    end
end)
