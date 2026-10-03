local FW = { DB = {}, equipmentRevision = 0 }
local profiles = {
    {id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}},
    {id="two",name="Caster",revision=1,color={r=.1,g=.3,b=.9}},
}
local calls = {score=0,compare=0,post=0}
local record = {stats={},equipLoc="INVTYPE_HEAD"}
function FW:GetProfiles() return profiles end
function FW:GetScore() calls.score=calls.score+1; return 100,record end
function FW:GetItem() return record end
function FW:Print(message) calls.error=message end
function FW:CompareItem()
    calls.compare=calls.compare+1
    return {score=100,record=record,comparisons={
        {label="Head",delta=10,percent=11.111,status="upgrade",baseline=90},
    }}
end

local function tooltip(name, link)
    local frame = {name=name,link=link,lines={},scripts={},shown=true}
    local function registerLines(self,index)
        if not self.name then return end
        _G[self.name .. "TextLeft" .. index]={
            GetText=function() return self.lines[index] and self.lines[index].text end,
            SetText=function(_,text) self.lines[index].text=text end,
        }
        _G[self.name .. "TextRight" .. index]={
            GetText=function() return self.lines[index] and self.lines[index].right end,
            SetText=function(_,text) self.lines[index].right=text end,
        }
    end
    function frame:AddLine(text,r,g,b)
        self.lines[#self.lines+1]={text=text,r=r,g=g,b=b}
        registerLines(self,#self.lines)
    end
    function frame:AddDoubleLine(left,right,r,g,b,rr,gg,bb)
        self.lines[#self.lines+1]={text=left,right=right,r=r,g=g,b=b,rr=rr,gg=gg,bb=bb}
        registerLines(self,#self.lines)
    end
    function frame:NumLines() return #self.lines end
    function frame:GetItem() return "Item",self.link end
    function frame:GetName() return self.name end
    function frame:IsShown() return self.shown end
    function frame:IsEquippedItem() return self.equipped == true end
    function frame:IsForbidden() return self.forbidden == true end
    function frame:HasScript() return true end
    function frame:HookScript(event, fn)
        self.scripts[event] = self.scripts[event] or {}
        self.scripts[event][#self.scripts[event]+1]=fn
    end
    function frame:Fire(event)
        for _,fn in ipairs(self.scripts[event] or {}) do fn(self) end
    end
    function frame:Show() self.shown=true; self:Fire("OnTooltipSetItem") end
    function frame:Hide() self.shown=false; self:Fire("OnHide") end
    function frame:Clear()
        self.lines={}; self:Fire("OnTooltipCleared")
    end
    function frame:SetHyperlink(itemLink)
        self:Clear(); self.link=itemLink; self.tooltipData={id=tonumber(itemLink:match("item:(%d+)"))}
        self:Fire("OnTooltipSetItem")
    end
    function frame:GetTooltipData() return self.tooltipData end
    function frame:SetBagItem(bag,slot) self:SetHyperlink(C_Container.GetContainerItemLink(bag,slot)) end
    function frame:SetInventoryItem(unit,slot)
        self.equipped=true; self:SetHyperlink(GetInventoryItemLink(unit,slot))
    end
    return frame
end
hooksecurefunc=function(target,method,callback)
    local original=target[method]
    target[method]=function(...)
        local result={original(...)}
        callback(...)
        return (unpack or table.unpack)(result)
    end
end
GameTooltip=tooltip("GameTooltip","item:100")
ItemRefTooltip=tooltip("ItemRefTooltip","item:101")
ShoppingTooltip1=tooltip("ShoppingTooltip1","item:102")
ShoppingTooltip2=tooltip("ShoppingTooltip2","item:103")
FW.ScanTooltip=tooltip("ZwykValuesScanTooltip","item:104")
local postCall
TooltipDataProcessor={AddTooltipPostCall=function(kind, fn)
    assert(kind==1); calls.post=calls.post+1; postCall=fn
end}
Enum={TooltipDataType={Item=1}}
assert(loadfile("Tooltips.lua"))("ZwykValues",FW)
FW:InstallTooltipHooks()
assert(calls.post==1)
assert(GameTooltip.fwHooked and not FW.ScanTooltip.fwHooked)

-- Legacy and modern callbacks can both fire, but never duplicate a section.
GameTooltip:Fire("OnTooltipSetItem")
local count=#GameTooltip.lines
assert(count==6 and calls.compare==2)
postCall(GameTooltip,{hyperlink="item:100"})
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==count and calls.compare==2)
assert(GameTooltip.lines[3].text=="Melee" and GameTooltip.lines[3].right=="100.00")
assert(GameTooltip.lines[3].r==.8 and GameTooltip.lines[3].rr==.8)
assert(GameTooltip.lines[4].text:find("+10.00 (+11.1%) upgrade",1,true))
assert(GameTooltip.lines[5].b==.9 and GameTooltip.lines[5].bb==.9)

-- Clearing native content must clear both the guard and the watched link.
GameTooltip:Clear()
assert(GameTooltip.fwSignature==nil)
GameTooltip.link="item:105"
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==count and calls.compare==4)
GameTooltip:Clear()
GameTooltip.equipped=true
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==4 and calls.compare==4 and calls.score==2)
ShoppingTooltip1:Fire("OnTooltipSetItem")
assert(#ShoppingTooltip1.lines==4 and calls.compare==4 and calls.score==4)
GameTooltip:Clear(); GameTooltip.equipped=false
FW.DB.options={showComparisons=false}
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==4 and calls.compare==4 and calls.score==6)
FW.DB.options.showComparisons=true
GameTooltip:Clear(); GameTooltip.equipped=true
GameTooltip:Fire("OnTooltipSetItem")

-- Scanner and forbidden tooltips must never receive our decoration.
FW:DecorateTooltip(FW.ScanTooltip)
local protected=tooltip("Protected","item:109"); protected.forbidden=true
FW:DecorateTooltip(protected)
assert(#FW.ScanTooltip.lines==0 and #protected.lines==0)

-- Modern data fallback handles clients where GetItem returns no link yet.
local fallback=tooltip("CustomItemTooltip",nil)
postCall(fallback,{hyperlink="item:110"})
assert(#fallback.lines==count and fallback.fwHooked)

-- Refresh reconstructs the tooltip's existing source, retaining equip context.
local refreshed=0
function GameTooltip:RefreshData()
    refreshed=refreshed+1
    self:Clear()
    postCall(self,{hyperlink=self.link})
end
FW.equipmentRevision=1
FW:RefreshTooltips()
assert(refreshed==1 and GameTooltip.shown and #GameTooltip.lines==4)
assert(not ShoppingTooltip1.shown and not fallback.shown)
local oldScore=calls.score
GameTooltip:Fire("OnTooltipSetItem")
assert(calls.score==oldScore)
profiles={}
FW:RefreshTooltips()
assert(#GameTooltip.lines==0 and GameTooltip.fwSignature==nil)
assert(FW:GetHoveredItemLink()=="item:105")
GameTooltip:Hide(); ItemRefTooltip:Hide()
assert(FW:GetHoveredItemLink()==nil)

-- Missing GetItem plus id-only data must retain a variant's exact source link.
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}}}
local modern=tooltip("ModernNoGetItem",nil); modern.GetItem=nil
FW.HookTooltip(modern)
local variant="item:501:1234:0:0:0:0:-7:111:60"
modern:SetHyperlink(variant)
assert(modern.fwSourceLink==variant and #modern.lines==4)
postCall(modern,{id=501})
assert(#modern.lines==4)
GameTooltip=modern
assert(FW:GetHoveredItemLink()==variant)
modern:Hide(); assert(modern.fwSourceLink==nil)
modern.shown=true
C_Container={GetContainerItemLink=function(bag,slot)
    assert(bag==2 and slot==4); return variant
end}
modern:SetBagItem(2,4)
assert(modern.fwSourceLink==variant and FW:GetHoveredItemLink()==variant)
GetInventoryItemLink=function(unit,slot) assert(unit=="player" and slot==16); return variant end
modern:SetInventoryItem("player",16)
assert(modern.fwSourceLink==variant and #modern.lines==3)

-- Inline diagnostics are opt-in, idempotent, and independent of active profiles.
FW.DB.options.debugUnknownStats=false
record.unrecognizedLines={{text="Equip: Grants +17 Mystery."}}
local debugTip=tooltip("DebugTooltip","item:600")
debugTip:AddLine("Mystery armor")
debugTip:AddLine("Equip: Grants +17 Mystery.")
FW:MarkUnknownStats(debugTip,record)
assert(not debugTip.lines[2].text:find("[ZV ?]",1,true))
FW.DB.options.debugUnknownStats=true
FW:MarkUnknownStats(debugTip,record)
local marked=debugTip.lines[2].text
FW:MarkUnknownStats(debugTip,record)
assert(marked:find("[ZV ?]",1,true) and debugTip.lines[2].text==marked)
local french=tooltip("FrenchDebugTooltip","item:601")
french:AddLine("Armure mystère")
french:AddLine("Équipé\194\160: Bonus mystère de 17.")
FW:MarkUnknownStats(french,{unrecognizedLines={{text="Équipé : Bonus mystère de 17."}}})
assert(french.lines[2].text:find("[ZV ?]",1,true))
profiles={}
debugTip:Clear(); debugTip:AddLine("Mystery armor"); debugTip:AddLine("Equip: Grants +17 Mystery.")
postCall(debugTip,{hyperlink="item:600"})
assert(#debugTip.lines==2 and debugTip.lines[2].text:find("[ZV ?]",1,true))
postCall(debugTip,{hyperlink="item:600"})
assert(debugTip.lines[2].text==marked)

-- A transient reader exception cannot disable decoration globally thereafter.
FW.DB.options.debugUnknownStats=false
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}}}
local oldCompare=FW.CompareItem
FW.CompareItem=function() error("temporary reader failure") end
local failed=tooltip("FailedTooltip","item:700")
postCall(failed,{hyperlink="item:700"})
assert(failed.fwSignature==nil and calls.error:find("temporary reader failure",1,true))
FW.CompareItem=oldCompare
local recovered=tooltip("RecoveredTooltip","item:701")
postCall(recovered,{hyperlink="item:701"})
assert(#recovered.lines==4 and recovered.fwSignature)
print("Tooltip tests passed")
