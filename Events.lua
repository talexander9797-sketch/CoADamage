local EventFrame = CreateFrame("Frame")

local lastQueuedSpellID = nil
local lastQueuedTime = 0

local function ResolveSpellID(spellName, spellRank)
    if not spellName then
        return nil
    end

    local numberOfTabs = GetNumSpellTabs() or 0

    for tabIndex = 1, numberOfTabs do
        local _, _, offset, numberOfSpells = GetSpellTabInfo(tabIndex)

        offset = offset or 0
        numberOfSpells = numberOfSpells or 0

        for spellIndex = offset + 1, offset + numberOfSpells do
            local bookName, bookRank =
                GetSpellBookItemName(spellIndex, BOOKTYPE_SPELL)

            local nameMatches = bookName == spellName
            local rankMatches =
                not spellRank
                or spellRank == ""
                or bookRank == spellRank

            if nameMatches and rankMatches then
                local link = GetSpellLink(spellIndex, BOOKTYPE_SPELL)

                if link then
                    local spellID = tonumber(
                        string.match(link, "spell:(%d+)")
                    )

                    if spellID then
                        return spellID
                    end
                end
            end
        end
    end

    return nil
end

local function QueueSuccessfulCast(...)
    local unit = select(1, ...)
    local spellName = select(2, ...)
    local spellRank = select(3, ...)

    if unit ~= "player" then
        return
    end

    local spellID = ResolveSpellID(spellName, spellRank)

    if not spellID then
        if CoA.debug then
            print(string.format(
                "|cffff3333CoADamage:|r could not resolve %s %s",
                tostring(spellName),
                tostring(spellRank)
            ))
        end

        return
    end

    local now = GetTime()

    -- Ascension may emit duplicate succeeded events for one cast.
    if spellID == lastQueuedSpellID
        and now - lastQueuedTime < 0.25 then
        return
    end

    lastQueuedSpellID = spellID
    lastQueuedTime = now

    if type(CoA.QueueSnapshot) == "function" then
        CoA:QueueSnapshot(spellID)
    end

    if CoA.debug then
        print(string.format(
            "|cff33ff99CoADamage:|r queued %s (%d)",
            spellName or "Unknown",
            spellID
        ))
    end
end

function CoA:RegisterEvents()
    EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    EventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            CoA:ParseCombatLog(...)

        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            QueueSuccessfulCast(...)
        end
    end)
end