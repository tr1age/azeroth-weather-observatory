# Azeroth Weather Observatory

A community weather report for World of Warcraft: Forever. The in-game addon records observations; the optional companion can share saved reports with [weather.craftingworlds.com](https://weather.craftingworlds.com) and download community reports. The website, addon and companion are independent of Blizzard Entertainment.

## Download

See [GitHub Releases](https://github.com/tr1age/azeroth-weather-observatory/releases) for the addon, Windows installer, and Mac companion builds. Choose the right Mac architecture. The installers are currently unsigned; Windows or macOS may warn about or block them.

## Privacy and behavior

The addon uses WoW's weather API when available and writes saved variables when WoW saves addon data. Manual reports are checked against the local game reading when possible. Sharing through the companion is optional and requires installation and consent. The companion reads the AzerothWeather saved data and sends weather, zone, realm, estimated layer identifier, observation time, source, optional intensity, and a random installation identifier. It does not send character or account names. Reports are public and not independently verified by the website. The identifier is pseudonymous, can be reset, and is used for counting and moderation.

The Windows companion displays its installed version and release date, and checks the website for the latest Windows version. If the check fails, it says so rather than claiming the app is current.

## Source

- `addon/AzerothWeather/`: in-game addon source. It references WoW's built-in icon textures and includes user-provided clear-weather and rain icons.
- `companion/companion.py` and `companion/saved_data.py`: companion and saved-variable parser.
- `companion/windows_installer.py`: single-file Windows installer and background runner.
- `companion/mac/`: Mac installer and stop scripts.
- `.github/workflows/build-macos.yml`: Mac build workflow.

The website source is maintained separately and is not included here.

## Building

The Windows release was built on Windows with Python 3.14 and PyInstaller 6.22.3:

```powershell
python -m pip install pyinstaller==6.22.3
python -m PyInstaller --noconfirm --clean --onefile --noconsole --name AzerothWeather-Setup companion/windows_installer.py
```

GitHub Actions builds Mac packages on both Apple silicon and Intel runners. The generated installers are not signed or notarized. Building from source yourself is an option; a published binary is not automatically proven safe merely because source is available.

## Limitations

WoW writes SavedVariables on reload or logout; the companion cannot send observations until then, and community reports load on a subsequent reload. The provided installers expect the standard WoW Forever installation path. Layer identifiers are estimated from nearby NPCs and can change or be unavailable. They are not official layer numbers; reports with unknown layers remain separate. Weather API behavior and layer information vary by client; test in game.
