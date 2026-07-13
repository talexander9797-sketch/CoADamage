local EventFrame = CreateFrame("Frame")

local lastQueuedName = nil
local lastQueuedTime = 0

local function QueueSuccessfulCast(unit, spellName)
    if unit ~= "player" or not spellName then
        return
    end

    local now = GetTime()

    if spellName == lastQueuedName and (now - lastQueuedTime) < 0.25 then
        return
    end

    lastQueuedName = spellName
    lastQueuedTime = now

    if type(CoA.QueueSnapshot) == "function" then
        -- Name-first queueing for Ascension.
        CoA:QueueSnapshot(nil, spellName)
    end

    if CoA.debug then
        print("|cff33ff99CoADamage:|r queued "..spellName)
    end
end

function CoA:RegisterEvents()
    EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    EventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

    EventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            CoA:ParseCombatLog(...)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            QueueSuccessfulCast(...)
        end
    end)
end