if not FlightTracker then return end

FlightTracker.Util = {}

function FlightTracker.Util.GetCurrentFlightNode()
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then
            return TaxiNodeName(i)
        end
    end
    return GetZoneText()
end

function FlightTracker.Util.FormatTime(seconds)
    if not seconds then return "00:00" end
    local m = math.floor(seconds / 60)
    local s = math.floor(math.mod(seconds, 60))
    return string.format("%02d:%02d", m, s)
end

function FlightTracker.Util.FormatLongTime(seconds)
    if not seconds or seconds == 0 then return "None" end
    
    local d = math.floor(seconds / 86400)
    local h = math.floor(math.mod(seconds, 86400) / 3600)
    local m = math.floor(math.mod(seconds, 3600) / 60)
    local s = math.floor(math.mod(seconds, 60))
    
    local text = ""
    if d > 0 then text = text .. d .. "d " end
    if h > 0 then text = text .. h .. "h " end
    if m > 0 then text = text .. m .. "m " end
    
    text = text .. s .. "s"
    
    return text
end

function FlightTracker.Util.FormatMoney(amount)
    if not amount then amount = 0 end
    
    local gold = math.floor(amount / 10000)
    local silver = math.floor(math.mod(amount, 10000) / 100)
    local copper = math.mod(amount, 100)
    
    local text = ""
    
    if gold > 0 then
        text = text .. "|cffffffff" .. gold .. "|r|cffffd700G|r "
    end
    if silver > 0 or gold > 0 then
        text = text .. "|cffffffff" .. silver .. "|r|cffc7c7cfS|r "
    end
    text = text .. "|cffffffff" .. copper .. "|r|cffeda55fC|r"
    
    return text
end