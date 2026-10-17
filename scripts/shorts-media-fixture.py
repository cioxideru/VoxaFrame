#!/usr/bin/env python3
"""Serve local H.264 Shorts and voice-over audio for playback UI tests."""

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg", default="ffmpeg", help="Path to an installed FFmpeg executable")
    parser.add_argument("--port", type=int, default=18765, help="Loopback port (use a separate port for concurrent workflows)")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="shorts-media-") as directory:
        root = Path(directory)
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
             "testsrc2=size=360x640:rate=30", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
             "-t", "120", "-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p",
             "-g", "60", "-sc_threshold", "0", "-b:v", "600k", "-c:a", "aac", "-b:a", "64k",
             "-f", "hls", "-hls_time", "2", "-hls_list_size", "0", "-hls_segment_filename",
             str(root / "seg%03d.ts"), str(root / "stream.m3u8")], check=True)
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
             "sine=frequency=660:sample_rate=48000", "-t", "120", "-c:a", "libmp3lame",
             "-b:a", "64k", str(root / "voice.mp3")], check=True)


        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(root / "stream.m3u8"),
             "-c", "copy", "-movflags", "+faststart", str(root / "video.mp4")], check=True)
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(root / "video.mp4"),
             "-t", "20", "-vf", "scale=1280:720", "-c:v", "libx264", "-preset", "veryfast",
             "-c:a", "copy", "-movflags", "+faststart", str(root / "video720.mp4")], check=True)
        subprocess.run(
            [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(root / "video.mp4"),
             "-vn", "-c:a", "copy", str(root / "original.m4a")], check=True)
        counts = {}
        counts_lock = Lock()

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                name = self.path.split("?")[0].rsplit("/", 1)[-1]
                if name != "metrics":
                    with counts_lock:
                        counts[self.path] = counts.get(self.path, 0) + 1
                if name == "metrics":
                    with counts_lock:
                        data = json.dumps(counts).encode()
                elif name == "health":
                    data = b"shorts-media-fixture"
                elif name == "master.m3u8":
                    time.sleep(0.35)
                    data = (b'#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=360x640,'
                            b'CODECS="avc1.4d401e,mp4a.40.2"\nstream.m3u8\n')
                elif name in ("stream.m3u8", "voice.mp3", "video.mp4", "video720.mp4", "original.m4a") or (name.startswith("seg") and name.endswith(".ts")
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
                status = 200
                full_length = len(data)
                range_header = self.headers.get("Range", "")
                if range_header.startswith("bytes=") and name.endswith((".mp4", ".m4a", ".mp3")):
                    try:
                        start, end = range_header[6:].split("-", 1)
                        start = int(start or 0)
                        end = min(int(end) if end else full_length - 1, full_length - 1)
                        if start < 0 or start > end:
                            raise ValueError()
                    except ValueError:
                        self.send_error(416)
                        return
                    data = data[start:end + 1]
                    status = 206
                self.send_response(status)
                if status == 206:
                    self.send_header("Content-Range", f"bytes {start}-{end}/{full_length}")
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Type", "application/vnd.apple.mpegurl"
                                 if name.endswith(".m3u8") else "audio/mpeg" if name == "voice.mp3"
                                 else "audio/mp4" if name.endswith(".m4a") else "video/mp4"
                                 if name.endswith(".mp4") else "application/json" if name == "metrics" else "video/mp2t")
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

        with ThreadingHTTPServer(("127.0.0.1", args.port), Handler) as server:
            print(f"Shorts fixture ready on http://127.0.0.1:{args.port}; Ctrl-C stops and removes media", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
