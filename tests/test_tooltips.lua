local FW = { DB = {}, equipmentRevision = 0 }
-- The markup must resolve to actual client-readable textures in the package.
-- Test dimensions, alpha and colors so a missing/broken asset cannot silently
-- turn the comparison indicator back into a box.
for _, asset in ipairs({{"ArrowUp",64,255,89}, {"ArrowDown",255,89,89}}) do
    local file = assert(io.open("Textures/" .. asset[1] .. ".tga", "rb"))
    local bytes = file:read("*a"); file:close()
    assert(#bytes == 18 + 16 * 16 * 4 and bytes:byte(3) == 2)
    assert(bytes:byte(13) == 16 and bytes:byte(14) == 0)
    assert(bytes:byte(15) == 16 and bytes:byte(16) == 0)
    assert(bytes:byte(17) == 32 and bytes:byte(18) == 40)
    local visible, transparent = 0, 0
    for offset = 19, #bytes, 4 do
        local b,g,r,a = bytes:byte(offset,offset+3)
        if a == 255 then
            visible = visible + 1
            assert(r == asset[2] and g == asset[3] and b == asset[4])
        else assert(a == 0); transparent = transparent + 1 end
    end
    assert(visible > 0 and transparent > 0)
end
local profiles = {
    {id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}},
    {id="two",name="Caster",revision=1,color={r=.1,g=.3,b=.9}},
}
local calls = {score=0,compare=0,post=0}
local record = {stats={},equipLoc="INVTYPE_HEAD"}
function FW:GetProfiles() return profiles end
function FW:GetScore(link) calls.score=calls.score+1; calls.scoreLink=link; return 100,record end
function FW:GetItem() return record end
function FW:ItemHasIssues(item, profile)
    return item and (item.partial or #(item.unrecognizedLines or {}) > 0 or
        (profile and item.scoreIssues and item.scoreIssues[profile.id]))
end
function FW:Print(message) calls.error=message end
function FW:CompareItem()
    calls.compare=calls.compare+1
    return {score=100,record=record,comparisons={
        {label="Head",delta=10,percent=11.111,status="upgrade",baseline=90},
    }}
end

local function tooltip(name, link)
    local frame = {name=name,link=link,lines={},scripts={},shown=true,fontStrings={}}
    local function registerLines(self,index)
        for _, side in ipairs({"Left", "Right"}) do
            local key = side .. index
            local field = side == "Left" and "text" or "right"
            if not self.fontStrings[key] then
                self.fontStrings[key]={
                    path="Tooltip.ttf",size=12,flags="OUTLINE",
                    GetText=function() return self.lines[index] and self.lines[index][field] end,
                    SetText=function(_,text) self.lines[index][field]=text end,
                    GetFont=function(font) return font.path,font.size,font.flags end,
                    SetFont=function(font,path,size,flags) font.path=path; font.size=size; font.flags=flags end,
                }
            end
            if self.name then _G[self.name .. "Text" .. key]=self.fontStrings[key] end
        end
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
    function frame:GetLeftLine(index) return self.fontStrings["Left" .. index] end
    function frame:GetRightLine(index) return self.fontStrings["Right" .. index] end
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
TooltipComparisonManager={SetItemTooltip=function(self,primary)
    local frame=self.tooltip.shoppingTooltips[primary and 1 or 2]
    frame:Clear(); frame.link=nil; frame.tooltipData={id=501}
    frame:AddLine("Equipped")
    if postCall then postCall(frame,frame.tooltipData) end
end}
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
assert(count==3 and calls.compare==2)
postCall(GameTooltip,{hyperlink="item:100"})
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==count and calls.compare==2)
assert(GameTooltip.lines[2].text=="Melee" and GameTooltip.lines[2].right=="100.00  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+10.00 (+11.1%)|r")
assert(GameTooltip.lines[2].r==.8 and GameTooltip.lines[2].rr==.8)
assert(GameTooltip.lines[3].b==.9 and GameTooltip.lines[3].bb==.9)
for _,line in ipairs(GameTooltip.lines) do assert(line.text~="ZwykValues") end

-- Clearing native content must clear both the guard and the watched link.
GameTooltip:Clear()
assert(GameTooltip.fwSignature==nil)
GameTooltip.link="item:105"
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==count and calls.compare==4)
GameTooltip:Clear()
GameTooltip.equipped=true
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==3 and calls.compare==4 and calls.score==2)
ShoppingTooltip1:Fire("OnTooltipSetItem")
assert(#ShoppingTooltip1.lines==3 and calls.compare==4 and calls.score==4)
assert(ShoppingTooltip1.lines[2].text=="Melee" and ShoppingTooltip1.lines[2].right=="100.00")
GameTooltip:Clear(); GameTooltip.equipped=false
FW.DB.options={showComparisons=false}
GameTooltip:Fire("OnTooltipSetItem")
assert(#GameTooltip.lines==3 and calls.compare==4 and calls.score==6)
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
assert(refreshed==1 and GameTooltip.shown and #GameTooltip.lines==3)
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
assert(modern.fwSourceLink==variant and #modern.lines==2)
postCall(modern,{id=501})
assert(#modern.lines==2)
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
assert(modern.fwSourceLink==variant and #modern.lines==2)

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
assert(#debugTip.lines==3 and debugTip.lines[2].text:find("[ZV ?]",1,true))
assert(debugTip.lines[3].text=="Partial stat data; /zv inspect or /zv exportissues.")
postCall(debugTip,{hyperlink="item:600"})
assert(debugTip.lines[2].text==marked)

-- A transient reader exception cannot disable decoration globally thereafter.
FW.DB.options.debugUnknownStats=false
record.unrecognizedLines={}
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}}}
local oldCompare=FW.CompareItem
FW.CompareItem=function() error("temporary reader failure") end
local failed=tooltip("FailedTooltip","item:700")
postCall(failed,{hyperlink="item:700"})
assert(failed.fwSignature==nil and calls.error:find("temporary reader failure",1,true))
FW.CompareItem=oldCompare
local recovered=tooltip("RecoveredTooltip","item:701")
postCall(recovered,{hyperlink="item:701"})
assert(#recovered.lines==2 and recovered.fwSignature)

-- Two replacements stay on one row; only comparison fragments get status colors.
FW.CompareItem=function()
    return {score=2.56,record=record,comparisons={
        {label="Ring 1",delta=1.52,percent=146.1538,status="upgrade",baseline=1.04},
        {label="Ring 2",delta=0,percent=0,status="equal",baseline=2.56},
    }}
end
local rings=tooltip("RingsTooltip","item:710")
postCall(rings,{hyperlink="item:710"})
assert(#rings.lines==2 and rings.lines[2].right==
    "2.56  |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+1.52 (+146.2%)|r | |cffb2b2b2=0.00 (+0.0%)|r")
assert(rings.lines[2].r==.8 and rings.lines[2].rr==.8)
FW.CompareItem=function()
    return {score=90,record=record,comparisons={
        {delta=-10,percent=-10,status="downgrade",baseline=100},
        {delta=90,status="upgrade",baseline=0},
        {delta=0,status="equal",baseline=0},
    }}
end
local lower=tooltip("LowerTooltip","item:711")
postCall(lower,{hyperlink="item:711"})
assert(lower.lines[2].right==
    "90.00  |cffff5959|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:12:12:0:0|t-10.00 (-10.0%)|r | |cff40ff59|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowUp:12:12:0:0|t+90.00 (n/a)|r | |cffb2b2b2=0.00 (+0.0%)|r")

-- Partial extraction and profile-only unit issues keep every score and add one
-- warning, even with debug markers off and more than one active profile.
FW.CompareItem=oldCompare
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}},
    {id="two",name="Caster",revision=1,color={r=.1,g=.3,b=.9}}}
record.partial=true
local partial=tooltip("PartialTooltip","item:720")
postCall(partial,{hyperlink="item:720"})
assert(#partial.lines==4 and partial.lines[2].right:find("100.00",1,true))
assert(partial.lines[4].text=="Partial stat data; /zv inspect or /zv exportissues.")
postCall(partial,{hyperlink="item:720"}); assert(#partial.lines==4)
record.partial=false; record.scoreIssues={one={missingStats={crit=true}}}
local units=tooltip("UnitsTooltip","item:721")
postCall(units,{hyperlink="item:721"})
assert(#units.lines==4 and units.lines[2].right:find("100.00",1,true))
record.scoreIssues=nil
FW.CompareItem=function()
    return {score=100,record=record,comparisons={
        {delta=10,percent=11.111,status="upgrade",baseline=90,hasIssues=true},
    }}
end
local baselineIssues=tooltip("BaselineIssuesTooltip","item:722")
postCall(baselineIssues,{hyperlink="item:722"})
assert(#baselineIssues.lines==4 and baselineIssues.lines[4].text:find("exportissues",1,true))
FW.CompareItem=oldCompare

-- Modern equipped comparison data resolves GUIDs to the exact enchanted /
-- random-suffix item link. Neither this path nor the helper fabricates an ID link.
C_Item={GetItemLinkByGUID=function(guid)
    assert(guid=="Item-0-1-501"); return variant
end}
local guidTip=tooltip("ShoppingTooltipGUID",nil); guidTip.GetItem=nil
postCall(guidTip,{id=501,guid="Item-0-1-501"})
assert(#guidTip.lines==3 and calls.scoreLink==variant)
assert(guidTip.lines[2].right=="100.00")
local emptyTip=tooltip("ShoppingTooltipEmptyLink",nil)
function emptyTip:GetItem() return "Variant","" end
postCall(emptyTip,{id=501,guid="Item-0-1-501"})
assert(#emptyTip.lines==3 and emptyTip.lines[2].right=="100.00" and calls.scoreLink==variant)
emptyTip:Clear()
postCall(emptyTip,{id=501,hyperlink="",itemLink=variant})
assert(#emptyTip.lines==3 and calls.scoreLink==variant)
local primaryTip=tooltip("ShoppingTooltipPrimaryGUID",nil); primaryTip.GetItem=nil
function primaryTip:GetPrimaryTooltipData() return {id=501,guid="Item-0-1-501"} end
postCall(primaryTip,{id=501})
assert(#primaryTip.lines==3 and calls.scoreLink==variant)
TooltipUtil={GetDisplayedItem=function() return "Variant",variant end}
local helperTip=tooltip("ShoppingTooltipHelper",nil); helperTip.GetItem=nil
postCall(helperTip,{id=501})
assert(#helperTip.lines==3 and calls.scoreLink==variant)
TooltipUtil=nil

-- The native manager can supply an exact source even if the displayed tooltip
-- exposes only an ID. Its finalize hook decorates with no item scripts/postcall.
local native1=tooltip("ShoppingTooltipNative1",nil); native1.GetItem=nil
local native2=tooltip("ShoppingTooltipNative2",nil); native2.GetItem=nil
TooltipComparisonManager.tooltip={shoppingTooltips={native1,native2}}
TooltipComparisonManager.compareInfo={item={guid="Item-0-1-501"},additionalItems={{hyperlink=variant}}}
TooltipComparisonManager.comparisonIndex=1
local savedPost=postCall; postCall=nil
TooltipComparisonManager:SetItemTooltip(true)
TooltipComparisonManager:SetItemTooltip(false)
assert(#native1.lines==4 and native1.lines[3].right=="100.00" and calls.scoreLink==variant)
assert(#native2.lines==4 and native2.lines[3].right=="100.00")
postCall=savedPost

-- Older Shopping frames can be populated by SetCompareItem without item events.
local legacy=tooltip("ShoppingTooltipLegacy",nil)
function legacy:SetCompareItem() self:Clear(); self.link=variant; self:AddLine("Equipped") end
FW.HookTooltip(legacy); legacy:SetCompareItem()
assert(#legacy.lines==4 and legacy.lines[3].right=="100.00" and calls.scoreLink==variant)

-- Each profile has a smaller base subline. It uses its own score/comparisons,
-- while native shopping/equipped tooltips and disabled comparisons show scores.
local baseCalls={score=0,compare=0}
function FW:GetBaseScore(link,profile)
    baseCalls.score=baseCalls.score+1; baseCalls.link=link
    return profile.id=="one" and 80 or 70,record
end
function FW:CompareBaseItem(link,profile)
    baseCalls.compare=baseCalls.compare+1; baseCalls.link=link
    return {score=profile.id=="one" and 80 or 70,record=record,comparisons={
        {delta=-5,percent=-5.882,status="downgrade",baseline=85},
        {delta=0,percent=0,status="equal",baseline=80},
    }}
end
local baseTip=tooltip("BaseTooltip",variant)
postCall(baseTip,{hyperlink=variant})
assert(#baseTip.lines==5 and baseCalls.compare==2 and baseCalls.link==variant)
assert(baseTip.lines[2].text=="Melee" and baseTip.lines[4].text=="Caster")
assert(baseTip.lines[3].text=="  Base" and baseTip.lines[5].text=="  Base")
assert(baseTip.lines[3].right==
    "80.00  |cffff5959|TInterface\\AddOns\\ZwykValues\\Textures\\ArrowDown:10:10:0:0|t-5.00 (-5.9%)|r | |cffb2b2b2=0.00 (+0.0%)|r")
assert(baseTip.lines[5].right:find("70.00",1,true) and baseTip.lines[5].b==.9)
assert(BaseTooltipTextLeft2.size==12 and BaseTooltipTextRight2.size==12)
assert(math.abs(BaseTooltipTextLeft3.size-10.2)<1e-9 and BaseTooltipTextRight3.flags=="OUTLINE")
postCall(baseTip,{hyperlink=variant})
assert(#baseTip.lines==5 and baseCalls.compare==2)
baseTip:Clear()
assert(BaseTooltipTextLeft3.size==12 and BaseTooltipTextRight3.size==12 and baseTip.fwBaseFonts==nil)
postCall(baseTip,{hyperlink=variant})
assert(math.abs(BaseTooltipTextLeft3.size-10.2)<1e-9) -- no cumulative shrinking
baseTip:Hide()
assert(BaseTooltipTextLeft3.size==12 and BaseTooltipTextRight5.size==12)
local anonymousBase=tooltip(nil,variant)
postCall(anonymousBase,{hyperlink=variant})
assert(math.abs(anonymousBase:GetLeftLine(3).size-10.2)<1e-9)
assert(math.abs(anonymousBase:GetRightLine(3).size-10.2)<1e-9)
anonymousBase:Clear()
assert(anonymousBase:GetLeftLine(3).size==12 and anonymousBase:GetRightLine(3).size==12)
local legacyBase=tooltip("LegacyBase",variant)
legacyBase.GetLeftLine=nil; legacyBase.GetRightLine=nil
postCall(legacyBase,{hyperlink=variant})
assert(math.abs(LegacyBaseTextLeft3.size-10.2)<1e-9 and math.abs(LegacyBaseTextRight3.size-10.2)<1e-9)
legacyBase:Hide()
assert(LegacyBaseTextLeft3.size==12 and LegacyBaseTextRight3.size==12)
baseTip:Clear(); baseTip.equipped=true
postCall(baseTip,{hyperlink=variant})
assert(baseTip.lines[3].right=="80.00" and baseCalls.score==2)
local baseShopping=tooltip("ShoppingTooltipBase",variant)
postCall(baseShopping,{hyperlink=variant})
assert(baseShopping.lines[3].right=="80.00" and baseCalls.score==4)
FW.DB.options.showComparisons=false
local baseNoCompare=tooltip("BaseNoCompare",variant)
postCall(baseNoCompare,{hyperlink=variant})
assert(baseNoCompare.lines[3].right=="80.00" and baseCalls.score==6)
FW.DB.options.showComparisons=true

-- A pending base read retains the full score, and base/full issue warnings
-- deduplicate. Unknown enchant text on the full item can coexist with clean base.
FW.CompareBaseItem=function() return nil,"Item data loading" end
local baseLoading=tooltip("BaseLoading",variant)
postCall(baseLoading,{hyperlink=variant})
assert(baseLoading.lines[2].right:find("100.00",1,true))
assert(baseLoading.lines[3].text=="  Base: Item data loading" and math.abs(BaseLoadingTextLeft3.size-10.2)<1e-9)
FW.CompareBaseItem=function()
    return {score=80,record={stats={}},comparisons={}}
end
record.partial=true
local basePartial=tooltip("BasePartial",variant)
postCall(basePartial,{hyperlink=variant})
assert(#basePartial.lines==6 and basePartial.lines[3].right=="80.00")
assert(basePartial.lines[6].text:find("exportissues",1,true))
record.partial=false
print("Tooltip tests passed")
