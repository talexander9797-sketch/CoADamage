local function SafeNumber(value)
    if type(value) == "number" then
        return value
    end
    return 0
end

local function Round(value, places)
    local multiplier = 10 ^ (places or 0)
    return math.floor(SafeNumber(value) * multiplier + 0.5) / multiplier
end

local function Average(total, count)
    if not count or count == 0 then
        return 0
    end
    return total / count
end

local function BuffSignature(buffs)
    if type(buffs) ~= "table" or #buffs == 0 then
        return "none"
    end

    local copy = {}
    for index = 1, #buffs do
        copy[index] = tostring(buffs[index])
    end
    table.sort(copy)
    return table.concat(copy, ";")
end

local STAT_DEFINITIONS = {
    { key = "attackPower", label = "Attack Power", short = "AP" },
    { key = "rangedAttackPower", label = "Ranged Attack Power", short = "RAP" },
    { key = "spellPower", label = "Spell Power", short = "SP" },
    { key = "strength", label = "Strength", short = "STR" },
    { key = "agility", label = "Agility", short = "AGI" },
    { key = "intellect", label = "Intellect", short = "INT" },
    { key = "weaponAverage", label = "Weapon Average", short = "Weapon" }
}

local function GetStatValue(player, key)
    if key == "weaponAverage" then
        return (SafeNumber(player.weaponMin) + SafeNumber(player.weaponMax)) / 2
    end
    return SafeNumber(player[key])
end

local function BuildState(observation)
    local player = observation.player or {}
    local state = {
        count = 0,
        total = 0,
        minimum = nil,
        maximum = nil,
        targetName = observation.targetName or "Unknown",
        targetLevel = observation.targetLevel or 0,
        buffs = BuffSignature(player.buffs),
        values = {}
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        state.values[definition.key] = Round(GetStatValue(player, definition.key), 2)
    end

    local parts = {
        state.targetName,
        tostring(state.targetLevel),
        state.buffs
    }
    for _, definition in ipairs(STAT_DEFINITIONS) do
        parts[#parts + 1] = definition.key .. "=" .. tostring(state.values[definition.key])
    end
    state.key = table.concat(parts, "|")
    return state
end

local function AddToState(state, damage)
    state.count = state.count + 1
    state.total = state.total + damage
    if not state.minimum or damage < state.minimum then
        state.minimum = damage
    end
    if not state.maximum or damage > state.maximum then
        state.maximum = damage
    end
end

function CoA:BuildAnalysis(spellId)
    local spell = CoADamageDB and CoADamageDB.spells and CoADamageDB.spells[spellId]
    if not spell then
        return nil
    end

    local analysis = {
        spellId = spellId,
        spellName = spell.name or ("Spell " .. spellId),
        totalSamples = spell.hits or 0,
        normalSamples = 0,
        criticalSamples = 0,
        normalTotal = 0,
        criticalTotal = 0,
        states = {},
        stateList = {},
        ranges = {}
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        analysis.ranges[definition.key] = { min = nil, max = nil }
    end

    for _, observation in ipairs(spell.observations or {}) do
        local damage = SafeNumber(observation.damage)
        if observation.critical then
            analysis.criticalSamples = analysis.criticalSamples + 1
            analysis.criticalTotal = analysis.criticalTotal + damage
        else
            analysis.normalSamples = analysis.normalSamples + 1
            analysis.normalTotal = analysis.normalTotal + damage

            local stateTemplate = BuildState(observation)
            local state = analysis.states[stateTemplate.key]
            if not state then
                state = stateTemplate
                analysis.states[state.key] = state
                analysis.stateList[#analysis.stateList + 1] = state
            end
            AddToState(state, damage)
        end

        local player = observation.player or {}
        for _, definition in ipairs(STAT_DEFINITIONS) do
            local value = Round(GetStatValue(player, definition.key), 2)
            local range = analysis.ranges[definition.key]
            if not range.min or value < range.min then
                range.min = value
            end
            if not range.max or value > range.max then
                range.max = value
            end
        end
    end

    analysis.normalAverage = Average(analysis.normalTotal, analysis.normalSamples)
    analysis.criticalAverage = Average(analysis.criticalTotal, analysis.criticalSamples)
    if analysis.normalAverage > 0 and analysis.criticalSamples > 0 then
        analysis.critMultiplier = analysis.criticalAverage / analysis.normalAverage
    end

    return analysis
end

local function StatesMatchExcept(left, right, candidateKey)
    if left.targetName ~= right.targetName or left.targetLevel ~= right.targetLevel or left.buffs ~= right.buffs then
        return false
    end

    for _, definition in ipairs(STAT_DEFINITIONS) do
        if definition.key ~= candidateKey and left.values[definition.key] ~= right.values[definition.key] then
            return false
        end
    end
    return true
end

function CoA:EstimateSingleStatScaling(analysis, candidateKey)
    local weightedSlope = 0
    local totalWeight = 0
    local comparisons = 0

    for leftIndex = 1, #analysis.stateList do
        local left = analysis.stateList[leftIndex]
        if left.count >= 5 then
            for rightIndex = leftIndex + 1, #analysis.stateList do
                local right = analysis.stateList[rightIndex]
                if right.count >= 5 and StatesMatchExcept(left, right, candidateKey) then
                    local deltaStat = right.values[candidateKey] - left.values[candidateKey]
                    if deltaStat ~= 0 then
                        local leftAverage = left.total / left.count
                        local rightAverage = right.total / right.count
                        local slope = (rightAverage - leftAverage) / deltaStat
                        local weight = math.min(left.count, right.count)
                        weightedSlope = weightedSlope + slope * weight
                        totalWeight = totalWeight + weight
                        comparisons = comparisons + 1
                    end
                end
            end
        end
    end

    if comparisons == 0 or totalWeight == 0 then
        return nil
    end

    return {
        coefficient = weightedSlope / totalWeight,
        comparisons = comparisons,
        weight = totalWeight
    }
end

function CoA:GetStatDefinitions()
    return STAT_DEFINITIONS
end
