from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess
import json

APP_DIR = "/home/danila/devops"

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length)

        try:
            data = json.loads(body)

            if "ref" in data:
                print("Push received")
                subprocess.run(["bash", f"{APP_DIR}/deploy.sh"])

        except Exception as e:
            print("Error:", e)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
