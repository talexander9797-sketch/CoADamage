CoA = CoA or {}
CoA.Experiment = CoA.Experiment or {}

local Experiment = CoA.Experiment
Experiment.current = nil

local function SortedBuffSignature(buffs)
    if type(buffs) ~= "table" or #buffs == 0 then
        return "none"
    end

    local copy = {}
    for index = 1, #buffs do
        copy[index] = tostring(buffs[index])
    end
    table.sort(copy)
    return table.concat(copy, "|")
end

function Experiment:Initialize()
    CoADamageDB.experiments = CoADamageDB.experiments or {}
    CoADamageDB.nextExperimentID = CoADamageDB.nextExperimentID or 1
    self.current = nil
end

function Experiment:GetGearHash()
    local parts = {}
    for slot = 1, 19 do
        local link = GetInventoryItemLink("player", slot)
        parts[#parts + 1] = tostring(slot) .. ":" .. (link or "0")
    end
    return table.concat(parts, ";")
end

function Experiment:GetBuffHash(snapshot)
    local buffs = snapshot and snapshot.buffs
    if not buffs then
        buffs = {}
        if type(UnitBuff) == "function" then
            for index = 1, 40 do
                local name = UnitBuff("player", index)
                if not name then
                    break
                end
                buffs[#buffs + 1] = name
            end
        end
    end
    return SortedBuffSignature(buffs)
end

function Experiment:GetTargetHash(observation)
    local guid = observation and observation.targetGUID or UnitGUID("target") or "NONE"
    local name = observation and observation.targetName or UnitName("target") or "NONE"
    local level = observation and observation.targetLevel or UnitLevel("target") or 0
    return table.concat({ tostring(guid), tostring(name), tostring(level) }, "|")
end

function Experiment:GetFingerprint(observation)
    local snapshot = observation and observation.player or nil
    return {
        gear = self:GetGearHash(),
        buffs = self:GetBuffHash(snapshot),
        target = self:GetTargetHash(observation)
    }
end

function Experiment:GetChangeReason(previous, current)
    if not previous then
        return "Initial observation"
    end
    if previous.gear ~= current.gear then
        return "Gear changed"
    end
    if previous.buffs ~= current.buffs then
        return "Buffs changed"
    end
    if previous.target ~= current.target then
        return "Target changed"
    end
    return nil
end

function Experiment:Start(reason, fingerprint)
    local id = CoADamageDB.nextExperimentID
    CoADamageDB.nextExperimentID = id + 1

    local experiment = {
        id = id,
        reason = reason or "Manual",
        started = time(),
        finished = nil,
        fingerprint = fingerprint or self:GetFingerprint(),
        observations = {}
    }

    CoADamageDB.experiments[id] = experiment
    self.current = experiment

    local ids = {}
    for experimentID in pairs(CoADamageDB.experiments) do
        ids[#ids + 1] = experimentID
    end
    table.sort(ids)
    while #ids > (CoA.MAX_EXPERIMENTS or 200) do
        CoADamageDB.experiments[ids[1]] = nil
        table.remove(ids, 1)
    end

    print(string.format("|cff33ff99CoADamage|r Started experiment #%d (%s)", id, experiment.reason))
    return experiment
end

function Experiment:Finish()
    if self.current and not self.current.finished then
        self.current.finished = time()
    end
end

function Experiment:GetCurrent()
    return self.current
end

function Experiment:AddObservation(spellID, observation)
    local fingerprint = self:GetFingerprint(observation)
    local reason = self:GetChangeReason(self.current and self.current.fingerprint, fingerprint)

    if not self.current or reason then
        self:Finish()
        self:Start(reason or "Automatic", fingerprint)
    end

    local record = {
        spellID = spellID,
        spellName = observation.spellName,
        observation = observation
    }

    table.insert(self.current.observations, record)
    local limit = CoA.MAX_OBSERVATIONS_PER_EXPERIMENT or 1000
    while #self.current.observations > limit do
        table.remove(self.current.observations, 1)
    end

    observation.experimentID = self.current.id
    return self.current
end
