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

local testTooltips = {}
local function tooltip(name, link)
    local frame = {name=name,link=link,lines={},scripts={},shown=true,fontStrings={}}
    testTooltips[#testTooltips+1] = frame
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

-- Base is useful only when its displayed values differ. Identical upgrade
-- comparisons use differently sized texture markup, but still express the
-- same score and comparison and must not produce a second row.
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}}}
local fullResult, baseResult, fullError, baseError
local fullScore, baseScore, fullScoreError, baseScoreError=100,100
local fullRecord, baseRecord={stats={}},{stats={}}
local relevantCalls={full=0,base=0}
FW.CompareItem=function()
    relevantCalls.full=relevantCalls.full+1
    return fullResult,fullError
end
FW.CompareBaseItem=function()
    relevantCalls.base=relevantCalls.base+1
    return baseResult,baseError
end
FW.GetScore=function() return fullScore,fullRecord,fullScoreError end
FW.GetBaseScore=function() return baseScore,baseRecord,baseScoreError end
local function compared(score,delta,percent)
    return {score=score,record={stats={}},comparisons={
        {delta=delta,percent=percent,status="upgrade",baseline=score-delta},
    }}
end
local function hasBase(tip)
    for _,line in ipairs(tip.lines) do
        if line.text=="  Base" or line.text:find("  Base:",1,true) then return true end
    end
    return false
end
local function decorateRelevant(name,equipped)
    local tip=tooltip(name,variant)
    tip.equipped=equipped
    postCall(tip,{hyperlink=variant})
    return tip
end
fullResult=compared(100,10,11.111)
baseResult=compared(100,10,11.111)
local equalBase=decorateRelevant("EqualBaseValues")
assert(#equalBase.lines==2 and not hasBase(equalBase), "equal full/base score and upgrade comparison must hide Base")
assert(equalBase.lines[2].right:find("ArrowUp:12:12",1,true), "the full comparison keeps its normal arrow size")
assert(EqualBaseValuesTextLeft2.size==12 and EqualBaseValuesTextRight2.size==12 and equalBase.fwBaseFonts==nil)

fullResult={score=100,record={stats={}},comparisons={}}
baseResult={score=80,record={stats={}},comparisons={}}
local scoreDifference=decorateRelevant("BaseScoreDifference")
assert(#scoreDifference.lines==3 and hasBase(scoreDifference) and scoreDifference.lines[3].right=="80.00", "a score-only difference keeps Base")

-- A candidate may have no scored enchant, while an equipped item's enchant
-- changes its replacement baseline. Base still conveys that comparison.
fullResult=compared(100,10,11.111)
baseResult=compared(100,20,25)
local baselineDifference=decorateRelevant("BaseBaselineDifference")
assert(#baselineDifference.lines==3 and hasBase(baselineDifference), "equal candidate scores with different equipped baselines keep Base")
assert(baselineDifference.lines[2].right:find("100.00",1,true) and baselineDifference.lines[3].right:find("100.00",1,true))
assert(baselineDifference.lines[3].right:find("+20.00 (+25.0%)",1,true))

fullResult={score=100,record={stats={}},comparisons={
    {delta=10,percent=11.111,status="upgrade",baseline=90},
    {delta=0,percent=0,status="equal",baseline=100},
}}
baseResult={score=100,record={stats={}},comparisons={
    {delta=10,percent=11.111,status="upgrade",baseline=90},
    {delta=20,percent=25,status="upgrade",baseline=80},
}}
local secondRingDifference=decorateRelevant("BaseSecondRingDifference")
assert(#secondRingDifference.lines==3 and hasBase(secondRingDifference), "the second ring's differing comparison keeps Base")
assert(secondRingDifference.lines[3].right:find(" | ",1,true) and secondRingDifference.lines[3].right:find("+20.00 (+25.0%)",1,true))

fullResult=compared(100.004,10.004,11.144)
baseResult=compared(100.001,10.001,11.141)
local roundedComparisons=decorateRelevant("RoundedBaseComparisons")
assert(#roundedComparisons.lines==2 and not hasBase(roundedComparisons), "values identical at tooltip precision hide Base")
assert(roundedComparisons.lines[2].right:find("100.00",1,true) and roundedComparisons.lines[2].right:find("+10.00 (+11.1%)",1,true))
FW.DB.options.showComparisons=false
fullScore,baseScore=100.004,100.001
local roundedScores=decorateRelevant("RoundedBaseScores")
assert(#roundedScores.lines==2 and not hasBase(roundedScores), "rounded-identical scores hide Base when comparisons are disabled")
fullScore,baseScore=100,100
local equalEquipped=decorateRelevant("EqualEquippedBase",true)
assert(#equalEquipped.lines==2 and not hasBase(equalEquipped), "equipped tooltips suppress an identical Base score")
baseScore=80
local differingEquipped=decorateRelevant("DifferingEquippedBase",true)
assert(#differingEquipped.lines==3 and differingEquipped.lines[3].right=="80.00", "equipped tooltips retain a differing Base score")
fullScore,baseScore=nil,nil
fullRecord,baseRecord="Item data loading","Item data loading"
local duplicateScoreLoading=decorateRelevant("DuplicateBaseScoreLoading")
assert(#duplicateScoreLoading.lines==2 and not hasBase(duplicateScoreLoading), "duplicate score-reader loading errors hide Base without comparisons")
baseRecord="Base item data loading"
local differingScoreLoading=decorateRelevant("DifferentBaseScoreLoading")
assert(#differingScoreLoading.lines==3 and differingScoreLoading.lines[3].text=="  Base: Base item data loading", "different score-reader errors retain Base without comparisons")
fullScoreError="excluded"
fullRecord={stats={}}
baseScore,baseRecord=80,{stats={}}
local excludedScoreBase=decorateRelevant("ExcludedBaseScore",true)
assert(#excludedScoreBase.lines==0 and not hasBase(excludedScoreBase), "excluded equipped items cannot expose a Base score")
fullScoreError=nil
fullScore,baseScore=100,100
fullRecord,baseRecord={stats={}},{stats={}}
FW.DB.options.showComparisons=true

fullResult,baseResult=nil,nil
fullError,baseError="Item data loading","Item data loading"
local duplicateLoading=decorateRelevant("DuplicateBaseLoading")
assert(#duplicateLoading.lines==2 and not hasBase(duplicateLoading), "duplicate loading errors do not add Base")
assert(duplicateLoading.lines[2].text=="Melee: Item data loading" and DuplicateBaseLoadingTextLeft2.size==12)
fullError,baseError="Cannot evaluate item","Cannot evaluate item"
local duplicateError=decorateRelevant("DuplicateBaseError")
assert(#duplicateError.lines==2 and not hasBase(duplicateError), "duplicate reader errors do not add Base")
baseError="Base item data loading"
local differingError=decorateRelevant("DifferentBaseError")
assert(#differingError.lines==3 and differingError.lines[3].text=="  Base: Base item data loading", "different full/base errors keep the Base error")
fullResult,fullError=compared(100,10,11.111),nil
baseError="Item data loading"
local unavailableBase=decorateRelevant("UnavailableRelevantBase")
assert(#unavailableBase.lines==3 and unavailableBase.lines[2].right:find("100.00",1,true), "pending Base data does not hide the full score")
assert(unavailableBase.lines[3].text=="  Base: Item data loading")
fullResult={score=100,record={stats={}},comparisons={{error="Equipped item data loading"}}}
baseResult={score=100,record={stats={}},comparisons={{error="Equipped item data loading"}}}
baseError=nil
local duplicateComparisonError=decorateRelevant("DuplicateBaseComparisonError")
assert(#duplicateComparisonError.lines==3 and not hasBase(duplicateComparisonError), "duplicate unavailable comparisons hide Base")
assert(duplicateComparisonError.lines[2].right:find("comparison unavailable",1,true) and duplicateComparisonError.lines[3].text=="  Equipped item data loading", "suppressed comparison errors still provide one diagnostic note")
baseResult,baseError=compared(100,10,11.111),nil
fullResult,fullError=nil,"Item data loading"
local unavailableFull=decorateRelevant("UnavailableRelevantFull")
assert(#unavailableFull.lines==3 and unavailableFull.lines[3].right:find("100.00",1,true), "available Base scores remain visible while full data is pending")

-- Hidden Base rows still contribute extraction and baseline warnings. Relevance
-- depends on visible values, not whether both readers report the same issues.
fullResult,fullError=compared(100,10,11.111),nil
baseResult=compared(100,10,11.111)
baseResult.record.partial=true
local hiddenBaseIssues=decorateRelevant("HiddenBaseIssues")
assert(#hiddenBaseIssues.lines==3 and not hasBase(hiddenBaseIssues), "hidden Base extraction issues do not force a duplicate value row")
assert(hiddenBaseIssues.lines[3].text=="Partial stat data; /zv inspect or /zv exportissues.", "hidden Base extraction issues propagate their warning")
baseResult.record.partial=false
baseResult.comparisons[1].hasIssues=true
local hiddenBaselineIssues=decorateRelevant("HiddenBaseBaselineIssues")
assert(#hiddenBaselineIssues.lines==3 and not hasBase(hiddenBaselineIssues), "hidden Base baseline issues do not force a duplicate row")
assert(hiddenBaselineIssues.lines[3].text:find("exportissues",1,true), "hidden Base baseline issues propagate their warning")

fullResult={excluded=true,record={stats={}},comparisons={}}
baseResult=compared(80,5,6.667)
local priorBaseCalls=relevantCalls.base
local excludedBase=decorateRelevant("ExcludedBaseProfile")
assert(#excludedBase.lines==0 and not hasBase(excludedBase), "excluded full items cannot expose Base")
assert(relevantCalls.base==priorBaseCalls, "excluded full items do not request a Base read")

-- A native refresh can reuse a FontString that previously held a shrunken Base
-- row. Suppressing that row must restore its original font for future content.
fullResult=compared(100,10,11.111)
baseResult=compared(80,5,6.667)
local relevanceRefresh=decorateRelevant("RelevantBaseRefresh")
assert(#relevanceRefresh.lines==3 and math.abs(RelevantBaseRefreshTextLeft3.size-10.2)<1e-9)
function relevanceRefresh:RefreshData()
    self:Clear()
    postCall(self,{hyperlink=self.link})
end
baseResult=compared(100,10,11.111)
FW.equipmentRevision=FW.equipmentRevision+1
FW:RefreshTooltips()
assert(#relevanceRefresh.lines==2 and not hasBase(relevanceRefresh), "native refresh removes a newly redundant Base row")
assert(RelevantBaseRefreshTextLeft3.size==12 and RelevantBaseRefreshTextRight3.size==12 and relevanceRefresh.fwBaseFonts==nil, "removed Base rows restore reused FontStrings")
relevanceRefresh:Clear()
relevanceRefresh:AddLine("Native row one")
relevanceRefresh:AddLine("Native row two")
relevanceRefresh:AddLine("Native row three")
assert(RelevantBaseRefreshTextLeft3.size==12 and RelevantBaseRefreshTextRight3.size==12, "native rows inherit normal fonts after Base disappears")
relevanceRefresh:Clear()
baseResult=compared(80,5,6.667)
postCall(relevanceRefresh,{hyperlink=variant})
assert(#relevanceRefresh.lines==3 and math.abs(RelevantBaseRefreshTextLeft3.size-10.2)<1e-9, "reappearing Base rows shrink once without accumulating")
relevanceRefresh:Hide()
assert(RelevantBaseRefreshTextLeft3.size==12 and RelevantBaseRefreshTextRight3.size==12)

-- Recipe and spell tooltips can use the same native frame and callbacks as
-- equipment. Their hyperlink payload must never enter the item-score pipeline.
for _, tip in ipairs(testTooltips) do tip:Hide() end
local ignoredCalls = {item=0,score=0,compare=0,baseScore=0,baseCompare=0}
local ignoredRefreshes = 0
local issueRecord = {stats={},partial=true,unrecognizedLines={{text="Recipe description"}}}
function FW:GetItem() ignoredCalls.item=ignoredCalls.item+1; return issueRecord end
function FW:GetScore() ignoredCalls.score=ignoredCalls.score+1; return 100,issueRecord end
function FW:GetBaseScore() ignoredCalls.baseScore=ignoredCalls.baseScore+1; return 80,issueRecord end
function FW:CompareItem()
    ignoredCalls.compare=ignoredCalls.compare+1
    return {score=100,record=issueRecord,comparisons={}}
end
function FW:CompareBaseItem()
    ignoredCalls.baseCompare=ignoredCalls.baseCompare+1
    return {score=80,record=issueRecord,comparisons={}}
end
FW.DB.options.debugUnknownStats=true
FW.DB.options.showComparisons=true
local function assertIgnored(tip, context)
    assert(#tip.lines==1 and tip.lines[1].text=="Native recipe description", context .. " keeps native rows without scores or warnings")
    assert(tip.fwSignature==nil and tip.fwSourceLink==nil, context .. " retains no item signature or source")
    for key,value in pairs(ignoredCalls) do assert(value==0, context .. " does not call " .. key) end
    tip.RefreshData=function() ignoredRefreshes=ignoredRefreshes+1 end
end
local rejectedTips = {}
for _, payload in ipairs({"enchant:7418", "spell:7418", "recipe:7418", "trade:Player-1-ABCD:7418"}) do
    for _, link in ipairs({payload, "|cffffd000|H" .. payload .. "|h[Recipe item:501]|h|r"}) do
        local index = #rejectedTips+1
        local fromItem=tooltip("NonItemGetItem" .. index,link)
        fromItem:AddLine("Native recipe description")
        FW.HookTooltip(fromItem)
        fromItem:Fire("OnTooltipSetItem")
        assertIgnored(fromItem,"GetItem " .. link)
        rejectedTips[#rejectedTips+1]=fromItem

        local fromHyperlink=tooltip("NonItemHyperlink" .. index,nil)
        FW.HookTooltip(fromHyperlink)
        fromHyperlink:SetHyperlink(link)
        fromHyperlink:AddLine("Native recipe description")
        assertIgnored(fromHyperlink,"SetHyperlink " .. link)
        rejectedTips[#rejectedTips+1]=fromHyperlink

        for _, field in ipairs({"hyperlink", "itemLink"}) do
            local fromPost=tooltip("NonItemPost" .. index .. field,nil)
            fromPost.GetItem=nil
            fromPost:AddLine("Native recipe description")
            postCall(fromPost,{[field]=link,id=7418})
            assertIgnored(fromPost,"Modern " .. field .. " " .. link)
            rejectedTips[#rejectedTips+1]=fromPost
        end
    end
end
FW:RefreshTooltips()
assert(ignoredRefreshes==0, "non-item tooltips are not watched for equipment refreshes")
for _, tip in ipairs(rejectedTips) do
    assert(tip:IsShown(), "refreshing items does not hide an unrelated recipe tooltip")
    assertIgnored(tip,"Refreshed non-item tooltip")
end
GameTooltip=rejectedTips[#rejectedTips]
assert(FW:GetHoveredItemLink()==nil, "a recipe hover cannot be inspected as an item")

-- Keep actual item variants working through each supported source, including
-- modern frames that only expose the exact variant through SetHyperlink.
FW.DB.options.debugUnknownStats=false
issueRecord={stats={}}
local validRaw=tooltip("ValidItemPayload","item:501:1234:0:0:0:0:-7:111:60")
FW.HookTooltip(validRaw)
validRaw:Fire("OnTooltipSetItem")
assert(#validRaw.lines==3 and validRaw.fwSignature, "a raw item payload still receives full and Base rows")
local validWrappedLink="|cff0070dd|Hitem:501:1234:0:0:0:0:-7:111:60|h[Equipment]|h|r"
local validWrapped=tooltip("ValidWrappedItem",nil)
validWrapped.GetItem=nil
FW.HookTooltip(validWrapped)
validWrapped:SetHyperlink(validWrappedLink)
assert(#validWrapped.lines==3 and validWrapped.fwSourceLink==validWrappedLink, "a wrapped item variant remains available to modern hooks")
local validModern=tooltip("ValidModernItem",nil)
validModern.GetItem=nil
postCall(validModern,{hyperlink=variant,id=501})
assert(#validModern.lines==3 and validModern.fwSignature, "modern item post data still receives scores")
assert(ignoredCalls.compare==3 and ignoredCalls.baseCompare==3 and ignoredCalls.item==0, "legitimate items reach comparison and Base readers once")

-- Switching this frame to a recipe must discard the item source rather than
-- reusing its previous exact variant when modern data is only an ID.
validWrapped:SetHyperlink("enchant:7418")
assert(#validWrapped.lines==0 and validWrapped.fwSignature==nil and validWrapped.fwSourceLink==nil, "an item-to-enchant transition clears saved item decoration")
validWrapped:AddLine("Native recipe description")
postCall(validWrapped,{id=7418})
assert(#validWrapped.lines==1 and validWrapped.fwSignature==nil and validWrapped.fwSourceLink==nil, "an ID-only recipe post call cannot reuse the previous item source")
assert(ignoredCalls.compare==3 and ignoredCalls.baseCompare==3, "recipe transitions do not score the previous item or their own payload")
validWrapped.RefreshData=function() ignoredRefreshes=ignoredRefreshes+1 end
validRaw:Hide(); validModern:Hide()
FW:RefreshTooltips()
assert(ignoredRefreshes==0 and validWrapped:IsShown(), "a transitioned recipe is removed from item refresh watching")
GameTooltip=validWrapped
assert(FW:GetHoveredItemLink()==nil, "a reused tooltip no longer exposes the old item as hovered")

-- Average Use starts from the unenchanted Base score. Display relevance uses
-- Base, even when Base's own row was suppressed against the regular score.
for _, tip in ipairs(testTooltips) do tip:Hide() end
profiles={{id="one",name="Melee",revision=1,color={r=.8,g=.2,b=.1}}}
FW.DB.options.debugUnknownStats=false
FW.DB.options.showComparisons=true
local averageFull, averageBase, averageValue
local averageError, averageMetadata
local averageCalls={compare=0,score=0}
FW.CompareItem=function() return averageFull end
FW.CompareBaseItem=function() return averageBase end
FW.GetScore=function() return averageFull.score,averageFull.record end
FW.GetBaseScore=function() return averageBase.score,averageBase.record end
FW.CompareAverageUseItem=function(_,link)
    averageCalls.compare=averageCalls.compare+1; averageCalls.link=link
    return averageValue,averageError
end
FW.GetAverageUseScore=function(_,link,_,ignoreFilters)
    averageCalls.score=averageCalls.score+1; averageCalls.link=link; averageCalls.ignoreFilters=ignoreFilters
    return averageValue and averageValue.score,averageValue and averageValue.record or averageError,nil,averageMetadata
end
local function hasAverage(tip)
    for _, line in ipairs(tip.lines) do
        if line.text=="  Average use" or line.text=="  Average use: unavailable" then return line end
    end
end
local function noteCount(tip,text)
    local count=0
    for _,line in ipairs(tip.lines) do if line.text=="  " .. text then count=count+1 end end
    return count
end
local assumption="Average use assumes use on cooldown."
local function decorateAverage(name,equipped)
    local tip=tooltip(name,variant); tip.equipped=equipped
    postCall(tip,{hyperlink=variant})
    return tip
end
averageFull=compared(100,10,11.111)
averageBase=compared(80,5,6.667)
averageValue=compared(80,5,6.667)
averageValue.hasAverageUse=false
local noAverage=decorateAverage("NoAverageUse")
assert(#noAverage.lines==3 and not hasAverage(noAverage) and noteCount(noAverage,assumption)==0, "no Use effect keeps regular and Base rows without a redundant average")
averageValue.hasAverageUse=true; averageValue.averageUseGain=0
local zeroWeightedAverage=decorateAverage("ZeroWeightedAverageUse")
assert(not hasAverage(zeroWeightedAverage) and noteCount(zeroWeightedAverage,assumption)==0, "a parsed zero-weight Use effect does not add duplicate values or an assumption")
averageValue=compared(100,10,11.111)
averageValue.hasAverageUse=true; averageValue.averageUseGain=20
local equalFullAverage=decorateAverage("AverageEqualsFull")
assert(#equalFullAverage.lines==5 and equalFullAverage.lines[4].text=="  Average use" and noteCount(equalFullAverage,assumption)==1, "Average equals Full still appears when its Base values differ")
assert(equalFullAverage.lines[2].text=="Melee" and equalFullAverage.lines[3].text=="  Base", "Full, Base and Average use retain their row order")
assert(equalFullAverage.lines[4].right:find("100.00",1,true) and equalFullAverage.lines[4].right:find(":10:10:",1,true), "Average comparisons use the smaller arrow texture")
assert(math.abs(AverageEqualsFullTextLeft4.size-10.2)<1e-9 and math.abs(AverageEqualsFullTextRight4.size-10.2)<1e-9, "Average use has the same smaller font as Base")
assert(AverageEqualsFullTextLeft2.size==12 and AverageEqualsFullTextLeft5.size==12, "regular scores and the assumption note retain native font size")

averageValue=compared(85,6,7.5)
averageValue.hasAverageUse=true; averageValue.averageUseGain=5
local unenchantedAverage=decorateAverage("UnenchantedAverage")
assert(unenchantedAverage.lines[4].right:find("85.00",1,true) and not unenchantedAverage.lines[4].right:find("105.00",1,true), "Average uses the Base-derived API score rather than adding Use gain to the enchanted score")
assert(averageCalls.link==variant, "Average readers receive the exact item variant for unenchanted extraction")
local averageLineCount=#unenchantedAverage.lines
local averageCompareCount=averageCalls.compare
postCall(unenchantedAverage,{hyperlink=variant})
unenchantedAverage:Fire("OnTooltipSetItem")
assert(#unenchantedAverage.lines==averageLineCount and averageCalls.compare==averageCompareCount, "modern and legacy callbacks do not duplicate Average rows or reads")

averageFull=compared(80,5,6.667)
averageBase=compared(80,5,6.667)
averageValue=compared(80,8,10)
averageValue.hasAverageUse=false; averageValue.averageUseGain=0
local baselineAverage=decorateAverage("BaselineOnlyAverage")
assert(#baselineAverage.lines==4 and not hasBase(baselineAverage) and hasAverage(baselineAverage), "equipped Use effects can change comparison relevance without a candidate Use effect")
assert(baselineAverage.lines[3].right:find("80.00",1,true) and baselineAverage.lines[3].right:find("+8.00 (+10.0%)",1,true), "an equal candidate score retains the differing averaged baseline delta")
averageBase={score=80,record={stats={}},comparisons={
    {delta=5,percent=6.667,status="upgrade"}, {delta=0,percent=0,status="equal"},
}}
averageValue={score=80,record={stats={}},hasAverageUse=false,averageUseGain=0,comparisons={
    {delta=5,percent=6.667,status="upgrade"}, {delta=-10,percent=-11.111,status="downgrade"},
}}
local secondAverage=decorateAverage("SecondSlotAverage")
assert(hasAverage(secondAverage).right:find(" | ",1,true) and hasAverage(secondAverage).right:find("-10.00 (-11.1%)",1,true), "the second replacement comparison can make Average use relevant")

averageFull=compared(100,10,11.111)
averageBase=compared(80.001,5.001,6.641)
averageValue=compared(80.004,5.004,6.644)
averageValue.hasAverageUse=true; averageValue.averageUseGain=.003
local roundedAverage=decorateAverage("RoundedAverageUse")
assert(not hasAverage(roundedAverage) and noteCount(roundedAverage,assumption)==0, "identical formatted score and comparisons hide Average use despite different raw values and arrow sizes")
averageBase=compared(80,5,6.667)
averageValue=compared(79,5,6.667)
averageValue.hasAverageUse=true; averageValue.averageUseGain=-1
local negativeAverage=decorateAverage("NegativeAverageUse")
assert(hasAverage(negativeAverage).right:find("79.00",1,true), "a negative weighted Use gain still retains a differing average")

-- Incomplete candidates and baselines are never shown as a confident numeric
-- average, even when the API returns a recognized subtotal alongside warnings.
averageValue={score=85,record={stats={}},comparisons={{baseline=80}}}
averageValue.hasAverageUse=true; averageValue.averageUseIncomplete=true
averageValue.averageUseWarnings={"Unsupported Use effect."}
local incompleteAverage=decorateAverage("IncompleteAverageUse")
assert(hasAverage(incompleteAverage).text=="  Average use: unavailable" and hasAverage(incompleteAverage).right==nil, "unsupported Use effects replace the numeric row with unavailable")
assert(incompleteAverage.lines[2].right:find("100.00",1,true) and incompleteAverage.lines[3].right:find("80.00",1,true), "an incomplete average preserves regular and Base scores")
assert(noteCount(incompleteAverage,"Unsupported Use effect.")==1 and noteCount(incompleteAverage,assumption)==0, "an incomplete estimate gives its warning without a numeric assumption")
assert(math.abs(IncompleteAverageUseTextLeft4.size-10.2)<1e-9, "the unavailable row also uses the smaller font")
averageValue={score=80,record={stats={}},hasAverageUse=true,averageUseIncomplete=true,
    averageUseWarnings={"Equipped Use effect unavailable."},comparisons={{error="Equipped Use effect unavailable."}}}
local incompleteBaseline=decorateAverage("IncompleteAverageBaseline")
assert(hasAverage(incompleteBaseline).right==nil and noteCount(incompleteBaseline,"Equipped Use effect unavailable.")==1, "an incomplete equipped effect hides all Average deltas and deduplicates its warning")

-- Score-only routes must retain the metadata fourth return and avoid the
-- comparison API. They still use the same Base relevance and uncertainty rule.
FW.DB.options.showComparisons=false
averageValue=compared(85,6,7.5)
averageMetadata={hasAverageUse=true,averageUseGain=5}
local beforeAverageCompare=averageCalls.compare
local scoreAverage=decorateAverage("ScoreOnlyAverage")
assert(hasAverage(scoreAverage).right=="85.00" and averageCalls.compare==beforeAverageCompare and averageCalls.score==1, "disabled comparisons use GetAverageUseScore and its numeric score")
assert(averageCalls.ignoreFilters==nil, "Average score rows retain profile item filters")
averageMetadata={hasAverageUse=true,averageUseIncomplete=true,averageUseWarnings={"Secondary unit unavailable."}}
local incompleteScoreAverage=decorateAverage("IncompleteScoreAverage")
assert(hasAverage(incompleteScoreAverage).right==nil and noteCount(incompleteScoreAverage,"Secondary unit unavailable.")==1, "score-only metadata prevents an incomplete numeric estimate")
averageValue=nil; averageError="Average item data loading"
local pendingAverage=decorateAverage("PendingScoreAverage")
assert(hasAverage(pendingAverage).text=="  Average use: unavailable", "known incomplete Use metadata is retained even when no score is ready")
averageError=nil
averageValue=compared(85,6,7.5)
averageMetadata={hasAverageUse=true,averageUseGain=5}
FW.DB.options.showComparisons=true
local equippedAverage=decorateAverage("EquippedAverageUse",true)
local shoppingAverage=decorateAverage("ShoppingTooltipAverageUse")
assert(hasAverage(equippedAverage).right=="85.00" and hasAverage(shoppingAverage).right=="85.00" and averageCalls.compare==beforeAverageCompare, "equipped and shopping tooltips use the score-only Average API")

local savedAverageCompare=FW.CompareAverageUseItem
FW.CompareAverageUseItem=nil
local beforeOptionalScore=averageCalls.score
local optionalAverage=decorateAverage("OptionalAverageComparisonAPI")
assert(not hasAverage(optionalAverage) and averageCalls.score==beforeOptionalScore, "a missing comparison method skips Average without calling the score-only method")
FW.CompareAverageUseItem=savedAverageCompare
local savedAverageScore=FW.GetAverageUseScore
FW.GetAverageUseScore=nil
local optionalScoreAverage=decorateAverage("OptionalAverageScoreAPI",true)
assert(not hasAverage(optionalScoreAverage) and averageCalls.score==beforeOptionalScore, "a missing score-only method skips Average without calling the comparison method")
FW.GetAverageUseScore=savedAverageScore
averageFull={excluded=true,record={stats={}},comparisons={}}
local beforeExcludedAverage=averageCalls.compare
local excludedAverage=decorateAverage("ExcludedAverageUse")
assert(#excludedAverage.lines==0 and averageCalls.compare==beforeExcludedAverage, "an excluded full result never requests an Average score")

averageFull=compared(100,10,11.111)
averageBase=compared(80,5,6.667)
averageValue=compared(85,6,7.5)
averageValue.hasAverageUse=true; averageValue.averageUseGain=5
profiles={profiles[1],{id="two",name="Caster",revision=1,color={r=.1,g=.3,b=.9}}}
local multipleAverages=decorateAverage("MultipleAverageProfiles")
assert(#multipleAverages.lines==8 and noteCount(multipleAverages,assumption)==1, "multiple visible profile averages share one assumption note")
profiles={profiles[1]}

-- Clear, hide and native refresh restore fonts when Average rows vanish, even
-- when the old Average FontString is reused for a regular note or native line.
for _, tip in ipairs(testTooltips) do tip:Hide() end
local averageRefresh=decorateAverage("AverageUseRefresh")
function averageRefresh:RefreshData() self:Clear(); postCall(self,{hyperlink=self.link}) end
averageValue=compared(80,5,6.667)
FW.equipmentRevision=FW.equipmentRevision+1
FW:RefreshTooltips()
assert(#averageRefresh.lines==3 and not hasAverage(averageRefresh) and AverageUseRefreshTextLeft4.size==12 and AverageUseRefreshTextRight4.size==12, "refresh removes a redundant Average row and restores its font")
averageRefresh:Clear()
for _,text in ipairs({"Native one","Native two","Native three","Native four"}) do averageRefresh:AddLine(text) end
assert(AverageUseRefreshTextLeft4.size==12, "native content can reuse a former Average row at normal size")
averageRefresh:Clear()
averageValue=compared(85,6,7.5)
postCall(averageRefresh,{hyperlink=variant})
assert(math.abs(AverageUseRefreshTextLeft4.size-10.2)<1e-9, "a returning Average row shrinks once")
averageRefresh:Hide()
assert(AverageUseRefreshTextLeft3.size==12 and AverageUseRefreshTextLeft4.size==12 and averageRefresh.fwBaseFonts==nil, "hiding restores both smaller Base and Average rows")
print("Tooltip tests passed")
