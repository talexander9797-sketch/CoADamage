CoA = CoA or {}
CoA.Version = "0.8.0"
CoA.debug = false
CoA.MAX_OBSERVATIONS_PER_SPELL = 500
CoA.MAX_EXPERIMENTS = 200
CoA.MAX_OBSERVATIONS_PER_EXPERIMENT = 1000

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")

frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        CoA:Initialize()
    end
end)

function CoA:Initialize()
    if type(self.InitializeDatabase) ~= "function" then
        print("|cffff3333CoADamage error: Data\\Database.lua did not load.|r")
        return
    end

    if type(self.CapturePlayerSnapshot) ~= "function" then
        print("|cffff3333CoADamage error: Data\\Stats.lua did not load.|r")
        return
    end

    self:InitializeDatabase()

    if self.Experiment and type(self.Experiment.Initialize) == "function" then
        self.Experiment:Initialize()
    end

    self:RegisterEvents()
    self:RegisterCommands()
    print("|cff33ff99CoADamage v" .. self.Version .. " loaded|r")
end
