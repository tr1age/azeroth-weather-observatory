-- Optional in-game sharing over Blizzard addon messages. Peer reports stay in memory.
local PREFIX='AWO13'
local peers, seenSenders, pending={}, {}, {}
local registered=false
local lastSent,lastSignature,lastRequest,lastQueue,lastResponse=0,nil,0,0,0
local warned=false
local function secret(v) return type(issecretvalue)=="function" and issecretvalue(v) end
local accepted={clear=true,rain=true,snow=true,sandstorm=true,miscellaneous=true}
local function clean(v,max)
    return type(v)=='string' and #v>0 and #v<=max and not v:find('[%c|]')
end
local function enabled() return type(AzerothWeatherDB)=='table' and AzerothWeatherDB.peerSharing==true end
local function register()
    if registered then return true end
    if not C_ChatInfo or type(C_ChatInfo.RegisterAddonMessagePrefix)~='function' then return false end
    local ok,result=pcall(C_ChatInfo.RegisterAddonMessagePrefix,PREFIX)
    registered=ok and (result==nil or result==true or result==0 or result==1)
    return registered
end
local function groupChannel()
    if IsInRaid and IsInRaid() then return 'RAID' end
    if IsInGroup and IsInGroup() then return 'PARTY' end
end
local function send(message,channel)
    if not enabled() or not register() or not C_ChatInfo or type(C_ChatInfo.SendAddonMessage)~='function' or #message>240 then return false end
    local ok,result=pcall(C_ChatInfo.SendAddonMessage,PREFIX,message,channel)
    local success=ok and (result==nil or result==true or result==0)
    if not success and not warned then warned=true;print('|cff65cdd1[Azeroth Weather]|r The game refused an in-game weather message; sharing may be restricted on this realm.') end
    return success
end
local function encode(r)
    if type(r)~='table' or not clean(r.zone,80) or not clean(r.realm,80) or not accepted[r.weather] or type(r.at)~='number' then return nil end
    local layer=r.layer or '-'
    if layer~='-' and (type(layer)~='string' or #layer>21 or not layer:match('^%d+%-%d+$')) then return nil end
    local payload=table.concat({'R',math.floor(r.at),r.weather,layer,r.zone,r.realm},'|')
    if #payload>240 then return nil end
    return payload
end
local function channels()
    local result={};if IsInGuild and IsInGuild() then result[#result+1]='GUILD' end
    local group=groupChannel();if group then result[#result+1]=group end
    return result
end
local function broadcastCurrent()
    if not enabled() or not AzerothWeather_GetCurrentObservation then return end
    local r=AzerothWeather_GetCurrentObservation();local payload=encode(r);if not payload then return end
    local now=time();if r.at<now-1800 or r.at>now+30 then return end
    local sig=table.concat({r.zone,r.realm,r.weather,r.layer or '-'},'|')
    if now-lastSent<15 or (sig==lastSignature and now-lastSent<120) then return end
    local available=channels();if #available==0 then return end
    for _,channel in ipairs(available) do send(payload,channel) end
    -- Throttle attempted sends too, including when the client refuses them.
    lastSent,lastSignature=now,sig
end
local function requestGroup()
    local channel=groupChannel();local now=time()
    if channel and now-lastRequest>=120 then lastRequest=now;send('Q',channel) end
end
local function prepareResponse(channel)
    if channel~=groupChannel() or #pending>0 then return end
    local newest={};local now=time();if now-lastResponse<120 then return end;lastResponse=now
    if type(AzerothWeatherDB.observations)~='table' then return end
    for _,r in ipairs(AzerothWeatherDB.observations) do
        if type(r)=='table' and r.source=='client' and type(r.at)=='number' and r.at>=now-1800 and r.at<=now+30 and clean(r.zone,80) and clean(r.realm,80) then
            local key=r.zone..'|'..r.realm..'|'..(r.layer or '-')
            if not newest[key] or newest[key].at<r.at then newest[key]=r end
        end
    end
    local reports={};for _,r in pairs(newest) do reports[#reports+1]=r end
    table.sort(reports,function(a,b)return a.at>b.at end)
    for i=1,math.min(#reports,8) do local msg=encode(reports[i]);if msg then pending[#pending+1]={msg=msg,channel=channel} end end
end
local function receive(prefix,payload,channel,sender)
    if not enabled() or secret(prefix) or secret(payload) or secret(channel) or secret(sender) then return end
    if prefix~=PREFIX or (channel~='GUILD' and channel~='PARTY' and channel~='RAID') then return end
    if type(payload)~='string' or #payload>240 or type(sender)~='string' or sender=='' then return end
    local now=time()
    local t=seenSenders[sender]
    if t and now-t<1 then return end
    seenSenders[sender]=now
    if payload=='Q' then if channel==groupChannel() then prepareResponse(channel) end;return end
    local stamp,weather,layer,zone,realm=payload:match('^R|(%d+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$')
    stamp=tonumber(stamp)
    if not stamp or stamp<now-1800 or stamp>now+30 or not accepted[weather] or not clean(zone,80) or not clean(realm,80) then return end
    if layer=='-' then layer=nil elseif #layer>21 or not layer:match('^%d+%-%d+$') then return end
    local key=zone:lower()..'|'..realm:lower()..'|'..(layer or '-')
    local old=peers[key]
    if old and old.at>=stamp then return end
    peers[key]={zone=zone,realm=realm,weather=weather,at=stamp,layer=layer,source='peer'}
    local n=0;for _ in pairs(peers) do n=n+1 end
    if n>250 then local oldest,at=nil,math.huge;for k,v in pairs(peers) do if v.at<at then oldest,at=k,v.at end end;if oldest then peers[oldest]=nil end end
    if AzerothWeather_PeerUpdated then AzerothWeather_PeerUpdated() end
end
function AzerothWeather_GetPeerReports() return peers end
function AzerothWeather_ToggleSharing()
    AzerothWeatherDB.peerSharing=not enabled()
    if not enabled() then peers={};pending={};lastSignature=nil end
    if enabled() and not register() then
        AzerothWeatherDB.peerSharing=false
        print('|cff65cdd1[Azeroth Weather]|r In-game sharing could not start on this client.')
    else
        print('|cff65cdd1[Azeroth Weather]|r In-game sharing '..(enabled() and 'ON (party, raid and guild; your character name is visible to recipients).' or 'OFF.') )
        if enabled() then broadcastCurrent();requestGroup() end
    end
    if AzerothWeather_PeerUpdated then AzerothWeather_PeerUpdated() end
end
local frame=CreateFrame('Frame');local elapsed=0
frame:RegisterEvent('ADDON_LOADED');frame:RegisterEvent('PLAYER_ENTERING_WORLD');frame:RegisterEvent('GROUP_ROSTER_UPDATE');frame:RegisterEvent('CHAT_MSG_ADDON')
frame:SetScript('OnEvent',function(_,event,...)
    if event=='ADDON_LOADED' then local name=...;if name=='AzerothWeather' and enabled() then register() end
    elseif event=='CHAT_MSG_ADDON' then receive(...)
    elseif enabled() then requestGroup();broadcastCurrent() end
end)
frame:SetScript('OnUpdate',function(_,delta)
    if not enabled() then return end
    elapsed=elapsed+delta
    if elapsed>=10 then elapsed=0;broadcastCurrent() end
    local now=time()
    if #pending>0 and now-lastQueue>=3 then
        local item=table.remove(pending,1);if item.channel==groupChannel() and not send(item.msg,item.channel) then pending={} end;lastQueue=now
    end
    local changed=false;for key,r in pairs(peers) do if now-r.at>1800 then peers[key]=nil;changed=true end end
    if changed and AzerothWeather_PeerUpdated then AzerothWeather_PeerUpdated() end
    for name,at in pairs(seenSenders) do if now-at>60 then seenSenders[name]=nil end end
end)
