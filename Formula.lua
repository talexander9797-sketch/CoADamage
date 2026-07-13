local function SafeNumber(value)
    if type(value) == "number" then
        return value
    end

    return 0
end

local function IsFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value ~= math.huge
        and value ~= -math.huge
end

local function BuffSignature(buffs)
    if type(buffs) ~= "table" then
        return "none"
    end

    local values = {}

    for key, value in pairs(buffs) do
        if type(key) == "number" then
            values[#values + 1] = tostring(value)
        elseif value then
            values[#values + 1] = tostring(key)
        end
    end

    if #values == 0 then
        return "none"
    end

    table.sort(values)

    return table.concat(values, ";")
end

local function GetWeaponAverage(snapshot)
    snapshot = snapshot or {}

    return (
        SafeNumber(snapshot.weaponMin)
        + SafeNumber(snapshot.weaponMax)
    ) / 2
end

local function GetPredictorValue(session, key)
    local snapshot =
        session.snapshot or {}

    if key == "weaponAverage" then
        return GetWeaponAverage(snapshot)
    end

    return SafeNumber(snapshot[key])
end

local function VectorDot(left, right)
    local total = 0

    for index = 1, #left do
        total =
            total
            + left[index] * right[index]
    end

    return total
end

local function VectorLength(vector)
    return math.sqrt(
        VectorDot(vector, vector)
    )
end

local FORMULA_PREDICTORS = {
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

local function SessionHasMitigation(session)
    for _, event in ipairs(
        session.damageEvents or {}
    ) do
        if SafeNumber(event.resisted) > 0
            or SafeNumber(event.blocked) > 0
            or SafeNumber(event.absorbed) > 0 then

            return true
        end
    end

    return false
end

local function SessionHasCriticalDamage(session)
    for _, event in ipairs(
        session.damageEvents or {}
    ) do
        if event.critical then
            return true
        end
    end

    return false
end

local function IsUsableFormulaSession(session)
    if type(session) ~= "table"
        or type(session.snapshot) ~= "table"
        or type(session.totalDamage) ~= "number"
        or session.totalDamage <= 0 then

        return false
    end

    if SafeNumber(session.directHits) <= 0 then
        return false
    end

    if #(session.damageEvents or {}) == 0 then
        return false
    end

    if SessionHasCriticalDamage(session)
        or SessionHasMitigation(session) then

        return false
    end

    return true
end

local function GetSessionTargetData(session)
    local firstEvent =
        session.damageEvents
        and session.damageEvents[1]
        or {}

    return
        firstEvent.targetName or "unknown",
        firstEvent.targetLevel or 0
end

local function BuildSessionContextKey(session)
    local snapshot =
        session.snapshot or {}

    local targetName, targetLevel =
        GetSessionTargetData(session)

    return table.concat({
        tostring(targetName),
        tostring(targetLevel),
        BuffSignature(snapshot.buffs),
        tostring(
            session.talentSignature
            or snapshot.talentSignature
            or "unavailable"
        )
    }, "|")
end

local function PredictorRange(sessions, key)
    local minimum = nil
    local maximum = nil

    for _, session in ipairs(sessions) do
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
    end

    return minimum, maximum
end

local function PredictorVaries(sessions, key)
    local minimum, maximum =
        PredictorRange(
            sessions,
            key
        )

    return minimum ~= nil
        and maximum ~= nil
        and math.abs(maximum - minimum)
            > 0.000001,
        minimum,
        maximum
end

local function CountVaryingPredictors(sessions)
    local count = 0

    for _, definition in ipairs(
        FORMULA_PREDICTORS
    ) do
        local varies =
            PredictorVaries(
                sessions,
                definition.key
            )

        if varies then
            count = count + 1
        end
    end

    return count
end

local function CalculateCorrelation(
    sessions,
    leftKey,
    rightKey
)
    local count = #sessions

    if count < 2 then
        return nil
    end

    local leftMean = 0
    local rightMean = 0

    for _, session in ipairs(sessions) do
        leftMean =
            leftMean
            + GetPredictorValue(
                session,
                leftKey
            )

        rightMean =
            rightMean
            + GetPredictorValue(
                session,
                rightKey
            )
    end

    leftMean = leftMean / count
    rightMean = rightMean / count

    local numerator = 0
    local leftVariance = 0
    local rightVariance = 0

    for _, session in ipairs(sessions) do
        local leftDifference =
            GetPredictorValue(
                session,
                leftKey
            ) - leftMean

        local rightDifference =
            GetPredictorValue(
                session,
                rightKey
            ) - rightMean

        numerator =
            numerator
            + leftDifference
            * rightDifference

        leftVariance =
            leftVariance
            + leftDifference
            * leftDifference

        rightVariance =
            rightVariance
            + rightDifference
            * rightDifference
    end

    if leftVariance <= 0
        or rightVariance <= 0 then

        return nil
    end

    return numerator
        / math.sqrt(
            leftVariance
            * rightVariance
        )
end

local function FindConfoundedPredictors(
    sessions,
    predictors
)
    local relationships = {}

    for leftIndex = 1, #predictors do
        for rightIndex =
            leftIndex + 1,
            #predictors
        do
            local left =
                predictors[leftIndex]

            local right =
                predictors[rightIndex]

            local correlation =
                CalculateCorrelation(
                    sessions,
                    left.key,
                    right.key
                )

            if correlation
                and math.abs(correlation)
                    >= 0.999999 then

                relationships[
                    #relationships + 1
                ] = {
                    left = left,
                    right = right,
                    correlation =
                        correlation
                }
            end
        end
    end

    return relationships
end

local function BuildConfoundingError(
    relationships
)
    if #relationships == 0 then
        return nil
    end

    local parts = {
        "Regression cannot separate "
    }

    for index, relationship in ipairs(
        relationships
    ) do
        if index > 1 then
            parts[#parts + 1] = "; "
        end

        parts[#parts + 1] =
            relationship.left.label
            .. " and "
            .. relationship.right.label
            .. " changed together"
            .. " (correlation "
            .. string.format(
                "%.4f",
                relationship.correlation
            )
            .. ")"
    end

    parts[#parts + 1] =
        ". Change only one of these predictors while keeping the other unchanged."

    return table.concat(parts)
end

local function FindBestSessionContext(sessions)
    local contexts = {}

    for _, session in ipairs(sessions or {}) do
        if IsUsableFormulaSession(session) then
            local key =
                BuildSessionContextKey(session)

            local context =
                contexts[key]

            if not context then
                context = {
                    key = key,
                    sessions = {}
                }

                contexts[key] = context
            end

            context.sessions[
                #context.sessions + 1
            ] = session
        end
    end

    local best = nil

    for _, context in pairs(contexts) do
        context.varyingPredictors =
            CountVaryingPredictors(
                context.sessions
            )

        context.score =
            context.varyingPredictors
                * 1000000
            + #context.sessions

        if not best
            or context.score > best.score then

            best = context
        end
    end

    return best
end

function CoA:SolveLeastSquares(
    designMatrix,
    responseVector,
    weights,
    options
)
    options = options or {}

    if type(designMatrix) ~= "table"
        or type(responseVector) ~= "table" then

        return nil, "Invalid regression data."
    end

    local inputRows =
        #designMatrix

    if inputRows == 0
        or #responseVector ~= inputRows then

        return nil,
            "Regression rows and responses do not match."
    end

    local columnCount =
        type(designMatrix[1]) == "table"
        and #designMatrix[1]
        or 0

    if columnCount == 0 then
        return nil, "Regression has no variables."
    end

    local effectiveRows = {}

    for rowIndex = 1, inputRows do
        local row =
            designMatrix[rowIndex]

        local response =
            responseVector[rowIndex]

        local weight =
            weights
            and weights[rowIndex]
            or 1

        if type(row) ~= "table"
            or #row ~= columnCount then

            return nil,
                "Regression matrix is not rectangular."
        end

        if not IsFiniteNumber(response)
            or not IsFiniteNumber(weight)
            or weight < 0 then

            return nil,
                "Regression contains invalid values."
        end

        for columnIndex = 1, columnCount do
            if not IsFiniteNumber(
                row[columnIndex]
            ) then
                return nil,
                    "Regression contains invalid values."
            end
        end

        if weight > 0 then
            effectiveRows[
                #effectiveRows + 1
            ] = {
                row = row,
                response = response,
                weight = weight
            }
        end
    end

    local rowCount =
        #effectiveRows

    if rowCount < columnCount then
        return nil,
            "Not enough independent sessions: "
            .. tostring(rowCount)
            .. " rows for "
            .. tostring(columnCount)
            .. " coefficients."
    end

    local weightedColumns = {}
    local weightedResponse = {}
    local columnScales = {}

    for columnIndex = 1, columnCount do
        weightedColumns[columnIndex] = {}
    end

    for rowIndex = 1, rowCount do
        local source =
            effectiveRows[rowIndex]

        local weightRoot =
            math.sqrt(source.weight)

        weightedResponse[rowIndex] =
            source.response * weightRoot

        for columnIndex = 1, columnCount do
            weightedColumns[columnIndex][rowIndex] =
                source.row[columnIndex]
                * weightRoot
        end
    end

    for columnIndex = 1, columnCount do
        local scale =
            VectorLength(
                weightedColumns[columnIndex]
            )

        if scale <= 0 then
            return nil,
                "Variable "
                .. tostring(columnIndex)
                .. " has no variation."
        end

        columnScales[columnIndex] = scale

        for rowIndex = 1, rowCount do
            weightedColumns[columnIndex][rowIndex] =
                weightedColumns[columnIndex][rowIndex]
                / scale
        end
    end

    local tolerance =
        options.tolerance
        or 0.0000000001

    local qColumns = {}
    local upper = {}

    for rowIndex = 1, columnCount do
        upper[rowIndex] = {}
    end

    for columnIndex = 1, columnCount do
        local working = {}

        for rowIndex = 1, rowCount do
            working[rowIndex] =
                weightedColumns[columnIndex][rowIndex]
        end

        for previousIndex = 1, columnIndex - 1 do
            local projection =
                VectorDot(
                    qColumns[previousIndex],
                    working
                )

            upper[previousIndex][columnIndex] =
                projection

            for rowIndex = 1, rowCount do
                working[rowIndex] =
                    working[rowIndex]
                    - projection
                    * qColumns[previousIndex][rowIndex]
            end
        end

        for previousIndex = 1, columnIndex - 1 do
            local correction =
                VectorDot(
                    qColumns[previousIndex],
                    working
                )

            upper[previousIndex][columnIndex] =
                upper[previousIndex][columnIndex]
                + correction

            for rowIndex = 1, rowCount do
                working[rowIndex] =
                    working[rowIndex]
                    - correction
                    * qColumns[previousIndex][rowIndex]
            end
        end

        local diagonal =
            VectorLength(working)

        if diagonal <= tolerance then
            return nil,
                "Variables are confounded near column "
                .. tostring(columnIndex)
                .. "."
        end

        upper[columnIndex][columnIndex] =
            diagonal

        qColumns[columnIndex] = {}

        for rowIndex = 1, rowCount do
            qColumns[columnIndex][rowIndex] =
                working[rowIndex]
                / diagonal
        end
    end

    local projectedResponse = {}
    local scaledCoefficients = {}

    for columnIndex = 1, columnCount do
        projectedResponse[columnIndex] =
            VectorDot(
                qColumns[columnIndex],
                weightedResponse
            )
    end

    for rowIndex = columnCount, 1, -1 do
        local value =
            projectedResponse[rowIndex]

        for columnIndex =
            rowIndex + 1,
            columnCount
        do
            value =
                value
                - upper[rowIndex][columnIndex]
                * scaledCoefficients[columnIndex]
        end

        local diagonal =
            upper[rowIndex][rowIndex]

        if math.abs(diagonal)
            <= tolerance then

            return nil,
                "Regression matrix is singular."
        end

        scaledCoefficients[rowIndex] =
            value / diagonal
    end

    local coefficients = {}

    for columnIndex = 1, columnCount do
        coefficients[columnIndex] =
            scaledCoefficients[columnIndex]
            / columnScales[columnIndex]
    end

    local totalWeight = 0
    local weightedMeanTotal = 0

    for rowIndex = 1, rowCount do
        local source =
            effectiveRows[rowIndex]

        totalWeight =
            totalWeight + source.weight

        weightedMeanTotal =
            weightedMeanTotal
            + source.response
            * source.weight
    end

    local responseMean =
        weightedMeanTotal / totalWeight

    local residuals = {}
    local residualSumSquares = 0
    local totalSumSquares = 0
    local maximumAbsoluteResidual = 0

    for rowIndex = 1, rowCount do
        local source =
            effectiveRows[rowIndex]

        local predicted = 0

        for columnIndex = 1, columnCount do
            predicted =
                predicted
                + source.row[columnIndex]
                * coefficients[columnIndex]
        end

        local residual =
            source.response - predicted

        residuals[rowIndex] =
            residual

        residualSumSquares =
            residualSumSquares
            + source.weight
            * residual
            * residual

        local meanDifference =
            source.response - responseMean

        totalSumSquares =
            totalSumSquares
            + source.weight
            * meanDifference
            * meanDifference

        maximumAbsoluteResidual =
            math.max(
                maximumAbsoluteResidual,
                math.abs(residual)
            )
    end

    local rSquared

    if totalSumSquares <= tolerance then
        rSquared =
            residualSumSquares <= tolerance
            and 1
            or 0
    else
        rSquared =
            1
            - residualSumSquares
            / totalSumSquares
    end

    local degreesOfFreedom =
        rowCount - columnCount

    local residualVariance =
        degreesOfFreedom > 0
        and residualSumSquares
            / degreesOfFreedom
        or nil

    return {
        coefficients = coefficients,
        residuals = residuals,

        rows = rowCount,
        columns = columnCount,
        rank = columnCount,

        degreesOfFreedom =
            degreesOfFreedom,

        residualSumSquares =
            residualSumSquares,

        totalSumSquares =
            totalSumSquares,

        residualVariance =
            residualVariance,

        rootMeanSquareError =
            math.sqrt(
                residualSumSquares
                / totalWeight
            ),

        maximumAbsoluteResidual =
            maximumAbsoluteResidual,

        rSquared = rSquared
    }
end

function CoA:BuildFormulaRegressionData(spellID)
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

    local sessions =
        spell.sessions or {}

    if #sessions == 0 then
        return nil,
            "No stored cast sessions for spell ID "
            .. tostring(spellID)
            .. "."
    end

    local context =
        FindBestSessionContext(sessions)

    if not context then
        return nil,
            "No clean non-critical cast sessions available."
    end

    local predictors = {}

    for _, definition in ipairs(
        FORMULA_PREDICTORS
    ) do
        local varies, minimum, maximum =
            PredictorVaries(
                context.sessions,
                definition.key
            )

        if varies then
            predictors[
                #predictors + 1
            ] = {
                key = definition.key,
                label = definition.label,
                minimum = minimum,
                maximum = maximum
            }
        end
    end

    if #predictors == 0 then
        local ranges = {}

        for _, definition in ipairs(
            FORMULA_PREDICTORS
        ) do
            local minimum, maximum =
                PredictorRange(
                    context.sessions,
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
            "No predictor varies across stored sessions. "
            .. table.concat(ranges, ", ")
    end

    local confounded =
        FindConfoundedPredictors(
            context.sessions,
            predictors
        )

    if #confounded > 0 then
        return nil,
            BuildConfoundingError(
                confounded
            )
    end

    local coefficientCount =
        1 + #predictors

    if #context.sessions
        <= coefficientCount then

        return nil,
            "Not enough sessions: "
            .. tostring(#context.sessions)
            .. " clean casts for "
            .. tostring(coefficientCount)
            .. " coefficients."
    end

    local designMatrix = {}
    local responseVector = {}

    for rowIndex, session in ipairs(
        context.sessions
    ) do
        local row = {
            1
        }

        for _, predictor in ipairs(
            predictors
        ) do
            row[#row + 1] =
                GetPredictorValue(
                    session,
                    predictor.key
                )
        end

        designMatrix[rowIndex] = row

        responseVector[rowIndex] =
            session.totalDamage
    end

    local coefficientDefinitions = {
        {
            key = "baseDamage",
            label = "Base Cast Damage"
        }
    }

    for _, predictor in ipairs(
        predictors
    ) do
        coefficientDefinitions[
            #coefficientDefinitions + 1
        ] = predictor
    end

    return {
        spellID = spellID,

        spellName =
            spell.name
            or (
                "Spell "
                .. tostring(spellID)
            ),

        dataSource = "cast-sessions",
        contextKey = context.key,

        sessions =
            context.sessions,

        samples =
            #context.sessions,

        predictors =
            predictors,

        coefficientDefinitions =
            coefficientDefinitions,

        designMatrix =
            designMatrix,

        responseVector =
            responseVector
    }
end

function CoA:EstimateFormula(spellID)
    local regressionData, errorMessage =
        self:BuildFormulaRegressionData(
            spellID
        )

    if not regressionData then
        return nil, errorMessage
    end

    local result, solveError =
        self:SolveLeastSquares(
            regressionData.designMatrix,
            regressionData.responseVector
        )

    if not result then
        return nil, solveError
    end

    result.spellID =
        regressionData.spellID

    result.spellName =
        regressionData.spellName

    result.samples =
        regressionData.samples

    result.predictors =
        regressionData.predictors

    result.coefficientDefinitions =
        regressionData.coefficientDefinitions

    result.contextKey =
        regressionData.contextKey

    result.dataSource =
        regressionData.dataSource

    return result
end