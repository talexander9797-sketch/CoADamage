local function SafeNumber(value)
    if type(value) == "number" then
        return value
    end

    return 0
end

local function Round(value, places)
    local multiplier = 10 ^ (places or 0)

    return math.floor(
        SafeNumber(value) * multiplier + 0.5
    ) / multiplier
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

local function BuildTalentSignature()
    if type(GetNumTalentTabs) ~= "function"
        or type(GetNumTalents) ~= "function"
        or type(GetTalentInfo) ~= "function" then
        return "unavailable"
    end

    local talents = {}
    local tabCount = GetNumTalentTabs() or 0

    for tabIndex = 1, tabCount do
        local talentCount =
            GetNumTalents(tabIndex) or 0

        for talentIndex = 1, talentCount do
            local name, iconTexture, tier, column, rank =
                GetTalentInfo(tabIndex, talentIndex)

            if name
                and type(rank) == "number"
                and rank > 0 then

                talents[#talents + 1] =
                    tostring(tabIndex)
                    .. ":"
                    .. tostring(talentIndex)
                    .. ":"
                    .. tostring(name)
                    .. ":"
                    .. tostring(rank)
            end
        end
    end

    table.sort(talents)

    if #talents == 0 then
        return "none"
    end

    return table.concat(talents, ";")
end

local STAT_DEFINITIONS = {
    {
        key = "attackPower",
        label = "Attack Power",
        short = "AP"
    },
    {
        key = "rangedAttackPower",
        label = "Ranged Attack Power",
        short = "RAP"
    },
    {
        key = "spellPower",
        label = "Spell Power",
        short = "SP"
    },
    {
        key = "strength",
        label = "Strength",
        short = "STR"
    },
    {
        key = "agility",
        label = "Agility",
        short = "AGI"
    },
    {
        key = "intellect",
        label = "Intellect",
        short = "INT"
    },
    {
        key = "weaponAverage",
        label = "Weapon Average",
        short = "Weapon"
    }
}

local function GetStatValue(player, key)
    if key == "weaponAverage" then
        return (
            SafeNumber(player.weaponMin)
            + SafeNumber(player.weaponMax)
        ) / 2
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

        targetName =
            observation.targetName or "Unknown",

        targetLevel =
            observation.targetLevel or 0,

        buffs =
            BuffSignature(player.buffs),

        talents =
            observation.talentSignature
            or "unavailable",

        values = {}
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        state.values[definition.key] =
            Round(
                GetStatValue(
                    player,
                    definition.key
                ),
                2
            )
    end

    local parts = {
        state.targetName,
        tostring(state.targetLevel),
        state.buffs,
        state.talents
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        parts[#parts + 1] =
            definition.key
            .. "="
            .. tostring(
                state.values[definition.key]
            )
    end

    state.key = table.concat(parts, "|")

    return state
end

local function AddToState(state, damage)
    state.count = state.count + 1
    state.total = state.total + damage

    if not state.minimum
        or damage < state.minimum then
        state.minimum = damage
    end

    if not state.maximum
        or damage > state.maximum then
        state.maximum = damage
    end
end

function CoA:BuildAnalysis(spellId)
    local spell =
        CoADamageDB
        and CoADamageDB.spells
        and CoADamageDB.spells[spellId]

    if not spell then
        return nil
    end

    local analysis = {
        spellId = spellId,

        spellName =
            spell.name
            or ("Spell " .. spellId),

        totalSamples =
            spell.hits or 0,

        normalSamples = 0,
        criticalSamples = 0,

        normalTotal = 0,
        criticalTotal = 0,

        states = {},
        stateList = {},
        ranges = {}
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        analysis.ranges[definition.key] = {
            min = nil,
            max = nil
        }
    end

    for _, observation in ipairs(
        spell.observations or {}
    ) do
        local damage =
            SafeNumber(observation.damage)

        if observation.critical then
            analysis.criticalSamples =
                analysis.criticalSamples + 1

            analysis.criticalTotal =
                analysis.criticalTotal + damage
        else
            analysis.normalSamples =
                analysis.normalSamples + 1

            analysis.normalTotal =
                analysis.normalTotal + damage

            local stateTemplate =
                BuildState(observation)

            local state =
                analysis.states[stateTemplate.key]

            if not state then
                state = stateTemplate

                analysis.states[state.key] =
                    state

                analysis.stateList[
                    #analysis.stateList + 1
                ] = state
            end

            AddToState(state, damage)
        end

        local player =
            observation.player or {}

        for _, definition in ipairs(
            STAT_DEFINITIONS
        ) do
            local value =
                Round(
                    GetStatValue(
                        player,
                        definition.key
                    ),
                    2
                )

            local range =
                analysis.ranges[
                    definition.key
                ]

            if not range.min
                or value < range.min then
                range.min = value
            end

            if not range.max
                or value > range.max then
                range.max = value
            end
        end
    end

    analysis.normalAverage =
        Average(
            analysis.normalTotal,
            analysis.normalSamples
        )

    analysis.criticalAverage =
        Average(
            analysis.criticalTotal,
            analysis.criticalSamples
        )

    if analysis.normalAverage > 0
        and analysis.criticalSamples > 0 then

        analysis.critMultiplier =
            analysis.criticalAverage
            / analysis.normalAverage
    end

    return analysis
end

local function StatesMatchExcept(
    left,
    right,
    candidateKey
)
    if left.targetName ~= right.targetName
        or left.targetLevel ~= right.targetLevel
        or left.buffs ~= right.buffs
        or left.talents ~= right.talents then

        return false
    end

    for _, definition in ipairs(
        STAT_DEFINITIONS
    ) do
        if definition.key ~= candidateKey
            and left.values[definition.key]
                ~= right.values[definition.key] then

            return false
        end
    end

    return true
end

local function Clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end

    if value > maximum then
        return maximum
    end

    return value
end

function CoA:EstimateSingleStatScaling(
    analysis,
    candidateKey
)
    local estimates = {}
    local weightedSlope = 0
    local totalWeight = 0
    local comparisons = 0

    for leftIndex = 1, #analysis.stateList do
        local left = analysis.stateList[leftIndex]

        if left.count >= 5 then
            for rightIndex = leftIndex + 1, #analysis.stateList do
                local right = analysis.stateList[rightIndex]

                if right.count >= 5
                    and StatesMatchExcept(
                        left,
                        right,
                        candidateKey
                    ) then

                    local deltaStat =
                        right.values[candidateKey]
                        - left.values[candidateKey]

                    if deltaStat ~= 0 then
                        local leftAverage =
                            left.total / left.count

                        local rightAverage =
                            right.total / right.count

                        local slope =
                            (rightAverage - leftAverage)
                            / deltaStat

                        local weight =
                            math.min(
                                left.count,
                                right.count
                            )

                        estimates[#estimates + 1] = {
                            slope = slope,
                            weight = weight
                        }

                        weightedSlope =
                            weightedSlope + slope * weight

                        totalWeight =
                            totalWeight + weight

                        comparisons =
                            comparisons + 1
                    end
                end
            end
        end
    end

    if comparisons == 0 or totalWeight == 0 then
        return nil
    end

    local coefficient =
        weightedSlope / totalWeight

    local weightedVariance = 0

    for _, estimate in ipairs(estimates) do
        local difference =
            estimate.slope - coefficient

        weightedVariance =
            weightedVariance
            + estimate.weight
            * difference
            * difference
    end

    weightedVariance =
        weightedVariance / totalWeight

    local standardDeviation =
        math.sqrt(weightedVariance)

    -- These scores are intentionally conservative.
    local comparisonScore =
        Clamp(comparisons / 5, 0, 1)

    local sampleScore =
        Clamp(totalWeight / 100, 0, 1)

    local scale =
        math.abs(coefficient) + 0.05

    local consistencyScore =
        1 / (1 + standardDeviation / scale)

    local confidence =
        100
        * comparisonScore
        * sampleScore
        * consistencyScore

    confidence =
        Clamp(confidence, 0, 99.9)

    return {
        coefficient = coefficient,
        comparisons = comparisons,
        weight = totalWeight,
        standardDeviation = standardDeviation,
        confidence = confidence
    }
end
function CoA:GetStatDefinitions()
    return STAT_DEFINITIONS
end

--------------------------------------------------
-- Experiment Manager
--------------------------------------------------

CoA.Experiment = CoA.Experiment or {}

CoA.Experiment.activeBySpell =
    CoA.Experiment.activeBySpell or {}

CoA.Experiment.lastActive =
    CoA.Experiment.lastActive or nil

CoA.Experiment.current =
    CoA.Experiment.current or nil

local function BuildExperimentFingerprint(observation)
    local player = observation.player or {}

    local parts = {
        "targetGUID=" .. tostring(observation.targetGUID or "none"),
        "targetLevel=" .. tostring(observation.targetLevel or 0),

        "AP=" .. tostring(Round(player.attackPower, 2)),
        "RAP=" .. tostring(Round(player.rangedAttackPower, 2)),
        "SP=" .. tostring(Round(player.spellPower, 2)),

        "STR=" .. tostring(Round(player.strength, 2)),
        "AGI=" .. tostring(Round(player.agility, 2)),
        "INT=" .. tostring(Round(player.intellect, 2)),

        "weaponMin=" .. tostring(Round(player.weaponMin, 2)),
        "weaponMax=" .. tostring(Round(player.weaponMax, 2)),
        "offhandMin=" .. tostring(Round(player.offhandMin, 2)),
        "offhandMax=" .. tostring(Round(player.offhandMax, 2)),

        "buffs=" .. BuffSignature(player.buffs),
        "talents=" .. tostring(
            observation.talentSignature or "unavailable"
        )
    }

    return table.concat(parts, "|")
end
local function FindExperimentChangeReason(
    oldObservation,
    newObservation
)
    if not oldObservation then
        return "First observation"
    end

    local oldPlayer =
        oldObservation.player or {}

    local newPlayer =
        newObservation.player or {}

    if oldObservation.talentSignature
        ~= newObservation.talentSignature then

        return "Talents changed"
    end

    if oldObservation.targetGUID
        ~= newObservation.targetGUID then

        return "Target changed"
    end

    if oldObservation.targetLevel
        ~= newObservation.targetLevel then

        return "Target level changed"
    end

    if Round(oldPlayer.weaponMin, 2)
            ~= Round(newPlayer.weaponMin, 2)
        or Round(oldPlayer.weaponMax, 2)
            ~= Round(newPlayer.weaponMax, 2)
        or Round(oldPlayer.offhandMin, 2)
            ~= Round(newPlayer.offhandMin, 2)
        or Round(oldPlayer.offhandMax, 2)
            ~= Round(newPlayer.offhandMax, 2) then

        return "Weapon damage changed"
    end

    if Round(oldPlayer.attackPower, 2)
        ~= Round(newPlayer.attackPower, 2) then

        return "Attack Power changed"
    end

    if Round(oldPlayer.rangedAttackPower, 2)
        ~= Round(newPlayer.rangedAttackPower, 2) then

        return "Ranged Attack Power changed"
    end

    if Round(oldPlayer.spellPower, 2)
        ~= Round(newPlayer.spellPower, 2) then

        return "Spell Power changed"
    end

    if Round(oldPlayer.strength, 2)
            ~= Round(newPlayer.strength, 2)
        or Round(oldPlayer.agility, 2)
            ~= Round(newPlayer.agility, 2)
        or Round(oldPlayer.intellect, 2)
            ~= Round(newPlayer.intellect, 2) then

        return "Primary stats changed"
    end

    if BuffSignature(oldPlayer.buffs)
        ~= BuffSignature(newPlayer.buffs) then

        return "Buffs changed"
    end

    return "Conditions changed"
end

function CoA.Experiment:Initialize()
    CoADamageDB.experiments =
        CoADamageDB.experiments or {}

    CoADamageDB.nextExperimentID =
        CoADamageDB.nextExperimentID or 1

    self.activeBySpell = {}
    self.lastActive = nil
    self.current = nil
end

function CoA.Experiment:GetTalentSignature()
    return BuildTalentSignature()
end

function CoA.Experiment:Create(
    spellID,
    observation,
    reason
)
    local id =
        CoADamageDB.nextExperimentID or 1

    CoADamageDB.nextExperimentID =
        id + 1

    local experiment = {
        id = id,
        spellID = spellID,

        spellName =
            observation.spellName
            or (
                "Spell "
                .. tostring(spellID)
            ),

        started =
            observation.timestamp or time(),

        ended = nil,

        reason =
            reason or "Automatic",

        fingerprint =
            BuildExperimentFingerprint(
                observation
            ),

        targetGUID =
            observation.targetGUID,

        targetName =
            observation.targetName,

        targetLevel =
            observation.targetLevel,

        talentSignature =
            observation.talentSignature,

        snapshotSource =
            observation.snapshotSource,

        observations = {},

        normalHits = 0,
        criticalHits = 0,
        totalDamage = 0
    }

    CoADamageDB.experiments[id] =
        experiment

    self.activeBySpell[spellID] =
        experiment

    self.lastActive = experiment
    self.current = experiment

    if CoA.debug then
        print(string.format(
            "|cff33ff99CoADamage:|r started experiment #%d for %s - %s",
            experiment.id,
            experiment.spellName,
            experiment.reason
        ))
    end

    return experiment
end

function CoA.Experiment:AddObservation(
    spellID,
    observation
)
    if type(spellID) ~= "number"
        or type(observation) ~= "table" then
        return
    end

    if not CoADamageDB then
        return
    end

    CoADamageDB.experiments =
        CoADamageDB.experiments or {}

    CoADamageDB.nextExperimentID =
        CoADamageDB.nextExperimentID or 1

    observation.talentSignature =
        observation.talentSignature
        or BuildTalentSignature()

    local fingerprint =
        BuildExperimentFingerprint(
            observation
        )

    local active =
        self.activeBySpell[spellID]

    -- Discard stale references after /coa clear.
    if active
        and not CoADamageDB.experiments[
            active.id
        ] then

        active = nil
        self.activeBySpell[spellID] = nil
    end

    if not active then
        active = self:Create(
            spellID,
            observation,
            "First observation"
        )

    elseif active.fingerprint
        ~= fingerprint then

        active.ended =
            observation.timestamp or time()

        local previous =
            active.observations[
                #active.observations
            ]

        local reason =
            FindExperimentChangeReason(
                previous,
                observation
            )

        active = self:Create(
            spellID,
            observation,
            reason
        )
    end

    table.insert(
        active.observations,
        observation
    )

    local limit =
        CoA.MAX_OBSERVATIONS_PER_EXPERIMENT
        or 1000

    while #active.observations > limit do
        table.remove(
            active.observations,
            1
        )
    end

    active.lastUpdated =
        observation.timestamp or time()

    active.totalDamage =
        active.totalDamage
        + SafeNumber(
            observation.damage
        )

    if observation.critical then
        active.criticalHits =
            active.criticalHits + 1
    else
        active.normalHits =
            active.normalHits + 1
    end

    self.lastActive = active
    self.current = active
end

function CoA.Experiment:GetCurrent(
    spellID
)
    if spellID then
        return self.activeBySpell[
            spellID
        ]
    end

    return self.lastActive
        or self.current
end

function CoA.Experiment:GetAllForSpell(
    spellID
)
    local results = {}

    for _, experiment in pairs(
        CoADamageDB.experiments or {}
    ) do
        if experiment.spellID
            == spellID then

            results[
                #results + 1
            ] = experiment
        end
    end

    table.sort(
        results,
        function(left, right)
            return left.id < right.id
        end
    )

    return results
end
