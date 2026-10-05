local _, FW = ...

local slotsByType = {
    INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3},
    INVTYPE_BODY={4}, INVTYPE_CHEST={5}, INVTYPE_ROBE={5}, INVTYPE_WAIST={6},
    INVTYPE_LEGS={7}, INVTYPE_FEET={8}, INVTYPE_WRIST={9}, INVTYPE_HAND={10},
    INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14}, INVTYPE_CLOAK={15},
    INVTYPE_WEAPONMAINHAND={16}, INVTYPE_WEAPONOFFHAND={17},
    INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17}, INVTYPE_2HWEAPON={16,17},
    INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18},
    INVTYPE_RELIC={18}, INVTYPE_TABARD={19}, INVTYPE_AMMO={INVSLOT_AMMO or 0},
}
local slotNames = {
    [INVSLOT_AMMO or 0]="Ammunition",
    [1]="Head", [2]="Neck", [3]="Shoulders", [4]="Shirt", [5]="Chest",
    [6]="Waist", [7]="Legs", [8]="Feet", [9]="Wrists", [10]="Hands",
    [11]="Ring 1", [12]="Ring 2", [13]="Trinket 1", [14]="Trinket 2",
    [15]="Back", [16]="Main hand", [17]="Off hand", [18]="Ranged", [19]="Tabard",
}

function FW:CalculateDelta(candidate, baseline)
    local delta = candidate - baseline
    return delta, baseline > 0 and (delta / baseline * 100) or nil,
        delta > 0.0000001 and "upgrade" or (delta < -0.0000001 and "downgrade" or "equal")
end

local function inventoryLink(slot)
    return GetInventoryItemLink and GetInventoryItemLink("player", slot) or nil
end

local function inventoryType(link)
    if not link then return nil end
    local getter = C_Item and C_Item.GetItemInfo or GetItemInfo
    if getter then
        local ok, _, _, _, _, _, _, _, _, equipLoc = pcall(getter, link)
        if ok then return equipLoc end
    end
end

-- Rings/trinkets are separate replacements. A two-handed weapon replaces the
-- combined main/off-hand score; a shield cannot be compared to an occupied 2H slot.
function FW:CompareItem(link, profile, baseOnly)
    local getScore = baseOnly and self.GetBaseScore or self.GetScore
    local score, record, detail = getScore(self, link, profile)
    if score == nil then
        if detail == "excluded" then return {excluded=true, record=record, comparisons={}} end
        return nil, record
    end
    local result = {score=score, record=record, comparisons={}}
    result.hasIssues = (self.ItemHasIssues and self:ItemHasIssues(record, profile)) or record.partial
    local equipLoc = record.equipLoc
    local needsMainType = equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" or
        equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE"
    local mainLink = needsMainType and inventoryLink(16) or nil
    local mainTypeLink = mainLink
    if baseOnly then mainTypeLink = self:GetBaseItemLink(mainLink) end
    local mainType = inventoryType(mainTypeLink)
    if mainLink and not mainType and (equipLoc == "INVTYPE_WEAPON" or
        equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_WEAPONOFFHAND" or
        equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE") then
        if self.AwaitItemData then self:AwaitItemData(mainLink) end
        result.note, result.pending = "Equipped main-hand item data is loading.", true
        return result
    end
    if (equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or
        equipLoc == "INVTYPE_WEAPONOFFHAND") and mainType == "INVTYPE_2HWEAPON" then
        result.note = "Requires a compatible main-hand weapon."
        return result
    end
    local groups = {}
    if equipLoc == "INVTYPE_2HWEAPON" then
        groups[1] = {slots={16,17}, label="Main + off hand"}
    elseif equipLoc == "INVTYPE_WEAPON" then
        groups[1] = {slots={16}, label=slotNames[16]}
        if CanDualWield and CanDualWield() and mainType ~= "INVTYPE_2HWEAPON" then
            groups[2] = {slots={17}, label=slotNames[17]}
        end
    else
        for _, slot in ipairs(slotsByType[equipLoc] or {}) do
            groups[#groups+1] = {slots={slot}, label=slotNames[slot] or tostring(slot)}
        end
    end
    for _, group in ipairs(groups) do
        local comparison = {label=group.label, slots=group.slots, links={}, baseline=0}
        for _, slot in ipairs(group.slots) do
            local equipped = inventoryLink(slot)
            if equipped then
                comparison.links[#comparison.links+1] = equipped
                local equippedScore, equippedRecord = getScore(self, equipped, profile, true)
                if equippedScore == nil then comparison.error = tostring(equippedRecord); break end
                if (self.ItemHasIssues and self:ItemHasIssues(equippedRecord, profile)) or equippedRecord.partial then
                    comparison.hasIssues, result.hasIssues = true, true
                end
                comparison.baseline = comparison.baseline + equippedScore
            end
        end
        if not comparison.error then
            comparison.delta, comparison.percent, comparison.status =
                self:CalculateDelta(score, comparison.baseline)
        end
        result.comparisons[#result.comparisons+1] = comparison
    end
    if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
        if mainType == "INVTYPE_2HWEAPON" then
            result.note = "Single weapon score; a future off-hand is not included."
        end
    end
    return result
end

function FW:CompareBaseItem(link, profile)
    return self:CompareItem(link, profile, true)
end
