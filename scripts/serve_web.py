#!/usr/bin/env python3
"""Serve the Godot export without allowing a browser to reuse an old PCK."""

from __future__ import annotations

import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory")
    parser.add_argument("port", nargs="?", type=int, default=8000)
    parser.add_argument("build_id", nargs="?", default="current")
    args = parser.parse_args()

    handler = functools.partial(NoCacheHandler, directory=args.directory)
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError:
        # A forgotten old preview must never cause the user to keep playing it.
        # Bind a fresh OS-selected port and print that exact URL instead.
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    actual_port = server.server_address[1]
    print(
        f"OPEN THIS BUILD: http://localhost:{actual_port}/?build={args.build_id}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
