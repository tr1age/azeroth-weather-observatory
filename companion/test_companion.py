import unittest, pathlib, tempfile, json, threading, time
from http.server import HTTPServer, BaseHTTPRequestHandler
from saved_data import parse_saved, SavedDataError
import companion
class TestCompanion(unittest.TestCase):
 def test_lua_data_and_reject_code(self):
  data=parse_saved('AzerothWeatherDB = { ["observations"] = { [1] = { ["zone"] = "Elwynn Forest", ["realm"] = "Test", ["weather"] = "rain", ["source"] = "client", ["at"] = 1794200000, ["intensity"] = 0.5, }, }, }')
  self.assertEqual(data['observations'][1]['weather'],'rain')
  with self.assertRaises(SavedDataError): parse_saved('AzerothWeatherDB = os.execute("oops")')
 def test_extraction_minimizes_and_checks_age(self):
  raw='AzerothWeatherDB = { observations = { { zone="Elwynn", realm="Realm", weather="rain", source="client", at=1794200000, intensity=0.5, character="SECRET", subzone="Goldshire" } } }'
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'AzerothWeather.lua';p.write_text(raw,encoding='utf-8')
   reports=companion.records_from_file(p,1794200001);self.assertEqual(len(reports),1)
   self.assertNotIn('character',reports[0]);self.assertNotIn('subzone',reports[0]);self.assertEqual(reports[0]['observed_at'],'2026-11-09T04:53:20.000Z')
   self.assertEqual(companion.records_from_file(p,1794200000+8*86400),[])
 def test_feed_sanitizes_untrusted_data(self):
  now=1794200000
  data={'observations':[{'zone':'Elwynn \" } }; hacked=true; --','realm':'Realm 1','weather':'rain','observed_at':'2026-11-09T04:53:20Z'}, {'zone':'Bad\nName','realm':'Realm','weather':'snow','observed_at':'2026-11-09T04:53:20Z'}]}
  text,count=companion.render_feed(data,now)
  self.assertEqual(count,1)
  self.assertIn('\\\"',text)
  self.assertNotIn('Bad\nName',text)
  self.assertNotIn('character',text)
 def test_miscellaneous_round_trip(self):
  raw='AzerothWeatherDB = { observations = { { zone="Elwynn", realm="Realm", weather="miscellaneous", source="client", at=1794200000 } } }'
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'AzerothWeather.lua';p.write_text(raw,encoding='utf-8')
   reports=companion.records_from_file(p,1794200001)
   self.assertEqual(reports[0]['weather'],'miscellaneous')
   text,count=companion.render_feed({'observations': reports},1794200001)
   self.assertEqual(count,1);self.assertIn('miscellaneous',text)
 def test_feed_refuses_unmanaged_file(self):
  with tempfile.TemporaryDirectory() as d:
   folder=pathlib.Path(d);(folder/'AzerothWeather.toc').write_text('toc');target=folder/'WeatherFeed.lua';target.write_text('user-created file')
   with self.assertRaises(ValueError): companion.refresh_feed(folder,'http://127.0.0.1:1')
   self.assertEqual(target.read_text(),'user-created file')
 def test_upload_and_dedup_key(self):
  class H(BaseHTTPRequestHandler):
   def do_POST(self):
    self.server.received=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
    self.send_response(201);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(b'{"inserted":true}')
   def log_message(self,*args): pass
  server=HTTPServer(('127.0.0.1',0),H);thread=threading.Thread(target=server.handle_request,daemon=True);thread.start()
  r={'zone':'Elwynn','realm':'Realm','weather':'rain','source':'client','observed_at':'2026-11-09T04:53:20.000Z'}
  companion.send(r,'http://127.0.0.1:'+str(server.server_port),'http://127.0.0.1');thread.join();server.server_close()
  self.assertEqual(server.received,r);self.assertEqual(companion.identifier(r),companion.identifier(dict(reversed(list(r.items())))))
if __name__=='__main__': unittest.main()

