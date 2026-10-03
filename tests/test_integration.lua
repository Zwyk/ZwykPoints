-- Exercise the actual reader -> persistent score cache -> comparison -> tooltip
-- pipeline. These mock APIs verify our contracts, not live client behavior.
local FW = {}
local itemDB={
    ["item:100:0:0:0:0:0:0:0:60"]={name="New helmet",strength=10,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:101:0:0:0:0:0:0:0:60"]={name="Old helmet",strength=8,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:100:0:0:0:0:0:-7:123:60"]={name="Variant helmet",strength=15,crit=1,equipLoc="INVTYPE_HEAD"},
    ["item:102:0:0:0:0:0:0:0:60"]={name="Scanner helmet",strength=4,crit=1,equipLoc="INVTYPE_HEAD"},
}
local candidate="item:100:0:0:0:0:0:0:0:60"
local baseline="item:101:0:0:0:0:0:0:0:60"
local variant="item:100:0:0:0:0:0:-7:123:60"
local scanned="item:102:0:0:0:0:0:0:0:60"
local reads,scans,scoreCalls=0,0,0
local function definition(link) return assert(itemDB[link],"Unexpected item " .. tostring(link)) end
local function sourceLines(link)
    local item=definition(link)
    return {item.name,"+" .. item.strength .. " Strength",
        "Equip: Increases your chance to get a critical strike by " .. item.crit .. "%."}
end
GetBuildInfo=function() return "16.0.0","65000","Oct 1 2026",160000 end
GetLocale=function() return "enUS" end
local level=60
UnitLevel=function() return level end
GetInventoryItemLink=function(_,slot) if slot==1 then return baseline end end
GetItemInfo=function(link)
    local item=definition(link)
    return item.name,link,3,60,60,"Armor","Plate",1,item.equipLoc
end
C_Item={
    GetItemInfo=GetItemInfo,
    GetItemStats=function(link)
        reads=reads+1
        local item=definition(link)
        return {ITEM_MOD_STRENGTH_SHORT=item.strength,ITEM_MOD_CRIT_SHORT=item.crit}
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
    assert(kind=="GameTooltip" and name=="ZwykPointsScanTooltip")
    local scanner=frame(name);_G[name]=scanner;return scanner
end
for _,file in ipairs({"JSON.lua","Stats.lua","Core.lua","Items.lua","Compare.lua","Tooltips.lua"}) do
    assert(loadfile(file))("ZwykPoints",FW)
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
assert(findLine("Melee").right=="30.00" and findLine("Caster").right=="5.00")
assert(findLine("  Head: +4.00 (+15.4%) upgrade"))
assert(findLine("  Head: +0.00 (+0.0%) equal"))
local lineCount=#GameTooltip.lines
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==lineCount and scoreCalls==4)
GameTooltip:SetHyperlink(candidate)
assert(reads==2 and scans==2 and scoreCalls==4)

-- Weight changes invalidate only that profile's totals, retaining item reads.
assert(FW:UpdateProfile(one.id,{weights={strength=3}}))
GameTooltip:SetHyperlink(candidate)
assert(reads==2 and scans==2 and scoreCalls==6)
assert(findLine("Melee").right=="40.00")
assert(FW:GetScore(variant,one)==55)
assert(reads==3 and scans==3 and scoreCalls==7)
assert(FW:GetScore(candidate,one)==40 and scoreCalls==7)

-- The actual legacy scanner must be excluded before SetHyperlink invokes hooks.
C_TooltipInfo=nil
assert(FW:GetScore(scanned,one)==22)
assert(FW.ScanTooltip and not FW.ScanTooltip.fwHooked and not FW.ScanTooltip.fwSignature)
assert(FW.ScanTooltip:NumLines()==3 and not FW.ScanTooltip:IsShown())

-- SavedVariables reused by a fresh addon namespace keep valid item totals.
local persisted=ZwykPointsDB
local reloaded={}
postCall=nil -- A client reload removes previous Lua/frame callback state.
for _,file in ipairs({"JSON.lua","Stats.lua","Core.lua","Items.lua"}) do
    assert(loadfile(file))("ZwykPoints",reloaded)
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
