"""Kuenstlicher Discover-Server fuer die Simulator-Tests. Alle Daten sind erfunden."""
import functools, json, re, struct, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

PORT = 8765
BASE = f"http://127.0.0.1:{PORT}"


@functools.lru_cache(maxsize=None)
def png(seed):
    size = 300
    r, g, b = (seed * 53) % 200 + 40, (seed * 97) % 200 + 40, (seed * 151) % 200 + 40
    rows = b"".join(
        b"\0" + bytes(c for x in range(size) for c in (r, (g + y // 3) % 256, (b + x // 3) % 256))
        for y in range(size))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 1)) + chunk(b"IEND", b""))


def wav(secs=180, rate=8000):
    data = b"\0\0" * (secs * rate)
    return (b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt "
            + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
            + b"data" + struct.pack("<I", len(data)) + data)


AUDIO = wav()


def track(i):
    return {"uri": f"spotify:track:test{i}", "name": f"Song {i}", "artist": f"Kuenstler {i % 9 + 1}",
            "artists": [{"name": f"Kuenstler {i % 9 + 1}", "uri": f"spotify:artist:test{i % 9 + 1}"}],
            "album": f"Album {i % 20 + 1}", "image": f"/cover/{i % 40 + 1}.png", "duration_ms": 180000,
            "downloaded": True, "navidromeId": f"test{i}"}


def playlist(i):
    return {"uri": f"spotify:playlist:test{i}", "name": f"Playlist {i}", "image": f"/cover/{i % 40 + 1}.png"}


def item(i):
    return dict(playlist(i), sub=f"Beschreibung {i}", type="playlist")


def stations():
    return [{"id": f"s{i}", "name": f"Sender {i}", "url": BASE + "/audio.wav",
             "favicon": f"/cover/{i}.png", "country": "Testland"} for i in range(1, 9)]


def route(path, q):
    if path == "/api/ping":
        return {"ok": True}
    if path == "/api/profiles":
        return {"profiles": [{"id": "test", "name": "Test", "color": "#1db954", "country": "DE", "is_admin": True}]}
    if path == "/api/playlists":
        off, lim = int(q.get("offset", ["0"])[0]), int(q.get("limit", ["50"])[0])
        items = [playlist(i) for i in range(1, 301)][off:off + lim]
        more = off + lim < 300
        return {"items": items, "next_offset": off + lim if more else None, "has_more": more}
    if path == "/api/home":
        return {"greeting": "Guten Abend", "user_name": "Test", "country": "DE",
                "quick": [item(i) for i in range(1, 7)],
                "sections": [{"title": f"Rubrik {s}", "subtitle": None, "uri": None,
                              "items": [item(s * 20 + i) for i in range(12)]} for s in range(1, 7)]}
    if path.startswith("/api/playlist/") or path.startswith("/api/album/"):
        return {"name": "Playlist", "tracks": [track(i) for i in range(1, 101)]}
    if path == "/api/search":
        return {"tracks": [track(i) for i in range(1, 11)],
                "artists": [{"uri": f"spotify:artist:test{i}", "name": f"Kuenstler {i}",
                             "image": f"/cover/{i}.png"} for i in range(1, 6)],
                "playlists": [dict(playlist(i), artist=None, owner="Test", desc="") for i in range(1, 7)]}
    if path == "/api/radio-livestream/favorites":
        return {"items": stations()}
    return {}


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        print(self.command, self.path[:80], args[1] if len(args) > 1 else "", flush=True)

    def send(self, body, ctype="application/json", code=200, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        m = re.fullmatch(r"/cover/(\d+)\.png", u.path)
        if m:
            return self.send(png(int(m.group(1))), "image/png", extra={"Cache-Control": "max-age=86400"})
        if u.path == "/audio.wav":
            r = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
            if r:
                a = int(r.group(1))
                b = min(int(r.group(2) or len(AUDIO) - 1), len(AUDIO) - 1)
                return self.send(AUDIO[a:b + 1], "audio/wav", 206, {
                    "Accept-Ranges": "bytes", "Content-Range": f"bytes {a}-{b}/{len(AUDIO)}"})
            return self.send(AUDIO, "audio/wav", extra={"Accept-Ranges": "bytes"})
        self.send(json.dumps(route(unquote(u.path), parse_qs(u.query))).encode())

    do_HEAD = do_GET

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if urlparse(self.path).path == "/api/stream-url":
            return self.send(json.dumps({"ok": True, "url": "/audio.wav", "source": "navidrome", "duration": 180}).encode())
        self.send(b"{}")


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
