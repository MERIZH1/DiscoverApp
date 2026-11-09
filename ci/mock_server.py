"""Kuenstlicher Discover-Server fuer die Simulator-Tests. Alle Daten sind erfunden."""
import functools, json, os, re, struct, time, zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

PORT = 8765
FIXTURE = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture.m4a"), "rb").read()
VIDEO = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixture.mp4"), "rb").read()
BASE = f"http://127.0.0.1:{PORT}"
LIKED = set()   # Herz im Player: gelikte Songs
REMOTE = {}     # Test „anderes Gerät spielt“: Stand, den /api/sync/wait meldet
SPECIAL = {}    # Test Sonderdesign: was /api/special meldet


def special_look():
    """Aussehen fürs Sonderdesign im Test: ci/special.json, sonst neutrale Sterne."""
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "special.json")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return {"symbol": "star.fill", "colors": ["#ffd60a", "#ffffff", "#ffe680"], "accent": "#ffd60a",
            "count": 14, "burst": "star.fill", "rain": True}


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


def hls():
    """Playlist fuer ci/fixture.m4a (Sinuston), aufgebaut wie Discovers /api/yt/hls."""
    d = FIXTURE
    pos = init = 0
    while True:
        size, kind = struct.unpack(">I4s", d[pos:pos + 8])
        if kind == b"moov":
            init = pos + size
        if kind == b"sidx":
            break
        pos += size
    ts = struct.unpack(">I", d[pos + 16:pos + 20])[0]
    if d[pos + 8] == 0:
        first = struct.unpack(">I", d[pos + 24:pos + 28])[0]
        table = pos + 28
    else:
        first = struct.unpack(">Q", d[pos + 28:pos + 36])[0]
        table = pos + 36
    count = struct.unpack(">H", d[table + 2:table + 4])[0]
    off = pos + size + first
    lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-TARGETDURATION:11", "#EXT-X-MEDIA-SEQUENCE:0",
             "#EXT-X-PLAYLIST-TYPE:VOD", "#EXT-X-INDEPENDENT-SEGMENTS", f'#EXT-X-MAP:URI="/seg",BYTERANGE="{init}@0"']
    for i in range(count):
        ref, dur, _ = struct.unpack(">III", d[table + 4 + i * 12:table + 16 + i * 12])
        lines += [f"#EXTINF:{dur / ts:.5f},", f"#EXT-X-BYTERANGE:{ref & 0x7fffffff}@{off}", "/seg"]
        off += ref & 0x7fffffff
    return "\n".join(lines + ["#EXT-X-ENDLIST", ""]).encode()


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
        alle = [{"uri": "spotify:collection:tracks", "name": "Liked Songs", "image": "/cover/7.png"}] +                [playlist(i) for i in range(1, 301)]
        items = alle[off:off + lim]
        more = off + lim < len(alle)
        return {"items": items, "next_offset": off + lim if more else None, "has_more": more}
    if path == "/api/home":
        return {"greeting": "Guten Abend", "user_name": "Test", "country": "DE",
                "quick": [item(i) for i in range(1, 7)],
                "sections": [{"title": f"Rubrik {s}", "subtitle": None, "uri": None,
                              "items": [item(s * 20 + i) for i in range(12)]} for s in range(1, 7)]}
    if path.startswith("/api/album/"):
        return {"name": "Album", "tracks": [track(i) for i in range(1, 13)], "release_date": "2013-09-16",
                "release_precision": "DAY", "year": "2013", "album_type": "album",
                "artists": [{"name": "Kuenstler 2", "uri": "spotify:artist:test2"}],
                "copyright": ["(C) 2013 Testlabel", "(P) 2013 Testlabel"]}
    if path.startswith("/api/playlist/") and "probe" in path:
        # Playlist mit Kapiteln (Feld „section“)
        return {"name": "Sonderkarte",
                "tracks": [dict(track(i), section=f"Kapitel {(i - 1) // 4 + 1}") for i in range(1, 13)]}
    if path.startswith("/api/playlist/"):
        return {"name": "Playlist", "tracks": [track(i) for i in range(1, 101)]}
    if path == "/api/search":
        if q.get("q", [""])[0].startswith("Buch"):
            return {"tracks": [], "artists": [], "albums": [], "playlists": [],
                    "shows": [{"uri": "spotify:show:buch1", "name": "Testbuch", "image": "/cover/4.png"}]}
        if q.get("q", [""])[0].startswith("Lokal"):
            lokal = {"uri": "navidrome:test50", "name": "Lokaler Song", "artist": "Kuenstler 2", "album": "Album 3",
                     "image": "/cover/3.png", "duration_ms": 180000, "navidromeId": "test50"}
            return {"tracks": [lokal], "playlists": [], "albums": [],
                    "artists": [{"uri": "spotify:artist:test2", "name": "Kuenstler 2", "image": "/cover/2.png"}]}
        if q.get("q", [""])[0] == "Album 3":
            return {"tracks": [], "artists": [], "albums": [], "playlists": [],
                    "local_albums": [{"uri": "navialbum:test3", "name": "Album 3", "image": "/cover/3.png"}]}
        if q.get("q", [""])[0].startswith("Tot"):
            return {"tracks": [dict(track(1), name="Toter Song", navidromeId="")], "artists": [], "albums": [], "playlists": []}
        return {"tracks": [track(i) for i in range(1, 11)],
                "artists": [{"uri": f"spotify:artist:test{i}", "name": f"Kuenstler {i}",
                             "image": f"/cover/{i}.png"} for i in range(1, 6)],
                "playlists": [dict(playlist(i), artist=None, owner="Test", desc="") for i in range(1, 7)]}
    if path.startswith("/api/podcast/"):
        return {"show": {"name": "Podcast"}, "episodes": []}
    if path.startswith("/api/artist/"):
        rel = [{"uri": "spotify:artist:test%d" % i, "name": "Kuenstler %d" % i, "image": "/cover/%d.png" % (i + 10)}
               for i in range(3, 9)]
        rels = [{"uri": "spotify:album:test%d" % i, "name": "Album %d" % i, "image": "/cover/%d.png" % (i + 20),
                 "year": str(2010 + i), "type": "album" if i < 4 else "single"} for i in range(1, 7)]
        return {"uri": "spotify:artist:test2", "name": "Kuenstler 2", "image": "/cover/2.png", "followers": 1000,
                "avatar": "/cover/2.png", "header_image": "/cover/1.png", "monthly_listeners": 1234567,
                "color": "#3d5474", "bio": "Erfundene Bio fuer den Test. " * 8, "about_image": "/cover/2.png",
                "related": rel, "discog_popular": rels[:4], "discog_albums": rels[:3], "discog_singles": rels[3:],
                "top_tracks": [track(i) for i in range(1, 8)], "albums": rels}
    if path in ("/api/sync/wait", "/api/sync/state"):
        if not REMOTE:
            return {"commands": [], "state": None, "wait": False}
        now = time.time() * 1000
        return {"commands": [], "state": {**REMOTE, "owner_seen_at": now, "updated_at": now}, "wait": False}
    if path == "/api/special":
        return SPECIAL
    if path == "/api/liked/check":
        return {"liked": {u: u in LIKED for u in q.get("uris", [""])[0].split(",") if u}}
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
        if u.path == "/special/voice.m4a":
            return self.send(FIXTURE, "audio/mp4")
        if u.path == "/special/video.mp4":
            r = re.fullmatch(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
            if r:
                a = int(r.group(1))
                b = min(int(r.group(2) or len(VIDEO) - 1), len(VIDEO) - 1)
                return self.send(VIDEO[a:b + 1], "video/mp4", 206, {
                    "Accept-Ranges": "bytes", "Content-Range": f"bytes {a}-{b}/{len(VIDEO)}"})
            return self.send(VIDEO, "video/mp4", extra={"Accept-Ranges": "bytes"})
        if u.path == "/dead.wav":
            return self.send(b"{}", code=502)
        if u.path == "/hls.m3u8":
            return self.send(hls(), "application/vnd.apple.mpegurl")
        if u.path == "/seg":
            r = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
            a, b = int(r.group(1)), int(r.group(2))
            return self.send(FIXTURE[a:b + 1], "audio/mp4", 206, {
                "Accept-Ranges": "bytes", "Content-Range": f"bytes {a}-{b}/{len(FIXTURE)}"})
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
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        if urlparse(self.path).path == "/api/bglog":
            print("BGLOG", f"{time.time():.3f}", body[:220].decode("utf-8", "replace"), flush=True)
        if urlparse(self.path).path == "/test/special":
            d = json.loads(body or b"{}")
            an = bool(d.get("on"))
            SPECIAL.clear()
            if an:
                # Eigene ID je Einschalten: Was das Gerät schon gezeigt hat, gilt dann nicht mehr
                SPECIAL.update({"id": f"test-extras-{int(time.time())}" if d.get("extras") else "test",
                                "end": time.time() + 3600,
                                "app": special_look(), "greeting": "Probe-Gruß",
                                "card": {"kicker": "Probe", "title": "Sonderkarte", "sub": "Nur im Test",
                                         "uri": "ytpl:probe", "image": "/cover/12.png"}})
            if an and d.get("extras"):
                # Nachricht beim Öffnen, Einblendung in 4 s mit Video, Sprachaufnahme nach 1 Songwechsel
                SPECIAL.update({
                    "message": {"title": "Probe-Nachricht", "text": "Erste Zeile.\nZweite Zeile.",
                                "button": "Playlist abspielen", "uri": "ytpl:probe"},
                    "notice": {"at": time.time() + 4, "title": "Probe-Einblendung", "text": "Tippen spielt das Video",
                               "video": "/special/video.mp4"},
                    "voice": {"url": "/special/voice.m4a", "after": 1, "label": "Probe-Aufnahme"}})
            print("SPECIAL", an, flush=True)
            return self.send(b'{"ok": true}')
        if urlparse(self.path).path == "/api/special/seen":
            what = json.loads(body or b"{}").get("what")
            SPECIAL.pop(what, None)
            print("SPECIAL seen", what, flush=True)
            return self.send(b'{"ok": true}')
        if urlparse(self.path).path == "/test/remote":
            REMOTE.clear()
            REMOTE.update(json.loads(body or b"{}"))
            print("REMOTE", REMOTE.get("device_name"), flush=True)
            return self.send(b'{"ok": true}')
        if urlparse(self.path).path == "/api/liked":
            d = json.loads(body or b"{}")
            uri, an = d.get("uri", ""), bool(d.get("liked", True))
            (LIKED.add if an else LIKED.discard)(uri)
            print("LIKED", "+" if an else "-", uri, flush=True)
            return self.send(json.dumps({"ok": True, "uri": uri, "liked": an}).encode())
        if urlparse(self.path).path == "/api/stream-url" and b"Toter Song" in body:
            return self.send(json.dumps({"ok": True, "url": "/dead.wav", "source": "youtube", "duration": 180}).encode())
        if urlparse(self.path).path == "/api/stream-url":
            return self.send(json.dumps({"ok": True, "url": "/audio.wav", "hls": "/hls.m3u8", "source": "youtube",
                                         "duration": 60}).encode())
        self.send(b"{}")


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
