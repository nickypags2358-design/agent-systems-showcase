#!/usr/bin/env python3
"""
VISION MCP — the closed visual loop.

The problem it solves, stated plainly:
  An agent that writes CSS but cannot see the result is guessing. A layout can pass
  every structural check — element counts, computed styles all correct — and still
  look wrong: a collapsed grid, colliding cards, a gradient that reads muddy instead
  of glowing. Nothing in a structure-only toolchain can tell the difference.

  This closes that gap: CAPTURE -> READ -> DIFF -> CORRECT -> RECAPTURE.

Why it works without installing anything:
  Headless Chrome ships a renderer most dev machines already have.
  No node, no npm, no ffmpeg, no ImageMagick, no Puppeteer required.

What it CANNOT do, stated up front so nobody builds on a false premise:
  It cannot generate matte-painting or photoreal 3D artwork. Reference imagery
  in that register is produced by a diffusion model or a 3D artist and composited.
  This tool replicates DESIGN — layout, colour, type, vector, motion — not ILLUSTRATION.
"""

import sys, json, os, subprocess, hashlib, struct, zlib

SERVER = {"name": "vision", "version": "1.0.0"}
# Headless Chrome binary used for screenshots. Override with CHROME_BIN if the
# default macOS install path does not match your machine.
CHROME = os.environ.get("CHROME_BIN", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
# Screenshot output directory: override with VISION_SHOTS_DIR, else write under
# the current working directory.
SHOTS = os.environ.get("VISION_SHOTS_DIR", os.path.join(os.getcwd(), "atelier-out", "shots"))

# ── capture ──────────────────────────────────────────────────────────────────

def capture(url, w=1440, h=1000, out=None, full=False, wait=9000, scheme=None):
    os.makedirs(SHOTS, exist_ok=True)
    if not out:
        out = os.path.join(SHOTS, hashlib.sha1((url + str(w) + str(h)).encode()).hexdigest()[:12] + ".png")
    if not os.path.exists(CHROME):
        raise RuntimeError("Chrome not found at " + CHROME + " (set CHROME_BIN to override)")
    cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
           f"--virtual-time-budget={wait}", f"--window-size={w},{h}",
           f"--screenshot={out}"]
    if full:
        cmd.append("--screenshot-full-page")   # honoured by newer builds
    if scheme in ("dark", "light"):
        cmd.append(f"--force-prefers-color-scheme={scheme}")
    cmd.append(url)
    subprocess.run(cmd, capture_output=True, timeout=90)
    if not os.path.exists(out):
        raise RuntimeError("capture produced no file")
    return out

# ── PNG reading, stdlib only (no third-party image library required) ─────────

def png_read(path):
    """Decode a PNG to (w, h, rows[bytes RGBA]) using zlib + manual unfiltering."""
    d = open(path, "rb").read()
    assert d[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
    pos, idat = 8, b""
    w = h = bitd = ct = None
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos+4])[0]
        typ = d[pos+4:pos+8]
        body = d[pos+8:pos+8+ln]
        if typ == b"IHDR":
            w, h, bitd, ct = struct.unpack(">IIBB", body[:10])
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0:1, 2:3, 3:1, 4:2, 6:4}[ct]
    stride = w * ch
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        f = raw[i]; i += 1
        line = bytearray(raw[i:i+stride]); i += stride
        for x in range(stride):
            a = line[x-ch] if x >= ch else 0
            b = prev[x]
            c = prev[x-ch] if x >= ch else 0
            if   f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line)); prev = line
    return w, h, rows, ch

def analyse(path, grid=12):
    """Structural read of an image: palette, luminance map, ink density, balance."""
    w, h, rows, ch = png_read(path)
    step = max(1, w // 260)
    hist = {}
    cw, chh = max(1, w // grid), max(1, h // grid)
    cells = [[0, 0] for _ in range(grid * grid)]      # [sum_lum, n]
    for y in range(0, h, step):
        r = rows[y]
        for x in range(0, w, step):
            o = x * ch
            R, G, B = r[o], r[o+1], r[o+2]
            q = (R//24*24, G//24*24, B//24*24)
            hist[q] = hist.get(q, 0) + 1
            L = (0.2126*R + 0.7152*G + 0.0722*B)
            gi = min(grid-1, y//chh) * grid + min(grid-1, x//cw)
            cells[gi][0] += L; cells[gi][1] += 1
    tot = sum(hist.values()) or 1
    pal = sorted(hist.items(), key=lambda kv: -kv[1])[:10]
    palette = [{"hex": "#%02X%02X%02X" % k, "pct": round(v*100/tot, 1)} for k, v in pal]
    lum = [round((c[0]/c[1]) if c[1] else 0, 1) for c in cells]
    ink = round(sum(1 for L in lum if L > 26) * 100 / len(lum), 1)
    left  = sum(lum[i] for i in range(len(lum)) if (i % grid) <  grid//2)
    right = sum(lum[i] for i in range(len(lum)) if (i % grid) >= grid//2)
    top   = sum(lum[i] for i in range(len(lum)) if (i //grid) <  grid//2)
    bot   = sum(lum[i] for i in range(len(lum)) if (i //grid) >= grid//2)
    return {"w": w, "h": h, "palette": palette,
            "ink_coverage_pct": ink,
            "balance": {"left_right": round(left/(right or 1), 2),
                        "top_bottom": round(top/(bot or 1), 2)},
            "luminance_grid": lum, "grid": grid,
            "dead_zones": [i for i, L in enumerate(lum) if L < 6]}

def compare(a_path, b_path, grid=12):
    A, B = analyse(a_path, grid), analyse(b_path, grid)
    dl = [round(A["luminance_grid"][i] - B["luminance_grid"][i], 1) for i in range(grid*grid)]
    worst = sorted(range(len(dl)), key=lambda i: -abs(dl[i]))[:8]
    ap = {p["hex"] for p in A["palette"]}; bp = {p["hex"] for p in B["palette"]}
    return {"ink_delta": round(A["ink_coverage_pct"] - B["ink_coverage_pct"], 1),
            "balance_delta": {"left_right": round(A["balance"]["left_right"] - B["balance"]["left_right"], 2),
                              "top_bottom": round(A["balance"]["top_bottom"] - B["balance"]["top_bottom"], 2)},
            "palette_only_in_target": sorted(ap - bp),
            "palette_only_in_mine":   sorted(bp - ap),
            "worst_cells": [{"cell": i, "row": i//grid, "col": i%grid, "delta": dl[i]} for i in worst],
            "verdict": "close" if max(abs(x) for x in dl) < 18 else "diverged"}

# ── MCP plumbing ─────────────────────────────────────────────────────────────

TOOLS = [
 {"name":"capture","description":"Headless-Chrome screenshot of any URL or file:// path. Returns the saved path. This is the eyes — use it after every visual change.",
  "inputSchema":{"type":"object","properties":{"url":{"type":"string"},"width":{"type":"integer","default":1440},
   "height":{"type":"integer","default":1000},"full_page":{"type":"boolean","default":False},
   "wait_ms":{"type":"integer","default":9000},"scheme":{"type":"string","enum":["dark","light"]}},"required":["url"]}},
 {"name":"analyse","description":"Structural read of a PNG: dominant palette with percentages, 12x12 luminance map, ink coverage, left/right and top/bottom balance, and dead zones. Stdlib only.",
  "inputSchema":{"type":"object","properties":{"path":{"type":"string"},"grid":{"type":"integer","default":12}},"required":["path"]}},
 {"name":"compare","description":"Diff a target design against your render: ink delta, balance drift, palette present in one but not the other, and the 8 worst-diverging grid cells. Returns close|diverged.",
  "inputSchema":{"type":"object","properties":{"target":{"type":"string"},"mine":{"type":"string"},"grid":{"type":"integer","default":12}},"required":["target","mine"]}},
 {"name":"iterate","description":"One full loop: capture a URL, compare it to a target image, and return the specific corrections implied by the diff. Repeat until verdict is close.",
  "inputSchema":{"type":"object","properties":{"url":{"type":"string"},"target":{"type":"string"},
   "width":{"type":"integer","default":1440},"height":{"type":"integer","default":1000}},"required":["url","target"]}},
]

def advise(cmp_):
    """Turn a numeric diff into instructions a builder can act on."""
    out = []
    if cmp_["ink_delta"] > 8:
        out.append("Target carries more ink — add density: more elements, tighter spacing, or raise contrast.")
    elif cmp_["ink_delta"] < -8:
        out.append("Your render is busier than the target — remove elements or drop opacity; the reference breathes more.")
    lr = cmp_["balance_delta"]["left_right"]
    if abs(lr) > 0.22:
        out.append(("Target is weighted left" if lr > 0 else "Target is weighted right") +
                   " — move the focal mass horizontally.")
    tb = cmp_["balance_delta"]["top_bottom"]
    if abs(tb) > 0.22:
        out.append(("Target is top-heavy" if tb > 0 else "Target is bottom-heavy") +
                   " — shift vertical emphasis.")
    if cmp_["palette_only_in_target"]:
        out.append("Colours in the target you are missing: " + ", ".join(cmp_["palette_only_in_target"][:5]))
    hot = [c for c in cmp_["worst_cells"] if abs(c["delta"]) > 22]
    if hot:
        out.append("Largest divergence at grid cells " +
                   ", ".join(f"(r{c['row']},c{c['col']} {'too dark' if c['delta']>0 else 'too bright'})" for c in hot[:4]))
    return out or ["Within tolerance — no structural correction implied."]

def call(name, a):
    if name == "capture":
        return capture(a["url"], a.get("width",1440), a.get("height",1000),
                       None, a.get("full_page",False), a.get("wait_ms",9000), a.get("scheme"))
    if name == "analyse":
        return json.dumps(analyse(a["path"], a.get("grid",12)), indent=2)
    if name == "compare":
        return json.dumps(compare(a["target"], a["mine"], a.get("grid",12)), indent=2)
    if name == "iterate":
        shot = capture(a["url"], a.get("width",1440), a.get("height",1000))
        c = compare(a["target"], shot)
        return json.dumps({"shot": shot, "diff": c, "do_next": advise(c)}, indent=2)
    raise ValueError("unknown tool: " + name)

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: req = json.loads(line)
        except Exception: continue
        mid, method = req.get("id"), req.get("method")
        try:
            if method == "initialize":
                res = {"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":SERVER}
            elif method == "tools/list":
                res = {"tools": TOOLS}
            elif method == "tools/call":
                p = req.get("params", {})
                res = {"content":[{"type":"text","text": call(p.get("name"), p.get("arguments", {}))}]}
            elif method and method.startswith("notifications/"):
                continue
            else:
                res = {}
            if mid is not None:
                sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,"result":res})+"\n"); sys.stdout.flush()
        except Exception as e:
            if mid is not None:
                sys.stdout.write(json.dumps({"jsonrpc":"2.0","id":mid,
                    "error":{"code":-32000,"message":str(e)}})+"\n"); sys.stdout.flush()

if __name__ == "__main__":
    main()
