import tempfile
import unittest
from pathlib import Path
import windows_installer as app

class SettingsTests(unittest.TestCase):
    def test_defaults_and_persistence(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'settings.json'
            self.assertTrue(app.read_startup_setting(path))
            self.assertTrue(app.read_tray_setting(path))
            app.write_startup_setting(path,False)
            app.write_tray_setting(path,False)
            self.assertFalse(app.read_tray_setting(path))
            app.write_tray_setting(path,True)
            self.assertFalse(app.read_startup_setting(path))
            self.assertTrue(app.read_tray_setting(path))
            app.write_startup_setting(path,True)
            self.assertTrue(app.read_tray_setting(path))

    def test_startup_file_follows_setting(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            app.configure_startup(root/'app',root/'startup',True)
            file=root/'startup'/'AzerothWeatherCompanion.vbs'
            self.assertIn(str(root/'app'/app.APP_NAME),file.read_text())
            app.configure_startup(root/'app',root/'startup',False)
            self.assertFalse(file.exists())

if __name__=='__main__': unittest.main()
