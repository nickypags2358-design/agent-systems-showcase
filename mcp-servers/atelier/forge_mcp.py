#!/usr/bin/env python3
"""
FORGE MCP — export interactive work as files you own.

The gap it closes:
  Widgets rendered in a chat live in the chat. Canvas panels can be right-clicked
  to a PNG, but a PNG is dead — the interaction is gone. This writes standalone
  .html files that keep working offline, forever, with no dependencies and no
  build step. Open it in any browser in five years and it still runs.

Completes the toolchain:
  atelier  — generate the visual (SVG / shader / CSS)
  vision   — look at the result and diff it against a target
  forge    — export it as something you can keep, send, or sell

Design constraints:
  no build tooling required — stdlib Python only
  uses a local headless Chrome for PNG rendering, if one is available
"""

import sys, json, os, re, subprocess, zipfile, datetime

SERVER = {"name": "forge", "version": "1.0.0"}
# Output directory: override with FORGE_OUT_DIR, else write under the current
# working directory. Kept separate from atelier's default so the two servers
# never collide when run side by side.
OUT = os.environ.get("FORGE_OUT_DIR", os.path.join(os.getcwd(), "atelier-out", "widgets"))
# Headless Chrome binary used for PNG rendering. Override with CHROME_BIN if the
# default macOS install path does not match your machine.
CHROME = os.environ.get("CHROME_BIN", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

# Default design tokens, inlined so an exported file never depends on a stylesheet.
TOKENS = """:root{--bg-0:#030912;--bg-1:#050F1F;--panel:#07172B;--panel-2:#0C2038;
--line:#0F2440;--rule:#17335C;--fg:#EAF2F8;--fg-2:#93A5C1;--fg-3:#5C6E8C;
--accent:#D9A441;--accent-lit:#FFD166;--info:#5B8CFF;--success:#46C08C;
--muted:#7C879E;--danger:#F0655C;
--surface-0:#030912;--surface-1:#07172B;--surface-2:#0C2038;
--text-primary:#EAF2F8;--text-secondary:#93A5C1;--text-muted:#5C6E8C;
--text-accent:#D9A441;--text-success:#46C08C;--text-danger:#F0655C;--text-warning:#D9A441;
--bg-accent:rgba(217,164,65,.10);--bg-success:rgba(70,192,140,.10);
--bg-danger:rgba(240,101,92,.10);--bg-warning:rgba(217,164,65,.10);
--border:#0F2440;--border-strong:#17335C;--border-stronger:#24507F;
--border-accent:#D9A441;--border-success:#46C08C;--border-danger:#F0655C;--border-warning:#D9A441;
--gap-xs:4px;--gap-sm:8px;--gap-md:16px;--gap-lg:24px;--gap-xl:32px;
--font-sans:"Helvetica Neue",Helvetica,Arial,sans-serif;
--font-mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
--font-voice:"Iowan Old Style",Palatino,Georgia,serif;
color-scheme:dark}
*,*::before,*::after{box-sizing:border-box}
body{margin:0;background:var(--bg-0);color:var(--fg);
font:16px/1.6 var(--font-sans);-webkit-font-smoothing:antialiased;
padding:clamp(16px,4vw,40px)}
.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;
clip:rect(0,0,0,0);white-space:nowrap;border:0}
h1,h2,h3{font-weight:500;letter-spacing:-.02em}
button{font-family:inherit}"""

SHELL = """<!DOCTYPE html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<meta name="description" content="{desc}">
<meta name="generator" content="Forge MCP — standalone interactive export">
<style>{tokens}
{extra}</style>
<!-- Exported {stamp}. Self-contained: no network, no dependencies, no build step.
     Open this file in any browser and it runs. -->
{body}
</html>
"""

def slug(s):
    s = re.sub(r"[^a-zA-Z0-9]+", "-", (s or "widget").strip().lower()).strip("-")
    return s or "widget"

OUT_REAL = os.path.realpath(OUT)

def safe_out_path(*parts):
    """Resolve OUT/<parts...> and refuse any result that escapes OUT (path traversal,
    absolute paths, symlink hops). Raises ValueError before anything is written."""
    target = os.path.realpath(os.path.join(OUT, *[str(p) for p in parts if p]))
    if os.path.commonpath([OUT_REAL, target]) != OUT_REAL:
        raise ValueError("path escapes the output directory: " + "/".join(str(p) for p in parts if p))
    return target

def export(code, title="Widget", desc="", extra_css="", subdir=None):
    d = safe_out_path(subdir) if subdir else OUT_REAL
    os.makedirs(d, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    html = SHELL.format(title=title, desc=(desc or title).replace('"', "'"),
                        tokens=TOKENS, extra=extra_css, stamp=stamp, body=code)
    fp = os.path.join(d, slug(title) + ".html")
    open(fp, "w", encoding="utf-8").write(html)
    return fp, len(html)

def to_png(path_or_url, out=None, w=1400, h=900, wait=9000):
    if not os.path.exists(CHROME):
        raise RuntimeError("Chrome not found (set CHROME_BIN to override the default path)")
    url = path_or_url if "://" in path_or_url else "file://" + os.path.abspath(path_or_url)
    if not out:
        base = os.path.splitext(os.path.basename(path_or_url))[0] or "render"
        os.makedirs(OUT, exist_ok=True)
        out = safe_out_path(base + ".png")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    f"--virtual-time-budget={wait}", f"--window-size={w},{h}",
                    f"--screenshot={out}", url], capture_output=True, timeout=90)
    if not os.path.exists(out):
        raise RuntimeError("render produced no file")
    return out

def bundle(name="widgets"):
    os.makedirs(OUT, exist_ok=True)
    zp = os.path.join(OUT, slug(name) + ".zip")
    n = 0
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(OUT):
            for f in files:
                if f.endswith((".html", ".svg", ".png")):
                    full = os.path.join(root, f)
                    z.write(full, os.path.relpath(full, OUT)); n += 1
    return zp, n

def listing():
    if not os.path.isdir(OUT): return []
    out = []
    for root, _, files in os.walk(OUT):
        for f in sorted(files):
            full = os.path.join(root, f)
            out.append({"file": os.path.relpath(full, OUT),
                        "bytes": os.path.getsize(full),
                        "path": full})
    return out

TOOLS = [
 {"name":"export_widget",
  "description":"Write HTML/CSS/JS as a STANDALONE interactive .html file that keeps working offline forever — default design tokens inlined, zero dependencies, zero build step. Returns the saved path.",
  "inputSchema":{"type":"object","properties":{
    "code":{"type":"string","description":"The widget body: markup plus any <style>/<script>."},
    "title":{"type":"string","default":"Widget"},
    "description":{"type":"string","default":""},
    "extra_css":{"type":"string","default":""},
    "subdir":{"type":"string"}},"required":["code"]}},
 {"name":"export_svg",
  "description":"Write raw SVG markup to a .svg file — resolution-independent, editable in any vector tool.",
  "inputSchema":{"type":"object","properties":{
    "svg":{"type":"string"},"title":{"type":"string","default":"figure"}},"required":["svg"]}},
 {"name":"render_png",
  "description":"Render any local .html or URL to a PNG via headless Chrome, at any size. Use for stills of an interactive piece.",
  "inputSchema":{"type":"object","properties":{
    "source":{"type":"string"},"width":{"type":"integer","default":1400},
    "height":{"type":"integer","default":900},"wait_ms":{"type":"integer","default":9000}},
    "required":["source"]}},
 {"name":"bundle_exports",
  "description":"Zip every exported .html/.svg/.png into one archive for sending or archiving.",
  "inputSchema":{"type":"object","properties":{"name":{"type":"string","default":"widgets"}}}},
 {"name":"list_exports",
  "description":"List everything exported so far, with sizes and absolute paths.",
  "inputSchema":{"type":"object","properties":{}}},
]

def call(name, a):
    if name == "export_widget":
        fp, n = export(a["code"], a.get("title","Widget"), a.get("description",""),
                       a.get("extra_css",""), a.get("subdir"))
        return f"{fp}\n{n} bytes · standalone · opens offline in any browser"
    if name == "export_svg":
        os.makedirs(OUT, exist_ok=True)
        fp = os.path.join(OUT, slug(a.get("title","figure")) + ".svg")
        open(fp, "w", encoding="utf-8").write(a["svg"])
        return f"{fp}\n{len(a['svg'])} bytes · vector · resolution-independent"
    if name == "render_png":
        return to_png(a["source"], None, a.get("width",1400), a.get("height",900), a.get("wait_ms",9000))
    if name == "bundle_exports":
        zp, n = bundle(a.get("name","widgets"))
        return f"{zp}\n{n} file(s) archived"
    if name == "list_exports":
        return json.dumps(listing(), indent=2)
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
