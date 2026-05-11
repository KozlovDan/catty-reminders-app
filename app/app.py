from http.server import BaseHTTPRequestHandler, HTTPServer

class AppHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Hello!!!! App is working")

HTTPServer(("0.0.0.0", 8181), AppHandler).serve_forever()

