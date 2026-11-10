"""Single-file installer and background runner for Azeroth Weather on Windows."""
import ctypes, datetime, json, os, pathlib, re, shutil, subprocess, sys, tempfile, threading, queue, urllib.request, webbrowser
import tkinter as tk
from tkinter import messagebox
import companion
import pystray
from PIL import Image

APP_VERSION='0.11.4'
APP_RELEASE_DATE='2026-11-10'
VERSION_URL='https://weather.craftingworlds.com/api/version'
DOWNLOAD_URL='https://weather.craftingworlds.com/#contribute'
APP_NAME='AzerothWeatherApp.exe'
INSTALL_DIR=pathlib.Path(os.environ['LOCALAPPDATA'])/'AzerothWeatherCompanion'
GAME_ROOT=companion.DEFAULT_ROOT

def startup_directory():
    buf=ctypes.create_unicode_buffer(260)
    result=ctypes.windll.shell32.SHGetFolderPathW(None,7,None,0,buf)
    if result: raise OSError('Could not find the Windows startup folder')
    return pathlib.Path(buf.value)

def stop_running(install_dir):
    env=os.environ.copy()
    env['AW_APP_EXE']=str(install_dir/APP_NAME)
    env['AW_PREVIOUS_EXE']=str(install_dir/'AzerothWeatherCompanion.exe')
    env['AW_PREVIOUS_SCRIPT']=str(install_dir/'companion.py')
    script=r'''$ErrorActionPreference='Stop'
$targets=Get-CimInstance Win32_Process | Where-Object {
  ($_.ExecutablePath -eq $env:AW_APP_EXE -and $_.CommandLine -match '(?:^|\s)--run(?:\s|$)') -or
  ($_.ExecutablePath -eq $env:AW_PREVIOUS_EXE) -or
  ($_.Name -eq 'pythonw.exe' -and $_.CommandLine -and $_.CommandLine.Contains($env:AW_PREVIOUS_SCRIPT))
}
foreach($proc in $targets) { Stop-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue }
'''
    subprocess.run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],env=env,check=True,creationflags=subprocess.CREATE_NO_WINDOW)

def install(source, install_dir, startup_dir, launch=True):
    if not GAME_ROOT.is_dir(): raise ValueError('WoW Forever was not found in the standard installation folder. Custom locations are not supported yet.')
    install_dir.mkdir(parents=True,exist_ok=True)
    startup_dir.mkdir(parents=True,exist_ok=True)
    destination=install_dir/APP_NAME
    stop_running(install_dir)
    if os.path.normcase(os.path.abspath(source)) != os.path.normcase(os.path.abspath(destination)):
        tmp=destination.with_suffix('.new')
        shutil.copy2(source,tmp)
        os.replace(tmp,destination)
    configure_startup(install_dir,startup_dir,read_startup_setting(install_dir/'settings.json'))
    if launch: subprocess.Popen([str(destination),'--run'],creationflags=subprocess.CREATE_NO_WINDOW,close_fds=True)

def configure_startup(install_dir,startup_dir,enabled):
    startup=startup_dir/'AzerothWeatherCompanion.vbs'
    if enabled:
        startup_dir.mkdir(parents=True,exist_ok=True)
        destination=install_dir/APP_NAME
        vbs='CreateObject("WScript.Shell").Run """'+str(destination).replace('"','""')+'"" --run", 0, False\n'
        startup.write_text(vbs,encoding='utf-8')
    elif startup.exists(): startup.unlink()

def stop(install_dir,startup_dir):
    stop_running(install_dir)

def version_parts(value):
    if not isinstance(value,str) or not re.fullmatch(r'[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}',value):
        raise ValueError('Invalid version')
    return tuple(int(part) for part in value.split('.'))

def check_latest():
    request=urllib.request.Request(VERSION_URL,headers={'Accept':'application/json','Cache-Control':'no-cache','User-Agent':'AzerothWeatherCompanion/version-check'})
    with urllib.request.urlopen(request,timeout=10) as response:
        body=response.read(8193)
        if len(body)>8192: raise ValueError('Version response too large')
    info=json.loads(body)['windows']
    version=info['version']; released=info['released']
    current, latest=version_parts(APP_VERSION), version_parts(version)
    datetime.date.fromisoformat(released)
    if latest>current: description='Update available'
    elif latest==current: description='You are up to date'
    else: description='Your version is newer than the published release'
    return f'{description}  |  Latest: v{version} ({released})'

def add_version_info(parent, window):
    tk.Label(parent,text=f'Your version: v{APP_VERSION}  |  Released {APP_RELEASE_DATE}',bg='#092b3d',fg='#c1dbe0',font=('Segoe UI',9)).pack(anchor='w')
    version_status=tk.StringVar(value='Checking for the latest version...')
    tk.Label(parent,textvariable=version_status,bg='#092b3d',fg='#9fd2da',font=('Segoe UI',9),wraplength=450,justify='left').pack(anchor='w',pady=(3,0))
    results=queue.Queue()
    def check():
        try: results.put(check_latest())
        except Exception: results.put('Could not check the latest version. Check your connection.')
    def poll():
        try: version_status.set(results.get_nowait())
        except queue.Empty: window.after(250,poll)
    threading.Thread(target=check,daemon=True).start()
    window.after(250,poll)
    link=tk.Label(parent,text='Downloads and release notes ↗',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',9,'underline'),cursor='hand2')
    link.pack(anchor='w',pady=(2,0)); link.bind('<Button-1>',lambda event: webbrowser.open(DOWNLOAD_URL))

def configure_window(window, geometry):
    # A dedicated app identity lets Windows display the companion icon in the taskbar.
    try:
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID('CraftingWorlds.WeatherForever.Companion')
    except (AttributeError, OSError):
        pass
    icon_root=pathlib.Path(getattr(sys, '_MEIPASS', pathlib.Path(__file__).resolve().parent))
    icon=icon_root/'weather-rain.ico'
    if icon.is_file():
        try: window.iconbitmap(default=str(icon))
        except tk.TclError: pass
    window.title('Weather Forever Companion')
    window.geometry(geometry)
    window.resizable(True,True)
    window.minsize(*map(int,geometry.split('x')))
    window.configure(bg='#092b3d')

def read_tray_setting(path):
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        return not isinstance(data, dict) or data.get('minimize_to_tray', True) is not False
    except (OSError, ValueError, TypeError):
        return True

def read_startup_setting(path):
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        return not isinstance(data,dict) or data.get('start_with_windows',True) is not False
    except (OSError, ValueError, TypeError):
        return True

def write_setting(path, key, enabled):
    path.parent.mkdir(parents=True,exist_ok=True)
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data,dict): data={}
    except (OSError,ValueError,TypeError): data={}
    data[key]=bool(enabled)
    tmp=path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    os.replace(tmp,path)

def write_tray_setting(path, enabled):
    write_setting(path,'minimize_to_tray',enabled)

def write_startup_setting(path, enabled):
    write_setting(path,'start_with_windows',enabled)

def icon_path():
    return pathlib.Path(getattr(sys,'_MEIPASS',pathlib.Path(__file__).resolve().parent))/'weather-rain.ico'

def running_window():
    # The worker belongs to this visible window: closing it ends the worker too.
    window=tk.Tk(); configure_window(window,'510x430')
    body=tk.Frame(window,bg='#092b3d',padx=28,pady=24); body.pack(fill='both',expand=True)
    tk.Label(body,text='WEATHER FOREVER',bg='#092b3d',fg='#e6f2ed',font=('Segoe UI',18,'bold')).pack(anchor='w')
    tk.Label(body,text='Companion for Windows',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',11)).pack(anchor='w',pady=(0,18))
    status=tk.StringVar(value='Weather sharing is running')
    tk.Label(body,textvariable=status,bg='#092b3d',fg='#a8e0cf',font=('Segoe UI',12,'bold'),wraplength=450,justify='left').pack(anchor='w')
    tk.Label(body,text='Your reports are shared after you reload or log out of WoW. Minimize to keep sharing; reopen from the notification area or taskbar. Closing it stops sharing.',bg='#092b3d',fg='#d0e1e3',font=('Segoe UI',10),wraplength=450,justify='left').pack(anchor='w',pady=(12,16))
    add_version_info(body,window)
    tray_setting_path=INSTALL_DIR/'settings.json'
    tray_enabled=tk.BooleanVar(value=read_tray_setting(tray_setting_path))
    actions=queue.Queue()
    tray_icon=None
    tray_generation=0
    startup_enabled=tk.BooleanVar(value=read_startup_setting(tray_setting_path))
    def open_settings():
        settings=tk.Toplevel(window)
        settings.title('Weather Forever Settings')
        settings.geometry('480x230')
        settings.configure(bg='#092b3d')
        settings.transient(window)
        panel=tk.Frame(settings,bg='#092b3d',padx=22,pady=18); panel.pack(fill='both',expand=True)
        def save_tray_setting():
            try: write_tray_setting(tray_setting_path,tray_enabled.get())
            except OSError as exc:
                tray_enabled.set(not tray_enabled.get())
                messagebox.showerror('Could not save setting',str(exc),parent=settings)
        def save_startup_setting():
            enabled=startup_enabled.get()
            try:
                configure_startup(INSTALL_DIR,startup_directory(),enabled)
                write_startup_setting(tray_setting_path,enabled)
            except OSError as exc:
                startup_enabled.set(not enabled)
                try: configure_startup(INSTALL_DIR,startup_directory(),not enabled)
                except OSError: pass
                messagebox.showerror('Could not save setting',str(exc),parent=settings)
        style=dict(bg='#092b3d',fg='#d0e1e3',selectcolor='#16445a',activebackground='#092b3d',activeforeground='#ffffff',font=('Segoe UI',10),highlightthickness=0)
        tk.Checkbutton(panel,text='Start with Windows',variable=startup_enabled,command=save_startup_setting,**style).pack(anchor='w')
        tk.Label(panel,text='Automatically start sharing when you sign in.',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',9)).pack(anchor='w',padx=24)
        tk.Checkbutton(panel,text='Minimize to the notification area',variable=tray_enabled,command=save_tray_setting,**style).pack(anchor='w',pady=(14,0))
        tk.Label(panel,text='Use the rain icon near the clock to reopen or stop sharing.',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',9),wraplength=420,justify='left').pack(anchor='w',padx=24)
        tk.Button(panel,text='Done',command=settings.destroy,bg='#244754',fg='white',padx=12).pack(anchor='e',pady=(12,0))
    errors=queue.Queue()
    def worker():
        try:
            companion.main()
            errors.put('Sharing stopped. Another companion may already be running.')
        except Exception as exc:
            errors.put('Sharing stopped: '+str(exc))
    def check_worker():
        try: status.set(errors.get_nowait())
        except queue.Empty: pass
        window.after(1000,check_worker)
    def stop_tray():
        nonlocal tray_icon, tray_generation
        tray_generation += 1
        if tray_icon is not None:
            tray_icon.stop()
            tray_icon=None
    def restore():
        stop_tray()
        window.deiconify()
        window.lift()
    def close():
        stop_tray()
        window.destroy()
    def on_minimize(event):
        nonlocal tray_icon, tray_generation
        if event.widget is not window or not tray_enabled.get() or tray_icon is not None:
            return
        def start_if_minimized():
            nonlocal tray_icon, tray_generation
            if window.state()!='iconic' or not tray_enabled.get() or tray_icon is not None:
                return
            try:
                with Image.open(icon_path()) as resource:
                    image=resource.convert('RGBA')
                menu=pystray.Menu(
                    pystray.MenuItem('Open Weather Forever',lambda icon,item: actions.put('open'),default=True),
                    pystray.MenuItem('Stop sharing and close',lambda icon,item: actions.put('close')))
                tray_icon=pystray.Icon('WeatherForever',image,'Weather Forever is sharing',menu)
                tray_generation+=1
                generation=tray_generation
                tray_icon.run_detached()
                def wait_for_icon(attempt=0):
                    if tray_icon is None or generation!=tray_generation: return
                    if tray_icon.visible:
                        if window.state()=='iconic': window.withdraw()
                        else: stop_tray()
                    elif attempt<30:
                        window.after(100,lambda: wait_for_icon(attempt+1))
                    else:
                        stop_tray()
                        window.deiconify()
                        messagebox.showerror('Notification area unavailable','Could not create the tray icon. The companion remains open.')
                window.after(100,wait_for_icon)
            except Exception as exc:
                stop_tray()
                window.deiconify()
                messagebox.showerror('Notification area unavailable',str(exc))
        window.after(100,start_if_minimized)
    def check_actions():
        try:
            action=actions.get_nowait()
            if action=='open': restore()
            elif action=='close': close(); return
        except queue.Empty: pass
        window.after(250,check_actions)
    buttons=tk.Frame(body,bg='#092b3d'); buttons.pack(anchor='w',pady=(14,0))
    tk.Button(buttons,text='Stop sharing and close',command=close,bg='#1c8191',fg='white',font=('Segoe UI',10,'bold'),padx=10,pady=6).pack(side='left')
    tk.Button(buttons,text='Settings',command=open_settings,bg='#244754',fg='white',font=('Segoe UI',10),padx=12,pady=6).pack(side='left',padx=12)
    window.protocol('WM_DELETE_WINDOW',close)
    window.bind('<Unmap>',on_minimize)
    threading.Thread(target=worker,daemon=True).start()
    window.after(250,check_actions)
    window.after(1000,check_worker)
    window.mainloop()

def main():
    if '--run' in sys.argv:
        sys.argv.remove('--run')
        if '--once' in sys.argv: companion.main()
        else: running_window()
        return
    if '--check-package' in sys.argv:
        assert callable(companion.main)
        return
    window=tk.Tk(); configure_window(window,'520x460')
    body=tk.Frame(window,bg='#092b3d',padx=28,pady=20); body.pack(fill='both',expand=True)
    tk.Label(body,text='WEATHER FOREVER',bg='#092b3d',fg='#e6f2ed',font=('Segoe UI',18,'bold')).pack(anchor='w')
    tk.Label(body,text='Companion for Windows',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',11)).pack(anchor='w',pady=(0,16))
    info=('Share weather reports automatically after you reload or log out of WoW. Community reports update when you reload.\n\n'
          'Activation copies the companion to your Windows profile. By default it starts with Windows; change this in Settings. It shares weather, zone, realm, estimated layer, time, source, optional intensity and a random installation ID. '
          'No character or account name is sent.')
    tk.Label(body,text=info,bg='#092b3d',fg='#d0e1e3',font=('Segoe UI',10),wraplength=452,justify='left').pack(anchor='w')
    add_version_info(body,window)
    status=tk.StringVar(value='The companion window stays open while sharing is enabled.')
    tk.Label(body,textvariable=status,bg='#092b3d',fg='#9fd2da',font=('Segoe UI',9),wraplength=450,justify='left').pack(anchor='w',pady=(12,8))
    buttons=tk.Frame(body,bg='#092b3d'); buttons.pack(anchor='w',pady=5)
    def handle_install():
        try:
            if not getattr(sys,'frozen',False): raise RuntimeError('Run the packaged Windows installer.')
            install(sys.executable,INSTALL_DIR,startup_directory())
            window.destroy()
        except Exception as exc: messagebox.showerror('Could not install',str(exc))
    def handle_stop():
        try:
            stop(INSTALL_DIR,startup_directory());status.set('Sharing stopped. It will restart at sign-in if Start with Windows is on.')
            messagebox.showinfo('Azeroth Weather','Sharing stopped. It will restart at sign-in if Start with Windows is on.')
        except Exception as exc: messagebox.showerror('Could not stop sharing',str(exc))
    tk.Button(buttons,text='Activate',command=handle_install,bg='#1c8191',fg='white',font=('Segoe UI',10,'bold'),padx=10,pady=5).pack(side='left')
    tk.Button(buttons,text='Stop sharing',command=handle_stop,bg='#244754',fg='white',font=('Segoe UI',10),padx=10,pady=5).pack(side='left',padx=12)
    window.mainloop()
if __name__=='__main__': main()
