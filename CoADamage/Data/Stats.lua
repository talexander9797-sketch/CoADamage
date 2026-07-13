local function SafeNumber(value)
    if type(value) == "number" then
        return value
    end
    return 0
end

local function GetPrimaryStats()
    local stats = {}
    for index = 1, 5 do
        local base, effective, positive, negative = UnitStat("player", index)
        stats[index] = SafeNumber(effective or base)
    end
    return stats
end

local function GetHighestSpellPower()
    local highest = 0
    if type(GetSpellBonusDamage) == "function" then
        for school = 2, 7 do
            local value = SafeNumber(GetSpellBonusDamage(school))
            if value > highest then
                highest = value
            end
        end
    end
    return highest
end

local function GetBuffNames()
    local buffs = {}
    if type(UnitBuff) ~= "function" then
        return buffs
    end

    for index = 1, 40 do
        local name = UnitBuff("player", index)
        if not name then
            break
        end
        buffs[#buffs + 1] = name
    end
    return buffs
end

function CoA:CapturePlayerSnapshot()
    local primary = GetPrimaryStats()

    local apBase, apPositive, apNegative = UnitAttackPower("player")
    local attackPower = SafeNumber(apBase) + SafeNumber(apPositive) + SafeNumber(apNegative)

    local rangedAttackPower = 0
    if type(UnitRangedAttackPower) == "function" then
        local rBase, rPositive, rNegative = UnitRangedAttackPower("player")
        rangedAttackPower = SafeNumber(rBase) + SafeNumber(rPositive) + SafeNumber(rNegative)
    end

    local mainMin, mainMax, offMin, offMax = UnitDamage("player")

    return {
        level = UnitLevel("player") or 0,
        strength = primary[1] or 0,
        agility = primary[2] or 0,
        stamina = primary[3] or 0,
        intellect = primary[4] or 0,
        spirit = primary[5] or 0,
        attackPower = attackPower,
        rangedAttackPower = rangedAttackPower,
        spellPower = GetHighestSpellPower(),
        weaponMin = SafeNumber(mainMin),
        weaponMax = SafeNumber(mainMax),
        offhandMin = SafeNumber(offMin),
        offhandMax = SafeNumber(offMax),
        buffs = GetBuffNames()
    }
end
