$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$icon = Join-Path $root 'companion/weather-rain.ico'
$entry = Join-Path $root 'companion/windows_installer.py'
python -m PyInstaller --noconfirm --clean --onefile --windowed --name WeatherForever-Setup-0.11.3 --icon $icon --add-data "${icon};." --distpath (Join-Path $root 'build-windows/dist') --workpath (Join-Path $root 'build-windows/work') --specpath (Join-Path $root 'build-windows') $entry
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }

