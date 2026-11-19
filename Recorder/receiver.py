#!/usr/bin/env python3
"""Reference receiver for the recorder's upload protocol. Use it to test the hardware
before the iOS app exists, and as the spec for the app's listener.

POST /upload   headers: X-Auth, X-Filename, Content-Length
reply 200:     body "OK <bytes_received> <crc32_hex>"   (device deletes its copy only if both match)

GET  /ping     reply 200, body "recorder-receiver". The device finds the server by scanning its subnet for this port
               and accepts only a host that answers this way. An iOS listener must implement it too.
"""
import os, re, sys, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TOKEN = os.environ.get("AUTH_TOKEN", "change-me")
OUT = os.environ.get("OUT_DIR", "received")
os.makedirs(OUT, exist_ok=True)

class H(BaseHTTPRequestHandler):
    def reply(self, code, text):
        b = text.encode()
        self.send_response(code); self.send_header("Content-Length", str(len(b)))
        self.send_header("Connection", "close"); self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        # The recorder scans the subnet and uses this to tell the real receiver from any other service on the port.
        if self.path == "/ping":
            return self.reply(200, "recorder-receiver")
        self.reply(404, "not found")

    def do_POST(self):
        name = os.path.basename(self.headers.get("X-Filename", ""))
        if self.path != "/upload" or self.headers.get("X-Auth") != TOKEN:
            return self.reply(403, "denied")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+\.wav", name):
            return self.reply(400, "bad name")
        total, left, crc = 0, int(self.headers.get("Content-Length", 0)), 0
        tmp = os.path.join(OUT, name + ".part")
        with open(tmp, "wb") as f:
            while left > 0:
                chunk = self.rfile.read(min(65536, left))
                if not chunk: break
                f.write(chunk); crc = zlib.crc32(chunk, crc); total += len(chunk); left -= len(chunk)
        if left:
            os.remove(tmp); return self.reply(400, "short body")
        os.replace(tmp, os.path.join(OUT, name))
        print(f"received {name} {total} bytes crc {crc:08x}", flush=True)
        self.reply(200, f"OK {total} {crc:x}")

    def log_message(self, *a): pass

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()
