import os
import sys
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class GameServer(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, address, handler, directory):
        super().__init__(address, handler)
        self.directory = directory
        self.close_requested_at = 0.0
        self.last_ping = time.monotonic()
        self.close_lock = threading.Lock()

    def schedule_shutdown(self):
        with self.close_lock:
            self.close_requested_at = time.monotonic()

        def wait_for_page_to_reopen():
            deadline = time.monotonic() + 4.0
            while time.monotonic() < deadline:
                time.sleep(0.25)
                with self.close_lock:
                    last_ping = self.last_ping
                if time.monotonic() - last_ping >= 1.5:
                    self.shutdown()
                    return

        threading.Thread(target=wait_for_page_to_reopen, daemon=True).start()


class Handler(SimpleHTTPRequestHandler):
    server_version = "RatsGameServer/1.0"

    def __init__(self, *args, **kwargs):
        directory = args[2].directory if len(args) >= 3 else os.getcwd()
        super().__init__(*args, directory=directory, **kwargs)

    def _send_empty(self, status=204):
        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/__rats_alive":
            self.server.last_ping = time.monotonic()
            self._send_empty(204)
            return
        super().do_GET()

    def do_POST(self):
        path = urlsplit(self.path).path
        if path == "/__rats_close":
            length = int(self.headers.get("Content-Length", "0") or 0)
            if length:
                self.rfile.read(min(length, 4096))
            self._send_empty(204)
            self.server.schedule_shutdown()
            return
        self._send_empty(404)

    def log_message(self, fmt, *args):
        # The launcher window is a lifecycle console, not a request log.
        return


def main():
    if len(sys.argv) < 2:
        print("Usage: game_server.py PORT [DIRECTORY]", file=sys.stderr)
        return 2
    port = int(sys.argv[1])
    directory = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.getcwd()
    server = GameServer(("127.0.0.1", port), Handler, directory)
    print(f"Rats game server listening on http://127.0.0.1:{port}/", flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
