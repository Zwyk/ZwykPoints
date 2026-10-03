local FW = {}
local counts={initialize=0,hooks=0,refresh=0,invalidate=0,loaded=0,ui=0}
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
function FW:OnItemDataLoaded(id) counts.loaded=counts.loaded+1;counts.lastID=id end
function FW:GetHoveredItemLink() return hovered end
function FW:ToggleUI() counts.ui=counts.ui+1 end
function FW:GetItem(link)
    return {stats={strength=10},percentStats={crit=1},ratingStats={},warnings={},unresolvedStats={}}
end
function FW:ShowTextDialog(title,text,editable)
    assert(title=="Item diagnostics" and text=="diagnostics" and editable==false)
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
fire("PLAYER_LEVEL_UP",61)
assert(counts.invalidate==1)
hovered="|cffaabbcc|Hitem:100:0:0:0:0:0:0:0|h[Test]|h|r"
fire("GET_ITEM_INFO_RECEIVED",999,true)
assert(counts.loaded==1 and counts.refresh==1)
fire("GET_ITEM_INFO_RECEIVED",100,false)
assert(counts.loaded==1 and counts.refresh==1)
fire("ITEM_DATA_LOAD_RESULT",100,true)
assert(counts.loaded==2 and counts.refresh==2)

-- Item data for an equipped baseline can unblock a pending hovered comparison.
equip[1]="item:200:0:0:0:0:0:0:0"
fire("GET_ITEM_INFO_RECEIVED",200,true)
assert(counts.loaded==3 and counts.refresh==3, "Loaded equipped comparison baseline must refresh hovered tooltip")
hovered=nil
fire("GET_ITEM_INFO_RECEIVED",200,true)
assert(counts.refresh==3, "Item load should not rebuild unrelated hidden tooltips")

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
print("Bootstrap tests passed")
