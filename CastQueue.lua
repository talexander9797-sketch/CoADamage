CoA.CastQueue = CoA.CastQueue or {}
CoA.CastQueue.queue = CoA.CastQueue.queue or {}
CoA.CastQueue.activeMatches = CoA.CastQueue.activeMatches or {}

CoA.CastQueue.maxAge = 10
CoA.CastQueue.reuseAge = 3

CoA.CastQueue.stats = CoA.CastQueue.stats or {
    matched = 0,
    matchedByID = 0,
    matchedByName = 0,
    reused = 0,
    expired = 0,
    fallbacks = 0
}

local function NormalizeSpellName(name)
    if type(name) ~= "string" then
        return nil
    end

    name = string.lower(name)
    name = string.gsub(name, "^%s+", "")
    name = string.gsub(name, "%s+$", "")

    if name == "" then
        return nil
    end

    return name
end

local function BuildActiveKey(spellID, spellName)
    local normalizedName =
        NormalizeSpellName(spellName)

    if normalizedName then
        return "name:" .. normalizedName
    end

    if spellID then
        return "id:" .. tostring(spellID)
    end

    return nil
end

function CoA:CleanupCastQueue()
    local now = GetTime()
    local queue = self.CastQueue.queue
    local maxAge = self.CastQueue.maxAge or 10
    local reuseAge = self.CastQueue.reuseAge or 3

    for index = #queue, 1, -1 do
        local entry = queue[index]
        local age = now - (entry.time or now)

        if age > maxAge then
            table.remove(queue, index)

            self.CastQueue.stats.expired =
                (self.CastQueue.stats.expired or 0) + 1
        end
    end

    for key, entry in pairs(
        self.CastQueue.activeMatches
    ) do
        local age =
            now - (entry.time or now)

        if age > reuseAge then
            self.CastQueue.activeMatches[key] = nil
        end
    end
end

function CoA:QueueSnapshot(spellID, spellName)
    if type(self.CapturePlayerSnapshot) ~= "function" then
        return
    end

    self:CleanupCastQueue()

    local resolvedName =
        spellName
        or (
            spellID
            and GetSpellInfo(spellID)
        )
        or "Unknown"

    table.insert(self.CastQueue.queue, {
        spellID = spellID,
        spellName = resolvedName,
        normalizedSpellName =
            NormalizeSpellName(resolvedName),
        snapshot =
            self:CapturePlayerSnapshot(),
        time = GetTime()
    })
end

local function ActivateMatchedEntry(
    castQueue,
    entry,
    spellID,
    spellName
)
    local key =
        BuildActiveKey(
            spellID or entry.spellID,
            spellName or entry.spellName
        )

    if key then
        castQueue.activeMatches[key] = {
            snapshot = entry.snapshot,
            time = entry.time or GetTime(),
            spellID = spellID or entry.spellID,
            spellName = spellName or entry.spellName
        }
    end
end

function CoA:GetQueuedSnapshot(spellID, spellName)
    self:CleanupCastQueue()

    local queue = self.CastQueue.queue
    local normalizedName =
        NormalizeSpellName(spellName)

    -- Always consume a newly queued cast before considering
    -- reuse from an older cast of the same spell.
    if normalizedName then
        for index = 1, #queue do
            local entry = queue[index]

            local entryName =
                entry.normalizedSpellName
                or NormalizeSpellName(entry.spellName)

            if entryName == normalizedName then
                table.remove(queue, index)

                self.CastQueue.stats.matched =
                    (self.CastQueue.stats.matched or 0) + 1

                self.CastQueue.stats.matchedByName =
                    (self.CastQueue.stats.matchedByName or 0) + 1

                ActivateMatchedEntry(
                    self.CastQueue,
                    entry,
                    spellID,
                    spellName
                )

                local delay =
                    GetTime()
                    - (entry.time or GetTime())

                return entry.snapshot,
                    delay,
                    "spell-name"
            end
        end
    end

    if spellID then
        for index = 1, #queue do
            local entry = queue[index]

            if entry.spellID
                and entry.spellID == spellID then

                table.remove(queue, index)

                self.CastQueue.stats.matched =
                    (self.CastQueue.stats.matched or 0) + 1

                self.CastQueue.stats.matchedByID =
                    (self.CastQueue.stats.matchedByID or 0) + 1

                ActivateMatchedEntry(
                    self.CastQueue,
                    entry,
                    spellID,
                    spellName
                )

                local delay =
                    GetTime()
                    - (entry.time or GetTime())

                return entry.snapshot,
                    delay,
                    "spell-id"
            end
        end
    end

    -- Multi-hit spells can generate several damage events from
    -- one cast. Reuse the matched cast snapshot for a brief window.
    local activeKey =
        BuildActiveKey(spellID, spellName)

    local active =
        activeKey
        and self.CastQueue.activeMatches[activeKey]

    if active then
        local age =
            GetTime() - (active.time or GetTime())

        if age <= (self.CastQueue.reuseAge or 3) then
            self.CastQueue.stats.reused =
                (self.CastQueue.stats.reused or 0) + 1

            return active.snapshot,
                age,
                "spell-name-reuse"
        end

        self.CastQueue.activeMatches[activeKey] = nil
    end

    return nil, nil, nil
end

function CoA:RecordSnapshotFallback()
    self.CastQueue.stats.fallbacks =
        (self.CastQueue.stats.fallbacks or 0) + 1
end

function CoA:GetQueueSize()
    self:CleanupCastQueue()

    return #self.CastQueue.queue
end

function CoA:GetQueueEntries()
    self:CleanupCastQueue()

    return self.CastQueue.queue
end

function CoA:GetQueueStats()
    return self.CastQueue.stats
end

function CoA:ClearCastQueue()
    self.CastQueue.queue = {}
    self.CastQueue.activeMatches = {}

    self.CastQueue.stats = {
        matched = 0,
        matchedByID = 0,
        matchedByName = 0,
        reused = 0,
        expired = 0,
        fallbacks = 0
    }
end