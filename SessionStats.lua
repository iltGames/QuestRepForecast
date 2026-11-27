local _, addon = ...
local sessions = {}
local session, pending, lastQuestTurnIn
local matchWindow, maxSamples, maxAge = 0.5, 20, 20 * 60

local function IsReadable(value, expectedType)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == expectedType
end

local function EscapePattern(text)
    return (text:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

local function MakeMessagePattern(format, allowSuffix)
    if not format then return end
    local pattern, cursor, nameFirst = "^", 1, nil
    while true do
        local first, last, kind = format:find("%%%d*%$?([sd])", cursor)
        if not first then break end
        if nameFirst == nil then nameFirst = kind == "s" end
        pattern = pattern .. EscapePattern(format:sub(cursor, first - 1))
            .. (kind == "s" and "(.+)" or "(%d+)")
        cursor = last + 1
    end
    return pattern .. EscapePattern(format:sub(cursor)) .. (allowSuffix and "" or "$"), nameFirst
end

local reputationPatterns = {}
local function AddReputationPattern(format)
    local pattern, nameFirst = MakeMessagePattern(format)
    if pattern then
        reputationPatterns[#reputationPatterns + 1] = { pattern = pattern, nameFirst = nameFirst }
    end
end
AddReputationPattern(FACTION_STANDING_INCREASED)
AddReputationPattern(FACTION_STANDING_INCREASED_ACCOUNT_WIDE)
local killXPPattern = MakeMessagePattern(COMBATLOG_XPGAIN_FIRSTPERSON, true)

function addon.UpdateSession(data)
    local now = GetTime()
    local id = data and data.factionID
    if id and id <= 0 then id = nil end
    if session and session.id ~= id then
        session.elapsed = session.elapsed + now - session.startedAt
        session, pending = nil, nil
    end
    if not id then return end
    if not session then
        session = sessions[id] or { id = id, elapsed = 0, earned = 0, kills = {} }
        session.startedAt, session.lastStanding = now, nil
        sessions[id] = session
    end
    session.name = data.name
    local standing = data.currentStanding
    if IsReadable(standing, "number") then
        if session.lastStanding then
            session.earned = session.earned + math.max(0, standing - session.lastStanding)
        end
        session.lastStanding = standing
    end
end

local function GetPendingBatch(now)
    if pending then return pending end
    local batch = { at = now, kills = 0, xpKills = 0, gains = {} }
    pending = batch
    C_Timer.After(matchWindow, function()
        if pending ~= batch then return end
        pending = nil
        if lastQuestTurnIn and lastQuestTurnIn >= batch.at - matchWindow then return end

        -- A death can produce both events. Skip batches where the gains can't be paired with kills.
        if #batch.gains ~= math.max(batch.kills, batch.xpKills) then return end
        for _, gain in ipairs(batch.gains) do
            local kills = session.kills
            kills[#kills + 1] = { at = batch.at, gain = gain }
            if #kills > maxSamples then table.remove(kills, 1) end
        end
    end)
    return batch
end

function addon.RecordSessionEvent(event, first, second)
    if not session then return end
    local now = GetTime()
    if event == "QUEST_TURNED_IN" then
        lastQuestTurnIn = now
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" and IsReadable(first, "string") then
        for _, entry in ipairs(reputationPatterns) do
            local left, right = first:match(entry.pattern)
            local name, amount = left, right
            if not entry.nameFirst then name, amount = right, left end
            local gain = tonumber(amount)
            if name == session.name and gain and gain > 0 then
                local batch = GetPendingBatch(now)
                batch.gains[#batch.gains + 1] = gain
                return
            end
        end
    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" and killXPPattern and IsReadable(first, "string")
        and first:match(killXPPattern) then
        local batch = GetPendingBatch(now)
        batch.xpKills = batch.xpKills + 1
    elseif event == "PARTY_KILL" and IsReadable(first, "string") and IsReadable(second, "string")
        and (second:match("^Creature%-") or second:match("^Vehicle%-")) then
        local player, pet = UnitGUID("player"), UnitGUID("pet")
        if (IsReadable(player, "string") and player == first) or (IsReadable(pet, "string") and pet == first) then
            local batch = GetPendingBatch(now)
            batch.kills = batch.kills + 1
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        pending = nil
    end
end

function addon.GetSessionRates()
    if not session then return 0 end
    local now = GetTime()
    local elapsed = session.elapsed + now - session.startedAt
    local total, count = 0, 0
    for index = #session.kills, 1, -1 do
        local sample = session.kills[index]
        if sample.at < now - maxAge then break end
        total, count = total + sample.gain, count + 1
    end
    return elapsed > 0 and session.earned * 3600 / elapsed or 0, count > 0 and total / count or nil
end
