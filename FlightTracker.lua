FlightTracker = CreateFrame("Frame", "FlightTracker")
FlightTracker:SetScript("OnEvent", function()
    if FlightTracker[event] then FlightTracker[event](FlightTracker) end
end)

FlightTracker:RegisterEvent("ADDON_LOADED")
FlightTracker:RegisterEvent("PLAYER_ENTERING_WORLD")
FlightTracker:RegisterEvent("TAXIMAP_OPENED")

local ADDON_PATH = "Interface\\AddOns\\FlightTracker\\"

local isFlying = false
local isPending = false 
local pendingDestName = nil
local pendingCost = 0

local startTime = 0
local originNode = nil
local destNode = nil
local flightTimerFrame = nil

local isTooltipHooked = false
local original_TaxiNodeOnButtonEnter = nil

StaticPopupDialogs["FLIGHTTRACKER_CONFIRM"] = {
    text = "Fly to %s?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(data)
        FlightTracker.confirming = true
        TakeTaxiNode(data.index)
        FlightTracker.confirming = false
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1
}

function FlightTracker:ADDON_LOADED()
    if arg1 ~= "FlightTracker" then return end

    local playerName = UnitName("player")

    if not FlightTrackerDB then FlightTrackerDB = {} end
    
    if not FlightTrackerDB.flights then FlightTrackerDB.flights = {} end
    
    if not FlightTrackerDB.char then FlightTrackerDB.char = {} end
    if not FlightTrackerDB.char[playerName] then FlightTrackerDB.char[playerName] = {} end

    if FlightTrackerDB.stats then
        FlightTrackerDB.char[playerName].stats = FlightTrackerDB.stats
        FlightTrackerDB.stats = nil
        self:Print("Global statistics migrated to character: " .. playerName)
    end

    if not FlightTrackerDB.char[playerName].stats then 
        FlightTrackerDB.char[playerName].stats = {
            totalFlights = 0,
            totalTime = 0,
            totalGold = 0,
            longestFlight = { duration = 0, route = "None" }
        }
    end

    self.charStats = FlightTrackerDB.char[playerName].stats

    local defaultSettings = {
        showTimer = true,
        autoDismount = true,
        confirmFlight = false,
        announceFlight = false,
        minimapPos = 45,
        showMinimapButton = true
    }

    if not FlightTrackerDB.settings then 
        FlightTrackerDB.settings = {}
    end

    for key, value in pairs(defaultSettings) do
        if FlightTrackerDB.settings[key] == nil then
            FlightTrackerDB.settings[key] = value
        end
    end

    self:Print("Loaded. Type /ft or /flighttracker to show stats.")
    self:CreateTimerFrame()
    self:CreateMinimapButton()
    
    tinsert(UISpecialFrames, "FlightTrackerMain")
end

function FlightTracker:PLAYER_ENTERING_WORLD()
    if UnitOnTaxi("player") then
        isFlying = true
        startTime = GetTime()
        destNode = "Unknown"
        flightTimerFrame:Show()
        self:StartMonitor()
    else
        isFlying = false
        isPending = false
        flightTimerFrame:Hide()
    end
end

function FlightTracker:TAXIMAP_OPENED()
    if FlightTrackerDB.settings.autoDismount then
        self:DismountPlayer()
    end

    self:HookTaxiMap()
end

function FlightTracker:HookTaxiMap()
    if isTooltipHooked then return end

    local original_TakeTaxiNode = TakeTaxiNode
    TakeTaxiNode = function(index)
        local type = TaxiNodeGetType(index)
        if type == "REACHABLE" then
            local destName = TaxiNodeName(index)
            
            if FlightTrackerDB.settings.confirmFlight and not FlightTracker.confirming then
                local dialog = StaticPopup_Show("FLIGHTTRACKER_CONFIRM", destName)
                if dialog then
                    dialog.data = {index = index, name = destName}
                end
                return 
            end
            
            FlightTracker:PrepareFlight(index, destName)
        end
        original_TakeTaxiNode(index)
    end

    original_TaxiNodeOnButtonEnter = TaxiNodeOnButtonEnter
    
    TaxiNodeOnButtonEnter = function(button)
        original_TaxiNodeOnButtonEnter(button)
        
        local index = button:GetID()
        if index then
            local type = TaxiNodeGetType(index)

            if type == "REACHABLE" then
                local destName = TaxiNodeName(index)
                local origin = FlightTracker.Util.GetCurrentFlightNode()
            
                local key = origin .. " -> " .. destName
                local duration = FlightTrackerDB.flights[key]
            
                local timeText = "--:--"
                if duration then
                    timeText = FlightTracker.Util.FormatTime(duration)
                end
                
                GameTooltip:AddLine("Flight Time: " .. timeText, 1, 1, 1)
                GameTooltip:Show()
            end
        end
    end

    isTooltipHooked = true
end


function FlightTracker:PrepareFlight(index, destName)
    isPending = true
    pendingDestName = destName
    pendingCost = TaxiNodeCost(index)
    
    self:StartMonitor()
end

function FlightTracker:StartMonitor()
    self:SetScript("OnUpdate", self.OnUpdateMonitor)
end

function FlightTracker:StopMonitor()
    self:SetScript("OnUpdate", nil)
end

function FlightTracker.OnUpdateMonitor()
    local self = FlightTracker

    if isPending then
        if UnitOnTaxi("player") then
            isPending = false
            self:StartFlight(pendingDestName, pendingCost)
        end
    elseif isFlying then
        if not UnitOnTaxi("player") then
            self:EndFlight()
        end
    else
        self:StopMonitor()
    end
end

function FlightTracker:StartFlight(destination, cost)
    isFlying = true
    startTime = GetTime()
    destNode = destination
    
    if self.charStats then
        self.charStats.totalGold = self.charStats.totalGold + (cost or 0)
        self.charStats.totalFlights = self.charStats.totalFlights + 1
    end

    originNode = FlightTracker.Util.GetCurrentFlightNode()

    local key = originNode .. " -> " .. destNode
    local knownDuration = FlightTrackerDB.flights[key]
    
    if FlightTrackerDB.settings.announceFlight then
        local msg = "Flying to " .. destNode .. "."
        
        if knownDuration then
            msg = msg .. " ETA: " .. FlightTracker.Util.FormatTime(knownDuration)
        end
        
        if GetNumRaidMembers() > 0 then
            SendChatMessage(msg, "RAID")
        elseif GetNumPartyMembers() > 0 then
            SendChatMessage(msg, "PARTY")
        end
    end

    if FlightTrackerDB.settings.showTimer then
        local node, zone = string.find(destNode, "^(.+), (.+)$")
        if not node then 
            node = destNode 
            zone = GetZoneText()
        else
            node = string.sub(destNode, 0, string.find(destNode, ",") - 1)
            zone = string.sub(destNode, string.find(destNode, ",") + 2)
        end

        flightTimerFrame.destText:SetText(node)
        flightTimerFrame.zoneText:SetText(zone)
        flightTimerFrame.max = knownDuration or 0
        flightTimerFrame:Show()
    end
    
    if FlightTracker.GUI then FlightTracker.GUI:UpdateStats() end
end

function FlightTracker:EndFlight()
    isFlying = false
    flightTimerFrame:Hide()
    
    if startTime == 0 then return end

    local endTime = GetTime()
    local duration = endTime - startTime
    
    if originNode and destNode and duration > 10 then
        local key = originNode .. " -> " .. destNode
        
        FlightTrackerDB.flights[key] = duration
        
        if self.charStats then
            self.charStats.totalTime = self.charStats.totalTime + duration
            
            if duration > self.charStats.longestFlight.duration then
                self.charStats.longestFlight.duration = duration
                self.charStats.longestFlight.route = key
            end
        end
        
        self:Print("Landed at " .. destNode .. ". Time: " .. self.Util.FormatTime(duration))
        
        if FlightTracker.GUI then FlightTracker.GUI:UpdateStats() end
    end
    
    startTime = 0
    originNode = nil
    destNode = nil
    self:StopMonitor()
end

function FlightTracker:DismountPlayer()
    if Dismount then
        Dismount()
        return
    end

    if not self.scanner then
        self.scanner = CreateFrame("GameTooltip", "FlightTrackerScanner", nil, "GameTooltipTemplate")
        self.scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    end

    for i = 0, 31 do
        local index = GetPlayerBuff(i, "HELPFUL")
        if index > -1 then
            self.scanner:ClearLines()
            self.scanner:SetPlayerBuff(index)
            local text = FlightTrackerScannerTextLeft2:GetText()
            if text and string.find(text, "Increases speed by %d+%%") then
                CancelPlayerBuff(index)
                return
            end
        end
    end
end

function FlightTracker:CreateMinimapButton()
    if self.minimapButton then return end

    local b = CreateFrame("Button", "FlightTrackerMinimapButton", Minimap)
    b:SetWidth(32)
    b:SetHeight(32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)

    local iconTexture = ADDON_PATH .. "img\\flight"

    local t = b:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(iconTexture)
    t:SetWidth(20)
    t:SetHeight(20)
    t:SetPoint("CENTER", 0, 0)
    b.icon = t

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(52)
    border:SetHeight(52)
    border:SetPoint("TOPLEFT", 0, 0)

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function()
        if FlightTracker.GUI then FlightTracker.GUI:Toggle() end
    end)
    
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("Flight Tracker")
        GameTooltip:AddLine("Click to open UI", 1, 1, 1)
        GameTooltip:AddLine("Shift+Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    
    b:SetScript("OnDragStart", function() 
        if IsShiftKeyDown() then
            this:LockHighlight() 
            this.isDragging = true 
        end
    end)
    
    b:SetScript("OnDragStop", function() this:UnlockHighlight() this.isDragging = false end)
    b:SetScript("OnUpdate", function()
        if this.isDragging then
            local xpos, ypos = GetCursorPosition()
            local xmin, ymin = Minimap:GetLeft(), Minimap:GetBottom()
            xpos = xmin - xpos / UIParent:GetScale() + 70
            ypos = ypos / UIParent:GetScale() - ymin - 70
            
            local angle = math.deg(math.atan2(ypos, xpos))
            FlightTrackerDB.settings.minimapPos = angle
            FlightTracker:UpdateMinimapButtonPosition()
        end
    end)
    
    self.minimapButton = b
    self:UpdateMinimapButtonPosition()
    self:UpdateMinimapButtonVisibility()
end

function FlightTracker:UpdateMinimapButtonVisibility()
    if not self.minimapButton then return end
    if FlightTrackerDB.settings.showMinimapButton then
        self.minimapButton:Show()
    else
        self.minimapButton:Hide()
    end
end

function FlightTracker:UpdateMinimapButtonPosition()
    if not self.minimapButton then return end
    local angle = FlightTrackerDB.settings.minimapPos or 45
    local radius = 80
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    
    self.minimapButton:SetPoint("CENTER", "Minimap", "CENTER", -x, y)
end

function FlightTracker:CreateTimerFrame()
    local f = CreateFrame("Frame", "FlightTrackerTimer", UIParent)
    f:SetWidth(180)
    f:SetHeight(64)
    f:SetPoint("TOP", 0, -50)
    f:SetClampedToScreen(true)
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", 
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    
    f:SetScript("OnMouseDown", function() 
        if IsShiftKeyDown() and arg1 == "LeftButton" then 
            this:StartMoving() 
        end 
    end)
    f:SetScript("OnMouseUp", function() 
        if arg1 == "LeftButton" then this:StopMovingOrSizing() end 
    end)
    f:Hide()

    f:SetResizable(true)
    f:SetMinResize(140, 64)
    f:SetMaxResize(300, 100)

    local resizer = CreateFrame("Button", nil, f)
    resizer:SetWidth(16)
    resizer:SetHeight(16)
    resizer:SetPoint("BOTTOMRIGHT", -4, 4)
    resizer:SetNormalTexture(ADDON_PATH .. "img\\sizegrabber-up.tga")
    resizer:SetHighlightTexture(ADDON_PATH .. "img\\sizegrabber-highlight.tga")
    resizer:SetPushedTexture(ADDON_PATH .. "img\\sizegrabber-down.tga")
    resizer:SetScript("OnMouseDown", function() 
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizer:SetScript("OnMouseUp", function() 
        f:StopMovingOrSizing()
    end)
    
    f.destText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.destText:SetPoint("TOP", 0, -10)
    f.destText:SetText("Destination")
    f.destText:SetFont("Fonts\\FRIZQT__.TTF", 12)
    
    f.zoneText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.zoneText:SetPoint("TOP", f.destText, "BOTTOM", 0, -2)
    f.zoneText:SetText("Zone Name")
    f.zoneText:SetTextColor(0.7, 0.7, 0.7)
    f.zoneText:SetFont("Fonts\\FRIZQT__.TTF", 10)

    f.timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.timerText:SetPoint("BOTTOM", 0, 10)
    f.timerText:SetText("00:00")
    f.timerText:SetTextColor(1, 0.82, 0)
    f.timerText:SetFont("Fonts\\FRIZQT__.TTF", 16)
    
    f:SetScript("OnSizeChanged", function()
        local h = this:GetHeight()
        local scale = h / 64
        if scale < 0.8 then scale = 0.8 end
        
        this.destText:SetFont("Fonts\\FRIZQT__.TTF", 12 * scale)
        this.zoneText:SetFont("Fonts\\FRIZQT__.TTF", 10 * scale)
        this.timerText:SetFont("Fonts\\FRIZQT__.TTF", 16 * scale)
    end)
    
    local help = CreateFrame("Frame", nil, f)
    help:SetWidth(16)
    help:SetHeight(16)
    help:SetPoint("TOPRIGHT", -4, -4)
    help:EnableMouse(true)
    
    local helpText = help:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("CENTER", 0, 0)
    helpText:SetText("?")
    helpText:SetTextColor(0.5, 0.5, 0.5)
    
    help:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Shift+Drag to Move")
        GameTooltip:Show()
        helpText:SetTextColor(1, 1, 1)
    end)
    help:SetScript("OnLeave", function()
        GameTooltip:Hide()
        helpText:SetTextColor(0.5, 0.5, 0.5)
    end)
    
    f:SetScript("OnUpdate", function()
        if not isFlying then return end

        if not this.elapsed then this.elapsed = 0 end
        this.elapsed = this.elapsed + arg1
        if this.elapsed < 0.5 then return end
        this.elapsed = 0
        
        local current = GetTime() - startTime
        local text = ""
        
        if this.max and this.max > 0 then
            local remaining = this.max - current
            if remaining < 0 then remaining = 0 end
            text = FlightTracker.Util.FormatTime(remaining)
        else
            text = FlightTracker.Util.FormatTime(current)
        end
        this.timerText:SetText(text)
    end)
    flightTimerFrame = f
end

SLASH_FLIGHTTRACKER1 = "/ft"
SLASH_FLIGHTTRACKER2 = "/flighttracker"
SlashCmdList["FLIGHTTRACKER"] = function(msg)
    if FlightTracker.GUI then 
        FlightTracker.GUI:Toggle()
    else
        FlightTracker:Print("GUI module not loaded.")
    end
end

function FlightTracker:Print(msg)
    local prefix = "|cffE0C709Flight|cffffffffTracker:|r"
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. " " .. tostring(msg))
end

