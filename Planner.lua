-- CoADamage Experiment Planner
-- Uses stored cast sessions to recommend the next controlled experiment.

local function SafeNumber(value)
    if type(value) == "number" then
        return value
    end

    return 0
end

local function GetWeaponAverage(snapshot)
    snapshot = snapshot or {}

    return (
        SafeNumber(snapshot.weaponMin)
        + SafeNumber(snapshot.weaponMax)
    ) / 2
end

local PLAN_PREDICTORS = {
    {
        key = "attackPower",
        label = "Attack Power"
    },
    {
        key = "rangedAttackPower",
        label = "Ranged Attack Power"
    },
    {
        key = "weaponAverage",
        label = "Weapon Damage"
    },
    {
        key = "spellPower",
        label = "Spell Power"
    }
}

local function GetPredictorValue(session, key)
    local snapshot =
        session.snapshot or {}

    if key == "weaponAverage" then
        return GetWeaponAverage(snapshot)
    end

    return SafeNumber(snapshot[key])
end

local function GetRange(sessions, key)
    local minimum = nil
    local maximum = nil
    local distinct = {}

    for _, session in ipairs(sessions or {}) do
        local value =
            GetPredictorValue(
                session,
                key
            )

        if minimum == nil
            or value < minimum then

            minimum = value
        end

        if maximum == nil
            or value > maximum then

            maximum = value
        end

        distinct[tostring(value)] = true
    end

    local distinctCount = 0

    for _ in pairs(distinct) do
        distinctCount =
            distinctCount + 1
    end

    return {
        minimum = minimum or 0,
        maximum = maximum or 0,
        span =
            (maximum or 0)
            - (minimum or 0),
        distinctCount = distinctCount
    }
end

local function SessionIsClean(session)
    if type(session) ~= "table"
        or type(session.snapshot) ~= "table"
        or type(session.totalDamage) ~= "number"
        or session.totalDamage <= 0
        or SafeNumber(session.directHits) <= 0 then

        return false
    end

    for _, event in ipairs(
        session.damageEvents or {}
    ) do
        if event.critical
            or SafeNumber(event.resisted) > 0
            or SafeNumber(event.blocked) > 0
            or SafeNumber(event.absorbed) > 0 then

            return false
        end
    end

    return true
end

function CoA:BuildExperimentPlan(spellID)
    if type(spellID) ~= "number" then
        return nil, "Invalid spell ID."
    end

    local spell =
        CoADamageDB
        and CoADamageDB.spells
        and CoADamageDB.spells[spellID]

    if not spell then
        return nil,
            "No data recorded for spell ID "
            .. tostring(spellID)
            .. "."
    end

    local cleanSessions = {}

    for _, session in ipairs(
        spell.sessions or {}
    ) do
        if SessionIsClean(session) then
            cleanSessions[
                #cleanSessions + 1
            ] = session
        end
    end

    if #cleanSessions == 0 then
        return nil,
            "No clean stored cast sessions available."
    end

    local predictors = {}
    local recommended = nil

    for _, definition in ipairs(
        PLAN_PREDICTORS
    ) do
        local range =
            GetRange(
                cleanSessions,
                definition.key
            )

        local item = {
            key = definition.key,
            label = definition.label,
            minimum = range.minimum,
            maximum = range.maximum,
            span = range.span,
            distinctCount =
                range.distinctCount,
            varies =
                range.distinctCount > 1
                and math.abs(range.span)
                    > 0.000001
        }

        predictors[
            #predictors + 1
        ] = item

        if not item.varies
            and not recommended then

            recommended = item
        end
    end

    if not recommended then
        local weakest = nil

        for _, item in ipairs(predictors) do
            if not weakest
                or item.distinctCount
                    < weakest.distinctCount
                or (
                    item.distinctCount
                        == weakest.distinctCount
                    and item.span
                        < weakest.span
                ) then

                weakest = item
            end
        end

        recommended = weakest
    end

    local instruction

    if recommended.key
        == "weaponAverage" then

        instruction =
            "Equip a weapon with different damage while keeping AP, RAP, SP, buffs, talents, and target unchanged."
    elseif recommended.key
        == "attackPower" then

        instruction =
            "Change Attack Power only, using gear or a controlled buff, while keeping weapon, RAP, SP, buffs, talents, and target unchanged."
    elseif recommended.key
        == "rangedAttackPower" then

        instruction =
            "Change Ranged Attack Power only while keeping weapon, AP, SP, buffs, talents, and target unchanged."
    elseif recommended.key
        == "spellPower" then

        instruction =
            "Change Spell Power only while keeping weapon, AP, RAP, buffs, talents, and target unchanged."
    else
        instruction =
            "Change one predictor only and keep all other conditions unchanged."
    end

    return {
        spellID = spellID,
        spellName =
            spell.name
            or (
                "Spell "
                .. tostring(spellID)
            ),

        sessions =
            #cleanSessions,

        predictors =
            predictors,

        recommended =
            recommended,

        instruction =
            instruction
    }
end
