#!/usr/bin/env python3
"""Generate a local H.264 Shorts fixture and serve it for ShortsPreloadingUITests."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default="ffmpeg", help="Path to an installed FFmpeg executable")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="shorts-media-") as directory:
        root = Path(directory)
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
             "testsrc2=size=360x640:rate=30", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
             "-t", "40", "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
             "-g", "60", "-sc_threshold", "0", "-b:v", "600k", "-c:a", "aac", "-b:a", "64k",
             "-f", "hls", "-hls_time", "2", "-hls_list_size", "0", "-hls_segment_filename",
             str(root / "seg%03d.ts"), str(root / "stream.m3u8")], check=True)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                name = self.path.split("?")[0].rsplit("/", 1)[-1]
                if name == "health":
                    data = b"shorts-media-fixture"
                elif name == "master.m3u8":
                    time.sleep(0.35)
                    data = (b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=360x640,'
                            b'CODECS="avc1.4d401e,mp4a.40.2"\nstream.m3u8\n')
                elif name == "stream.m3u8" or (name.startswith("seg") and name.endswith(".ts")
                                              and name[3:-3].isdigit()):
                    if name == "seg000.ts":
                        time.sleep(0.25)
                    try:
                        data = (root / name).read_bytes()
                    except FileNotFoundError:
                        self.send_error(404)
                        return
                else:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/vnd.apple.mpegurl"
                                 if name.endswith(".m3u8") else "video/mp2t")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                try:
                    self.wfile.write(data)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                print(json.dumps(dict(time=time.time(), path=self.path, bytes=len(data))), flush=True)

            def log_message(self, *args):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 18765), Handler) as server:
            print("Shorts fixture ready on http://127.0.0.1:18765; Ctrl-C stops and removes media", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
