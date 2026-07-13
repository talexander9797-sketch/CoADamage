local TRACKED_EVENTS = {
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true
}

local function UpdateMinMax(
    container,
    minKey,
    maxKey,
    amount
)
    if not container[minKey]
        or amount < container[minKey] then

        container[minKey] = amount
    end

    if not container[maxKey]
        or amount > container[maxKey] then

        container[maxKey] = amount
    end
end

function CoA:ParseCombatLog(...)
    local timestamp = select(1, ...)
    local eventType = select(2, ...)
    local sourceGUID = select(3, ...)
    local sourceName = select(4, ...)
    local destGUID = select(6, ...)
    local destName = select(7, ...)

    if not TRACKED_EVENTS[eventType] then
        return
    end

    if sourceGUID ~= UnitGUID("player") then
        return
    end

    local spellId = select(9, ...)
    local spellName = select(10, ...)
    local spellSchool = select(11, ...)
    local amount = select(12, ...)
    local overkill = select(13, ...)
    local resisted = select(15, ...)
    local blocked = select(16, ...)
    local absorbed = select(17, ...)
    local critical =
        select(18, ...) and true or false

    if type(spellId) ~= "number"
        or type(amount) ~= "number" then

        return
    end

    local spell = self:GetSpell(spellId)

    spell.name =
        spellName
        or spell.name
        or ("Spell " .. spellId)

    spell.school =
        spellSchool
        or spell.school

    spell.hits = spell.hits + 1
    spell.totalDamage =
        spell.totalDamage + amount

    UpdateMinMax(
        spell,
        "min",
        "max",
        amount
    )

    if critical then
        spell.crits =
            spell.crits + 1

        spell.critHits =
            spell.critHits + 1

        spell.critTotal =
            spell.critTotal + amount

        UpdateMinMax(
            spell,
            "critMin",
            "critMax",
            amount
        )
    else
        spell.normalHits =
            spell.normalHits + 1

        spell.normalTotal =
            spell.normalTotal + amount

        UpdateMinMax(
            spell,
            "normalMin",
            "normalMax",
            amount
        )
    end

    if type(self.CapturePlayerSnapshot)
        ~= "function" then

        if not self.snapshotErrorShown then
            self.snapshotErrorShown = true

            print(
                "|cffff3333CoADamage: "
                .. "Stats.lua is missing or "
                .. "not listed in CoADamage.toc.|r"
            )
        end

        return
    end

    local snapshot = nil
    local snapshotSource =
        "damage-fallback"

    local castDelay = nil
    local matchMethod = nil
    local session = nil
    local isTriggered = false

    if type(self.GetQueuedSnapshot)
        == "function" then

        snapshot, castDelay, matchMethod =
            self:GetQueuedSnapshot(
                spellId,
                spellName
            )
    end

    if snapshot then
        snapshotSource =
            "cast-queue-"
            .. tostring(
                matchMethod or "unknown"
            )

        if type(self.StartCastSession)
            == "function" then

            session =
                self:StartCastSession(
                    spellId,
                    spellName,
                    snapshot,
                    castDelay,
                    matchMethod
                )
        end
    else
        if type(self.FindDirectCastSession)
            == "function" then

            session =
                self:FindDirectCastSession(
                    spellId,
                    spellName
                )
        end

        if session then
            snapshot = session.snapshot
            snapshotSource =
                "cast-session-direct"
        elseif type(self.FindTriggeredCastSession)
            == "function" then

            session =
                self:FindTriggeredCastSession()

            if session then
                snapshot = session.snapshot
                snapshotSource =
                    "cast-session-triggered"

                isTriggered = true
            end
        end
    end

    if not snapshot then
        snapshot =
            self:CapturePlayerSnapshot()

        if type(self.RecordSnapshotFallback)
            == "function" then

            self:RecordSnapshotFallback()
        end
    end

    local observation = {
        timestamp = timestamp or time(),
        eventType = eventType,
        spellID = spellId,
        spellName = spell.name,
        damage = amount,
        critical = critical,

        snapshotSource = snapshotSource,
        castDelay = castDelay,
        queueMatchMethod = matchMethod,

        overkill = overkill or 0,
        resisted = resisted or 0,
        blocked = blocked or 0,
        absorbed = absorbed or 0,

        targetGUID = destGUID,
        targetName = destName,
        targetLevel =
            UnitLevel("target") or 0,

        player = snapshot
    }

    if session
        and type(self.RecordSessionDamage)
            == "function" then

        self:RecordSessionDamage(
            session,
            observation,
            isTriggered
        )
    end

    self:AddObservation(
        spell,
        observation
    )

    if self.Experiment
        and type(
            self.Experiment.AddObservation
        ) == "function" then

        self.Experiment:AddObservation(
            spellId,
            observation
        )
    end

    if self.debug then
        print(string.format(
            "|cff33ff99CoADamage:|r "
            .. "%s (%d) %d%s "
            .. "source=%s session=%s "
            .. "AP=%d SP=%d STR=%d "
            .. "AGI=%d INT=%d",
            spell.name,
            spellId,
            amount,
            critical and " CRIT" or "",
            snapshotSource,
            tostring(
                observation.castSessionID
                or "nil"
            ),
            snapshot.attackPower or 0,
            snapshot.spellPower or 0,
            snapshot.strength or 0,
            snapshot.agility or 0,
            snapshot.intellect or 0
        ))
    end
end