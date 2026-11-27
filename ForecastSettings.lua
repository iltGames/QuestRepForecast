local addonName, addon = ...
local title = "Quest Rep Forecast"
local setupControls, welcomePopup

addon.defaultFillColor = "FFDBA540"
addon.defaultBagColor = "FF45B8A1"

local function RegisterSetting(category, key, varType, label, default, onChange)
    local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key,
        addon.settings, varType, label, default)
    setting:SetValueChangedCallback(onChange)
    return setting
end

local function RegisterSlider(category, key, label, default, minimum, maximum, step, tooltip, formatter, onChange)
    local setting = RegisterSetting(category, key, Settings.VarType.Number, label, default, onChange)
    local options = Settings.CreateSliderOptions(minimum, maximum, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

local function RegisterFill(category, key, label, color, opacity, onChange)
    local setting = RegisterSetting(category, key .. "Color", Settings.VarType.String, label .. " color", color, onChange)
    local swatch = Settings.CreateColorSwatch(category, setting, "Choose the color of this reputation forecast fill.")
    local slider = RegisterSlider(category, key .. "Opacity", label .. " opacity", opacity, 0, 1, 0.05,
        "Adjust how much of the default reputation bar shows through this fill.",
        function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end, onChange)
    return swatch, slider
end

function addon.RegisterSettings(refreshForecast, refreshAppearance, refreshBarText)
    ForeverQuestRepDB = ForeverQuestRepDB or { firstRunPending = true }
    addon.settings = ForeverQuestRepDB

    local category = Settings.RegisterVerticalLayoutCategory(title)
    local trackedSetting = RegisterSetting(category, "trackedOnly", Settings.VarType.Boolean,
        "Tracked quests only", false, refreshForecast)
    local trackedOnly = Settings.CreateCheckbox(category, trackedSetting,
        "Only preview quest rep from quests tracked in the objective tracker. Bag turn-ins are shown separately.")
    local readyColor, readyOpacity = RegisterFill(category, "ready", "Ready to turn in", addon.defaultFillColor, 0.55, refreshAppearance)
    local bagColor, bagOpacity = RegisterFill(category, "bag", "Bag turn-ins", addon.defaultBagColor, 0.55, refreshAppearance)
    local inProgressColor, inProgressOpacity = RegisterFill(category, "inProgress", "In progress", addon.defaultFillColor, 0.40, refreshAppearance)
    local fontSize = RegisterSlider(category, "fontSize", "Rep bar font size", 12, 8, 24, 1,
        "Change the size of the text shown on the reputation bar.", tostring, refreshAppearance)
    local showTextSetting = RegisterSetting(category, "alwaysShowRepText", Settings.VarType.Boolean,
        "Always show rep bar text", false, refreshBarText)
    local alwaysShowText = Settings.CreateCheckbox(category, showTextSetting,
        "Keep the reputation bar text visible when the mouse is away from the bar.")

    setupControls = { trackedOnly, readyColor, readyOpacity, bagColor, bagOpacity,
        inProgressColor, inProgressOpacity, fontSize, alwaysShowText }
    Settings.RegisterAddOnCategory(category)
    refreshBarText()
end

function addon.ShowPendingSetupPopup()
    local settings = addon.settings
    if not settings or not settings.firstRunPending or InCombatLockdown() then return end

    if not welcomePopup then
        local popup = CreateFrame("Frame", addonName .. "WelcomePopup", UIParent, "BasicFrameTemplateWithInset")
        welcomePopup = popup
        popup:SetSize(620, 156 + #setupControls * 34)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("HIGH")
        popup:SetClampedToScreen(true)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup.TitleText:SetText(title)
        tinsert(UISpecialFrames, popup:GetName())

        local titleBar = CreateFrame("Frame", nil, popup)
        titleBar:SetPoint("TOPLEFT", 0, 0)
        titleBar:SetPoint("TOPRIGHT", -28, 0)
        titleBar:SetHeight(22)
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function() popup:StartMoving() end)
        titleBar:SetScript("OnDragStop", function() popup:StopMovingOrSizing() end)
        popup:HookScript("OnHide", function() popup:StopMovingOrSizing() end)

        local description = popup:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        description:SetPoint("TOPLEFT", 24, -44)
        description:SetPoint("TOPRIGHT", -24, -44)
        description:SetJustifyH("LEFT")
        description:SetText("Customize how turn-ins appear on your watched reputation bar. Changes apply immediately.\n"
            .. "Hover over the bar for the forecast and session grind stats.")

        for index, initializer in ipairs(setupControls) do
            local control = CreateFrame("Frame", nil, popup, initializer:GetTemplate())
            control:SetPoint("TOPLEFT", 12, -88 - (index - 1) * 34)
            control:SetPoint("TOPRIGHT", -12, -88 - (index - 1) * 34)
            -- The Options list normally supplies this accessor through its ScrollBox.
            control.GetElementData = function() return initializer end
            control:Init(initializer)
        end

        local done = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        done:SetSize(100, 24)
        done:SetPoint("BOTTOM", 0, 18)
        done:SetText("Done")
        done:SetScript("OnClick", function() popup:Hide() end)
    end

    welcomePopup:Show()
    settings.firstRunPending = nil
end

SLASH_QUESTREPFORECASTCONFIG1 = "/qrfconfig"
SlashCmdList.QUESTREPFORECASTCONFIG = function()
    if not addon.settings then return end
    addon.settings.firstRunPending = true
    addon.ShowPendingSetupPopup()
end
