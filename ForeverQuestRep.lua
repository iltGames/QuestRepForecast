local addonName, addon = ...
local overlays, turnInsByFaction = {}, {}
local questReputation, questDB, faction, hoveredTracker
local current, maximum, readyRep, inProgressRep, bagRep
local refreshQueued, repRateTicker, fillAtlasInfo
local fillAtlas = "UI-HUD-ExperienceBar-Fill-ArtifactPower"
local barMaskAtlas = "UI-HUD-ExperienceBar-Fill-Experience"
local timeToStandingFormatter = CreateAndInitFromMixin(SecondsFormatterMixin, 0, SecondsFormatter.Abbreviation.Truncate)

for questID, turnIn in pairs(addon.turnIns) do
    for _, factionID in ipairs(turnIn[3]) do
        local quests = turnInsByFaction[factionID] or {}
        quests[#quests + 1] = questID
        turnInsByFaction[factionID] = quests
    end
end

local function GetStandingProgress(data)
    local factionID = data.factionID
    if C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
        return
    end

    local friendship = C_GossipInfo and C_GossipInfo.GetFriendshipReputation(factionID)
    if friendship and friendship.friendshipFactionID > 0 then
        if friendship.nextThreshold and friendship.nextThreshold > friendship.reactionThreshold then
            return friendship.standing - friendship.reactionThreshold, friendship.nextThreshold - friendship.reactionThreshold
        end
    elseif data.reaction < (MAX_REPUTATION_REACTION or 8) then
        local span = data.nextReactionThreshold - data.currentReactionThreshold
        if span > 0 then
            return data.currentStanding - data.currentReactionThreshold, span
        end
    end
end

local function GetQuestGain(questID, factionID)
    -- Questie applies the active Legacy Diplomat rank as part of the reward estimate.
    local gain = 0
    for _, reward in ipairs(questReputation.GetReputationReward(questID) or {}) do
        if reward[1] == factionID and reward[2] > 0 then
            gain = gain + reward[2]
        end
    end
    return math.floor(gain + 0.5)
end

local function RequiresCloth(questID)
    if addon.clothQuests[questID] then return true end
    local objectives = questDB.QueryQuestSingle(questID, "objectives")
    for _, objective in pairs(objectives and objectives[3] or {}) do
        if addon.clothItems[objective[1]] then return true end
    end
    return false
end

local function ScanQuestLog(factionID)
    local ready, inProgress, active = 0, 0, {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() do
        local entry = C_QuestLog.GetInfo(index)
        if entry and not entry.isHeader and not entry.isHidden and entry.questID > 0 and not RequiresCloth(entry.questID) then
            local questID = entry.questID
            local gain = GetQuestGain(questID, factionID)
            if gain > 0 then
                local isReady = C_QuestLog.ReadyForTurnIn(questID) == true
                active[questID] = isReady
                if not addon.settings.trackedOnly or C_QuestLog.GetQuestWatchType(questID) ~= nil then
                    if isReady then
                        ready = ready + gain
                    else
                        inProgress = inProgress + gain
                    end
                end
            end
        end
    end
    return ready, inProgress, active
end

local function CountBagItems()
    local items = {}
    for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local item = C_Container.GetContainerItemInfo(bag, slot)
            if item and item.itemID and item.stackCount then
                items[item.itemID] = (items[item.itemID] or 0) + item.stackCount
            end
        end
    end
    return items
end

local function SpendItems(items, requirements, batches)
    for itemID, amount in pairs(requirements) do
        items[itemID] = math.max(0, (items[itemID] or 0) - batches * amount)
    end
end

local function CountBatches(items, requirements)
    local batches = math.huge
    for itemID, amount in pairs(requirements) do
        batches = math.min(batches, math.floor((items[itemID] or 0) / amount))
    end
    return batches
end

local function HasTurnInStarter(questID, items)
    local starters = questDB.QueryQuestSingle(questID, "startedBy")
    if not starters or not starters[3] or next(starters[1] or {}) or next(starters[2] or {}) then return true end
    for _, itemID in ipairs(starters[3]) do
        if (items[itemID] or 0) > 0 then return true end
    end
    return false
end

local function ScanBagTurnIns(data, active)
    local questIDs = turnInsByFaction[data.factionID]
    if not questIDs then return 0 end

    local items = CountBagItems()
    for questID in pairs(active) do
        local turnIn = addon.turnIns[questID]
        if turnIn then SpendItems(items, turnIn[4], 1) end
    end

    local offers, level = {}, UnitLevel("player")
    for _, questID in ipairs(questIDs) do
        local turnIn = addon.turnIns[questID]
        local requirements = turnIn[4]
        if level >= turnIn[1] and CountBatches(items, requirements) > 0 then
            local repeatable = turnIn[2] and questDB.IsRepeatable(questID)
                and not (questDB.IsDailyQuest(questID) or questDB.IsWeeklyQuest(questID) or questDB.IsMonthlyQuest(questID))
            local onQuest = active[questID] ~= nil or C_QuestLog.IsOnQuest(questID)
            local available = not onQuest and (repeatable or not C_QuestLog.IsQuestFlaggedCompleted(questID))
                and questDB.IsDoable(questID) and HasTurnInStarter(questID, items)
            if available or (repeatable and active[questID]) then
                local gain = GetQuestGain(questID, data.factionID)
                if gain > 0 and not RequiresCloth(questID) then
                    local itemTotal = 0
                    for _, amount in pairs(requirements) do itemTotal = itemTotal + amount end
                    offers[#offers + 1] = { id = questID, items = requirements, gain = gain,
                        valuePerItem = gain / itemTotal, repeatable = repeatable }
                end
            end
        end
    end

    -- Allocate shared bag stacks once, preferring the higher reputation per item.
    table.sort(offers, function(left, right)
        if left.valuePerItem == right.valuePerItem then return left.id < right.id end
        return left.valuePerItem > right.valuePerItem
    end)
    local total = 0
    for _, offer in ipairs(offers) do
        local batches = CountBatches(items, offer.items)
        if not offer.repeatable then batches = math.min(1, batches) end
        local limit = questDB.QueryQuestSingle(offer.id, "requiredMaxRep")
        if limit and limit[1] == data.factionID then
            local remaining = limit[2] - data.currentStanding - readyRep - total
            batches = math.min(batches, math.max(0, math.ceil(remaining / offer.gain)))
        end
        SpendItems(items, offer.items, batches)
        total = total + offer.gain * batches
    end
    return total
end

local function SetSegment(texture, bar, width, height, start, finish)
    if finish <= start then
        texture:Hide()
        return
    end
    if fillAtlasInfo then
        local left, right = fillAtlasInfo.leftTexCoord, fillAtlasInfo.rightTexCoord
        texture:SetTexCoord(left + (right - left) * start, left + (right - left) * finish,
            fillAtlasInfo.topTexCoord, fillAtlasInfo.bottomTexCoord)
    end
    texture:SetPoint("TOPLEFT", bar, "TOPLEFT", width * start, 0)
    texture:SetSize(width * (finish - start), height)
    texture:Show()
end

local function DrawForecast(bar)
    local overlay = overlays[bar]
    local width, height = bar:GetSize()
    if not maximum or width <= 0 or height <= 0 then
        overlay.ready:Hide()
        overlay.inProgress:Hide()
        overlay.bag:Hide()
        return
    end

    local start = math.max(0, math.min(1, current / maximum))
    local ready = math.min(1, start + readyRep / maximum)
    local bagEnd = math.min(1, ready + bagRep / maximum)
    local finish = math.min(1, bagEnd + inProgressRep / maximum)
    SetSegment(overlay.ready, bar, width, height, start, ready)
    SetSegment(overlay.bag, bar, width, height, ready, bagEnd)
    SetSegment(overlay.inProgress, bar, width, height, bagEnd, finish)
end

local function FormatRep(amount)
    return BreakUpLargeNumbers(math.floor(amount + 0.5))
end

local function GetRepToNextStanding()
    if maximum then return math.max(0, maximum - current) end
end

local function UpdateRepBarText(tracker, hovering)
    if not faction or not tracker.SetBarText or (tracker.factionID and tracker.factionID ~= faction.factionID) then return end
    local remaining = GetRepToNextStanding()
    local text = faction.name
    if remaining then
        text = ("%s %s / %s  -  %s rep to next standing  -  %s rep from turn-ins"):format(
            text, FormatRep(current), FormatRep(maximum), FormatRep(remaining), FormatRep(readyRep + bagRep + inProgressRep))
    end
    if hovering == nil then
        hovering = tracker:IsMouseMotionFocus()
    end
    if hovering or addon.settings.alwaysShowRepText then
        text = text .. "  -  " .. FormatRep(addon.GetSessionRates()) .. " rep/hr"
    end
    tracker:SetBarText(text)
end

local function ShowRepBarTextIfEnabled(tracker)
    local frame = tracker.OverlayFrame
    if addon.settings.alwaysShowRepText and frame and frame.Text then
        frame.Text:Show()
    end
end

local function ApplyFillAppearance(texture, key, brightness)
    local color, opacity = addon.settings[key .. "Color"], addon.settings[key .. "Opacity"]
    if fillAtlasInfo then
        local r, g, b = brightness, brightness, brightness
        local customized = color ~= addon.defaultFillColor
        if customized then r, g, b = CreateColorFromHexString(color):GetRGB() end
        texture:SetDesaturated(customized)
        texture:SetVertexColor(r, g, b, opacity)
    else
        local r, g, b = CreateColorFromHexString(color):GetRGB()
        if color ~= addon.defaultFillColor then brightness = 1 end
        texture:SetColorTexture(r * brightness, g * brightness, b * brightness, opacity)
    end
end

local function ApplyOverlayAppearance(overlay)
    ApplyFillAppearance(overlay.ready, "ready", 0.8)
    ApplyFillAppearance(overlay.bag, "bag", 0.8)
    ApplyFillAppearance(overlay.inProgress, "inProgress", 0.55)
    local frame = overlay.tracker.OverlayFrame
    local text = frame and frame.Text
    if text then
        local font, size, flags = text:GetFont()
        local desiredSize = addon.settings.fontSize
        if font and size ~= desiredSize then text:SetFont(font, desiredSize, flags) end
    end
end

local function RefreshAppearance()
    for _, overlay in pairs(overlays) do
        ApplyOverlayAppearance(overlay)
    end
end

local function RefreshPinnedRepBarText()
    if InCombatLockdown() then return end
    for _, overlay in pairs(overlays) do
        UpdateRepBarText(overlay.tracker)
    end
end

local function ApplyRepBarTextSetting()
    if addon.settings.alwaysShowRepText then
        repRateTicker = repRateTicker or C_Timer.NewTicker(30, RefreshPinnedRepBarText)
    elseif repRateTicker then
        repRateTicker:Cancel()
        repRateTicker = nil
    end
    for _, overlay in pairs(overlays) do
        local tracker = overlay.tracker
        if tracker.UpdateTextVisibility then tracker:UpdateTextVisibility() end
        UpdateRepBarText(tracker)
    end
end

local function HideForecastTooltip(tracker)
    if hoveredTracker ~= tracker then return end
    hoveredTracker = nil
    if GameTooltip:GetOwner() == tracker then
        GameTooltip:Hide()
    end
end

local function ShowForecastTooltip(tracker)
    if not faction then
        HideForecastTooltip(tracker)
        return
    end
    if GameTooltip:IsShown() and hoveredTracker ~= tracker then return end
    if GameTooltip:GetOwner() ~= tracker then
        GameTooltip:SetOwner(tracker, "ANCHOR_TOP")
    end
    hoveredTracker = tracker
    GameTooltip:SetText(faction.name)
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    GameTooltip_AddNormalLine(GameTooltip, addon.settings.trackedOnly and "Tracked quests" or "Quest rep")
    GameTooltip:AddDoubleLine("Ready to turn in", FormatRep(readyRep) .. " rep", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("In progress", FormatRep(inProgressRep) .. " rep", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Bag turn-ins", FormatRep(bagRep) .. " rep", 1, 0.82, 0, 1, 1, 1)
    local remaining = GetRepToNextStanding()
    if remaining then
        local afterForecast = math.max(0, remaining - readyRep - bagRep - inProgressRep)
        GameTooltip:AddDoubleLine("Rep remaining after forecast", FormatRep(afterForecast) .. " rep", 1, 0.82, 0, 1, 1, 1)
    end
    local hourlyRate, perKill = addon.GetSessionRates()
    GameTooltip_AddBlankLineToTooltip(GameTooltip)
    GameTooltip_AddNormalLine(GameTooltip, "Session")
    GameTooltip:AddDoubleLine("Session rep per hour", FormatRep(hourlyRate) .. " rep", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Avg rep per kill", perKill and FormatRep(perKill) .. " rep" or "Not enough data", 1, 0.82, 0, 1, 1, 1)
    if remaining then
        local time = hourlyRate > 0 and timeToStandingFormatter:Format(remaining * 3600 / hourlyRate) or "Not enough data"
        GameTooltip:AddDoubleLine("Time to next standing", time, 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function RefreshHoveredTooltip()
    if hoveredTracker and GameTooltip:GetOwner() == hoveredTracker then
        ShowForecastTooltip(hoveredTracker)
    end
end

local function CreateFillTexture(bar, mask)
    local texture = bar:CreateTexture(nil, "ARTWORK", nil, -1)
    if mask then
        texture:SetTexture(fillAtlasInfo.file or fillAtlasInfo.filename)
        texture:AddMaskTexture(mask)
    end
    texture:Hide()
    return texture
end

local function AttachOverlay(tracker)
    local bar = tracker and tracker.StatusBar
    if not bar or overlays[bar] then return end
    local mask
    if fillAtlasInfo then
        mask = bar:CreateMaskTexture()
        mask:SetAtlas(barMaskAtlas)
        mask:SetAllPoints(bar)
    end
    local overlay = { tracker = tracker, ready = CreateFillTexture(bar, mask),
        inProgress = CreateFillTexture(bar, mask), bag = CreateFillTexture(bar, mask) }
    overlays[bar] = overlay
    bar:HookScript("OnSizeChanged", DrawForecast)
    bar:HookScript("OnShow", DrawForecast)
    if tracker.UpdateCurrentText then hooksecurefunc(tracker, "UpdateCurrentText", UpdateRepBarText) end
    if tracker.UpdateTextVisibility then
        hooksecurefunc(tracker, "UpdateTextVisibility", ShowRepBarTextIfEnabled)
        tracker:UpdateTextVisibility()
    end
    tracker:HookScript("OnEnter", function(self)
        UpdateRepBarText(self, true)
        ShowForecastTooltip(self)
    end)
    tracker:HookScript("OnLeave", function(self)
        UpdateRepBarText(self, false)
        HideForecastTooltip(self)
    end)
    tracker:HookScript("OnHide", HideForecastTooltip)
    ApplyOverlayAppearance(overlay)
end

local function RefreshForecast()
    refreshQueued = false
    if not addon.settings then return end
    local data = C_Reputation.GetWatchedFactionData()
    addon.UpdateSession(data)
    faction, current, maximum = nil, nil, nil
    if questReputation and data and data.factionID > 0 then
        faction = data
        current, maximum = GetStandingProgress(data)
        local active
        readyRep, inProgressRep, active = ScanQuestLog(data.factionID)
        bagRep = ScanBagTurnIns(data, active)
    end

    local manager = StatusTrackingBarManager
    if not next(overlays) then
        local atlas = C_Texture and C_Texture.GetAtlasInfo(fillAtlas)
        if atlas and (atlas.file or atlas.filename) then fillAtlasInfo = atlas end
    end
    local repIndex = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum.Reputation
    if manager and manager.barContainers and repIndex then
        for _, container in ipairs(manager.barContainers) do
            AttachOverlay(container.bars and container.bars[repIndex])
        end
    else
        AttachOverlay(ReputationWatchBar)
    end
    for bar, overlay in pairs(overlays) do
        DrawForecast(bar)
        UpdateRepBarText(overlay.tracker)
    end
    RefreshHoveredTooltip()
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, RefreshForecast)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")
events:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
events:RegisterEvent("PARTY_KILL")
events:RegisterEvent("UPDATE_FACTION")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("TRAIT_CONFIG_UPDATED")
events:RegisterEvent("TRAIT_NODE_CHANGED")
events:RegisterUnitEvent("UNIT_AURA", "player")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == addonName then
            addon.RegisterSettings(QueueRefresh, RefreshAppearance, ApplyRepBarTextSetting)
        elseif loaded ~= "Blizzard_StatusTrackingBar" then
            return
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if addon.settings and addon.settings.firstRunPending then C_Timer.After(0, addon.ShowPendingSetupPopup) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        addon.ShowPendingSetupPopup()
    end
    addon.RecordSessionEvent(event, ...)
    if event ~= "CHAT_MSG_COMBAT_FACTION_CHANGE" and event ~= "CHAT_MSG_COMBAT_XP_GAIN" and event ~= "PARTY_KILL" then
        QueueRefresh()
    end
end)
C_Timer.NewTicker(5, RefreshHoveredTooltip)

Questie.API.RegisterOnReady(function()
    questReputation = QuestieLoader:ImportModule("QuestieReputation")
    questDB = QuestieLoader:ImportModule("QuestieDB")
    QueueRefresh()
end)
