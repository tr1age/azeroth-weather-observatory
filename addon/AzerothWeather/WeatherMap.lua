-- In-game weather markers: independent implementation using Blizzard's map canvas.
local paths={clear='MapSun',rain='MapRain',snow='MapSnow',sandstorm='MapStorm',miscellaneous='MapUnknown',unknown='MapUnknown'}
local labels={clear='Clear',rain='Rain',snow='Snow',sandstorm='Sandstorm',miscellaneous='Miscellaneous',unknown='Unknown'}
local layer, provider, pins, added, enabled=nil,nil,{},false,true
local function clearPins() for _,pin in ipairs(pins) do pin:Hide() end end
local function makePin(i)
    if pins[i] then return pins[i] end
    local pin=CreateFrame('Button',nil,layer)
    pin:SetSize(24,24)
    local texture=pin:CreateTexture(nil,'ARTWORK');texture:SetAllPoints();pin.icon=texture
    pin:SetScript('OnEnter',function(self)
        GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:AddLine(self.zone,1,.86,.35)
        GameTooltip:AddLine(self.condition,1,1,1)
        if self.record then
            local age=math.max(0,time()-self.record.at)
            local when=age<60 and 'just now' or (age<3600 and (math.floor(age/60)..'m ago') or (math.floor(age/3600)..'h ago'))
            GameTooltip:AddLine('Reported '..when,.7,.85,.9)
            GameTooltip:AddLine('Layer: '..(self.record.layer and (self.record.layer..' (estimated)') or 'Unknown'),.7,.85,.9)
        else GameTooltip:AddLine('No report for your realm and layer',.7,.85,.9) end
        GameTooltip:Show()
    end)
    pin:SetScript('OnLeave',function() GameTooltip:Hide() end)
    pins[i]=pin;return pin
end
local function refresh()
    if not layer or not enabled then clearPins();return end
    clearPins()
    local mapID=WorldMapFrame:GetMapID()
    if not mapID or not C_Map or not C_Map.GetMapInfo or not C_Map.GetMapRectOnMap then return end
    local info=C_Map.GetMapInfo(mapID);if not info then return end
    local types=Enum and Enum.UIMapType;local continentType=types and types.Continent or 2;local zoneType=types and types.Zone or 3
    local children={}
    if info.mapType==continentType and C_Map.GetMapChildrenInfo then
        local ok,result=pcall(C_Map.GetMapChildrenInfo,mapID,zoneType,true)
        if ok and type(result)=='table' then children=result end
    elseif info.mapType==zoneType then children={info} else return end
    local reports=AzerothWeather_GetMapReports and AzerothWeather_GetMapReports() or {}
    local width,height=layer:GetWidth(),layer:GetHeight();if not width or not height or width<=0 or height<=0 then return end
    local count=0
    for _,item in ipairs(children) do
        local id,name=item.mapID,item.name
        if id and type(name)=='string' and name~='' then
            local x,y=.5,.5
            if id~=mapID then
                local ok,left,right,top,bottom=pcall(C_Map.GetMapRectOnMap,id,mapID)
                if ok and type(left)=='number' and type(right)=='number' and type(top)=='number' and type(bottom)=='number' and right>left and bottom>top then x=(left+right)/2;y=(top+bottom)/2 else x=nil end
            end
            if x and x>=0 and x<=1 and y>=0 and y<=1 then
                count=count+1;local pin=makePin(count);local record=reports[name:lower()]
                pin.zone=name;pin.record=record;pin.condition=record and (labels[record.weather] or 'Unknown') or 'No reported weather'
                pin.icon:SetTexture('Interface\\AddOns\\AzerothWeather\\Media\\'..(record and (paths[record.weather] or 'MapUnknown') or 'MapUnobserved'))
                pin:SetAlpha(record and time()-record.at>1800 and .5 or 1)
                pin:ClearAllPoints();pin:SetPoint('CENTER',layer,'TOPLEFT',x*width,-y*height);pin:Show()
            end
        end
    end
end
local function install()
    if added or not WorldMapFrame or not WorldMapFrame.ScrollContainer or not WorldMapFrame.ScrollContainer.Child or not MapCanvasDataProviderMixin or not CreateFromMixins then return end
    layer=CreateFrame('Frame',nil,WorldMapFrame.ScrollContainer.Child);layer:SetAllPoints();layer:EnableMouse(false)
    provider=CreateFromMixins(MapCanvasDataProviderMixin)
    provider.OnMapChanged=refresh;provider.RefreshAllData=refresh;provider.RemoveAllData=clearPins;provider.OnCanvasScaleChanged=refresh
    WorldMapFrame:AddDataProvider(provider);added=true
    if WorldMapFrame:IsShown() then refresh() end
end
function AzerothWeather_RefreshMap() if added and WorldMapFrame:IsShown() then refresh() end end
function AzerothWeather_ToggleMap()
    enabled=not enabled
    if enabled then install();refresh() else clearPins() end
    print('|cff65cdd1[Azeroth Weather]|r Map markers '..(enabled and 'on' or 'off')..'.')
end
local watcher=CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_ENTERING_WORLD');watcher:RegisterEvent('ADDON_LOADED')
watcher:SetScript('OnEvent',function(_,event,name)
    if event=='PLAYER_ENTERING_WORLD' or name=='Blizzard_WorldMap' then pcall(install) end
end)
