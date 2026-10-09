-- Run from the addon directory: luatex --luaonly tests/test_report_armor.lua
-- Real-reader regressions for Tortoise Armor's 208 Armor / +40 Armor report.
local checks, failures = 0, {}
local function equal(actual, expected, message)
    checks = checks + 1
    assert(actual == expected, (message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function case(name, callback)
    local ok, message = pcall(callback)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(message) end
end
local function reader(fixture)
    local statCalls, tooltipCalls = 0, 0
    GetTime = function() return 100 end
    GetLocale = function() return fixture.locale or "enUS" end
    GetBuildInfo = function() return "1.60.1", "70205", "Oct 2 2026", 16001 end
    UnitLevel = function() return 60 end
    GetItemInfoInstant = nil
    GetItemStats = nil
    GetItemInfo = function(link)
        return "Tortoise Armor", link, 3, 35, 30, "Armor", "Leather", 1, "INVTYPE_CHEST", 0, 0, 4, 2
    end
    local function enchanted(link)
        local id = link:match("item:%d+:([%-]?%d+)")
        return id and tonumber(id) ~= 0
    end
    C_Item = {
        IsItemDataCachedByID = function() return true end,
        GetItemStats = function(link)
            statCalls = statCalls + 1
            return enchanted(link) and fixture.fullRaw or fixture.raw
        end,
    }
    C_TooltipInfo = { GetHyperlink = function(link)
        tooltipCalls = tooltipCalls + 1
        local text = enchanted(link) and fixture.fullLines or fixture.lines
        if not text then return nil end
        local lines = { { leftText = "Tortoise Armor" } }
        for _, value in ipairs(text) do lines[#lines + 1] = { leftText = value } end
        return { lines = lines }
    end }
    CreateFrame = nil
    ZwykValuesDB, ZwykPointsDB, ForeverWeightsDB = nil, nil, nil
    local FW = {}
    for _, file in ipairs({ "JSON.lua", "Stats.lua", "Core.lua", "Items.lua" }) do
        assert(loadfile(file))("ZwykValues", FW)
    end
    FW:Initialize()
    return FW, function() return statCalls, tooltipCalls end
end
local function armor(fixture, intrinsic, bonus)
    local FW, calls = reader(fixture)
    local record = assert(FW:GetItem("item:6907:0:0:0:0:0:0"))
    equal(record.stats.armor, intrinsic, "intrinsic armor")
    equal(record.stats.armorBonus, bonus, "bonus armor")
    local profile = assert(FW:CreateProfile("Different armor weights", { armor = 2, armorBonus = 3 }))
    equal(FW:GetScore(record.link, profile), intrinsic * 2 + (bonus or 0) * 3, "independent armor weights")
    if not record.partial then
        equal(FW:GetItem(record.link), record, "resolved record is cached")
        local statCalls, tooltipCalls = calls()
        equal(statCalls, 1, "cached reads do not extract raw stats again")
        equal(tooltipCalls, 1, "cached reads do not scan the tooltip again")
    end
    return record, FW
end

case("reported 208 + 40 with API total 248", function()
    armor({raw={RESISTANCE0_NAME=248},lines={"208 Armor", "+40 Armor"}}, 208, 40)
end)
case("the API and tooltip describe the same bonus once", function()
    armor({raw={RESISTANCE0_NAME=248,ITEM_MOD_EXTRA_ARMOR_SHORT=40},lines={"208 Armor", "+40 Armor"}}, 208, 40)
end)
case("tooltip-only intrinsic and bonus armor", function()
    armor({lines={"208 Armor", "+40 Armor"}}, 208, 40)
end)
case("French intrinsic and signed bonus armor", function()
    armor({locale="frFR",raw={ITEM_MOD_ARMOR_SHORT=248,ITEM_MOD_BONUS_ARMOR_SHORT=40},
        lines={"208 Armure", "+40 Armure"}}, 208, 40)
end)
case("label-first signed bonus armor", function()
    armor({raw={RESISTANCE0_NAME=248},lines={"208 Armor", "Armor +40"}}, 208, 40)
end)
case("multiple explicit bonuses", function()
    armor({raw={RESISTANCE0_NAME=248},lines={"208 Armor", "+20 Armor", "+20 Armor"}}, 208, 40)
end)
case("a bonus-only tooltip preserves the known API total", function()
    armor({raw={RESISTANCE0_NAME=248},lines={"+40 Armor"}}, 208, 40)
end)
case("a bonus-only stat has no intrinsic armor", function()
    armor({raw={},lines={"+40 Armor"}}, 0, 40)
end)
case("API-only total and bonus remain separate", function()
    armor({raw={RESISTANCE0_NAME=248,ITEM_MOD_EXTRA_ARMOR_SHORT=40},lines={"Binds when equipped"}}, 208, 40)
end)
case("API armor survives an unavailable tooltip", function()
    local record = armor({raw={RESISTANCE0_NAME=248,ITEM_MOD_EXTRA_ARMOR_SHORT=40}}, 208, 40)
    equal(record.partial, true, "missing tooltip remains a partial read")
end)
case("legacy bare armor row remains a total when no signed bonus is shown", function()
    armor({raw={RESISTANCE0_NAME=300,ITEM_MOD_EXTRA_ARMOR_SHORT=50},lines={"300 Armor"}}, 250, 50)
end)
case("ordinary intrinsic armor is unchanged", function()
    armor({raw={RESISTANCE0_NAME=141},lines={"141 Armor"}}, 141, nil)
end)

local function enchantedCase(baseArmor, baseBonus, baseLines, fullLines, fullArmor)
    local raw = {RESISTANCE0_NAME=baseArmor+(baseBonus or 0)}
    local FW = reader({raw=raw,fullRaw=raw,lines=baseLines,fullLines=fullLines})
    local profile = assert(FW:CreateProfile("Enchanted armor weights", {armor=2,armorBonus=3}))
    local link = "|cnIQ3:|Hitem:6907:8481:0:0:0:0:0|h[Tortoise Armor]|h|r"
    local score, full = FW:GetScore(link, profile)
    equal(full.stats.armor, fullArmor, "full armor retains established enchant semantics")
    equal(full.stats.armorBonus, baseBonus, "enchant does not duplicate or consume an item bonus")
    equal(score, fullArmor*2+(baseBonus or 0)*3, "full enchanted score")
    local baseScore, base = FW:GetBaseScore(link, profile)
    equal(base.stats.armor, baseArmor, "base read strips armor enchant only")
    equal(base.stats.armorBonus, baseBonus, "base read retains the item's own armor bonus")
    equal(baseScore, baseArmor*2+(baseBonus or 0)*3, "unenchanted base score")
end
case("separate armor enchant preserves existing behavior", function()
    enchantedCase(141,nil,{"141 Armor"},{"141 Armor", "Enchanted: Armor +16"},157)
end)
case("folded armor enchant is not added twice", function()
    enchantedCase(141,nil,{"141 Armor"},{"157 Armor", "Enchanted: Armor +16"},157)
end)
case("item bonus and separate armor enchant", function()
    enchantedCase(208,40,{"208 Armor", "+40 Armor"},
        {"208 Armor", "+40 Armor", "Enchanted: Armor +16"},224)
end)
case("item bonus and folded armor enchant", function()
    enchantedCase(208,40,{"208 Armor", "+40 Armor"},
        {"224 Armor", "+40 Armor", "Enchanted: Armor +16"},224)
end)

if #failures > 0 then
    for _, message in ipairs(failures) do print(message) end
    error(tostring(#failures) .. " armor regression cases failed after " .. checks .. " checks")
end
print("Report armor tests passed (" .. checks .. " checks)")
