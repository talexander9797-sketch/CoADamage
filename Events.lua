local EventFrame = CreateFrame("Frame")

local function FindSpellID(...)
    local count = select("#", ...)

    -- Search backward because the spell ID is usually near the end.
    for index = count, 2, -1 do
        local value = select(index, ...)

        if type(value) == "number" then
            local spellName = GetSpellInfo(value)

            if spellName then
                return value
            end
        end
    end

    return nil
end

function CoA:RegisterEvents()
    EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    EventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            CoA:ParseCombatLog(...)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local unit = select(1, ...)

            if unit ~= "player" then
                return
            end

            local spellID = FindSpellID(...)

            if spellID then
                CoA:QueueSnapshot(spellID)

                if CoA.debug then
                    local name = GetSpellInfo(spellID) or "Unknown"
                    print(string.format(
                        "|cff33ff99CoADamage:|r queued %s (%d)",
                        name,
                        spellID
                    ))
                end
            elseif CoA.debug then
                print("|cffff3333CoADamage:|r spellcast succeeded, but no spell ID was found")
            end
        end
    end)
end