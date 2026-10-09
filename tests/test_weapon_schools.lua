-- Run from the addon directory: luatex --luaonly tests/test_weapon_schools.lua
-- Damage schools on a wand's base range are weapon stats, not spell bonuses.
local checks = 0
local function check(value, message) assert(value, message); checks=checks+1 end
local function equal(actual, expected, message)
    check(actual==expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function approx(actual, expected, message)
    check(type(actual)=="number" and math.abs(actual-expected)<0.000001, message or (tostring(actual) .. " ~= " .. expected))
end
local function reader(options)
    local counts={stats=0,tooltip=0}
    GetBuildInfo=function() return "1.60.0","12345","Oct 2026",16000 end
    GetLocale=function() return options.locale or "enUS" end
    UnitLevel=function() return 60 end
    UnitClass=function() return "Paladin","PALADIN" end
    GetTime=function() return 10 end
    GetItemInfo=function(link)
        local equipLoc=options.equipLoc or "INVTYPE_RANGEDRIGHT"
        return "School damage wand",link,3,60,60,"Weapon","Wand",1,equipLoc,nil,nil,2,19
    end
    GetItemInfoInstant,GetItemStats,CreateFrame=nil,nil,nil
    C_Item={
        GetItemInfo=GetItemInfo,
        IsItemDataCachedByID=function() return true end,
        GetItemStats=function() counts.stats=counts.stats+1; return options.raw or {} end,
    }
    C_TooltipInfo={GetHyperlink=function()
        counts.tooltip=counts.tooltip+1
        local result={lines={}}
        for _,text in ipairs(options.lines) do result.lines[#result.lines+1]={leftText=text} end
        return result
    end}
    ZwykValuesDB,ZwykPointsDB,ForeverWeightsDB=nil,nil,nil
    local FW={}
    for _,file in ipairs({"JSON.lua","Stats.lua","Core.lua","Items.lua"}) do assert(loadfile(file))("ZwykValues",FW) end
    FW:Initialize()
    return FW,counts
end
local function completeRange(options,low,high,speed,dps)
    local FW,counts=reader(options)
    local link="item:200:0:0:0:0:0:0:0:60"
    local item=assert(FW:GetItem(link))
    equal(item.stats.lowDamage,low,"school range minimum")
    equal(item.stats.highDamage,high,"school range maximum")
    approx(item.stats.rangedSpeed,speed,"wand attack speed")
    approx(item.stats.rangedDps,dps,"wand damage per second")
    equal(item.stats.speed,nil,"wand speed stays distinct from melee speed")
    equal(item.stats.dps,nil,"wand DPS stays distinct from melee DPS")
    equal(item.stats.weaponDamage,nil,"a weapon range is not a flat damage bonus")
    for _,school in ipairs({"arcane","fire","nature","frost","shadow","holy"}) do equal(item.stats[school .. "Damage"],nil,"a weapon school is not a spell-damage bonus") end
    equal(item.stats.spellDamage,nil,"a weapon range is not generic spell damage")
    equal(item.stats.healing,nil,"a weapon range is not generic spell healing")
    equal(item.partial,false,"a complete school range resolves without partial warnings")
    equal(next(item.unresolvedStats),nil,"all requested weapon stats are available")
    equal(#item.unrecognizedLines,0,"a known school range is recognized")
    local profile=assert(FW:CreateProfile("Wand",{rangedDps=2,rangedSpeed=1,lowDamage=.1,highDamage=.2,spellDamage=100,fireDamage=100,shadowDamage=100}))
    approx(FW:GetScore(link,profile),dps*2+speed+low*.1+high*.2,"only weapon weights apply to the school range")
    local statsCalls,tooltipCalls=counts.stats,counts.tooltip
    equal(FW:GetItem(link),item,"the resolved record persists in the normal item cache")
    equal(counts.stats,statsCalls,"complete school ranges do not reread the stat API")
    equal(counts.tooltip,tooltipCalls,"complete school ranges do not rescan tooltip data")
end

-- Reported Fire/Shadow wand ranges with and without a displayed DPS line.
completeRange({lines={"Fire wand","28 - 52 Fire Damage","Speed 1.50"}},28,52,1.5,40/1.5)
completeRange({lines={"Shadow wand","16 - 31 Shadow Damage","Speed 1.50"}},16,31,1.5,23.5/1.5)
completeRange({lines={"Shadow wand","30 - 57 Shadow Damage","Speed 1.80","(24.2 damage per second)"}},30,57,1.8,24.2)

local schools={{"Arcane","Arcanes"},{"Fire","Feu"},{"Nature","Nature"},{"Frost","Givre"},{"Shadow","Ombre"},{"Holy","Sacré"},{"Physical","Physique"}}
for _,school in ipairs(schools) do
    completeRange({lines={"English wand","10 - 20 " .. school[1] .. " Damage","Speed 1.50"}},10,20,1.5,10)
    -- The French client DAMAGE_TEMPLATE_WITH_SCHOOL uses parenthetical schools.
    completeRange({locale="frFR",lines={"Baguette française","10 - 20 points de dégâts (" .. school[2] .. ")","Vitesse 1,50"}},10,20,1.5,10)
end
completeRange({locale="frFR",lines={"Baguette","10 - 20 dégâts de feu","Vitesse 1,50"}},10,20,1.5,10)
completeRange({lines={"Plain wand","10 - 20 Damage","Speed 1.50"}},10,20,1.5,10)
completeRange({locale="frFR",lines={"Baguette simple","10 - 20 dégâts","Vitesse 1,50"}},10,20,1.5,10)
completeRange({lines={"Decimal wand","10.5 - 20.5 Fire Damage","Speed 1.50"}},10.5,20.5,1.5,15.5/1.5)
completeRange({locale="frFR",lines={"Baguette décimale","10,5 - 20,5 points de dégâts (Feu)","Vitesse 1,50"}},10.5,20.5,1.5,15.5/1.5)
completeRange({raw={ITEM_MOD_DAMAGE_PER_SECOND_SHORT=40/1.5},lines={"Rounded wand","28 - 52 Fire Damage","Speed 1.50","(26.7 damage per second)"}},28,52,1.5,26.7)

-- Unknown schools and proc/cast damage must not satisfy the base weapon range.
for _,line in ipairs({
    "28 - 52 Sonic Damage", "28 - 52 points de dégâts (Mystère)",
    "28 - 52 Fire Damage plus 3 Mystery Flux", "Deals 28 - 52 Fire Damage",
    "Chance on hit: 28 - 52 Fire Damage", "Use: 28 - 52 Fire Damage",
    "28 - 52 Fire Damage for 10 sec.", "Équipé : Inflige 28 - 52 points de dégâts de Feu.",
}) do
    local FW=reader({lines={"Untrusted range wand",line,"Speed 1.50"}})
    local item=assert(FW:GetItem("item:201"))
    equal(item.stats.lowDamage,nil,"unknown or conditional damage cannot become weapon minimum")
    equal(item.stats.highDamage,nil,"unknown or conditional damage cannot become weapon maximum")
    equal(item.stats.rangedDps,nil,"untrusted ranges cannot derive weapon DPS")
    check(item.partial and item.unresolvedStats.lowDamage and item.unresolvedStats.highDamage,"missing base ranges retain actionable weapon warnings")
end

-- A separate school spell bonus remains separate from the physical weapon
-- range, and the existing melee versus ranged routing still applies.
local meleeFW=reader({equipLoc="INVTYPE_WEAPON",lines={"Fire sword","20 - 40 Fire Damage","Speed 2.00","Equip: Increases Fire spell damage by up to 12."}})
local melee=assert(meleeFW:GetItem("item:202"))
equal(melee.stats.lowDamage,20); equal(melee.stats.highDamage,40)
equal(melee.stats.speed,2); equal(melee.stats.dps,15)
equal(melee.stats.rangedSpeed,nil); equal(melee.stats.rangedDps,nil)
equal(melee.stats.fireDamage,12,"only the explicit spell bonus contributes school spell damage")
equal(melee.partial,false)
print("Weapon schools: " .. checks .. " checks passed")
