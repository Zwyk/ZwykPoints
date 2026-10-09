-- Run from the addon directory: luatex --luaonly tests/test_on_use_items.lua
local checks = 0
local function equal(actual, expected, message)
    checks=checks+1
    assert(actual==expected,(message or 'value')..': expected '..tostring(expected)..', got '..tostring(actual))
end
local function near(actual,expected,message)
    checks=checks+1
    assert(actual and math.abs(actual-expected)<1e-8,(message or 'value')..': '..tostring(actual)..' ~= '..expected)
end
local current, now, statCalls, tooltipCalls
local function reader(lines,locale,raw)
    current,now,statCalls,tooltipCalls={lines=lines},0,0,0
    GetTime=function() return now end
    GetLocale=function() return locale or 'enUS' end
    GetBuildInfo=function() return '1.60.1','70205','',16001 end
    UnitLevel=function() return 22 end
    GetItemInfoInstant=nil
    GetItemInfo=function(link) return 'Test Trinket',link,2,18,13,'Armor','Miscellaneous',1,'INVTYPE_TRINKET',0,0,4,0 end
    C_Item={IsItemDataCachedByID=function() return true end,GetItemStats=function()
        statCalls=statCalls+1;return raw or {ITEM_MOD_STRENGTH_SHORT=4}
    end,GetItemCooldown=function() error('remaining cooldown must not be read') end}
    GetItemCooldown=function() error('remaining cooldown must not be read') end
    C_TooltipInfo={GetHyperlink=function()
        tooltipCalls=tooltipCalls+1
        if current.details then return {lines=current.details} end
        local details={}
        for _,text in ipairs(current.lines) do details[#details+1]={leftText=text} end
        return {lines=details}
    end}
    ITEM_COOLDOWN_TOTAL_SEC,ITEM_COOLDOWN_TOTAL_MIN=nil,nil
    ITEM_COOLDOWN_TOTAL_HOUR,ITEM_COOLDOWN_TOTAL_HOURS=nil,nil
    CreateFrame=nil
    ZwykValuesDB,ZwykPointsDB,ForeverWeightsDB=nil,nil,nil
    local FW={}
    for _,file in ipairs({'JSON.lua','Stats.lua','Core.lua','Items.lua'}) do assert(loadfile(file))('ZwykValues',FW) end
    FW:Initialize()
    return FW
end
local function read(use,locale,extra)
    local lines={'Test Trinket','+4 Strength',use}
    if extra then lines[#lines+1]=extra end
    local FW=reader(lines,locale)
    return assert(FW:GetItem('item:900:0')),FW
end
local item,FW=read('Use: Increases spell power by 120 for 10 sec. (2 Min Cooldown)')
equal(item.parserVersion,8)
equal(item.stats.strength,4);equal(item.stats.spellDamage,nil);equal(item.stats.healing,nil)
near(item.onUseStats.spellDamage,10);near(item.onUseStats.healing,10)
equal(item.partial,false);equal(#item.warnings,0);equal(#item.unrecognizedLines,0)
equal(#item.onUseEffects,1);equal(#item.onUseUnsupported,0)
equal(item.onUseEffects[1].amount,120);equal(item.onUseEffects[1].duration,10);equal(item.onUseEffects[1].cooldown,120)
near(item.onUseEffects[1].uptime,1/12);equal(item.onUseEffects[1].stats.spellDamage,120)
equal(FW:GetItem(item.link),item);equal(statCalls,1);equal(tooltipCalls,1,'supported effect is persistently cached')
for _,case in ipairs({
    {'Use: Increases your spell power by 120 for10sec. (2 Min Cooldown)','spellDamage',10},
    {'Use: Increases damage and healing done by magical spells and effects by up to 120 for 10 sec. (2 Min Cooldown)','healing',10},
    {'Use: Increases damage and healing by up to 120 for 10 sec. (2 Min Cooldown)','spellDamage',10},
    {'Use: Increases Strength by 40 for 20 seconds. (10 Sec Cooldown)','strength',40},
    {'Use: +30 Agility for 15 sec.','agility',5,'enUS','(1 Min 30 Sec Cooldown)'},
    {'Use: Increases attack power by 200 for 1 minute. (1 Hour Cooldown)','attackPower',200/60},
    {'Utiliser : Augmente votre Force de 120 pendant 10 s. (2 min de recharge.)','strength',10,'frFR'},
    {'Utilisation : Augmente la puissance des sorts de 120 pendant 10 sec. (2 min de recharge.)','healing',10,'frFR'},
    {'Utiliser : Augmente les dégâts et les soins produits par les sorts et effets magiques de 120 au maximum pendant 10 secondes. (2 min de recharge.)','spellDamage',10,'frFR'},
    {'Utiliser : Augmente la puissance d’attaque de 90 pendant 15 s.','attackPower',15,'frFR','(1 min 30 s de recharge.)'},
    {'Use: Increases Fire spell damage by up to 80 for 10 sec. (40 Sec Cooldown)','fireDamage',20},
    {'Use: Increases the block value of your shield by 100 for 10 sec. (1 Min Cooldown)','blockValueBonus',100/6},
    {'Use: Increases armor by 200 for 10 sec. (1 Min Cooldown)','armorBonus',200/6},
    {'Use: +200 Armor for 10 sec. (1 Min Cooldown)','armorBonus',200/6},
    {'Use: Increases block value by 100 for 10 sec. (1 Min Cooldown)','blockValueBonus',100/6},
    {'Use: Increases all stats by 24 for 10 sec. (2 Min Cooldown)','intellect',2},
}) do
    item=read(case[1],case[4],case[5])
    near(item.onUseStats[case[2]],case[3],case[1]);equal(#item.onUseUnsupported,0);equal(item.partial,false)
    equal(item.stats.strength,4,'static value is never replaced by a timed buff')
end
FW=reader({'Test Trinket','150 Armor','Use: Increases armor by 200 for 10 sec. (1 Min Cooldown)'},
    'enUS',{RESISTANCE0_NAME=150})
item=assert(FW:GetItem('item:909'))
equal(item.stats.armor,150);equal(item.stats.armorBonus,nil)
equal(item.onUseStats.armor,nil);near(item.onUseStats.armorBonus,200/6)
equal(item.onUseEffects[1].stats.armor,nil);equal(item.onUseEffects[1].stats.armorBonus,200)
for _,case in ipairs({
    {'Use: Increases your critical strike rating by 60 for 10 sec. (1 Min Cooldown)','crit',10,'rating'},
    {'Use: Increases your critical strike chance by 2% for 30 sec. (2 Min Cooldown)','crit',0.5,'percent'},
    {'Use: Increases your chance to hit by 2% for 30 sec. (2 Min Cooldown)','hit',0.5,'percent'},
    {'Use: Increases defense skill by 10 for 30 sec. (1 Min Cooldown)','defense',5,'percent'},
    {'Utiliser : Augmente votre score de hâte de 60 pendant 10 s. (1 min de recharge.)','haste',10,'rating','frFR'},
    {'Use: Increases your defense rating by 60 for 10 sec. (1 Min Cooldown)','defense',10,'rating'},
    {'Utiliser : Augmente votre score de défense de 60 pendant 10 s. (1 min de recharge.)','defense',10,'rating','frFR'},
    {'Utiliser : Augmente vos chances de toucher de 1,5% pendant 10 s. (1 min de recharge.)','hit',0.25,'percent','frFR'},
}) do
    item=read(case[1],case[5])
    local values=case[4]=='rating' and item.onUseRatingStats or item.onUsePercentStats
    near(values[case[2]],case[3]);equal(#item.onUseUnsupported,0)
    equal(next(item.ratingStats),nil);equal(next(item.percentStats),nil);equal(item.partial,false)
end
-- Cooldown association is native-row adjacent, not adjacent after blank removal.
item,FW=read('Use: Increases Strength by 60 for 10 sec.','enUS','(1 Min Cooldown)')
near(item.onUseStats.strength,10)
FW=reader({'Test Trinket','+4 Strength'})
current.details={{leftText='Test Trinket'},{leftText='+4 Strength'},
    {leftText='Use: Increases Strength by 60 for 10 sec.',rightText='(1 Min Cooldown)'}}
item=assert(FW:GetItem('item:901'));near(item.onUseStats.strength,10)
FW=reader({'Test Trinket','+4 Strength','Use: Increases Strength by 60 for 10 sec.','','(1 Min Cooldown)'})
item=assert(FW:GetItem('item:902'));equal(next(item.onUseStats),nil);equal(#item.onUseUnsupported,1)
FW=reader({'Test Trinket','+4 Strength','(1 Min Cooldown)','Use: Increases Strength by 60 for 10 sec.'})
item=assert(FW:GetItem('item:903'));equal(next(item.onUseStats),nil,'previous cooldown cannot be borrowed')
-- Only total-cooldown native formats participate; remaining-time formats do not.
FW=reader({'Test Trinket','+4 Strength','Use: Increases Strength by 60 for 10 sec. (Délai complet : 1 minutes)'},'frFR')
ITEM_COOLDOWN_TOTAL_MIN='(Délai complet : %d minutes)'
item=assert(FW:GetItem('item:904'));near(item.onUseStats.strength,10)
for _,use in ipairs({
    'Use: Deals 300 Fire damage. (2 Min Cooldown)',
    'Use: Heals you for 300 health. (2 Min Cooldown)',
    'Use: Restores 300 mana over 10 sec. (2 Min Cooldown)',
    'Use: Increases Strength by 10% for 10 sec. (2 Min Cooldown)',
    'Use: Increases attack power by 10% of your base attack power for 10 sec. (2 Min Cooldown)',
    'Use: Increases Strength by 60 for 10 sec, stacking 5 times. (2 Min Cooldown)',
    'Use: Increases Strength by 60 while in Bear Form for 10 sec. (2 Min Cooldown)',
    'Use: Increases Strength by 60 and grants 3 Mystery Flux for 10 sec. (2 Min Cooldown)',
    'Use: Grants 60 Mystery Flux for 10 sec. (2 Min Cooldown)',
    'Use: Increases critical strike rating by 2% for 10 sec. (2 Min Cooldown)',
    'Use: Increases Strength by 60 for 10 sec. (0 Min Cooldown)',
    'Use: Increases Strength by 60 for 0 sec. (2 Min Cooldown)',
    'Use: Increases Strength by 60 for 10 sec. (2 Fortnights Cooldown)',
    'Use: Increases Strength by 60 for 10 sec. Temps de recharge : 2 min',
    'Use: Increases Strength by 60 for 10 sec.',
}) do
    item=read(use)
    equal(next(item.onUseStats),nil,use);equal(next(item.onUsePercentStats),nil);equal(next(item.onUseRatingStats),nil)
    equal(#item.onUseEffects,0);equal(#item.onUseUnsupported,1);equal(type(item.onUseUnsupported[1].reason),'string')
    equal(item.partial,false);equal(#item.warnings,0);equal(item.stats.strength,4)
end
item=read('Use: Grants 60 Mystery Flux for 10 sec. (2 Min Cooldown)')
equal(item.onUseRetryable,false,'known unsupported wording is stable')
item,FW=read('Use: Summons a companion. (2 Min Cooldown)')
equal(item.onUseRetryable,false,'unsupported instant actions must not retry')
now=2
equal(FW:RefreshOnUseItem(item),false);equal(tooltipCalls,1)
item,FW=read('Use: Increases Strength by 60. (1 Min Cooldown)')
equal(item.onUseRetryable,true,'a recognized stat buff with missing duration can recover')
current.lines[3]='Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'
now=1.1
equal(FW:RefreshOnUseItem(item),true);near(item.onUseStats.strength,10)
equal(statCalls,1);equal(tooltipCalls,2)
FW=reader({'Test Trinket','+4 Strength','Set (2/8)','Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'})
item=assert(FW:GetItem('item:905'));equal(next(item.onUseStats),nil);equal(#item.onUseUnsupported,1)
-- Multiple independently described effects add; duplicate left/right text does not.
FW=reader({'Test Trinket','+4 Strength','Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)',
    'Use: Increases Strength by 120 for 10 sec. (2 Min Cooldown)'})
item=assert(FW:GetItem('item:906'));near(item.onUseStats.strength,20);equal(#item.onUseEffects,2)
FW=reader({'Test Trinket','+4 Strength'})
current.details={{leftText='Test Trinket'},{leftText='+4 Strength'},
    {leftText='Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)',rightText='Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'}}
item=assert(FW:GetItem('item:907'));near(item.onUseStats.strength,10);equal(#item.onUseEffects,1)
-- Incomplete timing can recover without reading stats or changing static data.
item,FW=read('Use: Increases Strength by 60 for 10 sec.')
equal(item.onUseRetryable,true);equal(tooltipCalls,1)
item.averageUseScores={stale=true}
current.lines[3]='Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'
FW:RefreshOnUseItem(item);equal(tooltipCalls,1,'initial average lookup is throttled')
now=1.1
FW:RefreshOnUseItem(item);equal(tooltipCalls,2);equal(statCalls,1)
near(item.onUseStats.strength,10);equal(item.averageUseScores,nil);equal(item.onUseRetryable,false)
equal(item.stats.strength,4);equal(item.partial,false);equal(#item.warnings,0)
equal(item.diagnostic.tooltipDetails[3].leftText,current.lines[3])
now=3
FW:RefreshOnUseItem(item);equal(tooltipCalls,2,'successful timing stays cached')
item,FW=read('Use: Increases Strength by 60 for 10 sec.')
current.lines={'Test Trinket'}
now=1.1
equal(FW:RefreshOnUseItem(item),true);equal(item.onUseRetryable,true)
equal(#item.onUseUnsupported,1,'name-only refresh cannot establish absence of on-use effects')
equal(item.stats.strength,4);equal(item.partial,false);equal(statCalls,1)
current.lines={'Test Trinket','+4 Strength','Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'}
now=2.2
equal(FW:RefreshOnUseItem(item),true);near(item.onUseStats.strength,10)
equal(item.onUseRetryable,false);equal(#item.onUseUnsupported,0);equal(statCalls,1);equal(tooltipCalls,3)
item,FW=read('Use: Increases Strength by 60 for 10 sec.')
local clock=GetTime
GetTime=nil
for _=1,5 do equal(FW:RefreshOnUseItem(item),false) end
equal(tooltipCalls,1,'legacy clock absence cannot cause repeated scans across profiles')
GetTime=clock
local secret=setmetatable({},{__tostring=function() error('secret tooltip must not be stringified') end})
issecretvalue=function(value) return value==secret end
FW=reader({'Test Trinket','+4 Strength',secret})
item=assert(FW:GetItem('item:908'))
equal(item.onUseRetryable,true);equal(#item.onUseUnsupported,1);equal(item.partial,false)
current.lines[3]='Use: Increases Strength by 60 for 10 sec. (1 Min Cooldown)'
now=1.1
FW:RefreshOnUseItem(item);near(item.onUseStats.strength,10);equal(item.onUseRetryable,false);equal(statCalls,1)
issecretvalue=nil
print('On-use item parser tests passed: '..checks..' checks')
