"""Azeroth Weather desktop uploader. Runs on the player's PC, never inside WoW."""
import argparse, datetime as dt, hashlib, json, math, os, pathlib, sys, time, urllib.request, urllib.error, uuid
from saved_data import parse_saved, SavedDataError
URL='https://weather.craftingworlds.com/api/observations'
ORIGIN='https://weather.craftingworlds.com'
STATE_DIR=(pathlib.Path.home()/'Library'/'Application Support'/'AzerothWeatherCompanion') if sys.platform=='darwin' else pathlib.Path(os.environ.get('LOCALAPPDATA', pathlib.Path.home()))/'AzerothWeatherCompanion'
DEFAULT_ROOT=(pathlib.Path('/Applications/World of Warcraft') if sys.platform=='darwin' else pathlib.Path(os.environ.get('PROGRAMFILES(X86)',r'C:\Program Files (x86)'))/'World of Warcraft')/'_forever_'/'WTF'/'Account'

def records_from_file(path, now=None):
    now=time.time() if now is None else now
    before=path.stat()
    if before.st_size>2_000_000: raise SavedDataError('File too large')
    raw=path.read_text(encoding='utf-8-sig')
    after=path.stat()
    if (before.st_mtime_ns,before.st_size)!=(after.st_mtime_ns,after.st_size): raise SavedDataError('File changed while reading')
    root=parse_saved(raw); entries=root.get('observations',{})
    if not isinstance(entries,dict): raise SavedDataError('Missing observation table')
    out=[]
    for key,r in entries.items():
        if not isinstance(key,int) or not isinstance(r,dict): continue
        zone,realm,weather,source,stamp=(r.get(x) for x in ('zone','realm','weather','source','at'))
        if not all(isinstance(v,str) and 0<len(v.strip())<=100 for v in (zone,realm)): continue
        if any(ord(c)<32 or ord(c)==127 for c in zone+realm): continue
        if weather not in ('clear','rain','snow','sandstorm','unknown') or source not in ('client','manual'): continue
        if isinstance(stamp,bool) or not isinstance(stamp,(int,float)) or not math.isfinite(stamp) or not now-7*86400<=stamp<=now+300: continue
        intensity=r.get('intensity')
        if intensity is not None and (isinstance(intensity,bool) or not isinstance(intensity,(int,float)) or not math.isfinite(intensity) or not 0<=intensity<=10): continue
        item={'zone':zone.strip(),'realm':realm.strip(),'weather':weather,'observed_at':dt.datetime.fromtimestamp(stamp,dt.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z'),'source':source}
        if intensity is not None: item['intensity']=intensity
        out.append(item)
    return out

def installation_id(path=None):
    path=path or (STATE_DIR/'installation-id.txt')
    try:
        value=path.read_text(encoding='ascii').strip()
        if len(value)==32 and all(c in '0123456789abcdef' for c in value): return value
        raise ValueError('Invalid installation ID')
    except FileNotFoundError:
        path.parent.mkdir(parents=True,exist_ok=True)
        value=uuid.uuid4().hex
        with path.open('x',encoding='ascii') as f: f.write(value)
        return value

def identifier(record): return hashlib.sha256(json.dumps(record,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def send(record, url=URL, origin=ORIGIN):
    body=json.dumps(record,ensure_ascii=False,separators=(',',':')).encode('utf-8')
    request=urllib.request.Request(url,data=body,headers={'Content-Type':'application/json','Origin':origin,'User-Agent':'AzerothWeatherCompanion/0.1'},method='POST')
    with urllib.request.urlopen(request,timeout=15) as response:
        data=json.load(response)
        if response.status not in (200,201) or not isinstance(data.get('inserted'),bool): raise ValueError('Unexpected server response')

FEED_MARKER = '-- AzerothWeather managed feed v1'
def lua_quote(value):
    if not isinstance(value,str) or not 0<len(value)<=100 or any(ord(c)<32 or ord(c)==127 for c in value):
        raise ValueError('Invalid feed text')
    return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'
def render_feed(data, downloaded_at):
    if not isinstance(data,dict) or not isinstance(data.get('observations'),list): raise ValueError('Invalid community feed')
    lines=[FEED_MARKER, 'AzerothWeatherWebsiteFeed = { fetchedAt = '+str(int(downloaded_at))+', observations = {']
    accepted=0
    for r in data['observations'][:500]:
        if not isinstance(r,dict): continue
        try:
            zone=lua_quote(r['zone'].strip()); realm=lua_quote(r['realm'].strip()); weather=r['weather']
            if weather not in ('clear','rain','snow','sandstorm','unknown'): continue
            timestamp=dt.datetime.fromisoformat(r['observed_at'].replace('Z','+00:00'))
            if timestamp.tzinfo is None: continue
            stamp=int(timestamp.timestamp())
            if not downloaded_at-7*86400<=stamp<=downloaded_at+300: continue
            count=r.get('report_count',0); tied=r.get('tied',0)
            if isinstance(count,bool) or not isinstance(count,int) or not 0<=count<=1000000: count=0
            lines.append('  { zone='+zone+', realm='+realm+', weather='+lua_quote(weather)+', at='+str(stamp)+', count='+str(count)+', tied='+('true' if tied == 1 else 'false')+' },')
            accepted+=1
        except (KeyError,TypeError,ValueError,OverflowError,AttributeError): continue
    lines.append('} }')
    return '\n'.join(lines)+'\n',accepted
def refresh_feed(addon_dir, url=URL):
    target=addon_dir/'WeatherFeed.lua'
    if not (addon_dir/'AzerothWeather.toc').is_file() or not target.is_file(): return False
    prior=target.read_text(encoding='utf-8-sig')
    if not prior.startswith(FEED_MARKER): raise ValueError('Feed file is not managed by this companion')
    request=urllib.request.Request(url,headers={'User-Agent':'AzerothWeatherCompanion/0.2'})
    with urllib.request.urlopen(request,timeout=15) as response:
        raw=response.read(1_000_001)
        if len(raw)>1_000_000: raise ValueError('Community feed is too large')
        data=json.loads(raw)
    generated,count=render_feed(data,time.time())
    # Avoid rewriting an identical list only because fetch time changed.
    if prior.split('observations = {',1)[-1] == generated.split('observations = {',1)[-1]: return False
    temporary=target.with_suffix('.lua.tmp')
    temporary.write_text(generated,encoding='utf-8');os.replace(temporary,target)
    log('Updated website snapshot ('+str(count)+' zone reports); reload WoW to view it.')
    return True

def read_state(path):
    try:
        state=json.loads(path.read_text(encoding='utf-8'))
        return {str(k):float(v) for k,v in state.items() if isinstance(v,(float,int))}
    except (FileNotFoundError,ValueError,TypeError,OSError): return {}
def save_state(path,state):
    path.parent.mkdir(parents=True,exist_ok=True)
    temp=path.with_suffix('.tmp'); temp.write_text(json.dumps(state),encoding='utf-8'); os.replace(temp,path)
def log(text):
    STATE_DIR.mkdir(parents=True,exist_ok=True)
    with (STATE_DIR/'companion.log').open('a',encoding='utf-8') as f: f.write(dt.datetime.now().isoformat(timespec='seconds')+' '+text+'\n')
def main():
    ap=argparse.ArgumentParser(description='Automatically send Azeroth Weather observations after WoW saves them.')
    ap.add_argument('--root',type=pathlib.Path,default=DEFAULT_ROOT,help='WoW Forever WTF/Account directory')
    ap.add_argument('--once',action='store_true',help='Scan once then exit')
    ap.add_argument('--addon-dir',type=pathlib.Path,default=None,help='Addon directory for the community snapshot')
    args=ap.parse_args(); state_path=STATE_DIR/'sent.json'; state=read_state(state_path)
    STATE_DIR.mkdir(parents=True,exist_ok=True)
    lock_file=None
    if os.name=='nt':
        import msvcrt
        lock_file=(STATE_DIR/'companion.lock').open('a+b')
        lock_file.seek(0)
        try: msvcrt.locking(lock_file.fileno(),msvcrt.LK_NBLCK,1)
        except OSError: log('Companion is already running.'); return
    else:
        import fcntl
        lock_file=(STATE_DIR/'companion.lock').open('a+b')
        try: fcntl.flock(lock_file.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        except OSError: log('Companion is already running.'); return
    reporter=installation_id()
    log('Started. Sending weather, zone, realm, timestamp, source, optional intensity and a random installation ID.')
    addon_dir=args.addon_dir or (args.root.parent.parent/'Interface'/'AddOns'/'AzerothWeather')
    next_feed=0
    while True:
        now=time.time(); state={k:v for k,v in state.items() if v>now-8*86400}
        if now>=next_feed:
            try: refresh_feed(addon_dir)
            except (OSError,ValueError,TypeError,urllib.error.URLError) as e: log('Website snapshot unavailable; will retry: '+str(e))
            next_feed=now+120
        try:
            files=list(args.root.glob('*/SavedVariables/AzerothWeather.lua'))
            for path in files:
                try: records=records_from_file(path,now)
                except (OSError,UnicodeError,SavedDataError) as e: log('Skipped incomplete or unsupported addon save: '+str(e)); continue
                for record in records:
                    key=identifier(record)
                    if key in state: continue
                    try:
                        send({**record, 'reporter_id':reporter}); state[key]=now; save_state(state_path,state)
                        log('Sent observation for '+record['zone']+' on '+record['realm']+'.')
                        time.sleep(7)
                    except (OSError,ValueError,urllib.error.URLError) as e:
                        log('Upload failed; will retry later: '+str(e)); break
        except OSError as e: log('Could not scan saved data: '+str(e))
        if args.once: return
        time.sleep(30)
if __name__=='__main__': main()
