if not FlightTracker then return end

FlightTracker.Checklist = {}
local Checklist = FlightTracker.Checklist

local ADDON_PATH = "Interface\\AddOns\\FlightTracker\\"
local BACKDROP_COLOR = {0.1, 0.1, 0.1, 0.9}
local BORDER_COLOR = {0.4, 0.4, 0.4, 1}
local ROW_HEIGHT = 18
local MAX_ROWS = 30

local checklistFrame = nil
local scrollFrame = nil
local rows = {}
local displayList = {}
local displayCount = 0
local summaryText = nil

local fullList = {}
local fullCount = 0

-- Zone-to-continent mapping
local EASTERN_KINGDOMS = "Eastern Kingdoms"
local KALIMDOR = "Kalimdor"
local OTHER = "Other"

local zoneContinent = {
    -- Eastern Kingdoms
    ["Alterac Mountains"] = EASTERN_KINGDOMS,
    ["Arathi Highlands"] = EASTERN_KINGDOMS,
    ["Arathi"] = EASTERN_KINGDOMS,
    ["Badlands"] = EASTERN_KINGDOMS,
    ["Balor"] = EASTERN_KINGDOMS,
    ["Blasted Lands"] = EASTERN_KINGDOMS,
    ["Burning Steppes"] = EASTERN_KINGDOMS,
    ["Deadwind Pass"] = EASTERN_KINGDOMS,
    ["Dun Morogh"] = EASTERN_KINGDOMS,
    ["Duskwood"] = EASTERN_KINGDOMS,
    ["Eastern Plaguelands"] = EASTERN_KINGDOMS,
    ["Elwynn Forest"] = EASTERN_KINGDOMS,
    ["Grim Reaches"] = EASTERN_KINGDOMS,
    ["Hillsbrad Foothills"] = EASTERN_KINGDOMS,
    ["Hillsbrad"] = EASTERN_KINGDOMS,
    ["Ironforge"] = EASTERN_KINGDOMS,
    ["Lapidis Isle"] = EASTERN_KINGDOMS,
    ["Loch Modan"] = EASTERN_KINGDOMS,
    ["Northwind"] = EASTERN_KINGDOMS,
    ["Redridge Mountains"] = EASTERN_KINGDOMS,
    ["Redridge"] = EASTERN_KINGDOMS,
    ["Searing Gorge"] = EASTERN_KINGDOMS,
    ["Silverpine Forest"] = EASTERN_KINGDOMS,
    ["Stormwind City"] = EASTERN_KINGDOMS,
    ["Stranglethorn Vale"] = EASTERN_KINGDOMS,
    ["Stranglethorn"] = EASTERN_KINGDOMS,
    ["Swamp of Sorrows"] = EASTERN_KINGDOMS,
    ["The Hinterlands"] = EASTERN_KINGDOMS,
    ["Thalassian Highlands"] = EASTERN_KINGDOMS,
    ["Tirisfal Glades"] = EASTERN_KINGDOMS,
    ["Undercity"] = EASTERN_KINGDOMS,
    ["Western Plaguelands"] = EASTERN_KINGDOMS,
    ["Westfall"] = EASTERN_KINGDOMS,
    ["Wetlands"] = EASTERN_KINGDOMS,
    ["Gilneas"] = EASTERN_KINGDOMS,
    ["Gillijim's Isle"] = EASTERN_KINGDOMS,
    ["Tirisfal"] = EASTERN_KINGDOMS,
    -- Kalimdor
    ["Ashenvale"] = KALIMDOR,
    ["Azshara"] = KALIMDOR,
    ["Darkshore"] = KALIMDOR,
    ["Desolace"] = KALIMDOR,
    ["Durotar"] = KALIMDOR,
    ["Dustwallow Marsh"] = KALIMDOR,
    ["Felwood"] = KALIMDOR,
    ["Feralas"] = KALIMDOR,
    ["Moonglade"] = KALIMDOR,
    ["Moonwhisper Coast"] = KALIMDOR,
    ["Mulgore"] = KALIMDOR,
    ["Orgrimmar"] = KALIMDOR,
    ["Silithus"] = KALIMDOR,
    ["Stonetalon Mountains"] = KALIMDOR,
    ["Tanaris"] = KALIMDOR,
    ["Tel'Abim"] = KALIMDOR,
    ["Teldrassil"] = KALIMDOR,
    ["The Barrens"] = KALIMDOR,
    ["Thousand Needles"] = KALIMDOR,
    ["Thunder Bluff"] = KALIMDOR,
    ["Un'Goro Crater"] = KALIMDOR,
    ["Winterspring"] = KALIMDOR,
    ["Hyjal"] = KALIMDOR,
}

local function GetZoneFromNode(nodeName)
    local _, _, zone = string.find(nodeName, "^.+,%s*(.+)$")
    return zone or nodeName
end

local function GetContinent(nodeName)
    local zone = GetZoneFromNode(nodeName)
    return zoneContinent[zone] or OTHER
end

-- Continent sort order
local continentOrder = {
    [EASTERN_KINGDOMS] = 1,
    [KALIMDOR] = 2,
    [OTHER] = 3,
}

local function BuildFullList()
    fullList = {}
    fullCount = 0

    local routes = FlightTrackerDB.routes
    if not routes then routes = {} end

    local playerFaction = UnitFactionGroup("player")

    local function MatchesFaction(tag)
        return tag == true or tag == playerFaction or tag == "Both"
    end

    -- Build preloaded destinations lookup from node data
    local preloadDests = {}
    local preload = FlightTracker.PreloadedNodes
    if preload then
        for continent, factions in pairs(preload) do
            local nodes = factions[playerFaction]
            if nodes then
                for i = 1, table.getn(nodes) do
                    local src = nodes[i]
                    if not preloadDests[src] then
                        preloadDests[src] = {}
                    end
                    for j = 1, table.getn(nodes) do
                        if i ~= j then
                            preloadDests[src][nodes[j]] = true
                        end
                    end
                end
            end
        end
    end

    -- Collect all source nodes (confirmed + preloaded), faction-filtered
    local sourceSet = {}
    local sourceList = {}

    for source, dests in pairs(routes) do
        for dest, factionTag in pairs(dests) do
            if MatchesFaction(factionTag) then
                if not sourceSet[source] then
                    sourceSet[source] = true
                    tinsert(sourceList, source)
                end
                if not sourceSet[dest] then
                    sourceSet[dest] = true
                    tinsert(sourceList, dest)
                end
            end
        end
    end

    for node in pairs(preloadDests) do
        if not sourceSet[node] then
            sourceSet[node] = true
            tinsert(sourceList, node)
        end
    end

    -- Sort sources by continent, then alphabetically
    table.sort(sourceList, function(a, b)
        local ca = continentOrder[GetContinent(a)] or 99
        local cb = continentOrder[GetContinent(b)] or 99
        if ca ~= cb then return ca < cb end
        return a < b
    end)

    local knownRoutes = {}
    for source, dests in pairs(routes) do
        for dest, factionTag in pairs(dests) do
            if MatchesFaction(factionTag) then
                knownRoutes[source .. " -> " .. dest] = true
            end
        end
    end

    local lastContinent = nil
    local continentRecorded = {}
    local continentTotal = {}

    for i = 1, table.getn(sourceList) do
        local source = sourceList[i]
        local continent = GetContinent(source)
        local destSet = {}
        local destList = {}

        if routes[source] then
            for dest, factionTag in pairs(routes[source]) do
                if MatchesFaction(factionTag) and not destSet[dest] then
                    destSet[dest] = true
                    tinsert(destList, dest)
                end
            end
        end

        if preloadDests[source] then
            for dest in pairs(preloadDests[source]) do
                if not destSet[dest] then
                    destSet[dest] = true
                    tinsert(destList, dest)
                end
            end
        end

        if table.getn(destList) > 0 then
            table.sort(destList)

            if continent ~= lastContinent then
                fullCount = fullCount + 1
                fullList[fullCount] = {
                    isContinent = true,
                    text = continent
                }
                continentRecorded[continent] = 0
                continentTotal[continent] = 0
                lastContinent = continent
            end

            local srcRecorded = 0
            local srcTotal = table.getn(destList)
            for j = 1, srcTotal do
                local flightKey = source .. " -> " .. destList[j]
                if knownRoutes[flightKey] and FlightTrackerDB.flights[flightKey] then
                    srcRecorded = srcRecorded + 1
                end
            end

            continentRecorded[continent] = continentRecorded[continent] + srcRecorded
            continentTotal[continent] = continentTotal[continent] + srcTotal

            -- Header row
            fullCount = fullCount + 1
            fullList[fullCount] = {
                isHeader = true,
                text = source,
                continent = continent,
                srcRecorded = srcRecorded,
                srcTotal = srcTotal
            }

            -- Destination rows
            for j = 1, srcTotal do
                local dest = destList[j]
                local flightKey = source .. " -> " .. dest
                local duration = FlightTrackerDB.flights[flightKey]
                local state

                if knownRoutes[flightKey] and duration then
                    state = "recorded"
                elseif knownRoutes[flightKey] then
                    state = "known"
                else
                    state = "undiscovered"
                end

                fullCount = fullCount + 1
                fullList[fullCount] = {
                    isHeader = false,
                    continent = continent,
                    source = source,
                    dest = dest,
                    state = state,
                    duration = duration
                }
            end
        end
    end

    for i = 1, fullCount do
        local item = fullList[i]
        if item.isContinent then
            item.cRecorded = continentRecorded[item.text] or 0
            item.cTotal = continentTotal[item.text] or 0
        end
    end
end

local function BuildDisplayList()
    BuildFullList()

    displayList = {}
    displayCount = 0

    local expanded = FlightTrackerDB.checklistExpanded

    for i = 1, fullCount do
        local item = fullList[i]
        if item.isContinent then
            -- Continent headers always shown
            displayCount = displayCount + 1
            displayList[displayCount] = item
        elseif item.isHeader then
            -- Source headers only shown if continent is expanded
            if expanded[item.continent] then
                displayCount = displayCount + 1
                displayList[displayCount] = item
            end
        else
            -- Route rows only shown if both continent and source are expanded
            if expanded[item.continent] and expanded[item.source] then
                displayCount = displayCount + 1
                displayList[displayCount] = item
            end
        end
    end
end

local function GetRouteCounts()
    local recorded = 0
    local total = 0
    for i = 1, fullCount do
        local item = fullList[i]
        if not item.isHeader and not item.isContinent then
            total = total + 1
            if item.state == "recorded" then
                recorded = recorded + 1
            end
        end
    end
    return recorded, total
end

local function ToggleSource(sourceName)
    if FlightTrackerDB.checklistExpanded[sourceName] then
        FlightTrackerDB.checklistExpanded[sourceName] = nil
    else
        FlightTrackerDB.checklistExpanded[sourceName] = true
    end
end

local HEADER_HEIGHT = 48
local BOTTOM_PAD = 20

local function GetVisibleRows()
    if not checklistFrame then return 18 end
    local contentHeight = checklistFrame:GetHeight() - HEADER_HEIGHT - BOTTOM_PAD
    if contentHeight <= 0 then return 1 end
    local count = math.floor(contentHeight / ROW_HEIGHT)
    if count > MAX_ROWS then count = MAX_ROWS end
    if count < 1 then count = 1 end
    return count
end

local function UpdateScroll()
    if not checklistFrame or not scrollFrame then return end

    local visibleRows = GetVisibleRows()
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    FauxScrollFrame_Update(scrollFrame, displayCount, visibleRows, ROW_HEIGHT)

    for i = 1, MAX_ROWS do
        local row = rows[i]
        local index = offset + i

        if i > visibleRows then
            row:Hide()
        elseif index <= displayCount then
            local data = displayList[index]

            if data.isContinent then
                local isExpanded = FlightTrackerDB.checklistExpanded[data.text]
                local arrow = isExpanded and "v " or "> "
                local countText = "  |cff808080(" .. data.cRecorded .. "/" .. data.cTotal .. ")|r"

                row.status:SetText("")

                row.text:SetText(arrow .. "|cffffffff" .. data.text .. "|r" .. countText)
                row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.time:SetText("")
                row.headerSource = data.text
                row:Show()
            elseif data.isHeader then
                local isExpanded = FlightTrackerDB.checklistExpanded[data.text]
                local arrow = isExpanded and "v " or "> "
                local countText = "  |cff808080(" .. data.srcRecorded .. "/" .. data.srcTotal .. ")|r"

                row.status:SetText("")

                row.text:SetText(arrow .. "|cffE0C709" .. data.text .. "|r" .. countText)
                row.text:SetPoint("LEFT", row, "LEFT", 12, 0)
                row.time:SetText("")
                row.headerSource = data.text
                row:Show()
            else
                local statusChar, sr, sg, sb
                local tr, tg, tb

                if data.state == "recorded" then
                    statusChar = "+"
                    sr, sg, sb = 0, 1, 0
                    tr, tg, tb = 1, 1, 1
                elseif data.state == "known" then
                    statusChar = "o"
                    sr, sg, sb = 1, 0.82, 0
                    tr, tg, tb = 0.7, 0.7, 0.7
                else
                    statusChar = "?"
                    sr, sg, sb = 0.5, 0.5, 0.5
                    tr, tg, tb = 0.4, 0.4, 0.4
                end

                row.status:SetText(statusChar)
                row.status:SetTextColor(sr, sg, sb)

                row.text:SetText(data.dest)
                row.text:SetTextColor(tr, tg, tb)
                row.text:SetPoint("LEFT", row, "LEFT", 32, 0)

                if data.duration then
                    row.time:SetText(FlightTracker.Util.FormatTime(data.duration))
                    row.time:SetTextColor(0.7, 0.7, 0.7)
                else
                    row.time:SetText("--:--")
                    row.time:SetTextColor(0.3, 0.3, 0.3)
                end
                row.headerSource = nil
                row:Show()
            end
        else
            row:Hide()
        end
    end

    -- Update summary
    local recorded, total = GetRouteCounts()
    if summaryText then
        summaryText:SetText(recorded .. "/" .. total .. " routes recorded")
    end
end

function Checklist:Create()
    if checklistFrame then return checklistFrame end

    local f = CreateFrame("Frame", "FlightTrackerChecklist", UIParent)
    f:SetWidth(340)
    f:SetHeight(400)
    f:SetPoint("CENTER", 100, 0)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(300, 250)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")

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

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetWidth(24)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetNormalTexture(ADDON_PATH .. "img\\close.tga")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Route Checklist")

    -- Summary
    summaryText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", 12, -30)
    summaryText:SetTextColor(1, 0.82, 0)
    summaryText:SetText("0/0 routes recorded")

    -- Legend
    local legend = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("TOPRIGHT", -12, -30)
    legend:SetText("|cff00ff00+|r Recorded  |cffffcc00o|r Known  |cff808080?|r Undiscovered")
    legend:SetTextColor(0.6, 0.6, 0.6)

    -- Scroll area
    local scrollArea = CreateFrame("Frame", nil, f)
    scrollArea:SetPoint("TOPLEFT", 8, -48)
    scrollArea:SetPoint("BOTTOMRIGHT", -28, BOTTOM_PAD)

    scrollFrame = CreateFrame("ScrollFrame", "FlightTrackerChecklistScroll", scrollArea, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollFrame:SetScript("OnVerticalScroll", function()
        FauxScrollFrame_OnVerticalScroll(ROW_HEIGHT, UpdateScroll)
    end)

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, scrollArea)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollArea, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", scrollArea, "RIGHT", 0, 0)

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.status:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.status:SetWidth(16)
        row.status:SetJustifyH("CENTER")

        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
        row.text:SetPoint("RIGHT", row, "RIGHT", -50, 0)
        row.text:SetJustifyH("LEFT")

        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.time:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.time:SetJustifyH("RIGHT")

        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetAllPoints(row)
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.3)

        row.headerSource = nil
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function()
            if this.headerSource then
                ToggleSource(this.headerSource)
                BuildDisplayList()
                UpdateScroll()
            end
        end)

        rows[i] = row
    end

    -- Resizer
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetWidth(16)
    resizer:SetHeight(16)
    resizer:SetPoint("BOTTOMRIGHT", -4, 4)
    resizer:SetNormalTexture(ADDON_PATH .. "img\\sizegrabber-up.tga")
    resizer:SetHighlightTexture(ADDON_PATH .. "img\\sizegrabber-highlight.tga")
    resizer:SetPushedTexture(ADDON_PATH .. "img\\sizegrabber-down.tga")
    resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)

    f:SetScript("OnSizeChanged", function()
        UpdateScroll()
    end)

    f:SetScript("OnShow", function()
        Checklist:Refresh()
    end)

    f:Hide()
    checklistFrame = f

    tinsert(UISpecialFrames, "FlightTrackerChecklist")

    return f
end

function Checklist:Toggle()
    if not checklistFrame then
        self:Create()
    end
    if checklistFrame:IsShown() then
        checklistFrame:Hide()
    else
        checklistFrame:Show()
    end
end

function Checklist:IsOpen()
    return checklistFrame and checklistFrame:IsShown()
end

function Checklist:Refresh()
    BuildDisplayList()
    UpdateScroll()
end
