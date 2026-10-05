local FW = {}
local counts={initialize=0,hooks=0,refresh=0,invalidate=0,loaded=0,ui=0,
    upgradeInvalidations=0,indicators=0,recentInvalidations=0}
local messages, equip, hovered = {}, {}, nil
local events, eventHandler
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) messages[#messages+1]=message end}
SlashCmdList={}
CreateFrame=function(kind)
    assert(kind=="Frame")
    return {
        RegisterEvent=function(_,event) events=events or {}; events[event]=true end,
        SetScript=function(_,event,fn) assert(event=="OnEvent");eventHandler=fn end,
    }
end
GetInventoryItemLink=function(_,slot) return equip[slot] end
GetBuildInfo=function() return "16.0.0","65000","Oct 1 2026",160000 end
GetLocale=function() return "enUS" end
FW.JSON={Encode=function(value) FW.lastEncoded=value; return "diagnostics" end}
function FW:Initialize()
    counts.initialize=counts.initialize+1
    self.DB={cache={items={a={},b={}},scores={a={}}}}
end
function FW:InstallTooltipHooks() counts.hooks=counts.hooks+1 end
function FW:RefreshTooltips() counts.refresh=counts.refresh+1 end
function FW:InvalidateCache() counts.invalidate=counts.invalidate+1 end
function FW:InvalidateRecentItemReads() counts.recentInvalidations=counts.recentInvalidations+1 end
function FW:InvalidateUpgradeComparisons() counts.upgradeInvalidations=counts.upgradeInvalidations+1 end
function FW:RefreshUpgradeIndicators() counts.indicators=counts.indicators+1 end
function FW:OnItemDataLoaded(id,success)
    local pending=self.PendingItems and self.PendingItems[id]
    if self.PendingItems then self.PendingItems[id]=nil end
    if not pending or success==false then return false end
    counts.loaded=counts.loaded+1;counts.lastID=id
    return true
end
function FW:GetHoveredItemLink() return hovered end
function FW:ToggleUI() counts.ui=counts.ui+1 end
function FW:GetItem(link)
    return {stats={strength=10},percentStats={crit=1},ratingStats={},warnings={},unresolvedStats={}}
end
function FW:GetIssueReport() return {itemCount=1,items={{itemID=777}}} end
function FW:ClearItemIssues() counts.clearIssues=(counts.clearIssues or 0)+1 end
function FW:ShowTextDialog(title,text,editable)
    assert((title=="Item diagnostics" or title=="Item issues (1)") and text=="diagnostics" and editable==false)
    counts.dialogTitle=title
    counts.dialog=(counts.dialog or 0)+1
end
assert(loadfile("Bootstrap.lua"))("ZwykValues",FW)
assert(ZwykValues==FW and SLASH_ZWYKVALUES1=="/zv")
assert(SLASH_ZWYKVALUES2=="/zwykvalues" and SLASH_ZWYKVALUES3==nil)
assert(SlashCmdList.ZWYKPOINTS==nil and SLASH_ZWYKPOINTS1==nil, "ZwykValues must not register the old /zp command")
for _,event in ipairs({"ADDON_LOADED","PLAYER_EQUIPMENT_CHANGED","PLAYER_LEVEL_UP","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT"}) do
    assert(events[event])
end
local function fire(event,id,success) eventHandler(nil,event,id,success) end
fire("PLAYER_EQUIPMENT_CHANGED",16)
assert(counts.refresh==0)
fire("ADDON_LOADED","OtherAddon")
assert(counts.initialize==0)
fire("ADDON_LOADED","ZwykValues")
assert(counts.initialize==1 and counts.hooks==1)
fire("PLAYER_EQUIPMENT_CHANGED",16)
assert(FW.equipmentRevision==1 and counts.refresh==1)
assert(counts.recentInvalidations==1 and counts.upgradeInvalidations==1)
fire("PLAYER_LEVEL_UP",61)
assert(counts.invalidate==1)
hovered="|cffaabbcc|Hitem:100:0:0:0:0:0:0:0|h[Test]|h|r"
FW.PendingItems={}
local function redrawState()
    return {refresh=counts.refresh,upgrades=counts.upgradeInvalidations,indicators=counts.indicators,loaded=counts.loaded}
end
local function unchanged(before,message)
    assert(counts.refresh==before.refresh and counts.upgradeInvalidations==before.upgrades
        and counts.indicators==before.indicators and counts.loaded==before.loaded,message)
end
local idle=redrawState()
fire("GET_ITEM_INFO_RECEIVED",999,true)
unchanged(idle,"Unsolicited native item events must not invalidate decisions or refresh anything")
FW.PendingItems[100]=true
fire("GET_ITEM_INFO_RECEIVED",100,false)
assert(FW.PendingItems[100]==nil,"Failed loads consume their pending request")
unchanged(idle,"Failed requested loads must not invalidate decisions or refresh anything")
fire("ITEM_DATA_LOAD_RESULT",100,true)
unchanged(idle,"A later unsolicited result after failure is not a fresh completion")
FW.PendingItems[100]=true
fire("ITEM_DATA_LOAD_RESULT",100,true)
assert(counts.loaded==1 and counts.lastID==100 and counts.refresh==2)
assert(FW.PendingItems[100]==nil and counts.upgradeInvalidations==idle.upgrades+1
    and counts.indicators==idle.indicators+1,"Meaningful hovered success refreshes decisions, indicators and tooltip together")
local completed=redrawState()
for _=1,5 do
    fire("GET_ITEM_INFO_RECEIVED",100,true)
    fire("ITEM_DATA_LOAD_RESULT",100,true)
    fire("GET_ITEM_INFO_RECEIVED",999,true)
end
unchanged(completed,"Repeated and unrelated native cache events must not feed refresh loops")

-- Item data for an equipped baseline can unblock a pending hovered comparison.
equip[1]="item:200:0:0:0:0:0:0:0"
FW.PendingItems[200]=true
fire("GET_ITEM_INFO_RECEIVED",200,true)
assert(counts.loaded==2 and counts.refresh==3,"Requested equipped comparison baseline must refresh hovered tooltip")
assert(counts.upgradeInvalidations==completed.upgrades+1 and counts.indicators==completed.indicators+1)
completed=redrawState()
fire("ITEM_DATA_LOAD_RESULT",200,true)
unchanged(completed,"Duplicate baseline completion must not redraw")

-- Ammunition is equipped at slot zero, separately from the ranged weapon.
equip[0]="item:250:0"
FW.PendingItems[250]=true
fire("ITEM_DATA_LOAD_RESULT",250,true)
assert(counts.loaded==3 and counts.refresh==4,"Requested ammunition baseline at slot zero refreshes a hovered comparison")
assert(counts.upgradeInvalidations==completed.upgrades+1 and counts.indicators==completed.indicators+1)

-- An awaited item can affect bag indicators without being the current tooltip
-- or an equipped dependency; only its indicators and decisions need refresh.
completed=redrawState()
FW.PendingItems[300]=true
fire("GET_ITEM_INFO_RECEIVED",300,true)
assert(counts.loaded==4 and counts.refresh==completed.refresh)
assert(counts.upgradeInvalidations==completed.upgrades+1 and counts.indicators==completed.indicators+1,
    "Requested unrelated success refreshes indicators without rebuilding the hovered tooltip")
hovered=nil
completed=redrawState()
FW.PendingItems[200]=true
fire("GET_ITEM_INFO_RECEIVED",200,true)
assert(counts.loaded==5 and counts.refresh==completed.refresh,"Requested loads must not rebuild hidden tooltips")
assert(counts.upgradeInvalidations==completed.upgrades+1 and counts.indicators==completed.indicators+1)
completed=redrawState()
fire("GET_ITEM_INFO_RECEIVED",200,true)
fire("GET_ITEM_INFO_RECEIVED",999,false)
unchanged(completed,"Hidden repeated and unsolicited failed events must not refresh")

SlashCmdList.ZWYKVALUES("cache")
assert(messages[#messages]:find("2 cached item variants; 1 scored variants.",1,true))
SlashCmdList.ZWYKVALUES("  clearcache ")
assert(counts.invalidate==2)
SlashCmdList.ZWYKVALUES("")
assert(counts.ui==1)
SlashCmdList.ZWYKVALUES("help")
assert(messages[#messages]:find("/zv opens profiles",1,true))
SlashCmdList.ZWYKVALUES("inspect item:777")
assert(counts.dialog==1 and FW.lastEncoded.item=="item:777" and FW.lastEncoded.locale=="enUS")
SlashCmdList.ZWYKVALUES("inspect")
assert(messages[#messages]:find("Hover an item",1,true))
SlashCmdList.ZWYKVALUES("exportissues")
assert(counts.dialog==2 and counts.dialogTitle=="Item issues (1)" and FW.lastEncoded.items[1].itemID==777)
SlashCmdList.ZWYKVALUES("clearissues")
assert(counts.clearIssues==1 and counts.invalidate==2, "Clearing issue history must not clear the score cache")
assert(events.UNIT_INVENTORY_CHANGED)
local before=counts.refresh
local revision=FW.equipmentRevision
local recentBefore,upgradesBefore=counts.recentInvalidations,counts.upgradeInvalidations
fire("UNIT_INVENTORY_CHANGED","target")
assert(counts.refresh==before and FW.equipmentRevision==revision)
assert(counts.recentInvalidations==recentBefore and counts.upgradeInvalidations==upgradesBefore)
fire("UNIT_INVENTORY_CHANGED","player")
assert(counts.refresh==before+1 and FW.equipmentRevision==revision+1,
    "in-place equipment/enchant updates invalidate upgrade decisions")
assert(counts.recentInvalidations==recentBefore+1 and counts.upgradeInvalidations==upgradesBefore+1,
    "player inventory changes invalidate recent item reads and upgrade decisions together")
print("Bootstrap tests passed")
