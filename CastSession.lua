CoA.CastSession = CoA.CastSession or {}
CoA.CastSession.active = CoA.CastSession.active or {}
CoA.CastSession.nextID = CoA.CastSession.nextID or 1

CoA.CastSession.directWindow = 3
CoA.CastSession.triggerWindow = 1
CoA.CastSession.maxStoredPerSpell = 1000

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

local function CopyTable(source)
    if type(source) ~= "table" then
        return source
    end

    local result = {}

    for key, value in pairs(source) do
        if type(value) == "table" then
            result[key] = CopyTable(value)
        else
            result[key] = value
        end
    end

    return result
end

local function GetSpellRecord(spellID, spellName)
    if not CoADamageDB then
        CoADamageDB = {}
    end

    CoADamageDB.spells =
        CoADamageDB.spells or {}

    local spell =
        CoADamageDB.spells[spellID]

    if not spell then
        spell = {
            id = spellID,
            name =
                spellName
                or ("Spell " .. tostring(spellID)),
            observations = {},
            sessions = {}
        }

        CoADamageDB.spells[spellID] = spell
    end

    spell.sessions =
        spell.sessions or {}

    return spell
end

function CoA:StoreCastSession(session)
    if type(session) ~= "table"
        or session.stored then

        return false
    end

    if not session.spellID then
        return false
    end

    if #(session.damageEvents or {}) == 0 then
        return false
    end

    local spell =
        GetSpellRecord(
            session.spellID,
            session.spellName
        )

    local storedSession = {
        id = session.id,
        spellID = session.spellID,
        spellName = session.spellName,

        started = session.started,
        ended = GetTime(),

        snapshot =
            CopyTable(session.snapshot),

        castDelay = session.castDelay,
        matchMethod = session.matchMethod,

        totalDamage =
            session.totalDamage or 0,

        directHits =
            session.directHits or 0,

        triggeredHits =
            session.triggeredHits or 0,

        damageEvents = {}
    }

    for _, observation in ipairs(
        session.damageEvents or {}
    ) do
        storedSession.damageEvents[
            #storedSession.damageEvents + 1
        ] = {
            timestamp =
                observation.timestamp,

            eventType =
                observation.eventType,

            spellID =
                observation.spellID,

            spellName =
                observation.spellName,

            damage =
                observation.damage,

            critical =
                observation.critical,

            resisted =
                observation.resisted or 0,

            blocked =
                observation.blocked or 0,

            absorbed =
                observation.absorbed or 0,

            targetGUID =
                observation.targetGUID,

            targetName =
                observation.targetName,

            targetLevel =
                observation.targetLevel,

            snapshotSource =
                observation.snapshotSource,

            castSessionID =
                session.id
        }
    end

    spell.sessions[
        #spell.sessions + 1
    ] = storedSession

    local maximum =
        self.CastSession.maxStoredPerSpell
        or 1000

    while #spell.sessions > maximum do
        table.remove(spell.sessions, 1)
    end

    session.stored = true

    if self.debug then
        print(string.format(
            "|cff33ff99CoADamage:|r stored session %d for %s: %d damage, %d events",
            session.id or 0,
            tostring(
                session.spellName
                or session.spellID
                or "Unknown"
            ),
            session.totalDamage or 0,
            #(session.damageEvents or {})
        ))
    end

    return true
end

function CoA:CleanupCastSessions()
    local now = GetTime()
    local directWindow =
        self.CastSession.directWindow or 3

    for index =
        #self.CastSession.active,
        1,
        -1
    do
        local session =
            self.CastSession.active[index]

        local age =
            now - (session.started or now)

        if age > directWindow then
            self:StoreCastSession(session)

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
        triggeredHits = 0,
        stored = false
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

function CoA:GetStoredCastSessions(spellID)
    local spell =
        CoADamageDB
        and CoADamageDB.spells
        and CoADamageDB.spells[spellID]

    if not spell then
        return {}
    end

    spell.sessions =
        spell.sessions or {}

    return spell.sessions
end

function CoA:ClearCastSessions()
    for _, session in ipairs(
        self.CastSession.active
    ) do
        self:StoreCastSession(session)
    end

    self.CastSession.active = {}
    self.CastSession.nextID = 1
end