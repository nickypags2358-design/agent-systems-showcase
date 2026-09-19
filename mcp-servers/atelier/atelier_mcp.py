#!/usr/bin/env python3
"""
ATELIER MCP — deterministic visual synthesis for the web.

Why this exists, and why it is not another image-generation wrapper:

  Every image MCP surveyed (OpenAI gpt-image-1, Gemini imagen4, Replicate,
  Together/Flux) is an API wrapper. Each render costs money and returns a
  flat raster you cannot edit. For a landing page that is the wrong trade.

  Atelier emits CODE, not pixels: SVG scenes, WebGL shaders, and CSS layers
  that render live in the browser. Zero API calls. Zero per-image cost.
  Resolution-independent on Retina. Tweakable by changing one number.

Design constraints this was built against:
  - stdlib-only Python (no third-party imports) so it runs anywhere python3 runs
  - wide-gamut displays (Display P3) supported with an sRGB fallback
  - MCP clients cap tool responses at roughly 1MB -> large output goes to disk,
    the tool returns a path (the pattern every surveyed server converged on)

Transport: stdio JSON-RPC 2.0, the MCP baseline.
"""

import sys, json, math, os, re, hashlib, colorsys

SERVER = {"name": "atelier", "version": "1.0.0"}
# Output directory: override with ATELIER_OUT_DIR, else write under the current
# working directory so the server has no dependency on any specific machine layout.
OUT_DIR = os.environ.get("ATELIER_OUT_DIR", os.path.join(os.getcwd(), "atelier-out"))

# ─────────────────────────────────────────────────────────────────────────────
# COLOR — Display P3 aware.
# sRGB covers ~35% of visible color. Display P3 covers ~45%, and many modern
# displays support it. Emitting color(display-p3 ...) with an sRGB fallback means
# saturated accents render richer on P3-capable hardware and degrade safely elsewhere.
# ─────────────────────────────────────────────────────────────────────────────

def srgb_to_p3(r, g, b):
    """sRGB 0-255 -> approximate Display P3 0-1 triple."""
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    R, G, B = lin(r), lin(g), lin(b)
    # sRGB -> XYZ -> P3 collapsed into one matrix
    m = [[0.8225, 0.1774, 0.0000],
         [0.0332, 0.9669, 0.0000],
         [0.0171, 0.0724, 0.9108]]
    o = [m[i][0]*R + m[i][1]*G + m[i][2]*B for i in range(3)]
    def unlin(c):
        c = max(0.0, min(1.0, c))
        return 12.92*c if c <= 0.0031308 else 1.055*(c ** (1/2.4)) - 0.055
    return tuple(round(unlin(c), 4) for c in o)

def css_color(hexstr, alpha=1.0):
    """Emit a P3 color with an sRGB fallback line."""
    h = hexstr.lstrip('#')
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    p = srgb_to_p3(r, g, b)
    srgb = f"rgba({r},{g},{b},{alpha})"
    p3 = f"color(display-p3 {p[0]} {p[1]} {p[2]} / {alpha})"
    return srgb, p3

def ramp(hexstr, stops=5, spread=0.34):
    """Perceptual ramp around a hue — for gradients that don't go muddy."""
    h = hexstr.lstrip('#')
    r, g, b = [int(h[i:i+2], 16)/255 for i in (0, 2, 4)]
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    out = []
    for i in range(stops):
        t = i/(stops-1) if stops > 1 else 0.5
        l2 = max(0.04, min(0.96, ll + (t-0.5)*spread))
        s2 = max(0.0, min(1.0, ss * (1.0 - abs(t-0.5)*0.35)))
        rr, gg, bb = colorsys.hls_to_rgb((hh + (t-0.5)*0.045) % 1.0, l2, s2)
        out.append('#%02X%02X%02X' % (int(rr*255), int(gg*255), int(bb*255)))
    return out

def slug(s, n=64):
    """Filename-safe form of a user-supplied string (letters, digits, _ and - only)."""
    return re.sub(r'[^A-Za-z0-9_-]+', '-', str(s))[:n] or "x"

def _seed(s):
    return int(hashlib.sha256(s.encode()).hexdigest()[:8], 16)

def _rng(state):
    """Deterministic LCG — same spec always yields the same scene."""
    while True:
        state = (1103515245*state + 12345) & 0x7FFFFFFF
        yield state / 0x7FFFFFFF

# ─────────────────────────────────────────────────────────────────────────────
# SCENE 1 — CORE ORB
# The glowing sphere with orbital rings and a particle shell. This is the
# single most recognizable element in premium AI landing pages.
# ─────────────────────────────────────────────────────────────────────────────

def scene_orb(size=760, hue="#7C5CFF", accent="#31E5FF", particles=260,
              rings=3, seed="orb"):
    R = size/2
    rnd = _rng(_seed(seed))
    cols = ramp(hue, 5)
    p = []

    p.append(f'<svg viewBox="0 0 {size} {size}" width="{size}" height="{size}" '
             f'xmlns="http://www.w3.org/2000/svg" class="atl-orb">')
    p.append('<defs>')
    p.append(f'''<radialGradient id="core" cx="42%" cy="38%" r="68%">
      <stop offset="0%"  stop-color="{cols[4]}" stop-opacity=".95"/>
      <stop offset="38%" stop-color="{cols[3]}" stop-opacity=".72"/>
      <stop offset="72%" stop-color="{cols[1]}" stop-opacity=".38"/>
      <stop offset="100%" stop-color="{cols[0]}" stop-opacity="0"/>
    </radialGradient>''')
    p.append(f'''<radialGradient id="rim" cx="50%" cy="50%" r="50%">
      <stop offset="72%" stop-color="{accent}" stop-opacity="0"/>
      <stop offset="92%" stop-color="{accent}" stop-opacity=".55"/>
      <stop offset="100%" stop-color="{accent}" stop-opacity="0"/>
    </radialGradient>''')
    p.append('<filter id="bloom" x="-60%" y="-60%" width="220%" height="220%">'
             '<feGaussianBlur stdDeviation="16" result="b"/>'
             '<feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
    p.append('<filter id="soft" x="-40%" y="-40%" width="180%" height="180%">'
             '<feGaussianBlur stdDeviation="3.2"/></filter>')
    p.append('</defs>')

    # atmospheric wash
    p.append(f'<circle cx="{R}" cy="{R}" r="{R*0.97}" fill="url(#core)" filter="url(#bloom)" opacity=".85"/>')

    # latitude/longitude wireframe — reads as a sphere without any 3D engine
    for i in range(1, 9):
        t = i/9
        ry = R*0.82*math.sin(math.pi*t)
        cy = R - R*0.82*math.cos(math.pi*t)
        p.append(f'<ellipse cx="{R}" cy="{cy:.1f}" rx="{R*0.82:.1f}" ry="{ry*0.30:.1f}" '
                 f'fill="none" stroke="{accent}" stroke-width=".7" opacity="{0.05+0.13*math.sin(math.pi*t):.3f}"/>')
    for i in range(12):
        a = math.pi*i/12
        p.append(f'<ellipse cx="{R}" cy="{R}" rx="{abs(R*0.82*math.cos(a)):.1f}" ry="{R*0.82:.1f}" '
                 f'fill="none" stroke="{cols[3]}" stroke-width=".6" opacity=".10"/>')

    p.append(f'<circle cx="{R}" cy="{R}" r="{R*0.82}" fill="url(#rim)"/>')

    # orbital rings, tilted
    for k in range(rings):
        tilt = 16 + k*26
        rr = R*(0.90 + k*0.10)
        p.append(f'<g transform="rotate({tilt} {R} {R})">'
                 f'<ellipse cx="{R}" cy="{R}" rx="{rr:.1f}" ry="{rr*0.30:.1f}" fill="none" '
                 f'stroke="{accent}" stroke-width="1" opacity=".30" '
                 f'stroke-dasharray="2 9" class="atl-ring atl-ring-{k}"/></g>')

    # particle shell — density falls off toward the limb, like a real render
    for _ in range(particles):
        a = next(rnd)*math.tau
        rad = R*(0.86 + next(rnd)*0.34)
        x = R + math.cos(a)*rad
        y = R + math.sin(a)*rad*0.62
        sz = 0.5 + next(rnd)*1.7
        op = 0.14 + next(rnd)*0.55
        c = cols[int(next(rnd)*len(cols))]
        p.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{sz:.2f}" fill="{c}" opacity="{op:.2f}"/>')

    p.append(f'<circle cx="{R*0.86:.0f}" cy="{R*0.74:.0f}" r="{R*0.16:.0f}" fill="#FFFFFF" opacity=".13" filter="url(#soft)"/>')
    p.append('</svg>')

    css = """
.atl-orb{display:block;max-width:100%;height:auto}
.atl-ring{transform-box:fill-box;transform-origin:center;animation:atlSpin var(--d,26s) linear infinite}
.atl-ring-1{animation-duration:38s;animation-direction:reverse}
.atl-ring-2{animation-duration:52s}
@keyframes atlSpin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion:reduce){.atl-ring{animation:none}}
"""
    return "\n".join(p), css

# ─────────────────────────────────────────────────────────────────────────────
# SCENE 2 — NEBULA SHADER
# WebGL fragment shader: domain-warped fbm. A moving cosmic field. GPU-rendered,
# roughly 2KB of code, no asset.
# ─────────────────────────────────────────────────────────────────────────────

def scene_nebula(hue="#7C5CFF", accent="#31E5FF", speed=0.05):
    def h2v(hx):
        hx = hx.lstrip('#')
        return ", ".join(f"{int(hx[i:i+2],16)/255:.3f}" for i in (0, 2, 4))
    # Construction follows the widely published GLSL hash/value-noise/fbm pattern
    # popularised by Inigo Quilez (iquilezles.org articles); reimplemented here in Python.
    return f"""precision highp float;
uniform vec2  u_res;
uniform float u_time;
uniform vec2  u_mouse;

// value noise + fbm + domain warp  (Quilez-style)
float hash(vec2 p){{ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }}
float noise(vec2 p){{
  vec2 i=floor(p), f=fract(p);
  vec2 u=f*f*(3.0-2.0*f);
  return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),
             mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}}
float fbm(vec2 p){{
  float v=0.0, a=0.5;
  for(int i=0;i<6;i++){{ v+=a*noise(p); p*=2.02; a*=0.5; }}
  return v;
}}
void main(){{
  vec2 uv=(gl_FragCoord.xy-0.5*u_res)/u_res.y;
  float t=u_time*{speed};
  vec2 q=vec2(fbm(uv+t), fbm(uv+vec2(5.2,1.3)-t));
  vec2 r=vec2(fbm(uv+4.0*q+vec2(1.7,9.2)+0.15*t),
              fbm(uv+4.0*q+vec2(8.3,2.8)-0.12*t));
  float f=fbm(uv+4.0*r);

  vec3 deep=vec3(0.012,0.035,0.070);
  vec3 base=vec3({h2v(hue)});
  vec3 acc =vec3({h2v(accent)});

  vec3 col=mix(deep, base, clamp(f*f*1.9,0.0,1.0));
  col=mix(col, acc, clamp(length(r)*0.62,0.0,1.0));
  col+=acc*pow(clamp(1.0-length(uv)*0.85,0.0,1.0),3.0)*0.30;   // core bloom

  vec2 m=(u_mouse-0.5)*2.0;                                      // cursor lift
  col+=base*0.10*pow(clamp(1.0-length(uv-m*0.35),0.0,1.0),4.0);

  col=pow(col, vec3(0.4545));                                    // to sRGB
  gl_FragColor=vec4(col, 0.92);
}}"""

# ─────────────────────────────────────────────────────────────────────────────
# SCENE 3 — GLASS PANEL  (floating HUD cards)
# ─────────────────────────────────────────────────────────────────────────────

def scene_glass(accent="#31E5FF"):
    s_a, p_a = css_color(accent, .5)
    return f"""
.atl-glass{{
  position:relative; border-radius:14px; padding:16px 18px;
  background:linear-gradient(148deg, rgba(255,255,255,.075), rgba(255,255,255,.018));
  border:1px solid rgba(255,255,255,.10);
  box-shadow:0 22px 60px -26px rgba(0,0,0,.85), inset 0 1px 0 rgba(255,255,255,.13);
  backdrop-filter:blur(16px) saturate(150%);
  -webkit-backdrop-filter:blur(16px) saturate(150%);
  isolation:isolate;
}}
.atl-glass::before{{                      /* specular sweep along the top edge */
  content:""; position:absolute; inset:0; border-radius:inherit; padding:1px;
  background:linear-gradient(120deg, {s_a}, transparent 42%, transparent 62%, {s_a});
  background:linear-gradient(120deg, {p_a}, transparent 42%, transparent 62%, {p_a});
  -webkit-mask:linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0);
  -webkit-mask-composite:xor; mask-composite:exclude; opacity:.55; pointer-events:none;
}}
.atl-glass::after{{                       /* faint inner grid, the HUD tell */
  content:""; position:absolute; inset:0; border-radius:inherit; pointer-events:none;
  background-image:linear-gradient(rgba(255,255,255,.028) 1px,transparent 1px),
                   linear-gradient(90deg,rgba(255,255,255,.028) 1px,transparent 1px);
  background-size:22px 22px; opacity:.55; z-index:-1;
}}
@supports not (backdrop-filter:blur(2px)){{ .atl-glass{{ background:rgba(10,18,32,.92) }} }}
"""

# ─────────────────────────────────────────────────────────────────────────────
# MCP plumbing
# ─────────────────────────────────────────────────────────────────────────────

TOOLS = [
    {"name": "render_orb",
     "description": "Emit an SVG core-orb scene: volumetric sphere, lat/long wireframe, tilted orbital rings, particle shell. Returns live SVG + CSS. No API cost.",
     "inputSchema": {"type": "object", "properties": {
         "size": {"type": "integer", "default": 760},
         "hue": {"type": "string", "default": "#7C5CFF"},
         "accent": {"type": "string", "default": "#31E5FF"},
         "particles": {"type": "integer", "default": 260},
         "rings": {"type": "integer", "default": 3},
         "seed": {"type": "string", "default": "orb"},
         "write": {"type": "boolean", "default": False}}}},
    {"name": "render_nebula",
     "description": "Emit a GLSL fragment shader for a domain-warped fbm nebula field with cursor lift. GPU rendered, ~2KB, no asset.",
     "inputSchema": {"type": "object", "properties": {
         "hue": {"type": "string", "default": "#7C5CFF"},
         "accent": {"type": "string", "default": "#31E5FF"},
         "speed": {"type": "number", "default": 0.05}}}},
    {"name": "render_glass",
     "description": "Emit CSS for glassmorphic HUD panels: specular edge sweep, inner grid, backdrop blur, with a no-backdrop-filter fallback.",
     "inputSchema": {"type": "object", "properties": {
         "accent": {"type": "string", "default": "#31E5FF"}}}},
    {"name": "p3_palette",
     "description": "Convert a hex color into a Display P3 CSS value with sRGB fallback, plus a perceptual ramp.",
     "inputSchema": {"type": "object", "properties": {
         "hex": {"type": "string"}, "stops": {"type": "integer", "default": 5}},
         "required": ["hex"]}},
]

def call(name, a):
    if name == "render_orb":
        svg, css = scene_orb(a.get("size", 760), a.get("hue", "#7C5CFF"),
                             a.get("accent", "#31E5FF"), a.get("particles", 260),
                             a.get("rings", 3), a.get("seed", "orb"))
        if a.get("write"):
            os.makedirs(OUT_DIR, exist_ok=True)
            fp = os.path.join(OUT_DIR, f"orb-{slug(a.get('seed','orb'))}.svg")
            open(fp, "w").write(svg)
            return f"wrote {fp} ({len(svg)} bytes)\n\n/* CSS */\n{css}"
        return svg + "\n\n<style>" + css + "</style>"
    if name == "render_nebula":
        return scene_nebula(a.get("hue", "#7C5CFF"), a.get("accent", "#31E5FF"), a.get("speed", 0.05))
    if name == "render_glass":
        return scene_glass(a.get("accent", "#31E5FF"))
    if name == "p3_palette":
        s, p = css_color(a["hex"], 1.0)
        return json.dumps({"srgb": s, "display_p3": p,
                           "ramp": ramp(a["hex"], a.get("stops", 5))}, indent=2)
    raise ValueError(f"unknown tool: {name}")

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except Exception:
            continue
        mid, method = req.get("id"), req.get("method")
        try:
            if method == "initialize":
                res = {"protocolVersion": "2024-11-05",
                       "capabilities": {"tools": {}}, "serverInfo": SERVER}
            elif method == "tools/list":
                res = {"tools": TOOLS}
            elif method == "tools/call":
                p = req.get("params", {})
                out = call(p.get("name"), p.get("arguments", {}))
                res = {"content": [{"type": "text", "text": out}]}
            elif method and method.startswith("notifications/"):
                continue
            else:
                res = {}
            if mid is not None:
                sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": res}) + "\n")
                sys.stdout.flush()
        except Exception as e:
            if mid is not None:
                sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid,
                    "error": {"code": -32000, "message": str(e)}}) + "\n")
                sys.stdout.flush()

if __name__ == "__main__":
    main()
