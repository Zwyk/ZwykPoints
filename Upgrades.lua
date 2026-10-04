local _, FW = ...

local arrow = "|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t"
local memo, memoCount, memoSignature = {}, 0, nil

local function safeString(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return type(value) == "string" and value or nil
end

function FW:InvalidateUpgradeComparisons()
    memo, memoCount, memoSignature = {}, 0, nil
end

function FW:IsMainProfileUpgrade(link)
    link = safeString(link)
    if not link or not link:find("item:", 1, true) then return false end
    local profile = self:GetMainProfile()
    if not profile then return false end
    local signature = table.concat({profile.id, profile.revision or 0,
        self.equipmentRevision or 0}, ":")
    if signature ~= memoSignature then
        self:InvalidateUpgradeComparisons()
        memoSignature = signature
    end
    local key = self.ItemKey and self:ItemKey(link) or link
    if not key then return false end
    if memo[key] ~= nil then return memo[key] end
    local ok, result = pcall(self.CompareItem, self, link, profile)
    if not ok or not result or result.pending then return false end
    -- A partial subtotal is useful in a tooltip, but cannot establish whether
    -- an item is an upgrade. Do not persist temporary/loading decisions.
    if result.record and ((self.ItemHasIssues and self:ItemHasIssues(result.record, profile))
        or result.record.partial) then return false end
    local upgrade, complete = false, true
    for _, comparison in ipairs(result.comparisons or {}) do
        if comparison.error or comparison.hasIssues then complete = false
        elseif comparison.status == "upgrade" then upgrade = true end
    end
    if complete or upgrade then
        if memoCount >= (self.CACHE_LIMIT or 2000) then
            memo, memoCount = {}, 0
        end
        memo[key], memoCount = upgrade, memoCount + 1
    end
    return upgrade
end

function FW:DecorateUpgradeChatMessage(message)
    message = safeString(message)
    if not message or not self.DB or not self.DB.options.upgradeChat or not self:GetMainProfile() then
        return message
    end
    -- Keep the original hyperlink (including enchant/suffix fields) and all
    -- surrounding color codes intact. The icon is outside the clickable text.
    return (message:gsub("()(|Hitem:[^|]+|h.-|h)()", function(_, link, after)
        if message:sub(after, after + #arrow) == " " .. arrow then return link end
        if self:IsMainProfileUpgrade(link) then return link .. " " .. arrow end
        return link
    end))
end

local chatEvents = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_BATTLEGROUND", "CHAT_MSG_BATTLEGROUND_LEADER", "CHAT_MSG_LOOT", "CHAT_MSG_SYSTEM",
    "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_ACHIEVEMENT", "CHAT_MSG_GUILD_ACHIEVEMENT",
}
local registered = {}
local function filter(_, _, message, ...)
    -- Filtering changes local display only. Preserve every trailing argument,
    -- including nils, so sender identities/channel metadata are not altered.
    if safeString(message) then
        local ok, decorated = pcall(FW.DecorateUpgradeChatMessage, FW, message)
        if ok and decorated then return false, decorated, ... end
    end
    return false, message, ...
end

function FW:InstallUpgradeChatHooks()
    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    if not add then return end
    for _, event in ipairs(chatEvents) do
        if not registered[event] then
            local ok = pcall(add, event, filter)
            if ok then registered[event] = true end
        end
    end
end
