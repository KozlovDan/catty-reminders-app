from http.server import BaseHTTPRequestHandler, HTTPServer
import os

PORT = 8181

class Handler(BaseHTTPRequestHandler):

    def do_GET(self):

        if self.path == "/":
            deploy_ref = os.getenv("DEPLOY_REF", "unknown")

            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            self.wfile.write(f"""
            <html>
            <body>
                <h1>Catty Reminders App</h1>
                <p>Deploy ref: {deploy_ref}</p>
            </body>
            </html>
            """.encode())

        elif self.path == "/login":

            self.send_response(200)
            self.send_header("Content-type", "text/html")
            self.end_headers()

            self.wfile.write(b"""
            <html>
            <body>
                <h1>Login page</h1>
                <form>
                    <input type='text' placeholder='login'>
                    <input type='password' placeholder='password'>
                    <button>Login</button>
                </form>
            </body>
            </html>
            """)

        else:
            self.send_response(404)
            self.end_headers()

HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()