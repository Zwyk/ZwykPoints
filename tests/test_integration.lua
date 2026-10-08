-- Exercise the actual reader -> persistent score cache -> comparison -> tooltip
-- pipeline. These mock APIs verify our contracts, not live client behavior.
local FW = {}
local itemDB={
    ["item:100:0:0:0:0:0:0:0:60"]={name="New helmet",strength=10,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:101:0:0:0:0:0:0:0:60"]={name="Old helmet",strength=8,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:100:0:0:0:0:0:-7:123:60"]={name="Variant helmet",strength=15,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:102:0:0:0:0:0:0:0:60"]={name="Scanner helmet",strength=4,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:103:0:0:0:0:0:0:0:60"]={name="Partial helmet",strength=12,crit=1,equipLoc="INVTYPE_HEAD",unknown=3},
    ["item:104:8481:0:0:0:0:0:0:60"]={name="Enchanted new helmet",strength=10,crit=1,equipLoc="INVTYPE_HEAD",enchant=5},
    ["item:104:0:0:0:0:0:0:0:60"]={name="Base new helmet",strength=10,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:105:8481:0:0:0:0:0:0:60"]={name="Enchanted old helmet",strength=8,crit=1,equipLoc="INVTYPE_HEAD",enchant=10},
    ["item:105:0:0:0:0:0:0:0:60"]={name="Base old helmet",strength=8,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:106:0:0:0:0:0:0:0:60"]={name="Cloth helmet",strength=20,crit=1,equipLoc="INVTYPE_HEAD",subclassID=1},
    ["item:107:0:0:0:0:0:0:0:60"]={name="Warrior helmet",strength=20,crit=1,equipLoc="INVTYPE_HEAD",classes="Warrior"},
    ["item:108:0:0:0:0:0:0:0:60"]={name="Shared helmet",strength=20,crit=1,equipLoc="INVTYPE_HEAD",classes="Warrior, Paladin"},
    ["item:109:0:0:0:0:0:0:0:60"]={name="Strength potion",strength=99,crit=1,equipLoc="",classID=0,unknown=3},
    ["item:110:0:0:0:0:0:0:0:60"]={name="Quest item",strength=99,crit=1,equipLoc="",classID=12},
    ["item:111:0:0:0:0:0:0:0:60"]={name="Bag",strength=99,crit=1,equipLoc="INVTYPE_BAG",classID=1},
    ["item:112:0:0:0:0:0:0:0:60"]={name="New arrows",ammoDps=7.5,equipLoc="INVTYPE_AMMO",classID=6,subclassID=2},
    ["item:113:0:0:0:0:0:0:0:60"]={name="Equipped arrows",ammoDps=4,equipLoc="INVTYPE_AMMO",classID=6,subclassID=2},
    ["item:114:0:0:0:0:0:0:0:60"]={name="Equipped bow",strength=99,crit=1,equipLoc="INVTYPE_RANGED",classID=2,subclassID=2},
    ["item:115:8481:0:0:0:0:0:0:60"]={name="Enchanted Use helmet",strength=0,crit=0,spellPower=20,enchant=5,equipLoc="INVTYPE_HEAD",use="Use: Increases spell power by 120 for 10 sec. (2 Min Cooldown)"},
    ["item:115:0:0:0:0:0:0:0:60"]={name="Base Use helmet",strength=0,crit=0,spellPower=20,equipLoc="INVTYPE_HEAD",use="Use: Increases spell power by 120 for 10 sec. (2 Min Cooldown)"},
    ["item:116:8481:0:0:0:0:0:0:60"]={name="Equipped enchanted Use helmet",strength=0,crit=0,spellPower=18,enchant=10,equipLoc="INVTYPE_HEAD",use="Use: Increases spell power by 60 for 10 sec. (2 Min Cooldown)"},
    ["item:116:0:0:0:0:0:0:0:60"]={name="Equipped Base Use helmet",strength=0,crit=0,spellPower=18,equipLoc="INVTYPE_HEAD",use="Use: Increases spell power by 60 for 10 sec. (2 Min Cooldown)"},
    ["item:117:0:0:0:0:0:0:0:60"]={name="Passive spell-power helmet",strength=0,crit=0,spellPower=23,equipLoc="INVTYPE_HEAD"},
    ["item:118:0:0:0:0:0:0:0:60"]={name="Use helmet awaiting cooldown",strength=0,crit=0,spellPower=15,equipLoc="INVTYPE_HEAD",use="Use: Increases spell power by 120 for 10 sec."},
}
local candidate="item:100:0:0:0:0:0:0:0:60"
local baseline="item:101:0:0:0:0:0:0:0:60"
local variant="item:100:0:0:0:0:0:-7:123:60"
local scanned="item:102:0:0:0:0:0:0:0:60"
local partial="item:103:0:0:0:0:0:0:0:60"
local reads,scans,scoreCalls=0,0,0
local clock=10
GetTime=function() return clock end
local function definition(link)
    local payload=type(link)=="string" and link:match("(item:[^|%s]+)")
    return assert(itemDB[payload],"Unexpected item " .. tostring(link))
end
local function sourceLines(link)
    local item=definition(link)
    if item.ammoDps then return {item.name,"Adds " .. item.ammoDps .. " damage per second"} end
    local lines = {item.name,"+" .. item.strength .. " Strength",
        "Equip: Increases your chance to get a critical strike by " .. item.crit .. "%."}
    if item.spellPower then lines[#lines+1]="Equip: Increases damage and healing done by magical spells and effects by up to " .. item.spellPower .. "." end
    if item.unknown then lines[#lines+1]="+" .. item.unknown .. " Mystic Focus" end
    if item.enchant then lines[#lines+1]="Enchanted: Strength +" .. item.enchant end
    if item.classes then lines[#lines+1]="Classes: " .. item.classes end
    if item.use then lines[#lines+1]=item.use end
    return lines
end
GetBuildInfo=function() return "16.0.0","65000","Oct 1 2026",160000 end
GetLocale=function() return "enUS" end
local level=60
UnitLevel=function() return level end
UnitClass=function() return "Paladin","PALADIN" end
GetInventoryItemLink=function(_,slot) if slot==1 then return baseline end end
GetItemInfo=function(link)
    local item=definition(link)
    return item.name,link,3,60,60,"Armor","Plate",1,item.equipLoc,nil,nil,item.classID or 4,item.subclassID or 4
end
C_Item={
    GetItemInfo=GetItemInfo,
    GetItemStats=function(link)
        reads=reads+1
        local item=definition(link)
        if item.ammoDps then return {ITEM_MOD_DAMAGE_PER_SECOND_SHORT=item.ammoDps} end
        local stats = {ITEM_MOD_STRENGTH_SHORT=item.strength,ITEM_MOD_CRIT_SHORT=item.crit}
        if item.spellPower then stats.ITEM_MOD_SPELL_POWER_SHORT=item.spellPower end
        if item.unknown then stats.ITEM_MOD_FOREVER_FOCUS_SHORT=item.unknown end
        return stats
    end,
    IsItemDataCachedByID=function() return true end,
}
C_TooltipInfo={GetHyperlink=function(link)
    scans=scans+1
    local lines={}
    for _,text in ipairs(sourceLines(link)) do lines[#lines+1]={leftText=text} end
    return {lines=lines}
end}
Enum={TooltipDataType={Item=1}}
local postCall
TooltipDataProcessor={AddTooltipPostCall=function(_,fn) postCall=fn end}
UIParent={}
local function frame(name)
    local t={name=name,lines={},hooks={},shown=false}
    function t:GetName() return self.name end
    function t:AddLine(text) self.lines[#self.lines+1]={left=text} end
    function t:AddDoubleLine(left,right) self.lines[#self.lines+1]={left=left,right=right} end
    function t:NumLines() return #self.lines end
    function t:IsForbidden() return false end
    function t:IsEquippedItem() return false end
    function t:IsShown() return self.shown end
    function t:GetItem() return self.link and definition(self.link).name,self.link end
    function t:HasScript() return true end
    function t:HookScript(event,fn)
        self.hooks[event]=self.hooks[event] or {}
        self.hooks[event][#self.hooks[event]+1]=fn
    end
    function t:Fire(event)
        for _,fn in ipairs(self.hooks[event] or {}) do fn(self) end
    end
    function t:ClearLines() self.lines={};self:Fire("OnTooltipCleared") end
    function t:SetOwner() end
    function t:SetHyperlink(link)
        self:ClearLines();self.link=link;self.shown=true
        for _,text in ipairs(sourceLines(link)) do self:AddLine(text) end
        for index=1,#self.lines do
            local slot=index
            _G[self.name .. "TextLeft" .. index]={GetText=function() return self.lines[slot] and self.lines[slot].left end}
            _G[self.name .. "TextRight" .. index]={GetText=function() return self.lines[slot] and self.lines[slot].right end}
        end
        if postCall then postCall(self,{hyperlink=link}) end
        self:Fire("OnTooltipSetItem")
    end
    function t:Show() self.shown=true;self:Fire("OnTooltipSetItem") end
    function t:Hide() self.shown=false;self:Fire("OnHide") end
    return t
end
GameTooltip=frame("GameTooltip")
CreateFrame=function(kind,name)
    assert(kind=="GameTooltip" and name=="ZwykValuesScanTooltip")
    local scanner=frame(name);_G[name]=scanner;return scanner
end
for _,file in ipairs({"JSON.lua","Stats.lua","Core.lua","Items.lua","Compare.lua","Upgrades.lua","Tooltips.lua"}) do
    assert(loadfile(file))("ZwykValues",FW)
end
local actualScoreStats=FW.ScoreStats
function FW:ScoreStats(profile,stats) scoreCalls=scoreCalls+1;return actualScoreStats(self,profile,stats) end
FW:Initialize()
local one=FW:GetProfiles()[1]
assert(FW:UpdateProfile(one.id,{name="Melee",weights={strength=2,crit=10}}))
local two=assert(FW:CreateProfile("Caster",{crit=5}))
FW:InstallTooltipHooks()
GameTooltip:SetHyperlink(candidate)
assert(reads==2 and scans==2 and scoreCalls==4)
local function findLine(text)
    for _,line in ipairs(GameTooltip.lines) do if line.left==text then return line end end
end
assert(findLine("Melee").right=="30.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+4.00 (+15.4%)|r")
assert(findLine("Caster").right=="5.00  |cffb2b2b2=0.00 (+0.0%)|r")
assert(not findLine("  Base"), "unchanged full/Base values omit both duplicate profile sublines")
assert(not findLine("ZwykValues"), "Tooltip should not add an addon header")
local lineCount=#GameTooltip.lines
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==lineCount and scoreCalls==4)
GameTooltip:SetHyperlink(candidate)
assert(reads==2 and scans==2 and scoreCalls==4)

-- Weight changes invalidate only that profile's totals, retaining item reads.
assert(FW:UpdateProfile(one.id,{weights={strength=3}}))
GameTooltip:SetHyperlink(candidate)
assert(reads==2 and scans==2 and scoreCalls==6)
assert(findLine("Melee").right=="40.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+6.00 (+17.6%)|r")
assert(FW:GetScore(variant,one)==55)
assert(reads==3 and scans==3 and scoreCalls==7)
assert(FW:GetScore(candidate,one)==40 and scoreCalls==7)

-- A genuinely partial item still shows both profile subtotals, one warning,
-- and a complete aggregate diagnostic entry, even with inline debugging off.
GameTooltip:SetHyperlink(partial)
assert(findLine("Melee").right=="46.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+12.00 (+35.3%)|r")
assert(findLine("Caster").right=="5.00  |cffb2b2b2=0.00 (+0.0%)|r")
local warningCount=0
for _,line in ipairs(GameTooltip.lines) do
    if line.left:find("Partial stat data",1,true) then warningCount=warningCount+1 end
end
assert(warningCount==1, "One shared warning should cover all active profiles")
local report=assert(FW.JSON.Decode(assert(FW.JSON.Encode(FW:GetIssueReport()))))
assert(report.itemCount==1 and report.items[1].raw.ITEM_MOD_FOREVER_FOCUS_SHORT==3)
assert(report.items[1].profileScores[one.id].score==46 and report.items[1].profileScores[two.id].score==5)
assert(not FW.DB.cache.items[FW:ItemKey(partial)] and not FW.DB.cache.scores[FW:ItemKey(partial)])

-- A complete candidate still warns when its equipped comparison is partial.
local oldBaseline=baseline
baseline=partial
GameTooltip:SetHyperlink(candidate)
assert(findLine("Melee").right=="40.00  |cffff5959|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:12:12:0:0|t-6.00 (-13.0%)|r")
assert(findLine("Partial stat data; /zv inspect or /zv exportissues."))
baseline=oldBaseline

-- The full pipeline can report a downgrade with enchants and an upgrade on
-- the base subline, stripping the equipped enchant as well as the candidate.
baseline="|cnIQ2:|Hitem:105:8481:0:0:0:0:0:0:60|h[Enchanted old helmet]|h|r"
GameTooltip:SetHyperlink("|cnIQ2:|Hitem:104:8481:0:0:0:0:0:0:60|h[Enchanted new helmet]|h|r")
assert(findLine("Melee").right=="55.00  |cffff5959|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:12:12:0:0|t-9.00 (-14.1%)|r")
assert(findLine("  Base").right=="40.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+6.00 (+17.6%)|r")
assert(not findLine("Partial stat data; /zv inspect or /zv exportissues."))
-- Removing an equipped enchant changes the comparison even when the hovered
-- item's own score is unchanged. Only the profile valuing that enchant differs.
GameTooltip:SetHyperlink(candidate)
assert(findLine("Melee").right:find("40.00",1,true))
assert(findLine("  Base").right=="40.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+6.00 (+17.6%)|r")
local relevantBaseRows=0
for _,line in ipairs(GameTooltip.lines) do if line.left=="  Base" then relevantBaseRows=relevantBaseRows+1 end end
assert(relevantBaseRows==1,"Base visibility is calculated independently for each profile")
baseline=oldBaseline

-- The actual legacy scanner must be excluded before SetHyperlink invokes hooks.
C_TooltipInfo=nil
assert(FW:GetScore(scanned,one)==22)
assert(FW.ScanTooltip and not FW.ScanTooltip.fwHooked and not FW.ScanTooltip.fwSignature)
assert(FW.ScanTooltip:NumLines()==3 and not FW.ScanTooltip:IsShown())

-- Actual client metadata -> profile filters -> full/base tooltip and upgrade
-- decisions. The same item can be hidden for one profile and shown for another.
C_TooltipInfo={GetHyperlink=function(link)
    scans=scans+1
    local lines={}
    for _,text in ipairs(sourceLines(link)) do lines[#lines+1]={leftText=text} end
    return {lines=lines}
end}
assert(FW:UpdateProfile(one.id,{itemFilters={armor={["1"]=false},includeOtherClasses=false}}))
assert(FW:SetMainProfile(one.id))
local cloth="item:106:0:0:0:0:0:0:0:60"
GameTooltip:SetHyperlink(cloth)
assert(not findLine("Melee") and findLine("Caster") and not findLine("  Base"))
assert(not FW:IsMainProfileUpgrade(cloth))
local warriorItem="item:107:0:0:0:0:0:0:0:60"
GameTooltip:SetHyperlink(warriorItem)
assert(not findLine("Melee") and findLine("Caster"))
assert(not FW:IsMainProfileUpgrade(warriorItem))
local shared="item:108:0:0:0:0:0:0:0:60"
GameTooltip:SetHyperlink(shared)
assert(findLine("Melee").right:find("70.00",1,true) and FW:IsMainProfileUpgrade(shared))
-- Switch the current player's class without discarding numeric score caches.
UnitClass=function() return "Warrior","WARRIOR" end
GameTooltip:SetHyperlink(warriorItem)
assert(findLine("Melee").right:find("70.00",1,true))
UnitClass=function() return "Paladin","PALADIN" end
assert(FW:UpdateProfile(one.id,{itemFilters={armor={["1"]=true},includeOtherClasses=true}}))
GameTooltip:SetHyperlink(cloth)
assert(findLine("Melee").right:find("70.00",1,true) and FW:IsMainProfileUpgrade(cloth))

-- Native non-gear metadata suppresses values for every profile and does not
-- turn consumable text into missing-gear-stat diagnostics.
FW.DB.options.debugUnknownStats, FW.DB.options.upgradeChat = true, true
local beforeNonGearScores, beforeNonGearIssues = scoreCalls, FW:GetIssueReport().itemCount
for _, id in ipairs({109,110,111}) do
    local link="item:" .. id .. ":0:0:0:0:0:0:0:60"
    GameTooltip:SetHyperlink(link)
    assert(#GameTooltip.lines==#sourceLines(link), "non-gear keeps only its native tooltip lines")
    assert(not findLine("Melee") and not findLine("Caster") and not findLine("  Base"))
    assert(not FW:IsMainProfileUpgrade(link))
    local chat="|H" .. link .. "|h[Non-gear]|h"
    assert(FW:DecorateUpgradeChatMessage(chat)==chat)
    local score, record, detail=FW:GetScore(link,one,true)
    assert(score==nil and detail=="excluded" and next(record.stats)==nil)
    assert(not FW.DB.cache.scores[FW:ItemKey(link)])
end
assert(scoreCalls==beforeNonGearScores, "non-gear is never weighted")
assert(FW:GetIssueReport().itemCount==beforeNonGearIssues, "non-gear creates no missing-stat issues")
FW.DB.options.debugUnknownStats = false

-- Ammunition DPS uses the ranged weight and compares against the ammo slot,
-- not the equipped ranged weapon. Full/Base rows and upgrade links agree.
local ammoProfile = assert(FW:CreateProfile("Ammunition",{rangedDps=2,rangedSpeed=10,dps=100}))
assert(FW:SetMainProfile(ammoProfile.id))
local ammoLink="item:112:0:0:0:0:0:0:0:60"
local ammoBaseline="item:113:0:0:0:0:0:0:0:60"
local nativeInventoryLink=GetInventoryItemLink
GetInventoryItemLink=function(unit,slot)
    if slot==0 then return ammoBaseline end
    if slot==18 then return "item:114:0:0:0:0:0:0:0:60" end
    return nativeInventoryLink(unit,slot)
end
GameTooltip:SetHyperlink(ammoLink)
assert(findLine("Ammunition").right=="15.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+7.00 (+87.5%)|r")
assert(not findLine("  Base") and not findLine("Partial stat data; /zv inspect or /zv exportissues."),
    "unchanted ammo has no duplicate Base row")
local ammoComparison=assert(FW:CompareBaseItem(ammoLink,ammoProfile))
assert(#ammoComparison.comparisons==1 and ammoComparison.comparisons[1].slots[1]==0)
assert(ammoComparison.comparisons[1].baseline==8 and ammoComparison.comparisons[1].label=="Ammunition")
assert(FW:IsMainProfileUpgrade(ammoLink))
assert(FW:DecorateUpgradeChatMessage("|H" .. ammoLink .. "|h[Arrows]|h"):find("ArrowUp",1,true))
local afterAmmoScores=scoreCalls
GameTooltip:SetHyperlink(ammoLink)
assert(scoreCalls==afterAmmoScores,"ammo tooltip reuses full and Base score caches")
ammoBaseline=nil
FW.equipmentRevision=1
ammoComparison=assert(FW:CompareItem(ammoLink,ammoProfile))
assert(ammoComparison.comparisons[1].baseline==0 and ammoComparison.comparisons[1].percent==nil)
GetInventoryItemLink=nativeInventoryLink

-- A real Use line flows through parsing, Base-derived weighting, both equipped
-- averages and tooltip relevance. Static upgrade markers retain their score.
local averageProfile=assert(FW:CreateProfile("Average caster",{spellDamage=2,healing=1,strength=2}))
for _,profile in ipairs({one,two,ammoProfile}) do assert(FW:UpdateProfile(profile.id,{active=false})) end
assert(FW:SetMainProfile(averageProfile.id))
local enchantedUse="item:115:8481:0:0:0:0:0:0:60"
local baseUse="item:115:0:0:0:0:0:0:0:60"
local equippedUse="item:116:8481:0:0:0:0:0:0:60"
local equippedBaseUse="item:116:0:0:0:0:0:0:0:60"
local passiveUseCandidate="item:117:0:0:0:0:0:0:0:60"
local missingCooldown="item:118:0:0:0:0:0:0:0:60"
baseline=equippedUse
local fullUseScore=assert(FW:GetScore(enchantedUse,averageProfile))
local baseUseScore=assert(FW:GetBaseScore(enchantedUse,averageProfile))
local averageUseScore,useRecord,_,useMetadata=FW:GetAverageUseScore(enchantedUse,averageProfile)
assert(fullUseScore==70 and baseUseScore==60 and averageUseScore==90, "Use average adds its gain to the unenchanted score")
assert(useRecord==FW:GetItem(baseUse) and useRecord.stats.spellDamage==20 and useRecord.stats.healing==20, "Average scoring keeps the parsed Base item and its static stats")
assert(#useRecord.onUseEffects==1 and useRecord.onUseEffects[1].amount==120 and useRecord.onUseEffects[1].duration==10 and useRecord.onUseEffects[1].cooldown==120, "the actual parser reads the complete Use amount, duration and cooldown")
assert(useRecord.onUseStats.spellDamage==10 and useRecord.onUseStats.healing==10 and useMetadata.averageUseGain==30, "120 spell power for 10/120 seconds gives 10 averaged damage and healing")
assert(useMetadata.hasAverageUse and not useMetadata.averageUseIncomplete and #useMetadata.averageUseWarnings==0)
local equippedAverage,equippedRecord=FW:GetAverageUseScore(equippedUse,averageProfile,true)
assert(FW:GetScore(equippedUse,averageProfile)==74 and FW:GetBaseScore(equippedUse,averageProfile)==54 and equippedAverage==69, "the equipped item's enchant is removed before averaging its own Use effect")
assert(equippedRecord==FW:GetItem(equippedBaseUse) and equippedRecord.onUseStats.spellDamage==5)
local actualAverageComparison=assert(FW:CompareAverageUseItem(enchantedUse,averageProfile))
assert(actualAverageComparison.score==90 and actualAverageComparison.comparisons[1].baseline==69 and actualAverageComparison.comparisons[1].delta==21 and actualAverageComparison.comparisons[1].status=="upgrade", "the candidate and equipped Base-derived averages use the same weighting")
GameTooltip:SetHyperlink(enchantedUse)
assert(findLine("Average caster").right=="70.00  |cffff5959|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:12:12:0:0|t-4.00 (-5.4%)|r")
assert(findLine("  Base").right=="60.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+6.00 (+11.1%)|r")
assert(findLine("  Average use").right=="90.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+21.00 (+30.4%)|r")
assert(findLine("  Average use assumes use on cooldown.") and not findLine("Partial stat data; /zv inspect or /zv exportissues."))
assert(not FW:IsMainProfileUpgrade(enchantedUse), "Use averages do not change the main static-score upgrade decision")
local useChat="|H" .. enchantedUse .. "|h[Enchanted Use helmet]|h"
assert(FW:DecorateUpgradeChatMessage(useChat)==useChat, "chat upgrade arrows continue to use the regular enchanted score")
local cachedUseReads,cachedUseScans,cachedUseScores=reads,scans,scoreCalls
GameTooltip:SetHyperlink(enchantedUse)
assert(reads==cachedUseReads and scans==cachedUseScans and scoreCalls==cachedUseScores, "repeat complete Use tooltips reuse parsed records and weighted totals")

-- A passive candidate still needs an Average row when an equipped Use effect
-- changes only its replacement comparison, even with zero candidate Use gain.
GameTooltip:SetHyperlink(passiveUseCandidate)
local passiveScore,passiveRecord,_,passiveMetadata=FW:GetAverageUseScore(passiveUseCandidate,averageProfile)
assert(passiveScore==69 and not passiveMetadata.hasAverageUse and passiveMetadata.averageUseGain==0 and #passiveRecord.onUseEffects==0)
local passiveAverageComparison=assert(FW:CompareAverageUseItem(passiveUseCandidate,averageProfile))
assert(passiveAverageComparison.hasAverageUse and passiveAverageComparison.averageUseGain==0 and passiveAverageComparison.comparisons[1].baseline==69 and passiveAverageComparison.comparisons[1].status=="equal", "equipped effects make a passive candidate's average comparison relevant")
assert(findLine("  Base").right=="69.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+15.00 (+27.8%)|r")
assert(findLine("  Average use").right=="69.00  |cffb2b2b2=0.00 (+0.0%)|r", "an unchanged candidate score retains the equipped-use comparison difference")

-- Missing cooldown data is a retryable Use-only issue. Repairing tooltip text
-- after the one-second retry window preserves the cached static API extraction.
baseline=passiveUseCandidate
GameTooltip:SetHyperlink(missingCooldown)
local unavailableScore,unavailableRecord,_,unavailableMetadata=FW:GetAverageUseScore(missingCooldown,averageProfile)
assert(unavailableScore==45 and unavailableMetadata.hasAverageUse and unavailableMetadata.averageUseIncomplete and unavailableRecord.onUseRetryable)
assert(findLine("Average caster").right:find("45.00",1,true) and not findLine("  Base"), "missing Use cooldowns retain regular values without redundant Base")
assert(findLine("  Average use: unavailable") and not findLine("  Average use") and not findLine("  Average use assumes use on cooldown."), "incomplete Use estimates never show a confident numeric row")
assert(not findLine("Partial stat data; /zv inspect or /zv exportissues."), "a Use-only issue does not mark complete static stats as partial")
local unavailableWarning=false
for _,line in ipairs(GameTooltip.lines) do if line.left:find("full on-use cooldown",1,true) then unavailableWarning=true end end
assert(unavailableWarning,"the unavailable row explains the missing full cooldown")
local retryReads,retryScans=reads,scans
local staticSnapshot=assert(FW.JSON.Encode(unavailableRecord.stats))
itemDB[missingCooldown].use="Use: Increases spell power by 120 for 10 sec. (2 Min Cooldown)"
clock=clock+.5
local earlyScore,earlyRecord,_,earlyMetadata=FW:GetAverageUseScore(missingCooldown,averageProfile)
assert(earlyScore==45 and earlyRecord==unavailableRecord and earlyMetadata.averageUseIncomplete and reads==retryReads and scans==retryScans, "repeated incomplete hovers share the bounded retry window")
clock=clock+.5
local recoveredScore,recoveredRecord,_,recoveredMetadata=FW:GetAverageUseScore(missingCooldown,averageProfile)
assert(recoveredScore==75 and recoveredRecord==unavailableRecord and not recoveredMetadata.averageUseIncomplete and recoveredMetadata.averageUseGain==30 and #recoveredMetadata.averageUseWarnings==0, "an available cooldown recovers the same item record's average")
assert(reads==retryReads and scans==retryScans+1, "Use recovery rereads tooltip text once without repeating GetItemStats")
assert(assert(FW.JSON.Encode(recoveredRecord.stats))==staticSnapshot and FW:GetScore(missingCooldown,averageProfile)==45, "Use-only recovery does not alter static stats or cached static totals")
GameTooltip:SetHyperlink(missingCooldown)
assert(findLine("  Average use").right=="75.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:10:10:0:0|t+6.00 (+8.7%)|r" and not findLine("  Average use: unavailable"), "the repaired Use effect reaches comparison and tooltip display")
assert(findLine("  Average use assumes use on cooldown.") and reads==retryReads and scans==retryScans+1)
baseline=oldBaseline
for _,profile in ipairs({one,two,ammoProfile}) do assert(FW:UpdateProfile(profile.id,{active=true})) end
assert(FW:UpdateProfile(averageProfile.id,{active=false}))
assert(FW:SetMainProfile(ammoProfile.id))

-- SavedVariables reused by a fresh addon namespace keep valid item totals.
local persisted=ZwykValuesDB
local reloaded={}
postCall=nil -- A client reload removes previous Lua/frame callback state.
for _,file in ipairs({"JSON.lua","Stats.lua","Core.lua","Items.lua"}) do
    assert(loadfile(file))("ZwykValues",reloaded)
end
reloaded:Initialize()
assert(reloaded.DB==persisted)
local previousReads=reads
assert(reloaded:GetScore(candidate,reloaded.DB.profiles[one.id])==40)
assert(reads==previousReads)

-- Level-sensitive tooltip interpretation uses a distinct cache key.
level=61
assert(reloaded:GetScore(candidate,reloaded.DB.profiles[one.id])==40)
assert(reads==previousReads+1)
print("Integration tests passed")
