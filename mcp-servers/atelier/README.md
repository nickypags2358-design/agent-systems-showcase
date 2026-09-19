# Atelier MCP — deterministic visual synthesis

Three small MCP (Model Context Protocol) servers that emit **code**, not pixels:
SVG scenes, WebGL shaders, and CSS — plus a closed visual-verification loop.
Zero API calls, zero per-image cost, stdlib Python only.

## Why not an image-generation MCP

Every image MCP wraps a paid API and returns a flat raster you cannot edit. For
a landing page that is the wrong trade: no API cost, resolution-independent
output, and a one-line-diff between two renders instead of two unrelated PNGs.

## Servers

| server | does |
|---|---|
| `atelier_mcp.py` | `render_orb`, `render_nebula`, `render_glass`, `p3_palette` — generate SVG/GLSL/CSS |
| `forge_mcp.py` | `export_widget`, `export_svg`, `render_png`, `bundle_exports`, `list_exports` — write standalone, dependency-free files you own |
| `vision_mcp.py` | `capture`, `analyse`, `compare`, `iterate` — screenshot, read structure, diff against a target, suggest corrections |

Toolchain: **atelier** generates the visual → **vision** looks at the result and
diffs it against a target → **forge** exports it as a file you can keep or ship.

## Requirements

Stdlib-only — see `requirements.txt` (intentionally empty). `forge_mcp.py` and
`vision_mcp.py` shell out to a local headless Chrome for PNG rendering/capture;
if Chrome isn't found at the default path, set `CHROME_BIN`. Everything else
(SVG, GLSL, CSS generation, palette math, PNG analysis) is pure Python stdlib.

## Network and file access

`vision_mcp.py` `capture` and `forge_mcp.py` `render_png` hand the URL or file path
you supply straight to a locally installed headless Chrome. That process can reach the
network and read any local file the user points it at, so treat those two tools as
having the same reach as opening the same URL/file in your own browser. The "zero API
calls" claim above refers to paid image-generation APIs only, not to network access in
general.

## Configuration (env overrides, all optional)

| var | default | used by |
|---|---|---|
| `ATELIER_OUT_DIR` | `./atelier-out` | atelier_mcp.py |
| `FORGE_OUT_DIR` | `./atelier-out/widgets` | forge_mcp.py |
| `VISION_SHOTS_DIR` | `./atelier-out/shots` | vision_mcp.py |
| `CHROME_BIN` | macOS default Chrome path | forge_mcp.py, vision_mcp.py |

## Register with an MCP client

See `client-config.example.json`. Point `args` at the absolute path to each
`.py` file on your machine.

## Verify

```bash
python3 -m py_compile atelier_mcp.py forge_mcp.py vision_mcp.py
```

Each server speaks stdio JSON-RPC 2.0 (the MCP baseline): `initialize`,
`tools/list`, `tools/call`.
