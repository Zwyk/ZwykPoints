local FW = {}
local comparisons, calls, refreshes = {}, 0, 0
ZwykValuesDB = nil
for _, file in ipairs({"JSON.lua", "Stats.lua", "Core.lua", "Upgrades.lua"}) do
    assert(loadfile(file))("ZwykValues", FW)
end
FW:Initialize()
function FW:RefreshUpgradeIndicators() refreshes = refreshes + 1 end
function FW:ItemKey(link) return link:match("item:[^|]+") end
function FW:CompareItem(link, profile)
    calls = calls + 1
    local value = comparisons[self:ItemKey(link)]
    if type(value) == "function" then return value(profile) end
    return value
end
local main = FW:GetProfiles()[1]
local other = assert(FW:CreateProfile("Other", {strength=2}))
assert(FW:GetMainProfile() == nil)
for _, key in ipairs({"upgradeBags", "upgradeRolls", "upgradeChat"}) do assert(FW.DB.options[key] == false) end
assert(not FW:SetMainProfile("missing"))
assert(not FW:SetUpgradeOption("anything", true))
assert(not FW:SetUpgradeOption("upgradeBags", "yes"))
assert(FW:SetMainProfile(main.id) and FW:GetMainProfile() == main)
assert(FW:UpdateProfile(main.id, {active=false}))
assert(FW:GetMainProfile() == main, "main designation is independent of tooltip visibility")
assert(FW:CopyProfile(main.id) and FW:GetMainProfile() == main)
assert(FW:SetMainProfile(other.id) and FW:GetMainProfile() == other)
local saved = ZwykValuesDB
FW.DB = nil; FW:Initialize()
assert(FW.DB == saved and FW:GetMainProfile() == other)
assert(FW:SetMainProfile(nil) and not FW:GetMainProfile())
assert(not FW:IsMainProfileUpgrade("item:100") and calls == 0)
assert(FW:SetMainProfile(main.id))

comparisons["item:100"] = {record={}, comparisons={{status="upgrade"}}}
comparisons["item:101"] = {record={}, comparisons={{status="downgrade"}}}
comparisons["item:102"] = {record={}, comparisons={{status="equal"}}}
assert(FW:IsMainProfileUpgrade("item:100"))
local afterFirst = calls
assert(FW:IsMainProfileUpgrade("item:100") and calls == afterFirst, "repeated links reuse decisions")
assert(not FW:IsMainProfileUpgrade("item:101"))
assert(not FW:IsMainProfileUpgrade("item:102"))
local completeCalls = calls
assert(not FW:IsMainProfileUpgrade("item:102") and calls == completeCalls, "complete non-upgrades cache too")
FW.equipmentRevision = 1
comparisons["item:100"] = {record={}, comparisons={{status="equal"}}}
assert(not FW:IsMainProfileUpgrade("item:100") and calls == completeCalls+1, "equipment revision invalidates upgrades")
comparisons["item:100"] = {record={}, comparisons={{status="upgrade"}}}
assert(FW:UpdateProfile(main.id, {weights={strength=3}}))
assert(FW:IsMainProfileUpgrade("item:100"), "profile edits refresh comparisons")
comparisons["item:100:8481"] = {record={}, comparisons={{status="downgrade"}}}
assert(not FW:IsMainProfileUpgrade("item:100:8481"), "enchanted variants stay distinct")

-- Loading and partial totals never become permanent false/true answers.
assert(not FW:IsMainProfileUpgrade("item:103"))
comparisons["item:103"] = {record={}, comparisons={{status="upgrade"}}}
assert(FW:IsMainProfileUpgrade("item:103"))
comparisons["item:104"] = {record={partial=true}, comparisons={{status="upgrade"}}}
assert(not FW:IsMainProfileUpgrade("item:104"))
comparisons["item:104"].record.partial=false
assert(FW:IsMainProfileUpgrade("item:104"))
comparisons["item:105"] = {record={scoreIssues={[main.id]={warnings={"unit unknown"}}}}, comparisons={{status="upgrade"}}}
assert(not FW:IsMainProfileUpgrade("item:105"))
comparisons["item:105"].record.scoreIssues=nil
assert(FW:IsMainProfileUpgrade("item:105"))
comparisons["item:106"] = {record={}, comparisons={{status="upgrade",hasIssues=true}}}
assert(not FW:IsMainProfileUpgrade("item:106"))
comparisons["item:106"].comparisons[1].hasIssues=nil
assert(FW:IsMainProfileUpgrade("item:106"))
comparisons["item:107"] = {record={}, comparisons={{status="downgrade"},{status="upgrade"}}}
assert(FW:IsMainProfileUpgrade("item:107"), "either ring/trinket replacement may establish an upgrade")
comparisons["item:108"] = {record={}, comparisons={{error="loading"},{status="upgrade"}}}
assert(FW:IsMainProfileUpgrade("item:108"), "one fully known upgrade remains valid if the other slot loads")
comparisons["item:109"] = {record={}, comparisons={{error="loading"},{status="equal"}}}
assert(not FW:IsMainProfileUpgrade("item:109"))
comparisons["item:109"].comparisons[1]={status="upgrade"}
assert(FW:IsMainProfileUpgrade("item:109"), "missing baseline is retried")
comparisons["item:110"] = {record={}, comparisons={}, note="requires main hand"}
assert(not FW:IsMainProfileUpgrade("item:110"))
comparisons["item:112"] = {record={}, comparisons={}, pending=true}
assert(not FW:IsMainProfileUpgrade("item:112"))
comparisons["item:112"] = {record={}, comparisons={{status="upgrade"}}}
assert(FW:IsMainProfileUpgrade("item:112"), "main-hand compatibility loading is retried")
comparisons["item:111"] = function() error("temporary item error") end
assert(not FW:IsMainProfileUpgrade("item:111"))
comparisons["item:111"] = {record={},comparisons={{status="upgrade"}}}
assert(FW:IsMainProfileUpgrade("item:111"))
assert(FW:SetUpgradeOption("upgradeBags",true) and FW.DB.options.upgradeRolls==false)
assert(refreshes > 0)

-- Decorate received display strings, preserving variants, colors and links.
local arrow="|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t"
local link="|cff0070dd|Hitem:100|h[Upgrade]|h|r"
local variant="|cff0070dd|Hitem:100:8481|h[Same base item]|h|r"
local lower="|cff0070dd|Hitem:101|h[Lower]|h|r"
local message="Looking at " .. link .. " and " .. variant .. " and " .. lower .. "."
local oldCalls=calls
assert(FW:DecorateUpgradeChatMessage(message)==message and calls==oldCalls)
assert(FW:SetUpgradeOption("upgradeChat",true))
local decorated=FW:DecorateUpgradeChatMessage(message)
assert(decorated=="Looking at |cff0070dd|Hitem:100|h[Upgrade]|h " .. arrow .. "|r and " .. variant .. " and " .. lower .. ".")
assert(FW:DecorateUpgradeChatMessage(decorated)==decorated, "filter re-entry does not duplicate arrows")
assert(FW:DecorateUpgradeChatMessage("No link")=="No link")
assert(FW:DecorateUpgradeChatMessage("|Hspell:100|h[Spell]|h")=="|Hspell:100|h[Spell]|h")
local twice=FW:DecorateUpgradeChatMessage(link .. " " .. link)
local _, count=twice:gsub("ArrowUp", "")
assert(count==2, "each repeated link gets an adjacent marker")

local filters, modernAdds, legacyAdds = {},0,0
ChatFrameUtil={AddMessageEventFilter=function(event, callback)
    modernAdds=modernAdds+1; filters[event]=callback
end}
ChatFrame_AddMessageEventFilter=function() legacyAdds=legacyAdds+1 end
FW:InstallUpgradeChatHooks()
assert(modernAdds>0 and legacyAdds==0 and filters.CHAT_MSG_LOOT and filters.CHAT_MSG_CHANNEL)
local installed=modernAdds
FW:InstallUpgradeChatHooks(); assert(modernAdds==installed)
local function pack(...) return {n=select("#",...),...} end
local result=pack(filters.CHAT_MSG_CHANNEL({},"CHAT_MSG_CHANNEL",message,"Player",nil,9,nil,"Trade"))
assert(result.n==7 and result[1]==false and result[2]==decorated)
assert(result[3]=="Player" and result[4]==nil and result[5]==9 and result[6]==nil and result[7]=="Trade")
local secret=setmetatable({}, {__tostring=function() error("must not touch secret") end})
issecretvalue=function(value) return value==secret end
local protected=pack(filters.CHAT_MSG_LOOT({},"CHAT_MSG_LOOT",secret,"Sender"))
assert(protected[1]==false and protected[2]==secret and protected[3]=="Sender")
assert(not FW:IsMainProfileUpgrade(secret))
issecretvalue=nil
assert(FW:SetUpgradeOption("upgradeChat",false))
assert(select(2, filters.CHAT_MSG_LOOT({},"CHAT_MSG_LOOT",message))==message)
assert(FW:DeleteProfile(main.id) and FW:GetMainProfile()==nil)
assert(FW.DB.options.upgradeBags==true, "deleting main stops markers without changing location choices")

-- A fresh namespace also supports older clients with only the legacy API.
local legacy={GetMainProfile=function() return nil end}
ChatFrameUtil=nil
assert(loadfile("Upgrades.lua"))("ZwykValues",legacy)
legacy:InstallUpgradeChatHooks()
assert(legacyAdds==installed)
print("Upgrade profile/chat tests passed")
