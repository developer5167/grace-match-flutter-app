# Captures the simulator screen when the screenshot test asks: GET /shot?name=X
import http.server, subprocess, sys, urllib.parse, os
UDID, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get('name', ['shot'])[0])
        r = subprocess.run(['xcrun', 'simctl', 'io', UDID, 'screenshot', f'{OUT}/{name}.png'], capture_output=True)
        self.send_response(200 if r.returncode == 0 else 500); self.end_headers(); self.wfile.write(b'ok')
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', 8787), H).serve_forever()
