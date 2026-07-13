CoA.CastQueue = CoA.CastQueue or {}
CoA.CastQueue.queue = CoA.CastQueue.queue or {}

function CoA:QueueSnapshot(spellID)
    if type(self.CapturePlayerSnapshot) ~= "function" then
        return
    end

    local snapshot = self:CapturePlayerSnapshot()

    table.insert(self.CastQueue.queue, {
        spellID = spellID,
        snapshot = snapshot,
        time = GetTime()
    })
end

function CoA:GetQueuedSnapshot(spellID)
    for i = 1, #self.CastQueue.queue do
        local queued = self.CastQueue.queue[i]

        if queued.spellID == spellID then
            table.remove(self.CastQueue.queue, i)
            return queued.snapshot
        end
    end

    return nil
end

function CoA:GetQueueSize()
    return #self.CastQueue.queue
end

function CoA:ClearCastQueue()
    self.CastQueue.queue = {}
end