"""Python side of SealPad.

Every public function takes ONE json string and returns ONE json string,
so the Objective-C bridge stays tiny. Errors come back as {"error": "..."}.
Downloads run in worker threads and push events into a queue that Swift
drains with drain_events().
"""
import hashlib
import json
import os
import queue
import re
import shlex
import sys
import tempfile
import threading
import traceback
import urllib.request
import zipfile

_cfg = {}
_events = queue.Queue()
_cancelled = set()


def _guard(fn):
    def wrapper(arg="{}"):
        try:
            return json.dumps(fn(json.loads(arg or "{}")))
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            return json.dumps({"error": f"{type(e).__name__}: {e}"})
    wrapper.__name__ = fn.__name__
    return wrapper


# --------------------------------------------------------------------------
# setup / updated-yt-dlp activation
# --------------------------------------------------------------------------
def _ytdlp_root():
    return os.path.join(_cfg["support"], "ytdlp")


def _activate_updated():
    """Prefer the downloaded yt-dlp over the bundled one, fall back if broken."""
    marker = os.path.join(_ytdlp_root(), "current.txt")
    if not os.path.isfile(marker):
        return
    with open(marker) as f:
        path = os.path.join(_ytdlp_root(), f.read().strip())
    if not os.path.isdir(path):
        return
    sys.path.insert(0, path)
    try:
        import yt_dlp.version  # noqa: F401
    except Exception:  # noqa: BLE001
        traceback.print_exc()
        sys.path.remove(path)
        for name in [m for m in sys.modules if m.split(".")[0] in ("yt_dlp", "yt_dlp_ejs")]:
            del sys.modules[name]


def _version():
    import yt_dlp.version
    return yt_dlp.version.__version__


@_guard
def configure(a):
    _cfg.update(a)  # {"support": ..., "downloads": ...}
    try:  # iOS has no system CA bundle in the usual place
        import certifi
        os.environ.setdefault("SSL_CERT_FILE", certifi.where())
    except ImportError:
        pass
    _activate_updated()
    return {"version": _version()}


@_guard
def version(_a):
    return {"version": _version()}


def _cookiefile():
    p = os.path.join(_cfg["support"], "cookies.txt")
    return p if os.path.isfile(p) else None


# --------------------------------------------------------------------------
# info (for the format picker)
# --------------------------------------------------------------------------
@_guard
def extract_info(a):
    import yt_dlp
    warns = []

    class Log:
        def debug(self, m): pass
        def info(self, m): pass
        def warning(self, m): warns.append(m)
        def error(self, m): warns.append(m)

    opts = {
        "skip_download": True,
        "noplaylist": a.get("noplaylist", True),
        "extract_flat": "in_playlist",
        "logger": Log(),
        # return what was found (even nothing) so the app can explain why
        "ignore_no_formats_error": True,
    }
    if _cookiefile():
        opts["cookiefile"] = _cookiefile()
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.sanitize_info(ydl.extract_info(a["url"], download=False))

    formats = []
    for f in info.get("formats") or []:
        if f.get("ext") == "mhtml" or f.get("format_note") == "storyboard":
            continue
        formats.append({
            "id": f["format_id"],
            "ext": f.get("ext"),
            "resolution": f.get("resolution"),
            "height": f.get("height"),
            "vcodec": f.get("vcodec"),
            "acodec": f.get("acodec"),
            "filesize": f.get("filesize") or f.get("filesize_approx"),
            "tbr": f.get("tbr"),
            "note": f.get("format_note"),
        })
    entries = info.get("entries")
    return {
        "title": info.get("title") or a["url"],
        "uploader": info.get("uploader"),
        "thumbnail": info.get("thumbnail"),
        "duration": info.get("duration"),
        "is_playlist": entries is not None,
        "count": len(list(entries)) if entries is not None else None,
        "formats": formats,
        "warnings": [w[:300] for w in warns[-5:]],
    }


# --------------------------------------------------------------------------
# downloads
# --------------------------------------------------------------------------
def _custom_overrides(arg_string):
    """Turn a yt-dlp CLI string into ydl opts, keeping only what the user set."""
    from yt_dlp import parse_options
    args = shlex.split(arg_string)
    base = parse_options([]).ydl_opts
    given = parse_options(args).ydl_opts
    return {k: v for k, v in given.items() if base.get(k) != v}


def _has(codec):
    return codec not in (None, "none")


def _is_http(f):
    return f.get("protocol") in ("https", "http")


def _muxable_video(f):
    """H.264 video-only in mp4: AVFoundation can merge it with AAC on the device, no re-encode."""
    return (_has(f.get("vcodec")) and not _has(f.get("acodec"))
            and f.get("ext") == "mp4"
            and str(f.get("vcodec")).startswith(("avc1", "h264"))
            and _is_http(f))


def _aac_audio(f):
    return (_has(f.get("acodec")) and not _has(f.get("vcodec"))
            and f.get("ext") == "m4a" and _is_http(f))


def _abr(f):
    return f.get("abr") or f.get("tbr") or 0


def _make_selector(a, stats):
    """Format selector that inspects the real format list first (like -F), then picks.

    No ffmpeg on iOS, so we only choose things the device can finish itself:
      * a single file that already has video+audio, or
      * H.264/mp4 video-only + AAC/m4a audio -> downloaded as two files; Swift merges
        them with AVFoundation (stats["merge"] tells the worker to flag that).
    Options (all optional): mode (video|audio), format_id (pinned), max_height,
    audio_format (m4a|original).
    """
    mode = a.get("mode")
    pinned = a.get("format_id")
    max_h = int(a.get("max_height") or 0)
    audio_pref = a.get("audio_format") or "m4a"

    def selector(ctx):
        fmts = [f for f in ctx["formats"]
                if f.get("ext") != "mhtml" and f.get("format_note") != "storyboard"]
        combined = [f for f in fmts if _has(f.get("vcodec")) and _has(f.get("acodec")) and _is_http(f)]
        video_only = [f for f in fmts if _has(f.get("vcodec")) and not _has(f.get("acodec"))]
        audio_only = [f for f in fmts if _has(f.get("acodec")) and not _has(f.get("vcodec"))]
        aac_pool = [f for f in audio_only if _aac_audio(f)]
        stats.update(total=len(fmts), combined=len(combined), video_only=len(video_only),
                     audio_only=len(audio_only), aac=len(aac_pool),
                     muxable=len([f for f in video_only if _muxable_video(f)]))
        best_aac = max(aac_pool, key=_abr) if aac_pool else None

        def pair(v, au):
            stats["merge"] = True
            return {
                "format_id": f'{v["format_id"]}+{au["format_id"]}',
                "ext": "mp4",
                "requested_formats": [v, au],
                "protocol": f'{v.get("protocol", "https")}+{au.get("protocol", "https")}',
            }

        # A format the user picked by hand
        if pinned:
            f = next((x for x in fmts if x["format_id"] == pinned), None)
            if f is None:
                return
            if _muxable_video(f) and best_aac:
                yield pair(f, best_aac)
            else:
                yield f
            return

        if mode == "audio":
            pool = (aac_pool or audio_only) if audio_pref == "m4a" else audio_only
            if pool:
                yield max(pool, key=_abr)
            return

        # Video: best of {combined files, muxable video-only (needs AAC audio)}
        pool_all = list(combined)
        if best_aac:
            pool_all += [f for f in video_only if _muxable_video(f)]
        if not pool_all:
            return
        within = [f for f in pool_all if not max_h or (f.get("height") or 0) <= max_h]
        if within:
            best = max(within, key=lambda f: (f.get("height") or 0, _has(f.get("acodec")), f.get("tbr") or 0))
        else:  # everything is above the requested height: take the smallest
            best = min(pool_all, key=lambda f: f.get("height") or 0)
        yield best if _has(best.get("acodec")) else pair(best, best_aac)

    return selector


def _no_format_message(stats, warns):
    total = stats.get("total", 0)
    msg = (f"No format this app can save. yt-dlp found {total} formats "
           f"({stats.get('combined', 0)} video+audio, {stats.get('video_only', 0)} video-only "
           f"[{stats.get('muxable', 0)} H.264/mp4], {stats.get('audio_only', 0)} audio-only "
           f"[{stats.get('aac', 0)} AAC/m4a]). ")
    if total == 0:
        msg += ("Zero formats usually means the site's JavaScript challenge wasn't solved "
                "(YouTube needs a JS runtime). ")
    else:
        msg += ("Without ffmpeg only video+audio files, or H.264 video with AAC audio "
                "(merged on the device), can be saved. ")
    msg += "Tap Formats to see what exists."
    if warns:
        msg += " yt-dlp said: " + " | ".join(w[:160] for w in warns[-3:])
    return msg


def _download_worker(job, opts, stats):
    import yt_dlp
    jid = job["id"]
    files = []
    warns = []

    def emit(**kw):
        _events.put({"id": jid, **kw})

    def hook(d):
        if jid in _cancelled:
            raise yt_dlp.utils.DownloadCancelled("cancelled")
        if d["status"] == "finished":
            files.append(d["filename"])
        info = d.get("info_dict") or {}
        emit(type="progress", status=d["status"], title=info.get("title"),
             downloaded=d.get("downloaded_bytes"),
             total=d.get("total_bytes") or d.get("total_bytes_estimate"),
             speed=d.get("speed"), eta=d.get("eta"))

    class Log:
        def debug(self, m): pass
        def info(self, m): pass
        def warning(self, m):
            warns.append(m)
            emit(type="log", text=m)
        def error(self, m):
            warns.append(m)
            emit(type="log", text=m)

    opts = dict(opts, progress_hooks=[hook], logger=Log(), noprogress=True)
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([job["url"]])
        emit(type="done", files=files, merge=bool(stats.get("merge")))
    except Exception as e:  # noqa: BLE001
        if jid in _cancelled:
            emit(type="cancelled")
        else:
            traceback.print_exc()
            text = f"{type(e).__name__}: {e}"
            if "Requested format is not available" in str(e) or "No video formats found" in str(e):
                text = _no_format_message(stats, warns)
            elif warns:
                text += " | " + " | ".join(w[:160] for w in warns[-2:])
            emit(type="error", text=text)


@_guard
def start_download(a):
    out = _cfg["downloads"]
    stats = {}
    opts = {
        # Looks at the real format list first, then picks (see _make_selector)
        "format": _make_selector(a, stats),
        "outtmpl": os.path.join(out, "%(title).150B [%(id)s].%(ext)s"),
        "noplaylist": False,
        "concurrent_fragment_downloads": 4,
        "restrictfilenames": False,
        "windowsfilenames": True,
    }
    if _cookiefile():
        opts["cookiefile"] = _cookiefile()
    if a.get("custom_args", "").strip():
        opts.update(_custom_overrides(a["custom_args"]))
    threading.Thread(target=_download_worker, args=(a, opts, stats), daemon=True).start()
    return {"started": True}


@_guard
def cancel(a):
    _cancelled.add(a["id"])
    return {"ok": True}


@_guard
def drain_events(_a):
    events = []
    while True:
        try:
            events.append(_events.get_nowait())
        except queue.Empty:
            return {"events": events}


# --------------------------------------------------------------------------
# updater: pulls yt-dlp + its pinned yt-dlp-ejs from PyPI, verifies SHA-256
# --------------------------------------------------------------------------
def _pypi(name, version=None):
    path = f"{name}/{version}/json" if version else f"{name}/json"
    with urllib.request.urlopen(f"https://pypi.org/pypi/{path}", timeout=30) as r:
        return json.load(r)


def _install_wheel(meta, dest):
    wheel = next(u for u in meta["urls"]
                 if u["packagetype"] == "bdist_wheel" and u["filename"].endswith("none-any.whl"))
    fd, tmp = tempfile.mkstemp(suffix=".whl")
    os.close(fd)
    h = hashlib.sha256()
    with urllib.request.urlopen(wheel["url"], timeout=120) as r, open(tmp, "wb") as f:
        while chunk := r.read(1 << 16):
            h.update(chunk)
            f.write(chunk)
    if h.hexdigest() != wheel["digests"]["sha256"]:
        os.remove(tmp)
        raise RuntimeError(f"checksum mismatch for {wheel['filename']}")
    with zipfile.ZipFile(tmp) as z:
        z.extractall(dest)
        meta_txt = next((z.read(n).decode() for n in z.namelist()
                         if n.endswith(".dist-info/METADATA")), "")
    os.remove(tmp)
    return meta_txt


@_guard
def update(_a):
    current = _version()
    meta = _pypi("yt-dlp")
    latest = meta["info"]["version"]
    root = _ytdlp_root()
    dest = os.path.join(root, latest)

    if latest == current:
        return {"up_to_date": True, "version": current}
    if os.path.isdir(dest):
        return {"installed": latest, "previous": current, "restart_required": True}

    os.makedirs(root, exist_ok=True)
    tmp_dest = dest + ".part"
    if os.path.isdir(tmp_dest):
        import shutil
        shutil.rmtree(tmp_dest)

    metadata = _install_wheel(meta, tmp_dest)
    # Each yt-dlp release pins one exact yt-dlp-ejs version; install that one.
    m = re.search(r"Requires-Dist:\s*yt-dlp-ejs\s*\(?==\s*([\w.]+)", metadata)
    if m:
        _install_wheel(_pypi("yt-dlp-ejs", m.group(1)), tmp_dest)

    os.rename(tmp_dest, dest)
    with open(os.path.join(root, "current.txt"), "w") as f:
        f.write(latest)

    # keep the newest two installs, delete the rest
    import shutil
    olds = sorted(d for d in os.listdir(root)
                  if os.path.isdir(os.path.join(root, d)) and not d.endswith(".part"))
    for d in olds[:-2]:
        shutil.rmtree(os.path.join(root, d), ignore_errors=True)

    return {"installed": latest, "previous": current, "restart_required": True}
