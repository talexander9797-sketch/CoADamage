local function SafeNumber(value)
    if type(value) == "number" then return value end
    return 0
end

local function Round(value, places)
    local multiplier = 10 ^ (places or 0)
    return math.floor(SafeNumber(value) * multiplier + 0.5) / multiplier
end

local function Average(total, count)
    if not count or count == 0 then return 0 end
    return total / count
end

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function BuffSignature(buffs)
    if type(buffs) ~= "table" or #buffs == 0 then return "none" end
    local copy = {}
    for index = 1, #buffs do copy[index] = tostring(buffs[index]) end
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
        local talentCount = GetNumTalents(tabIndex) or 0
        for talentIndex = 1, talentCount do
            local name, _, _, _, rank = GetTalentInfo(tabIndex, talentIndex)
            if name and type(rank) == "number" and rank > 0 then
                talents[#talents + 1] = table.concat({
                    tostring(tabIndex), tostring(talentIndex),
                    tostring(name), tostring(rank)
                }, ":")
            end
        end
    end

    table.sort(talents)
    if #talents == 0 then return "none" end
    return table.concat(talents, ";")
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
    player = player or {}
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
        talents = observation.talentSignature or "unavailable",
        values = {}
    }

    for _, definition in ipairs(STAT_DEFINITIONS) do
        state.values[definition.key] = Round(GetStatValue(player, definition.key), 2)
    end

    local parts = {
        state.targetName,
        tostring(state.targetLevel),
        state.buffs,
        state.talents
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
    if not state.minimum or damage < state.minimum then state.minimum = damage end
    if not state.maximum or damage > state.maximum then state.maximum = damage end
end

function CoA:BuildAnalysis(spellId)
    local spell = CoADamageDB and CoADamageDB.spells and CoADamageDB.spells[spellId]
    if not spell then return nil end

    local analysis = {
        spellId = spellId,
        spellName = spell.name or ("Spell " .. tostring(spellId)),
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

            local template = BuildState(observation)
            local state = analysis.states[template.key]
            if not state then
                state = template
                analysis.states[state.key] = state
                analysis.stateList[#analysis.stateList + 1] = state
            end
            AddToState(state, damage)
        end

        local player = observation.player or {}
        for _, definition in ipairs(STAT_DEFINITIONS) do
            local value = Round(GetStatValue(player, definition.key), 2)
            local range = analysis.ranges[definition.key]
            if range.min == nil or value < range.min then range.min = value end
            if range.max == nil or value > range.max then range.max = value end
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
    if left.targetName ~= right.targetName
        or left.targetLevel ~= right.targetLevel
        or left.buffs ~= right.buffs
        or left.talents ~= right.talents then
        return false
    end

    for _, definition in ipairs(STAT_DEFINITIONS) do
        if definition.key ~= candidateKey
            and left.values[definition.key] ~= right.values[definition.key] then
            return false
        end
    end

    return true
end

function CoA:EstimateSingleStatScaling(analysis, candidateKey)
    if type(analysis) ~= "table" or type(analysis.stateList) ~= "table" then
        return nil
    end

    local estimates = {}
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
                        local slope = ((right.total / right.count) - (left.total / left.count)) / deltaStat
                        local weight = math.min(left.count, right.count)
                        estimates[#estimates + 1] = { slope = slope, weight = weight }
                        weightedSlope = weightedSlope + slope * weight
                        totalWeight = totalWeight + weight
                        comparisons = comparisons + 1
                    end
                end
            end
        end
    end

    if comparisons == 0 or totalWeight == 0 then return nil end

    local coefficient = weightedSlope / totalWeight
    local weightedVariance = 0

    for _, estimate in ipairs(estimates) do
        local difference = estimate.slope - coefficient
        weightedVariance = weightedVariance + estimate.weight * difference * difference
    end

    weightedVariance = weightedVariance / totalWeight
    local standardDeviation = math.sqrt(weightedVariance)
    local comparisonScore = Clamp(comparisons / 5, 0, 1)
    local sampleScore = Clamp(totalWeight / 100, 0, 1)
    local consistencyScore = 1 / (1 + standardDeviation / (math.abs(coefficient) + 0.05))
    local confidence = Clamp(100 * comparisonScore * sampleScore * consistencyScore, 0, 99.9)

    return {
        coefficient = coefficient,
        comparisons = comparisons,
        weight = totalWeight,
        standardDeviation = standardDeviation,
        confidence = confidence
    }
end

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function VectorDot(left, right)
    local total = 0
    for index = 1, #left do total = total + left[index] * right[index] end
    return total
end

local function VectorLength(vector)
    return math.sqrt(VectorDot(vector, vector))
end

function CoA:SolveLeastSquares(designMatrix, responseVector, weights, options)
    options = options or {}

    if type(designMatrix) ~= "table" or type(responseVector) ~= "table" then
        return nil, "Invalid regression data."
    end

    local inputRows = #designMatrix
    if inputRows == 0 or #responseVector ~= inputRows then
        return nil, "Regression rows and responses do not match."
    end

    local columnCount = type(designMatrix[1]) == "table" and #designMatrix[1] or 0
    if columnCount == 0 then return nil, "Regression has no variables." end

    local effectiveRows = {}

    for rowIndex = 1, inputRows do
        local row = designMatrix[rowIndex]
        local response = responseVector[rowIndex]
        local weight = weights and weights[rowIndex] or 1

        if type(row) ~= "table" or #row ~= columnCount then
            return nil, "Regression matrix is not rectangular."
        end
        if not IsFiniteNumber(response) or not IsFiniteNumber(weight) or weight < 0 then
            return nil, "Regression contains invalid values."
        end
        for columnIndex = 1, columnCount do
            if not IsFiniteNumber(row[columnIndex]) then
                return nil, "Regression contains invalid values."
            end
        end
        if weight > 0 then
            effectiveRows[#effectiveRows + 1] = { row = row, response = response, weight = weight }
        end
    end

    local rowCount = #effectiveRows
    if rowCount < columnCount then
        return nil, "Not enough independent samples: " .. rowCount .. " rows for " .. columnCount .. " coefficients."
    end

    local weightedColumns, weightedResponse, columnScales = {}, {}, {}
    for columnIndex = 1, columnCount do weightedColumns[columnIndex] = {} end

    for rowIndex = 1, rowCount do
        local source = effectiveRows[rowIndex]
        local weightRoot = math.sqrt(source.weight)
        weightedResponse[rowIndex] = source.response * weightRoot
        for columnIndex = 1, columnCount do
            weightedColumns[columnIndex][rowIndex] = source.row[columnIndex] * weightRoot
        end
    end

    for columnIndex = 1, columnCount do
        local scale = VectorLength(weightedColumns[columnIndex])
        if scale <= 0 then
            return nil, "Variable " .. columnIndex .. " has no variation."
        end
        columnScales[columnIndex] = scale
        for rowIndex = 1, rowCount do
            weightedColumns[columnIndex][rowIndex] = weightedColumns[columnIndex][rowIndex] / scale
        end
    end

    local tolerance = options.tolerance or 0.0000000001
    local qColumns, upper = {}, {}
    for rowIndex = 1, columnCount do upper[rowIndex] = {} end

    for columnIndex = 1, columnCount do
        local working = {}
        for rowIndex = 1, rowCount do
            working[rowIndex] = weightedColumns[columnIndex][rowIndex]
        end

        for previousIndex = 1, columnIndex - 1 do
            local projection = VectorDot(qColumns[previousIndex], working)
            upper[previousIndex][columnIndex] = projection
            for rowIndex = 1, rowCount do
                working[rowIndex] = working[rowIndex] - projection * qColumns[previousIndex][rowIndex]
            end
        end

        for previousIndex = 1, columnIndex - 1 do
            local correction = VectorDot(qColumns[previousIndex], working)
            upper[previousIndex][columnIndex] = upper[previousIndex][columnIndex] + correction
            for rowIndex = 1, rowCount do
                working[rowIndex] = working[rowIndex] - correction * qColumns[previousIndex][rowIndex]
            end
        end

        local diagonal = VectorLength(working)
        if diagonal <= tolerance then
            return nil, "Variables are confounded near column " .. columnIndex .. "."
        end

        upper[columnIndex][columnIndex] = diagonal
        qColumns[columnIndex] = {}
        for rowIndex = 1, rowCount do
            qColumns[columnIndex][rowIndex] = working[rowIndex] / diagonal
        end
    end

    local projectedResponse, scaledCoefficients = {}, {}
    for columnIndex = 1, columnCount do
        projectedResponse[columnIndex] = VectorDot(qColumns[columnIndex], weightedResponse)
    end

    for rowIndex = columnCount, 1, -1 do
        local value = projectedResponse[rowIndex]
        for columnIndex = rowIndex + 1, columnCount do
            value = value - upper[rowIndex][columnIndex] * scaledCoefficients[columnIndex]
        end
        local diagonal = upper[rowIndex][rowIndex]
        if math.abs(diagonal) <= tolerance then return nil, "Regression matrix is singular." end
        scaledCoefficients[rowIndex] = value / diagonal
    end

    local coefficients = {}
    for columnIndex = 1, columnCount do
        coefficients[columnIndex] = scaledCoefficients[columnIndex] / columnScales[columnIndex]
    end

    local totalWeight, weightedMeanTotal = 0, 0
    for rowIndex = 1, rowCount do
        local source = effectiveRows[rowIndex]
        totalWeight = totalWeight + source.weight
        weightedMeanTotal = weightedMeanTotal + source.response * source.weight
    end

    local responseMean = weightedMeanTotal / totalWeight
    local residuals = {}
    local residualSumSquares, totalSumSquares, maximumAbsoluteResidual = 0, 0, 0

    for rowIndex = 1, rowCount do
        local source = effectiveRows[rowIndex]
        local predicted = 0
        for columnIndex = 1, columnCount do
            predicted = predicted + source.row[columnIndex] * coefficients[columnIndex]
        end
        local residual = source.response - predicted
        residuals[rowIndex] = residual
        residualSumSquares = residualSumSquares + source.weight * residual * residual
        local meanDifference = source.response - responseMean
        totalSumSquares = totalSumSquares + source.weight * meanDifference * meanDifference
        maximumAbsoluteResidual = math.max(maximumAbsoluteResidual, math.abs(residual))
    end

    local rSquared
    if totalSumSquares <= tolerance then
        rSquared = residualSumSquares <= tolerance and 1 or 0
    else
        rSquared = 1 - residualSumSquares / totalSumSquares
    end

    local degreesOfFreedom = rowCount - columnCount
    local residualVariance = degreesOfFreedom > 0 and residualSumSquares / degreesOfFreedom or nil

    return {
        coefficients = coefficients,
        residuals = residuals,
        rows = rowCount,
        columns = columnCount,
        rank = columnCount,
        degreesOfFreedom = degreesOfFreedom,
        residualSumSquares = residualSumSquares,
        totalSumSquares = totalSumSquares,
        residualVariance = residualVariance,
        rootMeanSquareError = math.sqrt(residualSumSquares / totalWeight),
        maximumAbsoluteResidual = maximumAbsoluteResidual,
        rSquared = rSquared
    }
end

local FORMULA_PREDICTORS = {
    { key = "attackPower", label = "Attack Power" },
    { key = "rangedAttackPower", label = "Ranged Attack Power" },
    { key = "weaponAverage", label = "Weapon Damage" },
    { key = "spellPower", label = "Spell Power" }
}

local function GetFormulaPredictorValue(observation, key)
    return GetStatValue(observation.player or {}, key)
end

local function BuildFormulaContextKey(observation)
    local player = observation.player or {}

    return table.concat({
        tostring(observation.eventType or "unknown"),
        tostring(observation.targetName or "unknown"),
        tostring(observation.targetLevel or 0),
        BuffSignature(player.buffs),
        tostring(observation.talentSignature or "unavailable")
    }, "|")
end

local function IsUsableFormulaObservation(observation)
    if type(observation) ~= "table"
        or type(observation.damage) ~= "number"
        or observation.damage <= 0
        or observation.critical
        or type(observation.player) ~= "table" then
        return false
    end

    return SafeNumber(observation.resisted) == 0
        and SafeNumber(observation.blocked) == 0
        and SafeNumber(observation.absorbed) == 0
end

local function CountVaryingFormulaPredictors(observations)
    local varying = 0

    for _, definition in ipairs(FORMULA_PREDICTORS) do
        local minimum = nil
        local maximum = nil

        for _, observation in ipairs(observations) do
            local value = GetFormulaPredictorValue(
                observation,
                definition.key
            )

            if minimum == nil or value < minimum then
                minimum = value
            end

            if maximum == nil or value > maximum then
                maximum = value
            end
        end

        if minimum ~= nil
            and maximum ~= nil
            and math.abs(maximum - minimum) > 0.000001 then
            varying = varying + 1
        end
    end

    return varying
end

local function FindBestFormulaContext(observations)
    local contexts = {}

    for _, observation in ipairs(observations) do
        if IsUsableFormulaObservation(observation) then
            local key = BuildFormulaContextKey(observation)
            local context = contexts[key]

            if not context then
                context = {
                    key = key,
                    observations = {}
                }
                contexts[key] = context
            end

            context.observations[#context.observations + 1] = observation
        end
    end

    local best = nil

    for _, context in pairs(contexts) do
        context.varyingPredictors =
            CountVaryingFormulaPredictors(context.observations)

        context.score =
            context.varyingPredictors * 1000000
            + #context.observations

        if not best or context.score > best.score then
            best = context
        end
    end

    return best
end

local function PredictorHasVariation(observations, key)
    local minimum, maximum = nil, nil
    for _, observation in ipairs(observations) do
        local value = GetFormulaPredictorValue(observation, key)
        if minimum == nil or value < minimum then minimum = value end
        if maximum == nil or value > maximum then maximum = value end
    end
    return minimum ~= nil and maximum ~= nil and math.abs(maximum - minimum) > 0.000001,
        minimum, maximum
end

function CoA:BuildFormulaRegressionData(spellID)
    if type(spellID) ~= "number" then return nil, "Invalid spell ID." end

    local spell = CoADamageDB and CoADamageDB.spells and CoADamageDB.spells[spellID]
    if not spell then
        return nil, "No data recorded for spell ID " .. tostring(spellID) .. "."
    end

    local context = FindBestFormulaContext(spell.observations or {})
    if not context then return nil, "No clean non-critical observations available." end

    local predictors = {}
    for _, definition in ipairs(FORMULA_PREDICTORS) do
        local varies, minimum, maximum = PredictorHasVariation(context.observations, definition.key)
        if varies then
            predictors[#predictors + 1] = {
                key = definition.key,
                label = definition.label,
                minimum = minimum,
                maximum = maximum
            }
        end
    end

    if #predictors == 0 then
        local ranges = {}

        for _, definition in ipairs(FORMULA_PREDICTORS) do
            local _, minimum, maximum =
                PredictorHasVariation(
                    context.observations,
                    definition.key
                )

            ranges[#ranges + 1] =
                definition.label
                .. "="
                .. tostring(minimum or 0)
                .. "-"
                .. tostring(maximum or 0)
        end

        return nil,
            "No predictor varies in the selected context. "
            .. table.concat(ranges, ", ")
    end

    local coefficientCount = 1 + #predictors
    if #context.observations <= coefficientCount then
        return nil, "Not enough samples: " .. #context.observations
            .. " clean hits for " .. coefficientCount .. " coefficients."
    end

    local designMatrix, responseVector = {}, {}
    for rowIndex, observation in ipairs(context.observations) do
        local row = { 1 }
        for _, predictor in ipairs(predictors) do
            row[#row + 1] = GetFormulaPredictorValue(observation, predictor.key)
        end
        designMatrix[rowIndex] = row
        responseVector[rowIndex] = observation.damage
    end

    local coefficientDefinitions = {
        { key = "baseDamage", label = "Base Damage" }
    }
    for _, predictor in ipairs(predictors) do
        coefficientDefinitions[#coefficientDefinitions + 1] = predictor
    end

    return {
        spellID = spellID,
        spellName = spell.name or ("Spell " .. tostring(spellID)),
        contextKey = context.key,
        contextCount = 1,
        varyingPredictorCount = context.varyingPredictors or #predictors,
        observations = context.observations,
        samples = #context.observations,
        predictors = predictors,
        coefficientDefinitions = coefficientDefinitions,
        designMatrix = designMatrix,
        responseVector = responseVector
    }
end

function CoA:EstimateFormula(spellID)
    local regressionData, errorMessage = self:BuildFormulaRegressionData(spellID)
    if not regressionData then return nil, errorMessage end

    local result, solveError = self:SolveLeastSquares(
        regressionData.designMatrix,
        regressionData.responseVector
    )
    if not result then return nil, solveError end

    result.spellID = spellID
    result.spellName = regressionData.spellName
    result.samples = regressionData.samples
    result.predictors = regressionData.predictors
    result.coefficientDefinitions = regressionData.coefficientDefinitions
    result.contextKey = regressionData.contextKey
    return result
end

function CoA:GetStatDefinitions()
    return STAT_DEFINITIONS
end

--------------------------------------------------
-- Experiment Manager
--------------------------------------------------

CoA.Experiment = CoA.Experiment or {}
CoA.Experiment.activeBySpell = CoA.Experiment.activeBySpell or {}
CoA.Experiment.lastActive = CoA.Experiment.lastActive or nil
CoA.Experiment.current = CoA.Experiment.current or nil

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
        "talents=" .. tostring(observation.talentSignature or "unavailable")
    }
    return table.concat(parts, "|")
end

local function FindExperimentChangeReason(oldObservation, newObservation)
    if not oldObservation then return "First observation" end
    local oldPlayer = oldObservation.player or {}
    local newPlayer = newObservation.player or {}

    if oldObservation.talentSignature ~= newObservation.talentSignature then return "Talents changed" end
    if oldObservation.targetGUID ~= newObservation.targetGUID then return "Target changed" end
    if oldObservation.targetLevel ~= newObservation.targetLevel then return "Target level changed" end

    if Round(oldPlayer.weaponMin, 2) ~= Round(newPlayer.weaponMin, 2)
        or Round(oldPlayer.weaponMax, 2) ~= Round(newPlayer.weaponMax, 2)
        or Round(oldPlayer.offhandMin, 2) ~= Round(newPlayer.offhandMin, 2)
        or Round(oldPlayer.offhandMax, 2) ~= Round(newPlayer.offhandMax, 2) then
        return "Weapon damage changed"
    end

    if Round(oldPlayer.attackPower, 2) ~= Round(newPlayer.attackPower, 2) then return "Attack Power changed" end
    if Round(oldPlayer.rangedAttackPower, 2) ~= Round(newPlayer.rangedAttackPower, 2) then return "Ranged Attack Power changed" end
    if Round(oldPlayer.spellPower, 2) ~= Round(newPlayer.spellPower, 2) then return "Spell Power changed" end

    if Round(oldPlayer.strength, 2) ~= Round(newPlayer.strength, 2)
        or Round(oldPlayer.agility, 2) ~= Round(newPlayer.agility, 2)
        or Round(oldPlayer.intellect, 2) ~= Round(newPlayer.intellect, 2) then
        return "Primary stats changed"
    end

    if BuffSignature(oldPlayer.buffs) ~= BuffSignature(newPlayer.buffs) then return "Buffs changed" end
    return "Conditions changed"
end

function CoA.Experiment:Initialize()
    CoADamageDB.experiments = CoADamageDB.experiments or {}
    CoADamageDB.nextExperimentID = CoADamageDB.nextExperimentID or 1
    self.activeBySpell = {}
    self.lastActive = nil
    self.current = nil
end

function CoA.Experiment:GetTalentSignature()
    return BuildTalentSignature()
end

function CoA.Experiment:Create(spellID, observation, reason)
    local id = CoADamageDB.nextExperimentID or 1
    CoADamageDB.nextExperimentID = id + 1

    local experiment = {
        id = id,
        spellID = spellID,
        spellName = observation.spellName or ("Spell " .. tostring(spellID)),
        started = observation.timestamp or time(),
        ended = nil,
        reason = reason or "Automatic",
        fingerprint = BuildExperimentFingerprint(observation),
        targetGUID = observation.targetGUID,
        targetName = observation.targetName,
        targetLevel = observation.targetLevel,
        talentSignature = observation.talentSignature,
        snapshotSource = observation.snapshotSource,
        observations = {},
        normalHits = 0,
        criticalHits = 0,
        totalDamage = 0
    }

    CoADamageDB.experiments[id] = experiment
    self.activeBySpell[spellID] = experiment
    self.lastActive = experiment
    self.current = experiment

    if CoA.debug then
        print(string.format(
            "|cff33ff99CoADamage:|r started experiment #%d for %s - %s",
            experiment.id, experiment.spellName, experiment.reason
        ))
    end

    return experiment
end

function CoA.Experiment:AddObservation(spellID, observation)
    if type(spellID) ~= "number" or type(observation) ~= "table" or not CoADamageDB then return end

    CoADamageDB.experiments = CoADamageDB.experiments or {}
    CoADamageDB.nextExperimentID = CoADamageDB.nextExperimentID or 1
    observation.talentSignature = observation.talentSignature or BuildTalentSignature()

    local fingerprint = BuildExperimentFingerprint(observation)
    local active = self.activeBySpell[spellID]

    if active and not CoADamageDB.experiments[active.id] then
        active = nil
        self.activeBySpell[spellID] = nil
    end

    if not active then
        active = self:Create(spellID, observation, "First observation")
    elseif active.fingerprint ~= fingerprint then
        active.ended = observation.timestamp or time()
        local previous = active.observations[#active.observations]
        active = self:Create(spellID, observation, FindExperimentChangeReason(previous, observation))
    end

    table.insert(active.observations, observation)
    local limit = CoA.MAX_OBSERVATIONS_PER_EXPERIMENT or 1000
    while #active.observations > limit do table.remove(active.observations, 1) end

    active.lastUpdated = observation.timestamp or time()
    active.totalDamage = active.totalDamage + SafeNumber(observation.damage)
    if observation.critical then
        active.criticalHits = active.criticalHits + 1
    else
        active.normalHits = active.normalHits + 1
    end

    self.lastActive = active
    self.current = active
end

function CoA.Experiment:GetCurrent(spellID)
    if spellID then return self.activeBySpell[spellID] end
    return self.lastActive or self.current
end

function CoA.Experiment:GetAllForSpell(spellID)
    local results = {}
    for _, experiment in pairs((CoADamageDB and CoADamageDB.experiments) or {}) do
        if experiment.spellID == spellID then results[#results + 1] = experiment end
    end
    table.sort(results, function(left, right) return left.id < right.id end)
    return results
end