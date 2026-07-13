CoA.CastSession = CoA.CastSession or {}
CoA.CastSession.active = CoA.CastSession.active or {}
CoA.CastSession.nextID = CoA.CastSession.nextID or 1

CoA.CastSession.directWindow = 3
CoA.CastSession.triggerWindow = 1

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

function CoA:CleanupCastSessions()
    local now = GetTime()
    local directWindow =
        self.CastSession.directWindow or 3

    for index = #self.CastSession.active, 1, -1 do
        local session =
            self.CastSession.active[index]

        local age =
            now - (session.started or now)

        if age > directWindow then
            table.remove(
                self.CastSession.active,
                index
            )
        end
    end
end

function CoA:StartCastSession(
    spellID,
    spellName,
    snapshot,
    castDelay,
    matchMethod
)
    if type(snapshot) ~= "table" then
        return nil
    end

    self:CleanupCastSessions()

    local session = {
        id = self.CastSession.nextID,
        spellID = spellID,
        spellName = spellName,
        normalizedSpellName =
            NormalizeSpellName(spellName),

        started = GetTime(),
        snapshot = snapshot,
        castDelay = castDelay,
        matchMethod = matchMethod,

        damageEvents = {},
        totalDamage = 0,
        directHits = 0,
        triggeredHits = 0
    }

    self.CastSession.nextID =
        self.CastSession.nextID + 1

    table.insert(
        self.CastSession.active,
        session
    )

    return session
end

function CoA:FindDirectCastSession(
    spellID,
    spellName
)
    self:CleanupCastSessions()

    local normalizedName =
        NormalizeSpellName(spellName)

    for index =
        #self.CastSession.active,
        1,
        -1
    do
        local session =
            self.CastSession.active[index]

        if normalizedName
            and session.normalizedSpellName
                == normalizedName then

            return session
        end

        if spellID
            and session.spellID
            and session.spellID == spellID then

            return session
        end
    end

    return nil
end

function CoA:FindTriggeredCastSession()
    self:CleanupCastSessions()

    local now = GetTime()
    local triggerWindow =
        self.CastSession.triggerWindow or 1

    local candidate = nil
    local candidateCount = 0

    for index =
        #self.CastSession.active,
        1,
        -1
    do
        local session =
            self.CastSession.active[index]

        local age =
            now - (session.started or now)

        if age <= triggerWindow then
            candidate = session
            candidateCount =
                candidateCount + 1
        end
    end

    if candidateCount == 1 then
        return candidate
    end

    return nil
end

function CoA:RecordSessionDamage(
    session,
    observation,
    isTriggered
)
    if type(session) ~= "table"
        or type(observation) ~= "table" then

        return
    end

    session.damageEvents[
        #session.damageEvents + 1
    ] = observation

    session.totalDamage =
        (session.totalDamage or 0)
        + (observation.damage or 0)

    if isTriggered then
        session.triggeredHits =
            (session.triggeredHits or 0) + 1
    else
        session.directHits =
            (session.directHits or 0) + 1
    end

    observation.castSessionID =
        session.id
end

function CoA:GetActiveCastSessions()
    self:CleanupCastSessions()

    return self.CastSession.active
end

function CoA:ClearCastSessions()
    self.CastSession.active = {}
    self.CastSession.nextID = 1
end
