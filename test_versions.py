import io, json, sys, unittest
from unittest.mock import patch
sys.path.insert(0, "companion")
import windows_installer as app
class VersionCheck(unittest.TestCase):
 def check(self, v, date="2026-11-09"):
  body=json.dumps({"windows":{"version":v,"released":date}}).encode()
  with patch.object(app.urllib.request,"urlopen",return_value=io.BytesIO(body)):
   return app.check_latest()
 def test_version_comparison(self):
  self.assertIn("up to date",self.check("0.11.1"))
  self.assertIn("Update available",self.check("0.12.0"))
  self.assertIn("newer than",self.check("0.10.9"))
 def test_bad_metadata_is_not_up_to_date(self):
  for value in ("bad","0.11", "1.2.3.4"):
   with self.assertRaises(ValueError): self.check(value)
  with self.assertRaises(ValueError): self.check("0.11.1","tomorrow")
if __name__=="__main__": unittest.main()
