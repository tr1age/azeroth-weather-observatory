-- Weather Forever: independent implementation; no network access.
local ADDON = ...
local MAX_OBSERVATIONS = 250
local frame, conditionText, detailText, statusText, exportBox, minimapButton
local zoneRows, pageLabel, feedLabel, previousButton, nextButton = {}, nil, nil, nil, nil
local page = 1
local selectedWeather, selectedContinent, selectedZone, searchText = "all", "All continents", "All zones", ""
local searchBox, emptyLabel, conditionIcon, currentZoneText, shareNote, shareDot, sharePulse, partyButton
local weatherIcons = {clear="|TInterface\\AddOns\\AzerothWeather\\Media\\Clear:18:18|t", rain="|TInterface\\AddOns\\AzerothWeather\\Media\\Rain:18:18|t", snow="|TInterface\\Icons\\Spell_Frost_IceStorm:18:18|t", sandstorm="|TInterface\\Icons\\Spell_Nature_EarthShock:18:18|t", miscellaneous="|TInterface\\Icons\\INV_Misc_QuestionMark:18:18|t", unknown="—"}
local weatherNames = {clear="Clear", rain="Rain", snow="Snow", sandstorm="Sand", miscellaneous="Miscellaneous", unknown="Unknown"}
local continents, zoneCatalog = {}, {}
local function addZones(continent, list) for zone in list:gmatch("[^|]+") do continents[zone:lower()] = continent; zoneCatalog[#zoneCatalog+1] = {zone=zone, continent=continent} end end
addZones("Eastern Kingdoms", "Alterac Mountains|Arathi Highlands|Badlands|Blasted Lands|Burning Steppes|Deadwind Pass|Dun Morogh|Duskwood|Eastern Plaguelands|Elwynn Forest|Hillsbrad Foothills|Ironforge|Loch Modan|Redridge Mountains|Searing Gorge|Silverpine Forest|Stormwind City|Stranglethorn Vale|Swamp of Sorrows|The Hinterlands|Tirisfal Glades|Undercity|Western Plaguelands|Westfall|Wetlands|Eversong Woods|Ghostlands|Silvermoon City|Isle of Quel'Danas")
addZones("Kalimdor", "Ashenvale|Azshara|Azuremyst Isle|Bloodmyst Isle|Darkshore|Darnassus|Desolace|Durotar|Dustwallow Marsh|Felwood|Feralas|Moonglade|Mulgore|Orgrimmar|Silithus|Stonetalon Mountains|Tanaris|Teldrassil|The Barrens|The Exodar|Thousand Needles|Thunder Bluff|Un'Goro Crater|Winterspring")
local function continent(zone) return continents[zone:lower()] or "Other / Unknown" end
local function displayRealm(realm)
    local region, number = realm:match("^[Cc][Aa][Mm][Ww][Oo][Ww]%s+(%S+)%s+[Rr]ealm%s+(%d+)")
    local kind = realm:match("([Rr][Pp]%s+[Pp][Vv][Pp])$") or realm:match("([Rr][Pp]%s+[Pp][Vv][Ee])$") or realm:match("([Pp][Vv][Pp])$") or realm:match("([Pp][Vv][Ee])$")
    if region then return region:upper() .. " · Realm " .. number .. (kind and " · " .. kind or "") end
    return realm:gsub("[Cc][Aa][Mm][Ww][Oo][Ww]%s*", "")
end
local ROW_COUNT = 5
local ready = false
local current
local inferredLayer, layerVotes, layerSeen = nil, {}, {}
local observe, updateUI
local lastSignature, lastSavedAt = nil, 0
local lastManualAt = 0
local message = "Waiting for a weather observation."
local events = CreateFrame("Frame")
local function chat(text) print("|cff65cdd1[Weather Forever]|r " .. text) end
local function isSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end
local function safeText(value, fallback)
    if isSecret(value) or type(value) ~= "string" or value == "" then return fallback end
    return value
end
local function getLocation()
    local zone = safeText(GetZoneText and GetZoneText(), nil)
    local subzone = safeText(GetSubZoneText and GetSubZoneText(), "")
    local realm = safeText(GetRealmName and GetRealmName(), "Unknown realm")
    return zone, subzone, realm
end
local function classify(kind)
    local enums = Enum and Enum.WeatherType
    if type(enums) ~= "table" then return "unknown" end
    for _, pair in ipairs({{"Clear", "clear"}, {"Rain", "rain"}, {"Snow", "snow"}, {"Sandstorm", "sandstorm"}, {"Miscellaneous", "miscellaneous"}}) do
        if type(enums[pair[1]]) == "number" and kind == enums[pair[1]] then return pair[2] end
    end
    return "unknown"
end
-- A layer is inferred from agreeing nearby NPC identifiers, never from player names.
-- The numeric pair is an estimate, not a Blizzard-provided layer number.
local function resetLayer()
    inferredLayer, layerVotes, layerSeen = nil, {}, {}
end
local function sampleLayer(unit)
    if type(unit) ~= "string" or not UnitGUID then return end
    if IsInInstance then local ok, inside=pcall(IsInInstance); if not ok or isSecret(inside) or inside then return end end
    if UnitPlayerControlled then local ok, controlled=pcall(UnitPlayerControlled, unit); if not ok or isSecret(controlled) or controlled then return end end
    local ok, guid=pcall(UnitGUID, unit)
    if not ok or isSecret(guid) or type(guid) ~= "string" or layerSeen[guid] then return end
    local server, zoneId=guid:match("^Creature%-%d+%-(%d+)%-%d+%-(%d+)%-%d+%-%x+$")
    if not server then server, zoneId=guid:match("^Vehicle%-%d+%-(%d+)%-%d+%-(%d+)%-%d+%-%x+$") end
    if not server or #server>10 or #zoneId>10 then return end
    layerSeen[guid]=true
    local id=server .. "-" .. zoneId
    layerVotes[#layerVotes+1]=id
    if #layerVotes>5 then table.remove(layerVotes,1) end
    local count=0; for _, v in ipairs(layerVotes) do if v==id then count=count+1 end end
    if id~=inferredLayer and count >= (inferredLayer and 3 or 2) then
        inferredLayer=id
        if ready and observe then observe() end
    end
end
local function sampleNearby()
    sampleLayer("target"); sampleLayer("mouseover")
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates=pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates)=="table" and not isSecret(plates) then
            for _, plate in ipairs(plates) do
                if not isSecret(plate) then local valid, unit=pcall(function() return plate.namePlateUnitToken end); if valid then sampleLayer(unit) end end
            end
        end
    end
end
local function jsonString(value)
    return '"' .. tostring(value):gsub('[%z\1-\31\\"]', function(c)
        local replacements = {['\\']='\\\\', ['"']='\\"', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
        return replacements[c] or string.format('\\u%04x', string.byte(c))
    end) .. '"'
end
local function encode(record)
    if not record then return "" end
    local fields = {
        '"zone":' .. jsonString(record.zone),
        '"realm":' .. jsonString(record.realm),
        '"weather":' .. jsonString(record.weather),
        '"observed_at":' .. jsonString(date('!%Y-%m-%dT%H:%M:%SZ', record.at)),
        '"source":' .. jsonString(record.source),
    }
    if record.layer then fields[#fields + 1] = '"layer":' .. jsonString(record.layer) end
    if record.intensity then fields[#fields + 1] = '"intensity":' .. tostring(record.intensity) end
    return '{' .. table.concat(fields, ',') .. '}'
end
local function zoneReports()
    local newest = {}
    local function add(record, label)
        if type(record) ~= "table" or type(record.zone) ~= "string" or type(record.realm) ~= "string" or type(record.weather) ~= "string" or type(record.at) ~= "number" then return end
        local key = record.zone:lower()
        if not newest[key] or newest[key].record.at < record.at then newest[key] = {record=record, label=label} end
    end
    local feed = AzerothWeatherWebsiteFeed
    if type(feed) == "table" and type(feed.observations) == "table" then for _, r in ipairs(feed.observations) do add(r, "Website") end end
    if type(AzerothWeatherDB) == "table" and type(AzerothWeatherDB.observations) == "table" then for _, r in ipairs(AzerothWeatherDB.observations) do local existing=newest[type(r.zone)=="string" and r.zone:lower() or ""]; if not existing or existing.label=="You" then add(r, "You") end end end
    if AzerothWeather_GetPeerReports then for _,r in pairs(AzerothWeather_GetPeerReports()) do add(r,"In-game") end end
    local result = {}; for _, zone in ipairs(zoneCatalog) do local item = newest[zone.zone:lower()] or {record={zone=zone.zone}, label=""}; result[#result+1] = item end
    table.sort(result, function(a,b) local ca, cb = continent(a.record.zone), continent(b.record.zone); if ca ~= cb then return ca < cb end; return a.record.zone:lower() < b.record.zone:lower() end)
    return result
end
-- The world map uses only reports for the player's realm and inferred layer.
function AzerothWeather_GetMapReports()
    local realm=safeText(GetRealmName and GetRealmName(), "")
    local layer=current and current.layer or nil
    local result={}
    local function consider(r)
        if type(r)~="table" or type(r.zone)~="string" or type(r.realm)~="string" or type(r.weather)~="string" or type(r.at)~="number" then return end
        if r.realm~=realm or r.layer~=layer then return end
        local key=r.zone:lower(); local old=result[key]
        if not old or r.at>old.at then result[key]=r end
    end
    local feed=AzerothWeatherWebsiteFeed
    if type(feed)=="table" and type(feed.observations)=="table" then for _,r in ipairs(feed.observations) do consider(r) end end
    if type(AzerothWeatherDB)=="table" and type(AzerothWeatherDB.observations)=="table" then for _,r in ipairs(AzerothWeatherDB.observations) do consider(r) end end
    if AzerothWeather_GetPeerReports then for _,r in pairs(AzerothWeather_GetPeerReports()) do consider(r) end end
    return result, layer
end
function AzerothWeather_GetCurrentObservation() return current end
function AzerothWeather_PeerUpdated() if ready then updateUI() end end
local function ageLabel(at)
    local elapsed = math.max(0, time() - at)
    if elapsed < 60 then return "just now" end
    if elapsed < 3600 then return math.floor(elapsed / 60) .. "m ago" end
    if elapsed < 86400 then return math.floor(elapsed / 3600) .. "h ago" end
    return math.floor(elapsed / 86400) .. "d ago"
end
local function refreshZoneReports()
    if not pageLabel then return end
    local all = zoneReports()
    local entries = {}
    for _, item in ipairs(all) do
        local r = item.record
        if (selectedWeather == "all" or r.weather == selectedWeather) and (selectedContinent == "All continents" or continent(r.zone) == selectedContinent) and (selectedZone == "All zones" or r.zone == selectedZone) and (searchText == "" or r.zone:lower():find(searchText, 1, true)) then entries[#entries+1] = item end
    end
    if emptyLabel then if #entries == 0 then emptyLabel:Show() else emptyLabel:Hide() end end
    local pages = math.max(1, math.ceil(#entries / ROW_COUNT))
    page = math.max(1, math.min(page, pages))
    pageLabel:SetText("PAGE " .. page .. " / " .. pages)
    for i, row in ipairs(zoneRows) do
        local item = entries[(page-1)*ROW_COUNT+i]
        if item then
            local r=item.record
            row.zone:SetText(r.zone .. "  ·  " .. continent(r.zone))
            row.icon:SetText(weatherIcons[r.weather] or weatherIcons.unknown)
            if r.at then
                row.realm:SetText("Realm: " .. displayRealm(r.realm) .. "  ·  Layer: " .. (r.layer and (tostring(r.layer) .. " (estimated)") or "Unknown"))
                row.weather:SetText(weatherNames[r.weather] or "Unknown")
                local count=tonumber(r.count) or 0
                local summary = item.label=="In-game" and "In-game report" or (count>0 and (r.tied and "Tied · latest" or (count .. (count==1 and " reporter" or " reporters"))) or "Reported")
                row.age:SetText(summary .. " · " .. ageLabel(r.at))
                if time()-r.at > 1800 then row.age:SetTextColor(0.80, 0.65, 0.45) else row.age:SetTextColor(0.62, 0.75, 0.72) end
            else
                row.realm:SetText("Waiting for a traveler’s report"); row.weather:SetText("No reported weather"); row.age:SetText("")
            end
            row:Show()
        else row:Hide() end
    end
    local feed = AzerothWeatherWebsiteFeed
    if type(feed)=="table" and type(feed.fetchedAt)=="number" then
        feedLabel:SetText("Updated " .. ageLabel(feed.fetchedAt) .. " · /reload for newer reports")
    else feedLabel:SetText("Showing your reports · companion adds more zones") end
    if previousButton then previousButton:SetEnabled(page > 1) end
    if nextButton then nextButton:SetEnabled(page < pages) end
end
updateUI = function()
    if not frame then return end
    if current then
        conditionText:SetText(weatherNames[current.weather] or "Unknown")
        if conditionIcon then conditionIcon:SetText(weatherIcons[current.weather] or weatherIcons.unknown) end
        local where = current.zone
        if current.subzone ~= "" then where = where .. " · " .. current.subzone end
        currentZoneText:SetText(where)
        detailText:SetText("Realm: " .. displayRealm(current.realm) .. "  ·  Layer: " .. (current.layer and (current.layer .. " (estimated)") or "Unknown") .. "  ·  " .. ageLabel(current.at))
        statusText:SetText(message)
        exportBox:SetText(encode(current))
    else
        conditionText:SetText("Unknown")
        if conditionIcon then conditionIcon:SetText(weatherIcons.unknown) end
        currentZoneText:SetText("Waiting for your location")
        detailText:SetText("No current observation")
        statusText:SetText(message)
        exportBox:SetText("")
    end
    refreshZoneReports()
    if shareNote then
        local on = AzerothWeatherDB and AzerothWeatherDB.peerSharing
        shareNote:SetText("     Share with addon users: " .. (on and "ON" or "OFF"))
        if shareDot then
            shareDot:SetColorTexture(on and 1 or .35, on and .18 or .35, on and .18 or .35, 1)
            if on then if not sharePulse:IsPlaying() then sharePulse:Play() end else sharePulse:Stop(); shareDot:SetAlpha(1) end
        end
    end
    if partyButton then partyButton:SetText("Share party weather: " .. ((AzerothWeatherDB and AzerothWeatherDB.partyForecast) and "ON" or "OFF")) end
    if AzerothWeather_RefreshMap then pcall(AzerothWeather_RefreshMap) end
    if AzerothWeather_RefreshPanelMap then pcall(AzerothWeather_RefreshPanelMap) end
end
local function saveObservation(weather, intensity, source)
    local zone, subzone, realm = getLocation()
    if not zone then message = "Current zone is unavailable."; updateUI(); return end
    local now = time()
    if source == "manual" and lastManualAt > 0 and now - lastManualAt < 10 then
        message = "Please wait a few seconds before another report."
        updateUI(); return
    end
    if source == "manual" then lastManualAt = now end
    local record = {zone=zone, subzone=subzone, realm=realm, weather=weather, intensity=intensity, at=now, source=source, layer=inferredLayer}
    local previous = current
    current = record
    if source == "client" and AzerothWeather_PartyWeatherChanged then AzerothWeather_PartyWeatherChanged(previous, record) end
    local signature = table.concat({zone, subzone, realm, weather, tostring(intensity or ""), source, inferredLayer or ""}, "|")
    if source == "manual" or signature ~= lastSignature or now - lastSavedAt >= 300 then
        local log = AzerothWeatherDB.observations
        log[#log + 1] = record
        while #log > MAX_OBSERVATIONS do table.remove(log, 1) end
        lastSavedAt, lastSignature = now, signature
    end
    message = source == "manual" and "Report saved. Choose Share manually or use the companion." or "Your weather is recorded automatically."
    updateUI()
end
local function readWeather()
    local ok, result = pcall(function()
        if not C_Weather or type(C_Weather.GetCurrentWeather) ~= "function" then return nil end
        local info = C_Weather.GetCurrentWeather()
        if isSecret(info) or type(info) ~= "table" then return nil end
        local kind, intensity = info.type, info.intensity
        if isSecret(kind) or isSecret(intensity) or type(kind) ~= "number" or type(intensity) ~= "number" then return nil end
        if intensity ~= intensity or intensity < 0 or intensity > 10 then return nil end
        local weather=classify(kind)
        if weather=="unknown" then return nil end
        return {weather=weather, intensity=intensity}
    end)
    if ok then return result end
    return nil
end
observe = function()
    if not ready then return end
    local result=readWeather()
    if not result then
        current = nil
        message = "Weather unavailable. Reports cannot be checked right now."
        updateUI()
        return
    end
    saveObservation(result.weather, result.intensity, "client")
end
local function reportWeather(weather)
    local detected=readWeather()
    if not detected then
        message="Report not saved: the game’s weather could not be checked."
        updateUI(); return
    end
    if detected.weather ~= weather then
        message="Report not saved: the game reports " .. (weatherNames[detected.weather] or "different weather") .. "."
        updateUI(); return
    end
    saveObservation(detected.weather, detected.intensity, "manual")
end
local function addButton(parent, label, width, x, y, click)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 25); b:SetPoint("TOPLEFT", x, y)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
    b:SetBackdropColor(.09,.22,.29,.95); b:SetBackdropBorderColor(.27,.49,.57,1)
    local text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); text:SetPoint("CENTER"); b:SetFontString(text); b:SetText(label); b:SetScript("OnClick", click)
    b:SetScript("OnEnter", function(self) self:SetBackdropColor(.14,.32,.39,1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropColor(.09,.22,.29,.95) end)
    return b
end
local function toggleWindow()
    if frame:IsShown() then frame:Hide() else frame:Show(); updateUI() end
end
local function createMinimapButton()
    if not Minimap then return end
    local button = CreateFrame("Button", "AzerothWeatherMinimapButton", Minimap)
    minimapButton = button
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp"); button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03"); icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder"); border:SetSize(54, 54); border:SetPoint("TOPLEFT", -1, 1)
    local function place()
        local degrees = tonumber(AzerothWeatherDB.minimapAngle) or 225
        local angle = math.rad(degrees)
        local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2 + 5
        button:ClearAllPoints(); button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle)*radius, math.sin(angle)*radius)
    end
    local moved = false
    button:SetScript("OnMouseDown", function() moved = false end)
    button:SetScript("OnClick", function() if not moved then toggleWindow() end end)
    button:SetScript("OnDragStart", function(self)
        moved = true
        self:SetScript("OnUpdate", function()
            local cx, cy = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            if not cx or not cy or not scale or scale == 0 then return end
            local x, y = GetCursorPosition(); x, y = x / scale - cx, y / scale - cy
            AzerothWeatherDB.minimapAngle = math.deg(math.atan2(y, x))
            place()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); place() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:AddLine("Weather Forever", 1, 0.82, 0)
        if current then GameTooltip:AddLine(current.zone .. " · " .. current.weather, 1, 1, 1) else GameTooltip:AddLine("No current observation", 1, 1, 1) end
        GameTooltip:AddLine("Left-click: open or close", 0.7, 0.85, 0.9)
        GameTooltip:AddLine("Drag: move around minimap", 0.7, 0.85, 0.9); GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    place()
    if AzerothWeatherDB.minimapHidden then button:Hide() end
end
local function sectionLine(parent, y)
    local line = parent:CreateTexture(nil, "ARTWORK"); line:SetColorTexture(0.25, 0.55, 0.62, 0.55)
    line:SetPoint("TOPLEFT", 24, y); line:SetPoint("TOPRIGHT", -24, y); line:SetHeight(1)
end
local function createUI()
    frame = CreateFrame("Frame", "AzerothWeatherFrame", UIParent, "BackdropTemplate")
    frame:SetSize(610, 625); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Buttons\\WHITE8X8", edgeSize=1})
    frame:SetBackdropColor(.025,.075,.12,.98); frame:SetBackdropBorderColor(.25,.48,.57,1)
    frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local icon=frame:CreateTexture(nil,"ARTWORK"); icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03"); icon:SetSize(30,30); icon:SetPoint("TOPLEFT",22,-17)
    local title=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); title:SetPoint("TOPLEFT",62,-19); title:SetText("WEATHER FOREVER"); title:SetTextColor(.85,.94,1)
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-4,-3)
    local subtitle=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); subtitle:SetPoint("TOPLEFT",63,-40); subtitle:SetText("Weather reports from across Azeroth · /weather map toggles map markers"); subtitle:SetTextColor(.55,.75,.82)
    sectionLine(frame,-58)
    local weatherPanel=frame:CreateTexture(nil,"BACKGROUND"); weatherPanel:SetPoint("TOPLEFT",24,-65); weatherPanel:SetSize(562,71); weatherPanel:SetColorTexture(.07,.20,.27,.95)
    local accent=frame:CreateTexture(nil,"ARTWORK"); accent:SetPoint("TOPLEFT",24,-65); accent:SetSize(3,71); accent:SetColorTexture(.40,.78,.83,1)
    local locationLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); locationLabel:SetPoint("TOPLEFT",38,-70); locationLabel:SetText("YOUR WEATHER  ·  CURRENT ZONE"); locationLabel:SetTextColor(.54,.83,.87)
    currentZoneText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); currentZoneText:SetPoint("TOPLEFT",38,-84); currentZoneText:SetWidth(350); currentZoneText:SetJustifyH("LEFT"); currentZoneText:SetWordWrap(false); currentZoneText:SetTextColor(.94,.97,1)
    conditionIcon=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); conditionIcon:SetPoint("TOPLEFT",412,-84); conditionIcon:SetTextColor(.53,.84,.92)
    conditionText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); conditionText:SetPoint("TOPLEFT",438,-84); conditionText:SetWidth(130); conditionText:SetJustifyH("LEFT"); conditionText:SetWordWrap(false); conditionText:SetTextColor(.90,.95,1)
    detailText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); detailText:SetPoint("TOPLEFT",38,-103); detailText:SetWidth(530); detailText:SetJustifyH("LEFT"); detailText:SetWordWrap(false); detailText:SetTextColor(.69,.84,.89)
    statusText=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusText:SetPoint("TOPLEFT",38,-120); statusText:SetWidth(530); statusText:SetJustifyH("LEFT"); statusText:SetWordWrap(false); statusText:SetTextColor(.55,.75,.79)
    sectionLine(frame,-142)
    local listTitle=frame:CreateFontString(nil,"OVERLAY","GameFontNormal"); listTitle:SetPoint("TOPLEFT",25,-153); listTitle:SetText("WEATHER ACROSS AZEROTH"); listTitle:SetTextColor(.72,.86,.91)
    feedLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); feedLabel:SetPoint("TOPRIGHT",-25,-155); feedLabel:SetTextColor(.55,.72,.77)
    local searchLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); searchLabel:SetPoint("TOPLEFT",28,-181); searchLabel:SetText("Find a zone"); searchLabel:SetTextColor(.70,.84,.88)
    searchBox=CreateFrame("EditBox",nil,frame,"InputBoxTemplate"); searchBox:SetSize(150,22); searchBox:SetPoint("TOPLEFT",30,-199); searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(80)
    searchBox:SetScript("OnTextChanged",function(self) searchText=(self:GetText() or ""):lower(); page=1; refreshZoneReports() end)
    searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    local function dropdown(x, label, getItems, chosen, apply)
        local caption=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); caption:SetPoint("TOPLEFT",x+17,-181); caption:SetText(label); caption:SetTextColor(.70,.84,.88)
        local drop=CreateFrame("Frame",nil,frame,"UIDropDownMenuTemplate"); drop:SetPoint("TOPLEFT",x,-194)
        UIDropDownMenu_SetWidth(drop,155)
        UIDropDownMenu_Initialize(drop,function(self,level)
            for _, value in ipairs(getItems()) do
                local info=UIDropDownMenu_CreateInfo(); info.text=value; info.checked=(value==chosen()); info.func=function() apply(value); UIDropDownMenu_SetText(drop,value); page=1; refreshZoneReports() end; UIDropDownMenu_AddButton(info,level)
            end
        end)
        UIDropDownMenu_SetText(drop,chosen())
        return drop
    end
    local continentDrop, zoneDrop
    continentDrop = dropdown(188,"Continent",function() return {"All continents","Eastern Kingdoms","Kalimdor"} end,function() return selectedContinent end,function(v) selectedContinent=v; selectedZone="All zones"; if zoneDrop then UIDropDownMenu_SetText(zoneDrop,selectedZone) end end)
    local caption=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); caption:SetPoint("TOPLEFT",397,-181); caption:SetText("Zone"); caption:SetTextColor(.70,.84,.88)
    zoneDrop=CreateFrame("Frame",nil,frame,"UIDropDownMenuTemplate"); zoneDrop:SetPoint("TOPLEFT",380,-194); UIDropDownMenu_SetWidth(zoneDrop,155); UIDropDownMenu_SetText(zoneDrop,selectedZone)
    UIDropDownMenu_Initialize(zoneDrop,function(self,level)
        level=level or 1
        local function add(text, value, hasArrow, onClick)
            local info=UIDropDownMenu_CreateInfo(); info.text=text; info.value=value; info.hasArrow=hasArrow; info.notCheckable=hasArrow
            info.checked=not hasArrow and selectedZone==text; info.func=onClick; UIDropDownMenu_AddButton(info,level)
        end
        if level==1 then
            add("All zones",nil,false,function() selectedZone="All zones"; UIDropDownMenu_SetText(zoneDrop,selectedZone); page=1; refreshZoneReports() end)
            local letters={}
            for _, item in ipairs(zoneCatalog) do if selectedContinent=="All continents" or item.continent==selectedContinent then letters[item.zone:sub(1,1):upper()]=true end end
            local sorted={}; for letter in pairs(letters) do sorted[#sorted+1]=letter end; table.sort(sorted)
            for _, letter in ipairs(sorted) do add(letter,letter,true,nil) end
        elseif level==2 then
            local letter=UIDROPDOWNMENU_MENU_VALUE; local zones={}
            for _, item in ipairs(zoneCatalog) do if (selectedContinent=="All continents" or item.continent==selectedContinent) and item.zone:sub(1,1):upper()==letter then zones[#zones+1]=item end end
            table.sort(zones,function(a,b) return a.zone < b.zone end)
            for _, item in ipairs(zones) do
                local zone, c = item.zone, item.continent
                add(zone,nil,false,function() selectedZone=zone; selectedContinent=c; UIDropDownMenu_SetText(zoneDrop,zone); UIDropDownMenu_SetText(continentDrop,c); page=1; refreshZoneReports() end)
            end
        end
    end)
    local filterLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); filterLabel:SetPoint("TOPLEFT",25,-236); filterLabel:SetText("Show:"); filterLabel:SetTextColor(.70,.84,.88)
    for i, opt in ipairs({{"All","all"},{"Clear","clear"},{"Rain","rain"},{"Snow","snow"},{"Sand","sandstorm"},{"Misc","miscellaneous"}}) do
        local value=opt[2]; local label=(weatherIcons[value] and (weatherIcons[value] .. "  ") or "") .. opt[1]; addButton(frame,label,78,70+(i-1)*85,-229,function() selectedWeather=value; page=1; refreshZoneReports() end)
    end
    for i=1,ROW_COUNT do
        local row=CreateFrame("Frame",nil,frame); row:SetSize(560,42); row:SetPoint("TOPLEFT",25,-267-(i-1)*45)
        local bg=row:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(.08,.20,.26,.82)
        row.icon=row:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); row.icon:SetPoint("LEFT",10,0); row.icon:SetWidth(26); row.icon:SetTextColor(.55,.84,.91)
        row.zone=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.zone:SetPoint("TOPLEFT",44,-5); row.zone:SetWidth(345); row.zone:SetJustifyH("LEFT"); row.zone:SetTextColor(.90,.95,1)
        row.realm=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.realm:SetPoint("BOTTOMLEFT",44,5); row.realm:SetWidth(370); row.realm:SetJustifyH("LEFT"); row.realm:SetTextColor(.56,.74,.80)
        row.weather=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.weather:SetPoint("TOPRIGHT",-10,-5); row.weather:SetTextColor(.80,.90,.94)
        row.age=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.age:SetPoint("BOTTOMRIGHT",-10,5)
        zoneRows[i]=row
    end
    emptyLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); emptyLabel:SetPoint("TOP",0,-320); emptyLabel:SetText("No zones match. Try another search or filter."); emptyLabel:SetTextColor(.65,.79,.83)
    previousButton=addButton(frame,"<",36,25,-499,function() page=page-1; refreshZoneReports() end)
    nextButton=addButton(frame,">",36,139,-499,function() page=page+1; refreshZoneReports() end)
    pageLabel=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); pageLabel:SetPoint("TOPLEFT",65,-507); pageLabel:SetWidth(70); pageLabel:SetJustifyH("CENTER")
    local manual=frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); manual:SetPoint("TOPLEFT",200,-506); manual:SetText("Report what you see:"); manual:SetTextColor(.70,.84,.88)
    for i, option in ipairs({{"Clear","clear"},{"Rain","rain"},{"Snow","snow"},{"Sand","sandstorm"},{"Misc","miscellaneous"}}) do
        local weather=option[2]; local b=addButton(frame,weatherIcons[weather] .. " " .. option[1],52,331+(i-1)*52,-499,function() reportWeather(weather) end)
    end
    shareNote=addButton(frame,"Share with addon users: OFF",205,25,-535,function() if AzerothWeather_ToggleSharing then AzerothWeather_ToggleSharing() else chat("In-game sharing is unavailable.") end end)
    shareDot=shareNote:CreateTexture(nil,"OVERLAY"); shareDot:SetSize(8,8); shareDot:SetPoint("LEFT",9,0); local mask=shareNote:CreateMaskTexture(); if mask then mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE"); mask:SetAllPoints(shareDot); shareDot:AddMaskTexture(mask) end
    sharePulse=shareDot:CreateAnimationGroup(); sharePulse:SetLooping("BOUNCE"); local fade=sharePulse:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(.3); fade:SetDuration(.8)
    shareNote:SetScript("OnEnter",function(self) self:SetBackdropColor(.14,.32,.39,1); GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine("Share with addon users",1,.82,0); GameTooltip:AddLine("Exchange hidden weather and estimated layer reports with Weather Forever users in your party, raid and guild. Your character name is visible to recipients. Delivery depends on game restrictions.",1,1,1,true); GameTooltip:Show() end)
    shareNote:SetScript("OnLeave",function(self) self:SetBackdropColor(.09,.22,.29,.95); GameTooltip:Hide() end)
    partyButton=addButton(frame,"Share party weather: OFF",175,240,-535,function()
        if AzerothWeather_TogglePartyForecast then message=AzerothWeather_TogglePartyForecast(current); chat(message); updateUI() end
    end)
    partyButton:SetScript("OnEnter",function(self) self:SetBackdropColor(.14,.32,.39,1); GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine("Share Weather With Party",1,.82,0); GameTooltip:AddLine("Turn on flavorful visible party or raid forecasts when the weather changes. Your realm may require you to press Enter to send chat.",1,1,1,true); GameTooltip:Show() end)
    partyButton:SetScript("OnLeave",function(self) self:SetBackdropColor(.09,.22,.29,.95); GameTooltip:Hide() end)
    addButton(frame,"Share manually",130,450,-535,function()
        if not current then message="No weather report to copy yet."; updateUI(); return end
        exportBox:Show(); message="Press Ctrl+C (Mac: Command+C), then paste on the website."; updateUI(); exportBox:SetFocus(); exportBox:HighlightText()
    end)
    StaticPopupDialogs["WEATHER_FOREVER_SEND_REPORTS"] = {
        text="This will reload your UI to save your reports. If the Weather Forever companion is running, it will send eligible unsent reports automatically after the reload.",
        button1="Reload UI", button2="Cancel", timeout=0, whileDead=true, hideOnEscape=true,
        OnAccept=function()
            if C_UI and type(C_UI.Reload)=="function" then C_UI.Reload()
            elseif type(ReloadUI)=="function" then ReloadUI()
            else chat("Reload is unavailable. Type /reload to save your reports.") end
        end,
    }
    local sendButton=addButton(frame,"Send reports to website",200,25,-565,function() StaticPopup_Show("WEATHER_FOREVER_SEND_REPORTS") end)
    sendButton:SetScript("OnEnter",function(self) self:SetBackdropColor(.14,.32,.39,1); GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine("Send reports to website",1,.82,0); GameTooltip:AddLine("Reloads the UI so the running companion can send eligible unsent reports. The companion must be installed, running, and online.",1,1,1,true); GameTooltip:Show() end)
    sendButton:SetScript("OnLeave",function(self) self:SetBackdropColor(.09,.22,.29,.95); GameTooltip:Hide() end)
    exportBox=CreateFrame("EditBox",nil,frame,"InputBoxTemplate"); exportBox:SetSize(325,22); exportBox:SetPoint("TOPLEFT",250,-568); exportBox:SetAutoFocus(false); exportBox:SetMaxLetters(0); exportBox:Hide()
    if AzerothWeather_CreatePanelMap then AzerothWeather_CreatePanelMap(frame) end
    frame:Hide(); updateUI(); createMinimapButton()
end
SLASH_AZEROTHWEATHER1 = "/awo"
SLASH_AZEROTHWEATHER2 = "/weather"
SLASH_AZEROTHWEATHER3 = "/wf"
SlashCmdList.AZEROTHWEATHER = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "refresh" then observe(); chat(message)
    elseif input == "minimap" then
        AzerothWeatherDB.minimapHidden = not AzerothWeatherDB.minimapHidden
        if minimapButton then if AzerothWeatherDB.minimapHidden then minimapButton:Hide() else minimapButton:Show() end end
        chat(AzerothWeatherDB.minimapHidden and "Minimap button hidden. Use /weather minimap to show it." or "Minimap button shown.")
    elseif input == "export" then frame:Show(); exportBox:Show(); exportBox:SetFocus(); exportBox:HighlightText(); chat("Copy the selected report with Ctrl+C.")
    elseif input == "share" then if AzerothWeather_ToggleSharing then AzerothWeather_ToggleSharing() else chat("In-game sharing is unavailable.") end
    elseif input == "map" then if AzerothWeather_ToggleMap then AzerothWeather_ToggleMap() else chat("Weather map is not available yet.") end
    elseif input == "help" then chat("/weather or /wf opens the report; /weather refresh checks the client; /weather minimap shows or hides the button; /weather map toggles map markers; /weather share toggles in-game sharing.")
    else toggleWindow() end
end
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
-- Register defensively because events can vary between clients.
for _, event in ipairs({"WEATHER_CHANGED", "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "SHARD_TRANSFER", "SHARD_TRANSFER_IMMINENT"}) do
    pcall(function() events:RegisterEvent(event) end)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        if type(AzerothWeatherDB) ~= "table" then AzerothWeatherDB = {} end
        if type(AzerothWeatherDB.observations) ~= "table" then AzerothWeatherDB.observations = {} end
        createUI(); ready = true; chat("Loaded. Type /weather for your weather report.")
    elseif ready and event ~= "ADDON_LOADED" then
        if event=="NAME_PLATE_UNIT_ADDED" then sampleLayer(arg)
        elseif event=="PLAYER_TARGET_CHANGED" then sampleLayer("target")
        elseif event=="UPDATE_MOUSEOVER_UNIT" then sampleLayer("mouseover")
        elseif event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" or event=="SHARD_TRANSFER" or event=="SHARD_TRANSFER_IMMINENT" then
            resetLayer(); observe()
            if event~="SHARD_TRANSFER_IMMINENT" then sampleNearby() end
        else observe() end
    end
end)
local elapsed = 0
events:SetScript("OnUpdate", function(_, delta)
    if not ready then return end
    elapsed = elapsed + delta
    if elapsed >= 60 then elapsed = 0; sampleNearby(); observe() end
end)
