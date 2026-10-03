local FW = {}
local equipped, types, records, scores = {}, {}, {}, {}
GetInventoryItemLink = function(_, slot) return equipped[slot] end
GetItemInfo = function(link) return "item",link,1,1,1,"Weapon","Sword",1,types[link] end
CanDualWield = function() return true end
function FW:GetScore(link) return scores[link], records[link] or "Loading" end
assert(loadfile("Compare.lua"))("ZwykPoints",FW)
local function item(link, equipLoc, score)
    records[link]={equipLoc=equipLoc}; scores[link]=score; types[link]=equipLoc
end
local delta, percent, status=FW:CalculateDelta(120,100)
assert(delta==20 and percent==20 and status=="upgrade")
delta,percent,status=FW:CalculateDelta(0,0)
assert(delta==0 and percent==nil and status=="equal")
delta,percent,status=FW:CalculateDelta(5,-5)
assert(delta==10 and percent==nil and status=="upgrade")
item("ringA","INVTYPE_FINGER",100); item("ringB","INVTYPE_FINGER",80)
item("candidate","INVTYPE_FINGER",90); equipped[11]="ringA"; equipped[12]="ringB"
local result=FW:CompareItem("candidate",{})
assert(#result.comparisons==2)
assert(result.comparisons[1].delta==-10 and result.comparisons[2].delta==10)
item("sword","INVTYPE_WEAPON",100); item("shield","INVTYPE_SHIELD",50)
item("twohand","INVTYPE_2HWEAPON",140); equipped[16]="sword"; equipped[17]="shield"
result=FW:CompareItem("twohand",{})
assert(#result.comparisons==1 and result.comparisons[1].baseline==150)
assert(result.comparisons[1].delta==-10)
equipped[16]="twohand"; equipped[17]=nil
result=FW:CompareItem("shield",{})
assert(#result.comparisons==0 and result.note)
item("newSword","INVTYPE_WEAPON",110)
result=FW:CompareItem("newSword",{})
assert(#result.comparisons==1 and result.note)
equipped[16]="unloaded"
result=FW:CompareItem("twohand",{})
assert(result.comparisons[1].error and result.comparisons[1].delta==nil)
item("food","",100)
assert(#FW:CompareItem("food",{}).comparisons==0)
print("Comparison tests passed")
