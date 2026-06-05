"""Generate a 1024x1024 cartoon fish app icon as PNG using only stdlib."""
import zlib, struct, math, os

SIZE = 1024

def rgba(r, g, b, a=255):
    return (r, g, b, a)

BG       = rgba(30,  144, 255)   # dodger blue background
BODY     = rgba(255, 200,  50)   # golden yellow fish body
EYE_W    = rgba(255, 255, 255)   # white eye
EYE_P    = rgba( 30,  30,  30)   # dark pupil
TAIL     = rgba(255, 160,  20)   # slightly darker tail
MOUTH    = rgba(200,  80,  40)   # reddish mouth
GILL     = rgba(220, 150,  30)   # gill line
FIN      = rgba(255, 180,  30)   # dorsal/pectoral fin

def make_canvas(size, fill):
    return [[list(fill) for _ in range(size)] for _ in range(size)]

def draw_ellipse(canvas, cx, cy, rx, ry, color, aa=False):
    x0, x1 = max(0, int(cx-rx-1)), min(SIZE-1, int(cx+rx+1))
    y0, y1 = max(0, int(cy-ry-1)), min(SIZE-1, int(cy+ry+1))
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            dx = (x-cx)/rx
            dy = (y-cy)/ry
            d = dx*dx + dy*dy
            if d <= 1.0:
                canvas[y][x] = list(color)

def draw_poly(canvas, pts, color):
    """Scanline fill for convex polygon."""
    if len(pts) < 3:
        return
    min_y = max(0, int(min(p[1] for p in pts)))
    max_y = min(SIZE-1, int(max(p[1] for p in pts)))
    for y in range(min_y, max_y+1):
        xs = []
        n = len(pts)
        for i in range(n):
            x0,y0 = pts[i]
            x1,y1 = pts[(i+1)%n]
            if (y0 <= y < y1) or (y1 <= y < y0):
                if y1 != y0:
                    xs.append(x0 + (y-y0)*(x1-x0)/(y1-y0))
        xs.sort()
        for k in range(0, len(xs)-1, 2):
            for x in range(max(0,int(xs[k])), min(SIZE-1,int(xs[k+1]))+1):
                canvas[y][x] = list(color)

def draw_arc(canvas, cx, cy, r, t0, t1, thick, color):
    steps = int(abs(t1-t0) * r / 2) + 60
    for i in range(steps+1):
        t = t0 + (t1-t0)*i/steps
        for dr in range(-thick//2, thick//2+1):
            rx = int(cx + (r+dr)*math.cos(t))
            ry = int(cy + (r+dr)*math.sin(t))
            if 0 <= rx < SIZE and 0 <= ry < SIZE:
                canvas[ry][rx] = list(color)

def draw_rounded_rect(canvas, x0, y0, x1, y1, radius, color):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            canvas[y][x] = list(color)
    draw_ellipse(canvas, x0+radius, y0+radius, radius, radius, color)
    draw_ellipse(canvas, x1-radius, y0+radius, radius, radius, color)
    draw_ellipse(canvas, x0+radius, y1-radius, radius, radius, color)
    draw_ellipse(canvas, x1-radius, y1-radius, radius, radius, color)

cx, cy = SIZE//2, SIZE//2

canvas = make_canvas(SIZE, BG)

# ── Background: rounded square fill (already BG) ──────────────────────────────
# Add a subtle gradient-like vignette: darker corners
for y in range(SIZE):
    for x in range(SIZE):
        dx = (x - cx) / (SIZE/2)
        dy = (y - cy) / (SIZE/2)
        d  = math.sqrt(dx*dx + dy*dy)
        if d > 0.7:
            f = min(1.0, (d-0.7)/0.5) * 0.35
            c = canvas[y][x]
            canvas[y][x] = [int(c[0]*(1-f)), int(c[1]*(1-f)), int(c[2]*(1-f)), 255]

# ── Tail fin (right side, two lobes) ──────────────────────────────────────────
tail_pts_top = [
    (cx+260, cy),
    (cx+460, cy-200),
    (cx+420, cy-20),
]
tail_pts_bot = [
    (cx+260, cy),
    (cx+420, cy+20),
    (cx+460, cy+200),
]
draw_poly(canvas, tail_pts_top, TAIL)
draw_poly(canvas, tail_pts_bot, TAIL)

# ── Body (large horizontal ellipse, slightly offset left) ─────────────────────
draw_ellipse(canvas, cx-40, cy, 310, 200, BODY)

# ── Dorsal fin (top) ──────────────────────────────────────────────────────────
dorsal = [
    (cx-100, cy-195),
    (cx-180, cy-340),
    (cx-20,  cy-310),
    (cx+80,  cy-195),
]
draw_poly(canvas, dorsal, FIN)

# ── Pectoral fin (bottom) ─────────────────────────────────────────────────────
pectoral = [
    (cx-60,  cy+180),
    (cx-140, cy+310),
    (cx+20,  cy+290),
    (cx+80,  cy+180),
]
draw_poly(canvas, pectoral, FIN)

# ── Gill arc ──────────────────────────────────────────────────────────────────
draw_arc(canvas, cx+60, cy, 160, math.radians(120), math.radians(240), 14, GILL)

# ── Eye ───────────────────────────────────────────────────────────────────────
draw_ellipse(canvas, cx-150, cy-60, 52, 52, EYE_W)
draw_ellipse(canvas, cx-158, cy-60, 28, 28, EYE_P)
# eye shine
draw_ellipse(canvas, cx-168, cy-72, 10, 10, rgba(255,255,255,220))

# ── Mouth (small arc at left tip of body) ─────────────────────────────────────
draw_arc(canvas, cx-330, cy+30, 42, math.radians(-60), math.radians(60), 12, MOUTH)

# ── Scales (small semi-circles pattern) ───────────────────────────────────────
scale_color = rgba(255, 215, 40, 180)
for row in range(4):
    for col in range(6):
        scx = cx - 80 + col*70 - (row%2)*35
        scy = cy - 80 + row*70
        # only draw if inside body ellipse
        if ((scx-(cx-40))/310)**2 + ((scy-cy)/200)**2 < 0.75:
            draw_arc(canvas, scx, scy, 28,
                     math.radians(200), math.radians(340), 8, scale_color)

# ── Convert canvas to PNG ─────────────────────────────────────────────────────
def u32be(n):
    return struct.pack(">I", n)

def png_chunk(tag, data):
    c = tag + data
    return u32be(len(data)) + c + u32be(zlib.crc32(c) & 0xFFFFFFFF)

raw = bytearray()
for row in canvas:
    raw.append(0)  # filter byte: None
    for px in row:
        raw.extend(px[:3])  # RGB (drop alpha for smaller file; bg is opaque)

compressed = zlib.compress(bytes(raw), 9)

png  = b"\x89PNG\r\n\x1a\n"
png += png_chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
png += png_chunk(b"IDAT", compressed)
png += png_chunk(b"IEND", b"")

out_path = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "PrivacyDiary", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"
)
with open(out_path, "wb") as f:
    f.write(png)

print(f"Icon written: {out_path}  ({len(png):,} bytes)")
