print("|cff33ff99CoADamage: Advisor.lua loaded|r")
-- CoADamage Experiment Advisor
-- Load after Analysis.lua and before Commands.lua.
-- Compatible with Lua 5.1 / WoW 3.3.5a.

local function GetDefinitions()
    if type(CoA.GetStatDefinitions) ~= "function" then
        return {}
    end

    return CoA:GetStatDefinitions() or {}
end

local function SameTestingContext(left, right)
    return left.targetName == right.targetName
        and left.targetLevel == right.targetLevel
        and left.buffs == right.buffs
        and left.talents == right.talents
end

local function GetChangedStatKeys(left, right, definitions)
    local changed = {}

    for _, definition in ipairs(definitions) do
        local key = definition.key

        if left.values[key] ~= right.values[key] then
            changed[#changed + 1] = key
        end
    end

    return changed
end

local function GetDefinitionByKey(key, definitions)
    for _, definition in ipairs(definitions) do
        if definition.key == key then
            return definition
        end
    end

    return nil
end

local function SortedSetLabels(set, definitions)
    local labels = {}

    for key in pairs(set) do
        local definition = GetDefinitionByKey(key, definitions)

        labels[#labels + 1] =
            definition and definition.label or tostring(key)
    end

    table.sort(labels)

    return labels
end

function CoA:BuildExperimentAdvice(analysis)
    if type(analysis) ~= "table" then
        return nil
    end

    local definitions = GetDefinitions()

    if #definitions == 0 then
        return nil
    end

    local report = {
        spellID = analysis.spellId,
        spellName = analysis.spellName,
        states = #(analysis.stateList or {}),
        stats = {}
    }

    for _, definition in ipairs(definitions) do
        report.stats[definition.key] = {
            key = definition.key,
            label = definition.label,
            controlledComparisons = 0,
            confoundedComparisons = 0,
            confoundedWith = {}
        }
    end

    local states = analysis.stateList or {}

    for leftIndex = 1, #states do
        local left = states[leftIndex]

        for rightIndex = leftIndex + 1, #states do
            local right = states[rightIndex]

            if SameTestingContext(left, right) then
                local changedKeys =
                    GetChangedStatKeys(left, right, definitions)

                for _, candidateKey in ipairs(changedKeys) do
                    local result = report.stats[candidateKey]

                    if result then
                        if #changedKeys == 1 then
                            result.controlledComparisons =
                                result.controlledComparisons + 1
                        else
                            result.confoundedComparisons =
                                result.confoundedComparisons + 1

                            for _, otherKey in ipairs(changedKeys) do
                                if otherKey ~= candidateKey then
                                    result.confoundedWith[otherKey] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _, definition in ipairs(definitions) do
        local result = report.stats[definition.key]
        local range =
            analysis.ranges and analysis.ranges[definition.key]

        result.minimum = range and range.min
        result.maximum = range and range.max

        if result.controlledComparisons > 0 then
            result.status = "controlled"

        elseif result.confoundedComparisons > 0 then
            result.status = "confounded"

        elseif range
            and range.min ~= nil
            and range.max ~= nil
            and range.min ~= range.max then

            result.status = "incomparable"

        else
            result.status = "unchanged"
        end

        result.confoundedLabels =
            SortedSetLabels(result.confoundedWith, definitions)
    end

    return report
end