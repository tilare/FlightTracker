if not FlightTracker then return end

FlightTracker.GUI = {}
local GUI = FlightTracker.GUI

local ADDON_PATH = "Interface\\AddOns\\FlightTracker\\"
local BACKDROP_COLOR = {0.1, 0.1, 0.1, 0.9}
local BORDER_COLOR = {0.4, 0.4, 0.4, 1}

local mainFrame = nil
local optionsMenuFrame = nil

StaticPopupDialogs["FLIGHTTRACKER_RESET_STATS"] = {
    text = "Are you sure you want to reset your statistics for " .. UnitName("player") .. "?\n(Flight times will be preserved)",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function()
        if FlightTracker.charStats then
            FlightTracker.charStats.totalFlights = 0
            FlightTracker.charStats.totalTime = 0
            FlightTracker.charStats.totalGold = 0
            FlightTracker.charStats.longestFlight = { duration = 0, route = "None" }
        end
        
        if FlightTracker.GUI then FlightTracker.GUI:UpdateStats() end
        FlightTracker:Print("Statistics have been reset for " .. UnitName("player") .. ".")
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1
}

function GUI:Create()
    if mainFrame then return mainFrame end
    
    local f = CreateFrame("Frame", "FlightTrackerMain", UIParent)
    f:SetWidth(300) 
    f:SetHeight(140)
    f:SetPoint("CENTER", 0, 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(300, 140)
    f:SetClampedToScreen(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(unpack(BACKDROP_COLOR))
    f:SetBackdropBorderColor(unpack(BORDER_COLOR))
    
    f:SetScript("OnMouseDown", function() 
        if arg1 == "LeftButton" then this:StartMoving() end 
    end)
    f:SetScript("OnMouseUp", function() 
        if arg1 == "LeftButton" then this:StopMovingOrSizing() end 
    end)
    
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetWidth(24)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture(ADDON_PATH .. "img\\close.tga")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Flight Tracker")
    
    local optBtn = CreateFrame("Button", nil, f)
    optBtn:SetWidth(60)
    optBtn:SetHeight(20)
    optBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -5, -4) 
    
    optBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    optBtn:SetBackdropColor(0.1, 0.1, 0.1, 1)
    optBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local optText = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    optText:SetPoint("CENTER", 0, 0)
    optText:SetText("OPTIONS")
    optText:SetTextColor(0.7, 0.7, 0.7)
    
    optBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.2, 0.2, 0.2, 1)
        this:SetBackdropBorderColor(1, 0.82, 0, 1)
        optText:SetTextColor(1, 1, 1)
    end)
    optBtn:SetScript("OnLeave", function()
        this:SetBackdropColor(0.1, 0.1, 0.1, 1)
        this:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        optText:SetTextColor(0.7, 0.7, 0.7)
    end)
    
    optBtn:SetScript("OnClick", function()
        ToggleDropDownMenu(1, nil, optionsMenuFrame, this, 0, 0)
    end)
    
    local function CreateStatLine(label, yOffset)
        local l = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        l:SetPoint("TOPLEFT", 12, yOffset)
        l:SetText(label)
        l:SetTextColor(0.7, 0.7, 0.7)
        
        local v = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        v:SetPoint("TOPRIGHT", -12, yOffset)
        v:SetText("-")
        return v
    end
    
    f.statFlights = CreateStatLine("Total Flights:", -40)
    f.statTime    = CreateStatLine("Total Time:", -60)
    f.statGold    = CreateStatLine("Total Spent:", -80)
    
    f.statLongest = CreateStatLine("Longest Flight:", -100)
    
    f.statLongestRoute = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.statLongestRoute:SetPoint("TOP", 0, -118)
    f.statLongestRoute:SetText("-")
    f.statLongestRoute:SetJustifyH("CENTER")
    
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetWidth(16)
    resizer:SetHeight(16)
    resizer:SetPoint("BOTTOMRIGHT", -4, 4)
    resizer:SetNormalTexture(ADDON_PATH .. "img\\sizegrabber-up.tga")
    resizer:SetHighlightTexture(ADDON_PATH .. "img\\sizegrabber-highlight.tga")
    resizer:SetPushedTexture(ADDON_PATH .. "img\\sizegrabber-down.tga")
    resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    
    f:Hide()
    mainFrame = f
    
    GUI:CreateDropdown()
    GUI:UpdateStats()
    
    return f
end

function GUI:Toggle()
    if not mainFrame then
        self:Create()
        mainFrame:Show()
    else
        if mainFrame:IsShown() then
            mainFrame:Hide()
        else
            mainFrame:Show()
        end
    end
end

function GUI:CreateDropdown()
    local f = CreateFrame("Frame", "FlightTrackerOptionsMenu", UIParent, "UIDropDownMenuTemplate")
    optionsMenuFrame = f
    
    UIDropDownMenu_Initialize(f, function()
        local info = {}
        
        info.text = "Settings"
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = "Show In-Flight Timer"
        info.checked = FlightTrackerDB.settings.showTimer
        info.func = function() 
            FlightTrackerDB.settings.showTimer = not FlightTrackerDB.settings.showTimer
        end
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = "Auto Dismount"
        info.checked = FlightTrackerDB.settings.autoDismount
        info.func = function() 
            FlightTrackerDB.settings.autoDismount = not FlightTrackerDB.settings.autoDismount
        end
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = "Confirm Flights"
        info.checked = FlightTrackerDB.settings.confirmFlight
        info.func = function() 
            FlightTrackerDB.settings.confirmFlight = not FlightTrackerDB.settings.confirmFlight
        end
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = "Announce ETA to Party/Raid"
        info.checked = FlightTrackerDB.settings.announceFlight
        info.func = function() 
            FlightTrackerDB.settings.announceFlight = not FlightTrackerDB.settings.announceFlight
        end
        UIDropDownMenu_AddButton(info)

        info = {}
        info.text = "Show Minimap Button"
        info.checked = FlightTrackerDB.settings.showMinimapButton
        info.func = function() 
            FlightTrackerDB.settings.showMinimapButton = not FlightTrackerDB.settings.showMinimapButton
            if FlightTracker.UpdateMinimapButtonVisibility then
                FlightTracker:UpdateMinimapButtonVisibility()
            end
        end
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = ""
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)
        
        info = {}
        info.text = "|cffff0000Reset Statistics|r"
        info.notCheckable = true
        info.func = function()
            StaticPopup_Show("FLIGHTTRACKER_RESET_STATS")
            CloseDropDownMenus()
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")
end

function GUI:UpdateStats()
    if not mainFrame or not FlightTracker.charStats then return end
    
    local s = FlightTracker.charStats
    local u = FlightTracker.Util
    
    local formatLong = u.FormatLongTime or function(t) return t end
    local formatMoney = u.FormatMoney or function(c) return c end
    local formatTime = u.FormatTime or function(t) return t end
    
    mainFrame.statFlights:SetText(s.totalFlights or 0)
    mainFrame.statTime:SetText(formatLong(s.totalTime or 0))
    mainFrame.statGold:SetText(formatMoney(s.totalGold or 0))
    
    local lDuration = 0
    local lRoute = ""
    
    if type(s.longestFlight) == "table" then
        lDuration = s.longestFlight.duration or 0
        lRoute = s.longestFlight.route or ""
    else
        lDuration = s.longestFlight or 0
    end
    
    if string.len(lRoute) > 48 then
        lRoute = string.sub(lRoute, 1, 45) .. "..."
    end
    
    if lDuration > 0 then
        mainFrame.statLongest:SetText(formatTime(lDuration))
        mainFrame.statLongestRoute:SetText(lRoute)
    else
        mainFrame.statLongest:SetText("None")
        mainFrame.statLongestRoute:SetText("")
    end
end
