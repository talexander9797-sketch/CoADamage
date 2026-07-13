function CoA:InitializeDatabase()
    CoADamageDB = CoADamageDB or {}
    CoADamageDB.version = 5
    CoADamageDB.spells = CoADamageDB.spells or {}
    CoADamageDB.experiments = CoADamageDB.experiments or {}
    CoADamageDB.nextExperimentID = CoADamageDB.nextExperimentID or 1
end

function CoA:GetSpell(id)
    local spell = CoADamageDB.spells[id]

    if not spell then
        spell = {}
        CoADamageDB.spells[id] = spell
    end

    spell.hits = spell.hits or 0
    spell.totalDamage = spell.totalDamage or 0
    spell.crits = spell.crits or 0
    spell.min = spell.min
    spell.max = spell.max

    spell.normalHits = spell.normalHits or 0
    spell.normalTotal = spell.normalTotal or 0
    spell.normalMin = spell.normalMin
    spell.normalMax = spell.normalMax

    spell.critHits = spell.critHits or spell.crits or 0
    spell.critTotal = spell.critTotal or 0
    spell.critMin = spell.critMin
    spell.critMax = spell.critMax

    spell.observations = spell.observations or {}
    return spell
end

function CoA:AddObservation(spell, observation)
    local observations = spell.observations
    table.insert(observations, observation)

    local limit = self.MAX_OBSERVATIONS_PER_SPELL or 500
    while #observations > limit do
        table.remove(observations, 1)
    end
end
