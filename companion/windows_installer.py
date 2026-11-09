"""Single-file installer and background runner for Azeroth Weather on Windows."""
import ctypes, os, pathlib, shutil, subprocess, sys, tempfile, threading, queue
import tkinter as tk
from tkinter import messagebox
import companion

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
    vbs='CreateObject("WScript.Shell").Run """'+str(destination).replace('"','""')+'"" --run", 0, False\n'
    startup=startup_dir/'AzerothWeatherCompanion.vbs'
    startup.write_text(vbs,encoding='utf-8')
    if launch: subprocess.Popen([str(destination),'--run'],creationflags=subprocess.CREATE_NO_WINDOW,close_fds=True)

def stop(install_dir,startup_dir):
    stop_running(install_dir)
    startup=startup_dir/'AzerothWeatherCompanion.vbs'
    if startup.exists(): startup.unlink()

def running_window():
    # The worker belongs to this visible window: closing it ends the worker too.
    window=tk.Tk(); window.title('Azeroth Weather Companion'); window.geometry('510x300'); window.resizable(False,False); window.configure(bg='#092b3d')
    body=tk.Frame(window,bg='#092b3d',padx=28,pady=24); body.pack(fill='both',expand=True)
    tk.Label(body,text='AZEROTH WEATHER',bg='#092b3d',fg='#e6f2ed',font=('Segoe UI',18,'bold')).pack(anchor='w')
    tk.Label(body,text='Companion for Windows',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',11)).pack(anchor='w',pady=(0,18))
    status=tk.StringVar(value='Weather sharing is running')
    tk.Label(body,textvariable=status,bg='#092b3d',fg='#a8e0cf',font=('Segoe UI',12,'bold'),wraplength=450,justify='left').pack(anchor='w')
    tk.Label(body,text='Your reports are shared after you reload or log out of WoW. Keep this window open while you want to share.',bg='#092b3d',fg='#d0e1e3',font=('Segoe UI',10),wraplength=450,justify='left').pack(anchor='w',pady=(12,16))
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
    def close():
        try:
            startup=startup_directory()/'AzerothWeatherCompanion.vbs'
            if startup.exists(): startup.unlink()
        except OSError as exc:
            messagebox.showerror('Could not stop sharing',str(exc)); return
        window.destroy()
    tk.Button(body,text='Stop sharing and close',command=close,bg='#1c8191',fg='white',font=('Segoe UI',10,'bold'),padx=10,pady=6).pack(anchor='w')
    window.protocol('WM_DELETE_WINDOW',close)
    threading.Thread(target=worker,daemon=True).start()
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
    window=tk.Tk(); window.title('Azeroth Weather Companion'); window.geometry('520x385'); window.resizable(False,False); window.configure(bg='#092b3d')
    body=tk.Frame(window,bg='#092b3d',padx=28,pady=20); body.pack(fill='both',expand=True)
    tk.Label(body,text='AZEROTH WEATHER',bg='#092b3d',fg='#e6f2ed',font=('Segoe UI',18,'bold')).pack(anchor='w')
    tk.Label(body,text='Companion for Windows',bg='#092b3d',fg='#9fd2da',font=('Segoe UI',11)).pack(anchor='w',pady=(0,16))
    info=('Share weather reports automatically after you reload or log out of WoW. Community reports update when you reload.\n\n'
          'Installing enables public sharing of weather, zone, realm, estimated layer, time, source, optional intensity and a random installation ID. '
          'No character or account name is sent. The companion starts with Windows.')
    tk.Label(body,text=info,bg='#092b3d',fg='#d0e1e3',font=('Segoe UI',10),wraplength=452,justify='left').pack(anchor='w')
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
            stop(INSTALL_DIR,startup_directory());status.set('Automatic sharing is stopped. Your saved data is kept.')
            messagebox.showinfo('Azeroth Weather','Automatic sharing is stopped. Your saved data is kept.')
        except Exception as exc: messagebox.showerror('Could not stop sharing',str(exc))
    tk.Button(buttons,text='Install & enable sharing',command=handle_install,bg='#1c8191',fg='white',font=('Segoe UI',10,'bold'),padx=10,pady=5).pack(side='left')
    tk.Button(buttons,text='Stop sharing',command=handle_stop,bg='#244754',fg='white',font=('Segoe UI',10),padx=10,pady=5).pack(side='left',padx=12)
    window.mainloop()
if __name__=='__main__': main()
