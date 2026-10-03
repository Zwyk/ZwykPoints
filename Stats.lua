local _, FW = ...

-- Keep these keys compatible with the flat Sixty Upgrades weight JSON.
-- The secondary-stat unit is selected by the profile, not inferred from a
-- client version. Percentage weights mean one percentage point (defense is
-- one skill point); rating weights mean one raw item rating point.
FW.StatDefinitions = {
    { key = "strength", label = "Strength", group = "Attributes" },
    { key = "agility", label = "Agility", group = "Attributes" },
    { key = "stamina", label = "Stamina", group = "Attributes" },
    { key = "intellect", label = "Intellect", group = "Attributes" },
    { key = "spirit", label = "Spirit", group = "Attributes" },
    { key = "health", label = "Health", group = "Resources" },
    { key = "hp5", label = "Health per 5 seconds", group = "Resources" },
    { key = "spellDamage", label = "Spell damage", group = "Spell" },
    { key = "healing", label = "Healing", group = "Spell" },
    { key = "spellPen", label = "Spell penetration", group = "Spell" },
    { key = "mp5", label = "Mana per 5 seconds", group = "Resources" },
    { key = "arcaneDamage", label = "Arcane damage", group = "Spell" },
    { key = "fireDamage", label = "Fire damage", group = "Spell" },
    { key = "natureDamage", label = "Nature damage", group = "Spell" },
    { key = "frostDamage", label = "Frost damage", group = "Spell" },
    { key = "shadowDamage", label = "Shadow damage", group = "Spell" },
    { key = "holyDamage", label = "Holy damage", group = "Spell" },
    { key = "attackPower", label = "Attack power", group = "Attack" },
    { key = "feralAttackPower", label = "Feral attack power", group = "Attack" },
    { key = "dps", label = "Melee weapon DPS", group = "Weapon" },
    { key = "lowDamage", label = "Weapon minimum damage", group = "Weapon" },
    { key = "highDamage", label = "Weapon maximum damage", group = "Weapon" },
    { key = "weaponDamage", label = "Flat added weapon damage", group = "Weapon" },
    { key = "speed", label = "Melee weapon speed", group = "Weapon" },
    { key = "hit", label = "Hit", group = "Secondary", secondary = true },
    { key = "crit", label = "Critical strike", group = "Secondary", secondary = true },
    { key = "haste", label = "Haste", group = "Secondary", secondary = true },
    { key = "expertise", label = "Expertise", group = "Secondary", secondary = true },
    { key = "rangedDps", label = "Ranged weapon DPS", group = "Weapon" },
    { key = "rangedSpeed", label = "Ranged weapon speed", group = "Weapon" },
    { key = "rangedAttackPower", label = "Ranged attack power", group = "Attack" },
    { key = "armor", label = "Base armor", group = "Defense" },
    { key = "armorBonus", label = "Bonus armor", group = "Defense" },
    { key = "defense", label = "Defense (skill / rating)", group = "Secondary", secondary = true },
    { key = "dodge", label = "Dodge", group = "Secondary", secondary = true },
    { key = "parry", label = "Parry", group = "Secondary", secondary = true },
    { key = "block", label = "Block chance", group = "Secondary", secondary = true },
    { key = "blockValue", label = "Block value", group = "Defense" },
    { key = "blockValueBonus", label = "Bonus block value", group = "Defense" },
    { key = "arcaneResist", label = "Arcane resistance", group = "Resistance" },
    { key = "fireResist", label = "Fire resistance", group = "Resistance" },
    { key = "natureResist", label = "Nature resistance", group = "Resistance" },
    { key = "frostResist", label = "Frost resistance", group = "Resistance" },
    { key = "shadowResist", label = "Shadow resistance", group = "Resistance" },
}

FW.StatByKey = {}
for _, definition in ipairs(FW.StatDefinitions) do
    FW.StatByKey[definition.key] = definition
end
