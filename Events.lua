local EventFrame = CreateFrame("Frame")

function CoA:RegisterEvents()
    EventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        CoA:ParseCombatLog(...)
    end
end)
