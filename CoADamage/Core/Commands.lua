SLASH_COADAMAGE1 = "/coa"

local function Trim(msg)
    return (msg or ""):match("^%s*(.-)%s*$")
end

local function Round(value)
    return math.floor((value or 0) + 0.5)
end

local function Average(total, count)
    if not count or count == 0 then
        return 0
    end
    return total / count
end

local function PrintSpellSummary(id, spell)
    local normalAvg = Average(spell.normalTotal, spell.normalHits)
    local critAvg = Average(spell.critTotal, spell.critHits)
    local critRate = spell.hits > 0 and ((spell.crits / spell.hits) * 100) or 0

    print(string.format("|cffffff00%s (%d)|r", spell.name or "Unknown", id))
    print(string.format(
        "  Normal: %d hits, avg %d, min %d, max %d",
        spell.normalHits or 0,
        Round(normalAvg),
        spell.normalMin or 0,
        spell.normalMax or 0
    ))
    print(string.format(
        "  Critical: %d hits, avg %d, min %d, max %d",
        spell.critHits or 0,
        Round(critAvg),
        spell.critMin or 0,
        spell.critMax or 0
    ))
    print(string.format(
        "  Total samples: %d, crit rate: %.1f%%, saved observations: %d",
        spell.hits or 0,
        critRate,
        #(spell.observations or {})
    ))
end

local function PrintObservation(index, observation)
    local player = observation.player or {}
    print(string.format(
        "  #%d damage=%d%s AP=%d RAP=%d SP=%d STR=%d AGI=%d INT=%d weapon=%.1f-%.1f target=%s(L%d)",
        index,
        observation.damage or 0,
        observation.critical and " CRIT" or "",
        player.attackPower or 0,
        player.rangedAttackPower or 0,
        player.spellPower or 0,
        player.strength or 0,
        player.agility or 0,
        player.intellect or 0,
        player.weaponMin or 0,
        player.weaponMax or 0,
        observation.targetName or "Unknown",
        observation.targetLevel or 0
    ))
end


local function FormatRange(range)
    if not range or range.min == nil or range.max == nil then
        return "unknown"
    end
    if range.min == range.max then
        return string.format("%.1f (unchanged)", range.min)
    end
    return string.format("%.1f to %.1f", range.min, range.max)
end

local function PrintAnalysis(id)
    if type(CoA.BuildAnalysis) ~= "function" then
        print("|cffff3333CoADamage: Analysis.lua did not load.|r")
        return
    end

    local analysis = CoA:BuildAnalysis(id)
    if not analysis then
        print("No data recorded for spell ID " .. id .. ".")
        return
    end

    print(string.format("|cffffff00Analysis: %s (%d)|r", analysis.spellName, id))
    print(string.format(
        "  Saved samples: %d normal, %d critical; distinct normal stat states: %d",
        analysis.normalSamples,
        analysis.criticalSamples,
        #analysis.stateList
    ))
    print(string.format("  Average normal: %.2f", analysis.normalAverage or 0))
    if analysis.criticalSamples > 0 then
        print(string.format(
            "  Average critical: %.2f; observed crit multiplier: %.3fx",
            analysis.criticalAverage or 0,
            analysis.critMultiplier or 0
        ))
    else
        print("  No saved critical observations yet.")
    end

    print("|cff33ff99Observed stat ranges:|r")
    for _, definition in ipairs(CoA:GetStatDefinitions()) do
        print(string.format("  %s: %s", definition.label, FormatRange(analysis.ranges[definition.key])))
    end

    print("|cff33ff99Controlled scaling estimates:|r")
    local foundEstimate = false
    for _, definition in ipairs(CoA:GetStatDefinitions()) do
        local estimate = CoA:EstimateSingleStatScaling(analysis, definition.key)
        if estimate then
            foundEstimate = true
            print(string.format(
                "  %s: %.4f damage per point (%d controlled comparison%s)",
                definition.label,
                estimate.coefficient,
                estimate.comparisons,
                estimate.comparisons == 1 and "" or "s"
            ))
        end
    end

    if not foundEstimate then
        print("  Not enough controlled variation yet.")
        print("  Collect at least 5 non-critical hits in two setups where only one recorded stat changes.")
    end
end

SlashCmdList.COADAMAGE = function(msg)
    msg = Trim(msg)
    local command, argument = msg:match("^(%S+)%s*(.-)$")
    command = string.lower(command or "")

    if command == "stats" then
        print("|cff33ff99CoADamage Known Spells|r")
        local found = false
        for id, spell in pairs(CoADamageDB.spells) do
            if spell.hits and spell.hits > 0 then
                found = true
                PrintSpellSummary(id, spell)
            end
        end
        if not found then
            print("No damaging spells recorded yet.")
        end

    elseif command == "inspect" then
        local id = tonumber(argument)
        if not id then
            print("Usage: /coa inspect <spellID>")
            return
        end

        local spell = CoADamageDB.spells[id]
        if not spell then
            print("No data recorded for spell ID " .. id .. ".")
            return
        end

        PrintSpellSummary(id, spell)
        local observations = spell.observations or {}
        local first = math.max(1, #observations - 9)
        print("|cff33ff99Most recent observations:|r")
        for index = first, #observations do
            PrintObservation(index, observations[index])
        end

    elseif command == "analyze" then
        local id = tonumber(argument)
        if not id then
            print("Usage: /coa analyze <spellID>")
            return
        end
        PrintAnalysis(id)

    elseif command == "experiment" then
        if not CoA.Experiment then
            print("|cffff3333CoADamage: Experiment.lua did not load.|r")
            return
        end
        local experiment = CoA.Experiment:GetCurrent()
        if not experiment then
            print("No active experiment. Deal damage to begin one.")
        else
            print(string.format("|cff33ff99Current experiment #%d|r", experiment.id))
            print("  Reason: " .. tostring(experiment.reason or "Unknown"))
            print("  Observations: " .. tostring(#(experiment.observations or {})))
        end

    elseif command == "debug" then
        CoA.debug = not CoA.debug
        print("|cff33ff99CoADamage debug:|r " .. (CoA.debug and "ON" or "OFF"))

    elseif command == "clear" then
        CoADamageDB.spells = {}
        CoADamageDB.experiments = {}
        CoADamageDB.nextExperimentID = 1
        if CoA.Experiment then CoA.Experiment.current = nil end
        print("|cff33ff99CoADamage:|r recorded spell and experiment data cleared.")

    else
        print("|cff33ff99CoADamage commands:|r")
        print("/coa stats - summarize recorded spells")
        print("/coa inspect <spellID> - show recent hits and stat snapshots")
        print("/coa analyze <spellID> - summarize variation and controlled scaling evidence")
        print("/coa experiment - show the active experiment")
        print("/coa debug - toggle one-line event logging")
        print("/coa clear - erase recorded data")
    end
end

function CoA:RegisterCommands()
end
