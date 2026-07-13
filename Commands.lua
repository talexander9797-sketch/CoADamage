local function PrintHeader(text)
    print("|cff33ff99CoADamage:|r " .. tostring(text))
end

local function PrintError(text)
    print("|cffff3333CoADamage:|r " .. tostring(text))
end

local function Trim(text)
    text = tostring(text or "")
    return text:match("^%s*(.-)%s*$")
end

local function SplitCommand(message)
    local command, argument =
        tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")

    return string.lower(command or ""), Trim(argument)
end

local function GetSpellRecord(spellID)
    return CoADamageDB
        and CoADamageDB.spells
        and CoADamageDB.spells[spellID]
end

local function PrintHelp()
    PrintHeader("Commands")
    print("/coa stats - Show database totals")
    print("/coa inspect <spellID> - Inspect recorded spell data")
    print("/coa analyze <spellID> - Analyze controlled scaling")
    print("/coa advise <spellID> - Show experiment advice")
    print("/coa formula <spellID> - Solve the spell damage formula")
    print("/coa dump <spellID> - Show raw stored observations")
    print("/coa sessions - Show active cast sessions")
    print("/coa experiment - Show the active experiment")
    print("/coa queue - Show cast snapshot queue")
    print("/coa debug - Toggle debug output")
    print("/coa clear - Clear recorded data")
end

function CoA:PrintStats()
    local spellCount = 0
    local observationCount = 0
    local experimentCount = 0

    for _, spell in pairs(
        CoADamageDB
        and CoADamageDB.spells
        or {}
    ) do
        spellCount = spellCount + 1
        observationCount =
            observationCount
            + #(spell.observations or {})
    end

    for _ in pairs(
        CoADamageDB
        and CoADamageDB.experiments
        or {}
    ) do
        experimentCount = experimentCount + 1
    end

    PrintHeader("Database Statistics")
    print("Spells: " .. tostring(spellCount))
    print("Observations: " .. tostring(observationCount))
    print("Experiments: " .. tostring(experimentCount))
end

function CoA:PrintInspection(spellID)
    local spell = GetSpellRecord(spellID)

    if not spell then
        PrintError(
            "No data recorded for spell ID "
            .. tostring(spellID)
            .. "."
        )
        return
    end

    local normalHits = 0
    local criticalHits = 0
    local totalDamage = 0

    for _, observation in ipairs(
        spell.observations or {}
    ) do
        totalDamage =
            totalDamage
            + (tonumber(observation.damage) or 0)

        if observation.critical then
            criticalHits = criticalHits + 1
        else
            normalHits = normalHits + 1
        end
    end

    PrintHeader(
        tostring(spell.name or ("Spell " .. spellID))
        .. " ("
        .. tostring(spellID)
        .. ")"
    )

    print(
        "Observations: "
        .. tostring(#(spell.observations or {}))
    )

    print("Normal hits: " .. tostring(normalHits))
    print("Critical hits: " .. tostring(criticalHits))
    print("Total damage: " .. tostring(totalDamage))
end

function CoA:PrintAnalysis(spellID)
    if type(self.BuildAnalysis) ~= "function" then
        PrintError("Analysis is unavailable.")
        return
    end

    local analysis = self:BuildAnalysis(spellID)

    if not analysis then
        PrintError(
            "No data recorded for spell ID "
            .. tostring(spellID)
            .. "."
        )
        return
    end

    PrintHeader(
        tostring(analysis.spellName)
        .. " Analysis"
    )

    print(
        "Samples: "
        .. tostring(analysis.totalSamples or 0)
    )

    print(string.format(
        "Average normal damage: %.2f",
        analysis.normalAverage or 0
    ))

    if analysis.critMultiplier then
        print(string.format(
            "Critical multiplier: %.3f",
            analysis.critMultiplier
        ))
    else
        print("Critical multiplier: insufficient data")
    end

    local definitions =
        type(self.GetStatDefinitions) == "function"
        and self:GetStatDefinitions()
        or {}

    for _, definition in ipairs(definitions) do
        local range =
            analysis.ranges
            and analysis.ranges[definition.key]

        local estimate =
            type(self.EstimateSingleStatScaling)
                == "function"
            and self:EstimateSingleStatScaling(
                analysis,
                definition.key
            )
            or nil

        if estimate then
            print(string.format(
                "%s: %.6f (%d comparisons, %.1f%% confidence)",
                definition.label,
                estimate.coefficient or 0,
                estimate.comparisons or 0,
                estimate.confidence or 0
            ))
        elseif range
            and range.min ~= nil
            and range.max ~= nil
            and range.min ~= range.max then

            print(
                definition.label
                .. ": varied but remained confounded"
            )
        else
            print(
                definition.label
                .. ": not enough controlled variation"
            )
        end
    end
end

function CoA:PrintAdvice(spellID)
    if type(self.BuildAnalysis) ~= "function"
        or type(self.BuildExperimentAdvice) ~= "function" then

        PrintError("Advisor is unavailable.")
        return
    end

    local analysis = self:BuildAnalysis(spellID)

    if not analysis then
        PrintError(
            "No data recorded for spell ID "
            .. tostring(spellID)
            .. "."
        )
        return
    end

    local advice =
        self:BuildExperimentAdvice(analysis)

    if not advice then
        PrintError("No experiment advice is available.")
        return
    end

    PrintHeader(
        tostring(advice.spellName)
        .. " Experiment Advice"
    )

    local definitions =
        type(self.GetStatDefinitions) == "function"
        and self:GetStatDefinitions()
        or {}

    for _, definition in ipairs(definitions) do
        local result =
            advice.stats
            and advice.stats[definition.key]

        if result then
            if result.status == "controlled" then
                print(
                    definition.label
                    .. ": controlled variation available"
                )
            elseif result.status == "confounded" then
                print(
                    definition.label
                    .. ": variation is confounded"
                )
            else
                print(
                    definition.label
                    .. ": not enough variation"
                )
            end
        end
    end
end

function CoA:PrintFormula(spellID)
    if type(self.EstimateFormula) ~= "function" then
        PrintError("Formula solver is unavailable.")
        return
    end

    local result, errorMessage =
        self:EstimateFormula(spellID)

    if not result then
        PrintError(
            errorMessage
            or "Unable to solve the formula."
        )
        return
    end

    PrintHeader(
        tostring(result.spellName)
        .. " Formula ("
        .. tostring(result.spellID)
        .. ")"
    )

    print(
        "Samples: "
        .. tostring(result.samples or 0)
    )

    for index, definition in ipairs(
        result.coefficientDefinitions or {}
    ) do
        local coefficient =
            result.coefficients
            and result.coefficients[index]

        if type(coefficient) == "number" then
            print(string.format(
                "%s: %.6f",
                definition.label
                    or definition.key
                    or ("Coefficient " .. index),
                coefficient
            ))
        end
    end

    print(string.format(
        "R²: %.6f",
        result.rSquared or 0
    ))

    print(string.format(
        "RMSE: %.4f",
        result.rootMeanSquareError or 0
    ))

    print(string.format(
        "Maximum residual: %.4f",
        result.maximumAbsoluteResidual or 0
    ))

    print(
        "Degrees of freedom: "
        .. tostring(result.degreesOfFreedom or 0)
    )
end


local function CountDistinctValues(observations, extractor)
    local values = {}
    local count = 0

    for _, observation in ipairs(observations or {}) do
        local value = extractor(observation)
        local key = tostring(value)

        if not values[key] then
            values[key] = true
            count = count + 1
        end
    end

    return count
end

local function GetPlayerValue(observation, key)
    local player =
        observation
        and observation.player
        or {}

    return player[key]
end

local function GetWeaponAverage(observation)
    local player =
        observation
        and observation.player
        or {}

    local minimum =
        tonumber(player.weaponMin)
        or 0

    local maximum =
        tonumber(player.weaponMax)
        or 0

    return (minimum + maximum) / 2
end

local function PrintValue(label, value)
    print(
        tostring(label)
        .. ": "
        .. tostring(value == nil and "nil" or value)
    )
end

function CoA:PrintObservationDump(spellID)
    local spell = GetSpellRecord(spellID)

    if not spell then
        PrintError(
            "No data recorded for spell ID "
            .. tostring(spellID)
            .. "."
        )
        return
    end

    local observations =
        spell.observations or {}

    PrintHeader(
        tostring(spell.name or ("Spell " .. spellID))
        .. " Raw Observations"
    )

    PrintValue(
        "Total observations",
        #observations
    )

    PrintValue(
        "Distinct Attack Power values",
        CountDistinctValues(
            observations,
            function(observation)
                return GetPlayerValue(
                    observation,
                    "attackPower"
                )
            end
        )
    )

    PrintValue(
        "Distinct Ranged Attack Power values",
        CountDistinctValues(
            observations,
            function(observation)
                return GetPlayerValue(
                    observation,
                    "rangedAttackPower"
                )
            end
        )
    )

    PrintValue(
        "Distinct Spell Power values",
        CountDistinctValues(
            observations,
            function(observation)
                return GetPlayerValue(
                    observation,
                    "spellPower"
                )
            end
        )
    )

    PrintValue(
        "Distinct Weapon Damage values",
        CountDistinctValues(
            observations,
            GetWeaponAverage
        )
    )

    PrintValue(
        "Distinct Experiment IDs",
        CountDistinctValues(
            observations,
            function(observation)
                return observation.experimentID
            end
        )
    )

    PrintValue(
        "Distinct Target GUIDs",
        CountDistinctValues(
            observations,
            function(observation)
                return observation.targetGUID
            end
        )
    )

    PrintValue(
        "Distinct Target Names",
        CountDistinctValues(
            observations,
            function(observation)
                return observation.targetName
            end
        )
    )

    local firstIndex =
        math.max(
            1,
            #observations - 9
        )

    for index = firstIndex, #observations do
        local observation =
            observations[index]

        local player =
            observation.player or {}

        print("----------------------------------------")
        PrintValue("Observation", index)
        PrintValue("Damage", observation.damage)
        PrintValue("Critical", observation.critical)
        PrintValue("Event Type", observation.eventType)
        PrintValue("Experiment ID", observation.experimentID)

        PrintValue(
            "Snapshot Time",
            observation.snapshotTime
            or player.timestamp
            or observation.timestamp
        )

        PrintValue(
            "Snapshot Source",
            observation.snapshotSource
        )

        PrintValue(
            "Attack Power",
            player.attackPower
        )

        PrintValue(
            "Ranged Attack Power",
            player.rangedAttackPower
        )

        PrintValue(
            "Spell Power",
            player.spellPower
        )

        PrintValue(
            "Strength",
            player.strength
        )

        PrintValue(
            "Agility",
            player.agility
        )

        PrintValue(
            "Intellect",
            player.intellect
        )

        PrintValue(
            "Weapon Min",
            player.weaponMin
        )

        PrintValue(
            "Weapon Max",
            player.weaponMax
        )

        PrintValue(
            "Weapon Average",
            GetWeaponAverage(observation)
        )

        PrintValue(
            "Target Name",
            observation.targetName
        )

        PrintValue(
            "Target GUID",
            observation.targetGUID
        )

        PrintValue(
            "Target Level",
            observation.targetLevel
        )

        PrintValue(
            "Talent Signature",
            observation.talentSignature
        )

        local buffCount = 0

        for _ in pairs(player.buffs or {}) do
            buffCount = buffCount + 1
        end

        PrintValue(
            "Buff Count",
            buffCount
        )
    end

    print("----------------------------------------")
end


function CoA:PrintCastSessions()
    if type(self.GetActiveCastSessions) ~= "function" then
        PrintError("Cast session manager is unavailable.")
        return
    end

    local sessions =
        self:GetActiveCastSessions()
        or {}

    if #sessions == 0 then
        PrintHeader("No active cast sessions.")
        return
    end

    PrintHeader(
        "Active Cast Sessions: "
        .. tostring(#sessions)
    )

    for _, session in ipairs(sessions) do
        local snapshot =
            session.snapshot or {}

        print("----------------------------------------")

        PrintValue(
            "Session ID",
            session.id
        )

        PrintValue(
            "Spell",
            session.spellName
            or session.spellID
            or "Unknown"
        )

        PrintValue(
            "Spell ID",
            session.spellID
        )

        PrintValue(
            "Age",
            string.format(
                "%.3f",
                GetTime()
                - (session.started or GetTime())
            )
        )

        PrintValue(
            "Match Method",
            session.matchMethod
        )

        PrintValue(
            "Cast Delay",
            session.castDelay
        )

        PrintValue(
            "Attack Power",
            snapshot.attackPower
        )

        PrintValue(
            "Ranged Attack Power",
            snapshot.rangedAttackPower
        )

        PrintValue(
            "Spell Power",
            snapshot.spellPower
        )

        PrintValue(
            "Strength",
            snapshot.strength
        )

        PrintValue(
            "Agility",
            snapshot.agility
        )

        PrintValue(
            "Intellect",
            snapshot.intellect
        )

        PrintValue(
            "Weapon Min",
            snapshot.weaponMin
        )

        PrintValue(
            "Weapon Max",
            snapshot.weaponMax
        )

        local weaponAverage =
            (
                (tonumber(snapshot.weaponMin) or 0)
                + (tonumber(snapshot.weaponMax) or 0)
            ) / 2

        PrintValue(
            "Weapon Average",
            weaponAverage
        )

        PrintValue(
            "Direct Hits",
            session.directHits or 0
        )

        PrintValue(
            "Triggered Hits",
            session.triggeredHits or 0
        )

        PrintValue(
            "Total Damage",
            session.totalDamage or 0
        )

        PrintValue(
            "Damage Events",
            #(session.damageEvents or {})
        )

        for eventIndex, observation in ipairs(
            session.damageEvents or {}
        ) do
            print(string.format(
                "  %d. %s: %s%s [%s]",
                eventIndex,
                tostring(
                    observation.spellName
                    or observation.spellID
                    or "Unknown"
                ),
                tostring(observation.damage or 0),
                observation.critical
                    and " CRIT"
                    or "",
                tostring(
                    observation.snapshotSource
                    or "unknown"
                )
            ))
        end
    end

    print("----------------------------------------")
end

function CoA:PrintExperiment()
    if not self.Experiment
        or type(self.Experiment.GetCurrent)
            ~= "function" then

        PrintError("Experiment manager is unavailable.")
        return
    end

    local experiment =
        self.Experiment:GetCurrent()

    if not experiment then
        PrintHeader("No active experiment.")
        return
    end

    PrintHeader(
        "Experiment #"
        .. tostring(experiment.id)
        .. ": "
        .. tostring(experiment.spellName)
    )

    print(
        "Reason: "
        .. tostring(experiment.reason or "Unknown")
    )

    print(
        "Observations: "
        .. tostring(#(experiment.observations or {}))
    )

    print(
        "Normal hits: "
        .. tostring(experiment.normalHits or 0)
    )

    print(
        "Critical hits: "
        .. tostring(experiment.criticalHits or 0)
    )
end

function CoA:PrintQueue()
    local queue =
        self.CastQueue
        or self.castQueue
        or self.pendingCasts

    if type(self.PrintCastQueue) == "function" then
        self:PrintCastQueue()
        return
    end

    if type(queue) ~= "table" then
        PrintHeader("Cast queue is empty.")
        return
    end

    local count = 0

    for _ in pairs(queue) do
        count = count + 1
    end

    PrintHeader(
        "Cast queue entries: "
        .. tostring(count)
    )
end

function CoA:ClearData()
    if type(self.InitializeDatabase) == "function" then
        CoADamageDB = {
            spells = {},
            experiments = {},
            nextExperimentID = 1
        }

        if self.Experiment
            and type(self.Experiment.Initialize)
                == "function" then

            self.Experiment:Initialize()
        end

        PrintHeader("Recorded data cleared.")
        return
    end

    PrintError("Database manager is unavailable.")
end

function CoA:RegisterCommands()
    SLASH_COADAMAGE1 = "/coa"

    SlashCmdList.COADAMAGE = function(message)
        local command, argument =
            SplitCommand(message)

        if command == ""
            or command == "help" then

            PrintHelp()

        elseif command == "stats" then
            CoA:PrintStats()

        elseif command == "inspect" then
            local spellID = tonumber(argument)

            if not spellID then
                PrintError(
                    "Usage: /coa inspect <spellID>"
                )
                return
            end

            CoA:PrintInspection(spellID)

        elseif command == "analyze" then
            local spellID = tonumber(argument)

            if not spellID then
                PrintError(
                    "Usage: /coa analyze <spellID>"
                )
                return
            end

            CoA:PrintAnalysis(spellID)

        elseif command == "advise" then
            local spellID = tonumber(argument)

            if not spellID then
                PrintError(
                    "Usage: /coa advise <spellID>"
                )
                return
            end

            CoA:PrintAdvice(spellID)

        elseif command == "formula" then
            local spellID = tonumber(argument)

            if not spellID then
                PrintError(
                    "Usage: /coa formula <spellID>"
                )
                return
            end

            CoA:PrintFormula(spellID)

        elseif command == "dump" then
            local spellID = tonumber(argument)

            if not spellID then
                PrintError(
                    "Usage: /coa dump <spellID>"
                )
                return
            end

            CoA:PrintObservationDump(spellID)

        elseif command == "sessions" then
            CoA:PrintCastSessions()

        elseif command == "experiment" then
            CoA:PrintExperiment()

        elseif command == "queue" then
            CoA:PrintQueue()

        elseif command == "debug" then
            CoA.debug = not CoA.debug

            PrintHeader(
                "Debug "
                .. (
                    CoA.debug
                    and "enabled."
                    or "disabled."
                )
            )

        elseif command == "clear" then
            CoA:ClearData()

        else
            PrintError(
                "Unknown command: "
                .. tostring(command)
            )

            PrintHelp()
        end
    end
end