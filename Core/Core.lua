local ADDON_NAME = ...

CoA = CoA or {}
CoA.Version = "0.0.4"
CoA.debug = false
CoA.MAX_OBSERVATIONS_PER_SPELL = 500

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        CoA:Initialize()
    end
end)

function CoA:Initialize()
    if type(self.CapturePlayerSnapshot) ~= "function" then
        print("|cffff3333CoADamage error: Stats.lua did not load. Reinstall the entire addon folder.|r")
        return
    end

    self:InitializeDatabase()
    self:RegisterEvents()
    self:RegisterCommands()
    print("|cff33ff99CoADamage v" .. self.Version .. " loaded|r")
end
