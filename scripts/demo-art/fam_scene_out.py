"""fam_scene_out — drawn "photographs" of places, streets, weather and moments.

Every picture is one SVG built from the motifs below: a tiny perspective
camera (`Cam`) that projects boxes with hipped roofs, so a city has one light
direction and real depth; and flat 2D motifs (sky, sun, ridges, water, trees,
lamps, rain, trams, a bridge, boats, bicycles, silhouettes). One small
composition function per key, each with its own palette, viewpoint, time of
day and weather, so no two pictures in the demo read as the same scene.

No words, no logos, no faces: people are distant silhouettes only.
"""

import functools
import math
import random

# ── colour ────────────────────────────────────────────────────────────────


@functools.lru_cache(maxsize=None)
def hx(c):
    c = c.lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def rgb(v):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(x)))) for x in v)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    A, B = hx(a), hx(b)
    return rgb([A[i] + (B[i] - A[i]) * t for i in range(3)])


def dark(c, k):
    return mix(c, "#000000", k)


def light(c, k):
    return mix(c, "#ffffff", k)


# ── svg primitives ────────────────────────────────────────────────────────


def n(v):
    return ("%.1f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def attrs(kw):
    out = []
    for k, v in kw.items():
        if v is None:
            continue
        k = k.rstrip("_").replace("_", "-")
        out.append(f'{k}="{n(v)}"')
    return " ".join(out)


def rect(x, y, w, h, fill, **kw):
    return f'<rect x="{n(x)}" y="{n(y)}" width="{n(w)}" height="{n(h)}" fill="{fill}" {attrs(kw)}/>'


def pts(p):
    return " ".join(f"{n(float(x))},{n(float(y))}" for x, y in p)


def poly(p, fill, **kw):
    return f'<polygon points="{pts(p)}" fill="{fill}" {attrs(kw)}/>'


def pline(p, stroke, sw=1, **kw):
    return f'<polyline points="{pts(p)}" fill="none" stroke="{stroke}" stroke-width="{n(sw)}" {attrs(kw)}/>'


def path(d, fill, **kw):
    return f'<path d="{d}" fill="{fill}" {attrs(kw)}/>'


def circ(cx, cy, r, fill, **kw):
    return f'<circle cx="{n(cx)}" cy="{n(cy)}" r="{n(r)}" fill="{fill}" {attrs(kw)}/>'


def ell(cx, cy, rx, ry, fill, **kw):
    return f'<ellipse cx="{n(cx)}" cy="{n(cy)}" rx="{n(rx)}" ry="{n(ry)}" fill="{fill}" {attrs(kw)}/>'


def line(x1, y1, x2, y2, stroke, sw=1, **kw):
    return (f'<line x1="{n(x1)}" y1="{n(y1)}" x2="{n(x2)}" y2="{n(y2)}" '
            f'stroke="{stroke}" stroke-width="{n(sw)}" {attrs(kw)}/>')


def g(items, **kw):
    if isinstance(items, str):
        items = [items]
    return f'<g {attrs(kw)}>' + "".join(items) + "</g>"


def smooth(points, closed=False):
    """Catmull-Rom through points → cubic path data."""
    if len(points) < 3:
        return "M" + " L".join(f"{n(float(x))} {n(float(y))}" for x, y in points)
    p = points
    d = f"M{n(float(p[0][0]))} {n(float(p[0][1]))}"
    m = len(p)
    rng_ = range(m) if closed else range(m - 1)
    for i in rng_:
        p0 = p[(i - 1) % m] if (closed or i > 0) else p[i]
        p1 = p[i]
        p2 = p[(i + 1) % m]
        p3 = p[(i + 2) % m] if (closed or i + 2 < m) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += (f" C{n(float(c1[0]))} {n(float(c1[1]))} {n(float(c2[0]))} {n(float(c2[1]))} "
              f"{n(float(p2[0]))} {n(float(p2[1]))}")
    return d + (" Z" if closed else "")


class Svg:
    def __init__(self, w, h, bg="#000"):
        self.w, self.h, self.bg = w, h, bg
        self.defs = []
        self.out = []
        self.k = 0

    def uid(self, p="d"):
        self.k += 1
        return f"{p}{self.k}"

    def __call__(self, *items):
        for it in items:
            if isinstance(it, (list, tuple)):
                self.out.extend(it)
            elif it:
                self.out.append(it)

    @staticmethod
    def _stops(stops):
        s = []
        for i, st in enumerate(stops):
            if isinstance(st, str):
                st = (i / max(1, len(stops) - 1), st)
            off, col = st[0], st[1]
            op = st[2] if len(st) > 2 else 1
            s.append(f'<stop offset="{n(float(off))}" stop-color="{col}" stop-opacity="{n(float(op))}"/>')
        return "".join(s)

    def lin(self, stops, x1=0, y1=0, x2=0, y2=1, user=False):
        i = self.uid("l")
        u = ' gradientUnits="userSpaceOnUse"' if user else ""
        self.defs.append(f'<linearGradient id="{i}" x1="{n(x1)}" y1="{n(y1)}" x2="{n(x2)}" y2="{n(y2)}"{u}>'
                         f"{self._stops(stops)}</linearGradient>")
        return f"url(#{i})"

    def rad(self, stops, cx=0.5, cy=0.5, r=0.5, user=False, fx=None, fy=None, tf=None):
        i = self.uid("r")
        u = ' gradientUnits="userSpaceOnUse"' if user else ""
        fxy = f' fx="{n(fx)}" fy="{n(fy)}"' if fx is not None else ""
        t = f' gradientTransform="{tf}"' if tf else ""
        self.defs.append(f'<radialGradient id="{i}" cx="{n(cx)}" cy="{n(cy)}" r="{n(r)}"{fxy}{u}{t}>'
                         f"{self._stops(stops)}</radialGradient>")
        return f"url(#{i})"

    def blur(self, sx, sy=None):
        i = self.uid("b")
        sd = f"{n(sx)} {n(sy)}" if sy is not None else n(sx)
        self.defs.append(f'<filter id="{i}" x="-50%" y="-50%" width="200%" height="200%">'
                         f'<feGaussianBlur stdDeviation="{sd}"/></filter>')
        return f"url(#{i})"

    def clip(self, inner):
        i = self.uid("c")
        self.defs.append(f'<clipPath id="{i}">{inner}</clipPath>')
        return f"url(#{i})"

    def pattern(self, w, h, inner, tf=None):
        i = self.uid("p")
        t = f' patternTransform="{tf}"' if tf else ""
        self.defs.append(f'<pattern id="{i}" width="{n(w)}" height="{n(h)}" '
                         f'patternUnits="userSpaceOnUse"{t}>{inner}</pattern>')
        return f"url(#{i})"

    def html(self):
        w, h = self.w, self.h
        return ("<!doctype html><html><head><meta charset='utf-8'><style>"
                f"html,body{{margin:0;padding:0;overflow:hidden;width:{w}px;height:{h}px;background:{self.bg}}}"
                "svg{display:block}</style></head><body>"
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                f"<defs>{''.join(self.defs)}</defs>{''.join(self.out)}</svg></body></html>")


# ── 2D motifs ─────────────────────────────────────────────────────────────


def sky(S, stops, y0=0, y1=None):
    y1 = S.h if y1 is None else y1
    return rect(0, y0, S.w, y1 - y0, S.lin(stops, 0, y0, 0, y1, user=True))


def glow(S, cx, cy, r, col, op=1.0, mid=0.35):
    f = S.rad([(0, col, op), (mid, col, op * 0.45), (1, col, 0)])
    return circ(cx, cy, r, f)


def noise1(rng, octaves=4):
    comps = [(rng.uniform(0.6, 1.0) / (k + 1) ** 1.2, rng.uniform(0, 6.3), (k + 1) * rng.uniform(0.8, 1.3))
             for k in range(octaves)]
    tot = sum(c[0] for c in comps)
    return lambda t: sum(a * math.sin(f * t * 6.283 + p) for a, p, f in comps) / tot


def ridge(S, rng, y, amp, fill, freq=1.0, x0=None, x1=None, bottom=None, steps=48, octaves=4, **kw):
    x0 = -4 if x0 is None else x0
    x1 = S.w + 4 if x1 is None else x1
    bottom = S.h + 4 if bottom is None else bottom
    f = noise1(rng, octaves)
    p = [(x0 + (x1 - x0) * i / steps, y + amp * f(freq * i / steps)) for i in range(steps + 1)]
    d = smooth(p) + f" L{n(float(x1))} {n(float(bottom))} L{n(float(x0))} {n(float(bottom))} Z"
    return path(d, fill, **kw)


def blob(cx, cy, r, rng, fill, lobes=9, jitter=0.18, **kw):
    p = []
    for i in range(lobes):
        a = i / lobes * 6.283
        rr = r * (1 + rng.uniform(-jitter, jitter))
        p.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.92))
    return path(smooth(p, closed=True), fill, **kw)


def tree(x, yb, h, rng, leaf, trunk, hi=None, lightx=-1, shadow=None, spread=1.0):
    """A deciduous tree: trunk and limbs, a canopy of lobes shaded away from the light."""
    hi = hi or light(leaf, 0.25)
    lo = dark(leaf, 0.22)
    out = []
    if shadow:
        out.append(ell(x - lightx * h * 0.25, yb, h * 0.35, h * 0.05, shadow))
    tw = h * 0.045
    out.append(poly([(x - tw, yb), (x + tw, yb), (x + tw * 0.6, yb - h * 0.6), (x - tw * 0.6, yb - h * 0.6)], trunk))
    for sgn in (-1, 1):
        out.append(line(x, yb - h * 0.42, x + sgn * h * 0.16, yb - h * 0.7, trunk, tw * 0.9, stroke_linecap="round"))
    cy = yb - h * 0.68
    r = h * 0.3 * spread
    lobes = []
    for i in range(10):
        a = rng.uniform(0, 6.283)
        d = r * math.sqrt(rng.random()) * 0.75
        lobes.append((x + math.cos(a) * d, cy + math.sin(a) * d * 0.7, r * rng.uniform(0.34, 0.52)))
    for lx, ly, lr in lobes:
        out.append(blob(lx, ly + lr * 0.15, lr, rng, lo))
    for lx, ly, lr in lobes:
        out.append(blob(lx - lightx * lr * -0.08, ly - lr * 0.08, lr * 0.86, rng, leaf))
    for lx, ly, lr in sorted(lobes, key=lambda t: -((t[0] - x) * lightx + (cy - t[1])))[:4]:
        out.append(blob(lx + lightx * lr * 0.25, ly - lr * 0.3, lr * 0.45, rng, hi))
    return "".join(out)


def cypress(x, yb, h, fill, hi=None):
    w = h * 0.13
    d = (f"M{n(x)} {n(yb - h)} C{n(x + w)} {n(yb - h * 0.7)} {n(x + w * 1.1)} {n(yb - h * 0.2)} {n(x + w * 0.5)} {n(yb)} "
         f"L{n(x - w * 0.5)} {n(yb)} C{n(x - w * 1.1)} {n(yb - h * 0.2)} {n(x - w)} {n(yb - h * 0.7)} {n(x)} {n(yb - h)} Z")
    out = path(d, fill)
    if hi:
        d2 = (f"M{n(x)} {n(yb - h)} C{n(x - w)} {n(yb - h * 0.7)} {n(x - w * 1.1)} {n(yb - h * 0.2)} {n(x - w * 0.5)} {n(yb)} "
              f"L{n(x - w * 0.1)} {n(yb)} C{n(x - w * 0.4)} {n(yb - h * 0.4)} {n(x - w * 0.3)} {n(yb - h * 0.8)} {n(x)} {n(yb - h)} Z")
        out += path(d2, hi)
    return out


def person(x, yb, h, fill, **kw):
    """A distant standing silhouette, no features."""
    hr = h * 0.085
    sw = h * 0.16
    d = (f"M{n(x - sw * 0.75)} {n(yb)} L{n(x - sw)} {n(yb - h * 0.62)} "
         f"Q{n(x - sw)} {n(yb - h * 0.8)} {n(x)} {n(yb - h * 0.8)} "
         f"Q{n(x + sw)} {n(yb - h * 0.8)} {n(x + sw)} {n(yb - h * 0.62)} L{n(x + sw * 0.75)} {n(yb)} Z")
    return path(d, fill, **kw) + circ(x, yb - h * 0.8 - hr * 1.05, hr, fill, **kw)


def umbrella(x, y, r, fill, stick="#1b1b22", hi=None):
    ribs = 4
    d = f"M{n(x - r)} {n(y)} A{n(r)} {n(r * 0.62)} 0 0 1 {n(x + r)} {n(y)}"
    for i in range(ribs, 0, -1):
        x1 = x - r + (i - 1) * 2 * r / ribs
        d += f" Q{n(x1 + r / ribs)} {n(y - r * 0.12)} {n(x1)} {n(y)}"
    out = path(d + " Z", fill)
    if hi:
        out += path(f"M{n(x - r * 0.9)} {n(y - r * 0.05)} A{n(r * 0.9)} {n(r * 0.55)} 0 0 1 {n(x)} {n(y - r * 0.6)} "
                    f"L{n(x)} {n(y - r * 0.1)} Z", hi, opacity=0.5)
    out += line(x, y - r * 0.62, x, y + r * 0.9, stick, max(1.0, r * 0.06))
    return out


def rain(S, rng, count, angle=0.18, length=(14, 30), col="#dfe8f2", op=0.35, sw=1.1, y1=None):
    out = []
    y1 = S.h if y1 is None else y1
    for _ in range(count):
        x, y = rng.uniform(-40, S.w + 20), rng.uniform(-20, y1)
        L = rng.uniform(*length)
        out.append(line(x, y, x + L * angle, y + L, col, sw, opacity=round(op * rng.uniform(0.5, 1), 2),
                        stroke_linecap="round"))
    return g(out)


def lamp_post(x, yb, h, post, head_col, glow_col, S, glow_r=None, on=True, style="classic"):
    out = [rect(x - h * 0.012, yb - h, h * 0.024, h, post),
           rect(x - h * 0.03, yb - h * 0.04, h * 0.06, h * 0.04, post)]
    hy = yb - h
    if on:
        out.insert(0, glow(S, x, hy - h * 0.04, glow_r or h * 0.35, glow_col, 0.55))
    if style == "classic":
        out.append(poly([(x - h * 0.05, hy - h * 0.12), (x + h * 0.05, hy - h * 0.12), (x + h * 0.035, hy), (x - h * 0.035, hy)],
                        head_col))
        out.append(poly([(x - h * 0.065, hy - h * 0.12), (x + h * 0.065, hy - h * 0.12), (x, hy - h * 0.17)], post))
    else:
        out.append(ell(x, hy - h * 0.05, h * 0.05, h * 0.06, head_col))
    return "".join(out)


def water_glints(rng, x0, x1, y0, y1, col, count, op=0.5, wmax=40, center=None, spread=None):
    out = []
    for _ in range(count):
        y = rng.uniform(y0, y1)
        t = (y - y0) / max(1, y1 - y0)
        if center is not None:
            cx = center + rng.gauss(0, (spread or 30) * (0.4 + t))
        else:
            cx = rng.uniform(x0, x1)
        w = rng.uniform(4, wmax) * (0.35 + t)
        out.append(rect(cx - w / 2, y, w, 1 + t * 2.2, col, opacity=round(op * rng.uniform(0.4, 1), 2), rx=1))
    return "".join(out)


# ── the perspective camera ────────────────────────────────────────────────


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def v_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_norm(a):
    L = math.sqrt(v_dot(a, a)) or 1
    return (a[0] / L, a[1] / L, a[2] / L)


class Cam:
    """Pinhole camera, Y up, +Z forward at yaw 0. pitch > 0 looks down.

    Faces are shaded by one light (`light` points TOWARD the light), between a
    tinted shadow and a tinted lit colour, then fogged toward `fog` by distance —
    that is the atmospheric perspective every city scene shares."""

    def __init__(self, pos, yaw=0.0, pitch=0.0, f=500, cx=0, cy=0, light=(0.5, 0.8, -0.3),
                 shadow="#3a3560", shadow_k=0.55, lit="#fff4e0", lit_k=0.12, fog="#ffffff",
                 fogd=1e9, fogmax=1.0, amb=0.0):
        self.pos = pos
        self.yaw, self.pitch = math.radians(yaw), math.radians(pitch)
        self.f, self.cx, self.cy = f, cx, cy
        self.L = v_norm(light)
        self.shadow, self.shadow_k, self.lit, self.lit_k = shadow, shadow_k, lit, lit_k
        self.fog, self.fogd, self.fogmax, self.amb = fog, fogd, fogmax, amb

    def to_cam(self, p):
        x, y, z = v_sub(p, self.pos)
        cy_, sy_ = math.cos(self.yaw), math.sin(self.yaw)
        x, z = x * cy_ - z * sy_, x * sy_ + z * cy_
        cp, sp = math.cos(self.pitch), math.sin(self.pitch)
        y, z = y * cp + z * sp, -y * sp + z * cp
        return x, y, z

    def p(self, p):
        x, y, z = self.to_cam(p)
        z = max(z, 0.05)
        return (self.cx + self.f * x / z, self.cy - self.f * y / z)

    def depth(self, p):
        return self.to_cam(p)[2]

    def scale(self, p):
        return self.f / max(0.05, self.depth(p))

    def dist(self, p):
        d = v_sub(p, self.pos)
        return math.sqrt(v_dot(d, d))

    def fogged(self, col, p, k=1.0):
        t = (1 - math.exp(-self.dist(p) / self.fogd)) * self.fogmax * k
        return mix(col, self.fog, t)

    def lightcol(self, base, normal, where):
        lam = max(0.0, v_dot(v_norm(normal), self.L))
        lam = self.amb + (1 - self.amb) * lam
        c = mix(mix(base, self.shadow, self.shadow_k), mix(base, self.lit, self.lit_k), lam)
        return self.fogged(c, where)

    def visible(self, pts3, centre):
        a, b, c = pts3[0], pts3[1], pts3[2]
        nrm = v_cross(v_sub(b, a), v_sub(c, a))
        fc = tuple(sum(p[i] for p in pts3) / len(pts3) for i in range(3))
        if v_dot(nrm, v_sub(fc, centre)) < 0:
            nrm = (-nrm[0], -nrm[1], -nrm[2])
        return v_dot(nrm, v_sub(self.pos, fc)) > 0, nrm, fc

    def face(self, pts3, base, centre=None, flat=False, **kw):
        """A shaded polygon, or '' if it faces away (only when `centre` given)."""
        fc = tuple(sum(p[i] for p in pts3) / len(pts3) for i in range(3))
        if centre is not None:
            vis, nrm, fc = self.visible(pts3, centre)
            if not vis:
                return ""
            col = self.fogged(base, fc) if flat else self.lightcol(base, nrm, fc)
        else:
            col = self.fogged(base, fc) if flat else base
        return poly([self.p(q) for q in pts3], col, **kw)


def house(cam, x0, x1, z0, z1, y0, H, R, wall, roof, rng, win=None, tiles=True, floor_h=3.2,
          win_w=0.34, win_h=0.5, shutters=None, cornice=None, lit_windows=0.0, lit_col="#ffcf7a",
          roof_rim=None, doors=False, frame=None, sill_plants=0.0):
    """A box with a hipped roof. Returns (distance, svg) for painter sorting."""
    c = ((x0 + x1) / 2, y0 + H / 2, (z0 + z1) / 2)
    P = {
        "a": (x0, y0, z0), "b": (x1, y0, z0), "c": (x1, y0, z1), "d": (x0, y0, z1),
        "A": (x0, y0 + H, z0), "B": (x1, y0 + H, z0), "C": (x1, y0 + H, z1), "D": (x0, y0 + H, z1),
    }
    out = []
    corners = [cam.p(v) for v in P.values()]
    if all(cam.depth(v) < 0.5 for v in P.values()):
        return 0, ""
    xs_ = [q[0] for q in corners]
    ys_ = [q[1] for q in corners]
    if max(xs_) < -20 or min(xs_) > cam.cx * 2 + 20 or max(ys_) < -20 or min(ys_) > cam.cy * 3:
        return 0, ""
    walls = [("a", "b", "B", "A"), ("b", "c", "C", "B"), ("c", "d", "D", "C"), ("d", "a", "A", "D")]
    for w in walls:
        q = [P[k] for k in w]
        vis, nrm, fc = cam.visible(q, c)
        if not vis:
            continue
        col = cam.lightcol(wall, nrm, fc)
        out.append(poly([cam.p(p) for p in q], col))
        pq = [cam.p(p) for p in q]
        if win is not False and math.dist(pq[0], pq[3]) > 16 and math.dist(pq[0], pq[1]) > 10:
            width = math.dist((q[0][0], q[0][2]), (q[1][0], q[1][2]))
            cols = max(1, int(width / 3.4))
            rows = max(1, int(H / floor_h))
            gl = win or dark(mix(wall, "#1e2a3a", 0.7), 0.35)
            for r_ in range(rows):
                for k in range(cols):
                    if rng.random() < 0.12:
                        continue
                    u0 = (k + 0.5 - win_w / 2 * 3.4 / (width / cols)) / cols
                    u1 = (k + 0.5 + win_w / 2 * 3.4 / (width / cols)) / cols
                    v0 = (r_ + 0.25) / rows
                    v1 = v0 + win_h / rows * (floor_h / (H / rows))
                    def at(u, v, q=q):
                        return tuple(q[0][i] + (q[1][i] - q[0][i]) * u + (q[3][i] - q[0][i]) * v for i in range(3))
                    if doors and r_ == 0:
                        v0 = 0.0
                    wq = [at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]
                    lit_here = rng.random() < lit_windows
                    wc = lit_col if lit_here else gl
                    if not lit_here:
                        wc = cam.fogged(mix(wc, col, 0.15), fc)
                    else:
                        wc = cam.fogged(wc, fc, 0.5)
                    if frame:
                        fu, fv = (u1 - u0) * 0.14, (v1 - v0) * 0.08
                        fq = [at(u0 - fu, v0 - fv), at(u1 + fu, v0 - fv), at(u1 + fu, v1 + fv), at(u0 - fu, v1 + fv)]
                        out.append(poly([cam.p(p) for p in fq], cam.lightcol(frame, nrm, fc)))
                    out.append(poly([cam.p(p) for p in wq], wc))
                    if sill_plants and rng.random() < sill_plants:
                        pc = cam.p(at((u0 + u1) / 2, v0))
                        pr = math.dist(cam.p(at(u0, v0)), cam.p(at(u1, v0))) * 0.35
                        out.append(blob(pc[0], pc[1] - pr * 0.5, pr, rng, cam.fogged(rng.choice(["#3f7a45", "#4f8a3f"]), fc)))
                        out.append(circ(pc[0] + pr * 0.3, pc[1] - pr * 0.8, pr * 0.25, cam.fogged("#e0503a", fc)))
                    if shutters and not lit_here:
                        du = (u1 - u0) * 0.45
                        for su0, su1 in ((u0 - du, u0), (u1, u1 + du)):
                            sq = [at(su0, v0), at(su1, v0), at(su1, v1), at(su0, v1)]
                            out.append(poly([cam.p(p) for p in sq], cam.lightcol(shutters, nrm, fc)))
        if cornice:
            def at2(u, v):
                return tuple(q[0][i] + (q[1][i] - q[0][i]) * u + (q[3][i] - q[0][i]) * v for i in range(3))
            cq = [at2(0, 0.97), at2(1, 0.97), at2(1, 1), at2(0, 1)]
            out.append(poly([cam.p(p) for p in cq], cam.lightcol(cornice, nrm, fc)))
    if R > 0:
        top = y0 + H + R
        if (x1 - x0) >= (z1 - z0):
            hz = (z1 - z0) / 2
            r1, r2 = (x0 + hz, top, (z0 + z1) / 2), (x1 - hz, top, (z0 + z1) / 2)
            planes = [(P["A"], P["B"], r2, r1), (P["B"], P["C"], r2), (P["C"], P["D"], r1, r2), (P["D"], P["A"], r1)]
        else:
            hx_ = (x1 - x0) / 2
            r1, r2 = ((x0 + x1) / 2, top, z0 + hx_), ((x0 + x1) / 2, top, z1 - hx_)
            planes = [(P["A"], P["B"], r1), (P["B"], P["C"], r2, r1), (P["C"], P["D"], r2), (P["D"], P["A"], r1, r2)]
        rc = ((x0 + x1) / 2, y0 + H + R * 0.3, (z0 + z1) / 2)
        drawn = []
        for pl in planes:
            vis, nrm, fc = cam.visible(list(pl), rc)
            if not vis:
                continue
            col = cam.lightcol(roof, nrm, fc)
            drawn.append((cam.depth(fc), pl, col, fc))
        drawn.sort(key=lambda t: -t[0])
        for _, pl, col, fc in drawn:
            pp = [cam.p(p) for p in pl]
            out.append(poly(pp, col))
            size = math.dist(pp[0], pp[1])
            if tiles and size > 70:
                # tile courses run straight down the slope, stopped by the hips
                e0, e1 = pl[0], pl[1]
                em = tuple((e0[j] + e1[j]) / 2 for j in range(3))
                if len(pl) == 3:
                    v = tuple(pl[2][j] - em[j] for j in range(3))
                    inset = 0.5
                else:
                    rm = tuple((pl[2][j] + pl[3][j]) / 2 for j in range(3))
                    v = tuple(rm[j] - em[j] for j in range(3))
                    le = math.dist(e0, e1)
                    inset = max(0.01, min(0.5, math.dist(pl[3], pl[2]) and (le - math.dist(pl[3], pl[2])) / 2 / le))
                k = max(3, int(size / 11))
                lc = dark(col, 0.25)
                for i in range(1, k):
                    t = i / k
                    frac = min(1.0, t / inset, (1 - t) / inset) * 0.97
                    s0 = tuple(e0[j] + (e1[j] - e0[j]) * t for j in range(3))
                    e = tuple(s0[j] + v[j] * frac for j in range(3))
                    a2, b2 = cam.p(s0), cam.p(e)
                    out.append(line(a2[0], a2[1], b2[0], b2[1], lc, max(0.5, size / 150), opacity=0.5))
            if roof_rim:
                out.append(pline([cam.p(pl[-1]), cam.p(pl[-2])] if len(pl) == 4 else [cam.p(pl[0]), cam.p(pl[2])],
                                 roof_rim, max(0.8, size / 90), opacity=0.8))
    return cam.dist(c), "".join(out)


def draw_sorted(items):
    return "".join(s for _, s in sorted(items, key=lambda t: -t[0]))


# ── shared scene parts ────────────────────────────────────────────────────


def lisbon_walls(rng):
    return rng.choice(["#f3ead8", "#efe3c8", "#f1d9b5", "#e9c9a6", "#f4efe6", "#e8d2c2",
                       "#d9e0d6", "#f0dfa8", "#e8c7b8", "#f6f1e7"])


def lisbon_roof(rng):
    return rng.choice(["#c4623a", "#b8573a", "#cf7048", "#a94c33", "#d4784e", "#bd6040"])


def city_grid(cam, rng, xs, zs, ground, hmin, hmax, walls=None, roofs=None, gap=0.18, skip=0.05,
              lot=(12, 22), depth=(10, 16), **kw):
    """Blocks of houses filling a region; returns painter items."""
    items = []
    z = zs[0]
    while z < zs[1]:
        dz = rng.uniform(*depth)
        x = xs[0] + rng.uniform(-6, 0)
        while x < xs[1]:
            dx = rng.uniform(*lot)
            if rng.random() > skip:
                y0 = ground(x + dx / 2, z + dz / 2)
                H = rng.uniform(hmin, hmax)
                items.append(house(cam, x, x + dx * (1 - gap * rng.random()), z, z + dz * (1 - gap * 0.5), y0 - 2,
                                   H + 2, rng.uniform(2.2, 4.0), (walls or lisbon_walls)(rng), (roofs or lisbon_roof)(rng),
                                   rng, **kw))
            x += dx
        z += dz * rng.uniform(1.0, 1.25)
    return items


def tram_side(x, y, L, col="#f3b61f", roof="#f1ece0", glass="#2c3440", skirt="#3a3a3e", lamp=True, pole=True,
              shade="#c98f10"):
    """A Lisbon-style yellow tram, side view, level, top-left at (x, y); height ≈ 0.44 L."""
    H = L * 0.44
    out = []
    # trolley pole
    if pole:
        out.append(line(x + L * 0.62, y + H * 0.05, x + L * 0.25, y - H * 0.55, "#26262a", L * 0.012))
        out.append(line(x + L * 0.62, y + H * 0.05, x + L * 0.58, y - H * 0.02, "#26262a", L * 0.03))
    # roof
    out.append(path(f"M{n(x + L * 0.03)} {n(y + H * 0.12)} Q{n(x + L * 0.04)} {n(y)} {n(x + L * 0.12)} {n(y)} "
                    f"L{n(x + L * 0.88)} {n(y)} Q{n(x + L * 0.96)} {n(y)} {n(x + L * 0.97)} {n(y + H * 0.12)} Z", roof))
    # body
    out.append(rect(x, y + H * 0.11, L, H * 0.73, col, rx=L * 0.03))
    out.append(rect(x, y + H * 0.58, L, H * 0.26, shade, rx=L * 0.02, opacity=0.55))
    out.append(rect(x, y + H * 0.555, L, H * 0.03, dark(col, 0.35), opacity=0.7))
    # windows
    nw = 7
    ww = L * 0.86 / nw
    for i in range(nw):
        wx = x + L * 0.07 + i * ww
        out.append(rect(wx + ww * 0.08, y + H * 0.2, ww * 0.84, H * 0.3, glass, rx=L * 0.006))
        out.append(rect(wx + ww * 0.12, y + H * 0.22, ww * 0.3, H * 0.26, "#ffffff", opacity=0.12))
    # door
    out.append(rect(x + L * 0.07 + ww * 0.08, y + H * 0.2, ww * 0.84, H * 0.58, dark(glass, 0.1), rx=L * 0.006))
    # skirt, wheels
    out.append(rect(x + L * 0.02, y + H * 0.84, L * 0.96, H * 0.08, skirt))
    for wx in (0.22, 0.78):
        out.append(circ(x + L * wx, y + H * 0.93, H * 0.08, "#1c1c1f"))
    if lamp:
        out.append(circ(x + L * 0.985, y + H * 0.66, L * 0.012, "#fff6cf"))
    return "".join(out)


def sailboat(x, y, h, fill):
    return (path(f"M{n(x - h * 0.45)} {n(y)} L{n(x + h * 0.45)} {n(y)} L{n(x + h * 0.32)} {n(y + h * 0.12)} "
                 f"L{n(x - h * 0.34)} {n(y + h * 0.12)} Z", fill)
            + poly([(x, y - h), (x, y - 2), (x + h * 0.36, y - 2)], fill)
            + poly([(x - 2, y - h * 0.85), (x - 2, y - 2), (x - h * 0.3, y - 2)], fill, opacity=0.85))


def cloud(S, x, y, w, rng, col="#ffffff", shade="#c9d6e8", lobes=6):
    out = []
    for i in range(lobes):
        cx = x + (i + 0.5) / lobes * w + rng.uniform(-w * 0.05, w * 0.05)
        r = w * rng.uniform(0.12, 0.2) * (1 - abs(i / (lobes - 1) - 0.5) * 0.9)
        out.append(circ(cx, y - r * 0.5, r, col))
    out.append(rect(x, y - w * 0.06, w, w * 0.08, col, rx=w * 0.04))
    body = "".join(out)
    fill = S.lin([(0, col), (0.55, col), (1, shade)])
    return g(body) + g(f'<rect x="{n(float(x))}" y="{n(float(y - w * 0.3))}" width="{n(float(w))}" height="{n(float(w * 0.34))}" fill="{fill}"/>',
                       clip_path=S.clip(body))


# ── compositions ──────────────────────────────────────────────────────────


def shot_13(p):
    """Late sun over Lisbon roofs, the river beyond — backlit, portrait."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("shot-13")
    hy = 300
    S(sky(S, [(0, "#6f7fa6"), (0.45, "#d99a7a"), (0.8, "#f5c27a"), (1, "#fbe3a6")], 0, hy + 20))
    S(glow(S, 400, hy - 18, 320, "#ffe2a0", 0.55))
    S(glow(S, 400, hy - 18, 90, "#fff6dc", 0.9))
    S(circ(400, hy - 18, 26, "#fff8e6"))
    # far bank
    S(ridge(S, rng, hy - 6, 7, "#c99a86", freq=1.4, bottom=hy + 4))
    S(ridge(S, rng, hy - 1, 4, "#b98a82", freq=2.2, bottom=hy + 4))
    # river
    S(rect(0, hy + 2, w, h - hy, S.lin([(0, "#f4c98a"), (0.25, "#dca27c"), (0.6, "#9a6f7e"), (1, "#6a4c6a")], 0, 0, 0, 1)))
    S(water_glints(rng, 0, w, hy + 6, hy + 120, "#fff3cf", 70, 0.8, 50, center=400, spread=22))
    for bx, by, bs in ((150, hy + 46, 1.0), (250, hy + 22, 0.6)):
        S(sailboat(bx, by, 40 * bs, "#6e4a5e"))
    cam = Cam((0, 70, -10), yaw=4, pitch=10, f=560, cx=w / 2, cy=hy + 98, light=(0.35, 0.28, 1.0),
              shadow="#4a2f55", shadow_k=0.68, lit="#ffc97e", lit_k=0.45, fog="#eeb28a", fogd=240, fogmax=0.85)

    def ground(x, z):
        return -0.2 * z + 0.02 * x
    items = city_grid(cam, rng, (-170, 190), (2, 250), ground, 9, 20, gap=0.12, skip=0.04,
                      roof_rim="#ffcf8a", win_w=0.3)
    # a bell tower and a cypress mid-slope
    items.append(house(cam, 20, 30, 120, 130, ground(25, 125), 40, 8, "#efdcc0", "#b0583a", rng, win=False,
                       roof_rim="#ffd79a"))
    S(draw_sorted(items))
    for x, yb, hh in ((72, 640, 150), (540, 700, 190)):
        S(cypress(x, yb, hh, "#3a2f3f", hi="#5b4250"))
    S(rect(0, 0, w, h, S.lin([(0, "#000", 0), (0.75, "#2a1830", 0), (1, "#2a1830", 0.35)])))
    return S.html()


def dome(cam, S, base, R, H_drum, wall="#f4f0e8", shade="#9aa7bd", lantern=True):
    """A church dome on a drum, drawn flat at a projected point (lit from the left)."""
    cx, cy = cam.p(base)
    s = cam.scale(base)
    r = R * s
    dh = H_drum * s
    out = []
    drum = S.lin([(0, light(wall, 0.4)), (0.45, wall), (1, shade)], 0, 0, 1, 0)
    out.append(rect(cx - r * 0.86, cy - dh, r * 1.72, dh, drum))
    for i in range(9):
        t = (i + 0.5) / 9
        x = cx - r * 0.86 + r * 1.72 * t
        out.append(rect(x - r * 0.035, cy - dh * 0.9, r * 0.07, dh * 0.8, dark(shade, 0.15), opacity=0.35 + 0.4 * t))
    out.append(rect(cx - r * 0.95, cy - dh - r * 0.06, r * 1.9, r * 0.1, light(wall, 0.2)))
    dfill = S.lin([(0, "#ffffff"), (0.35, wall), (1, dark(shade, 0.1))], 0, 0, 1, 0.3)
    top = cy - dh - r * 0.05
    out.append(path(f"M{n(cx - r * 0.9)} {n(top)} C{n(cx - r * 0.9)} {n(top - r * 1.2)} {n(cx + r * 0.9)} {n(top - r * 1.2)} "
                    f"{n(cx + r * 0.9)} {n(top)} Z", dfill))
    for i in range(1, 6):
        t = i / 6
        x = cx - r * 0.9 + r * 1.8 * t
        out.append(path(f"M{n(x)} {n(top)} Q{n(cx + (x - cx) * 0.55)} {n(top - r * 0.8)} {n(cx)} {n(top - r * 0.9)}",
                        "none", stroke=dark(shade, 0.1), stroke_width=max(0.6, r * 0.02), opacity=0.35))
    if lantern:
        lt = top - r * 0.88
        out.append(rect(cx - r * 0.16, lt - r * 0.36, r * 0.32, r * 0.36, S.lin([(0, "#ffffff"), (1, shade)], 0, 0, 1, 0)))
        out.append(path(f"M{n(cx - r * 0.2)} {n(lt - r * 0.34)} Q{n(cx)} {n(lt - r * 0.62)} {n(cx + r * 0.2)} {n(lt - r * 0.34)} Z",
                        light(wall, 0.2)))
        out.append(rect(cx - r * 0.02, lt - r * 0.8, r * 0.04, r * 0.24, dark(shade, 0.2)))
    return "".join(out)


def ig_photo_0(p):
    """Lisbon rooftops at midday, terracotta close up, a white dome behind."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-photo-0")
    hy = 330
    S(sky(S, [(0, "#1f5fb8"), (0.6, "#4f90d8"), (1, "#b4d6f0")], 0, hy + 10))
    S(cloud(S, 60, 120, 170, rng, shade="#c3d4ea"))
    S(cloud(S, 420, 70, 120, rng, shade="#c3d4ea"))
    S(ridge(S, rng, hy - 8, 6, "#a9bfd6", freq=1.2, bottom=hy + 30))
    S(rect(0, hy + 4, w, h - hy, S.lin([(0, "#c9d3dc"), (0.3, "#d8c2b0"), (1, "#c98a6a")])))
    cam = Cam((0, 34, -6), yaw=-12, pitch=5, f=520, cx=w / 2, cy=hy + 45, light=(-0.7, 0.9, -0.55),
              shadow="#5a6a9a", shadow_k=0.42, lit="#fff8ea", lit_k=0.3, fog="#bfd6ee", fogd=420, fogmax=0.85)

    def ground(x, z):
        return -0.05 * z + 0.2 * max(0.0, z - 140)
    items = city_grid(cam, rng, (-280, 170), (4, 330), ground, 8, 16, gap=0.08, skip=0.03, win_w=0.28, lot=(15, 26),
                      shutters=None)
    dz = 215
    gy = ground(30, dz)
    items.append(house(cam, 2, 58, dz, dz + 38, gy - 2, 24, 0, "#f2ede4", "#c46a44", rng, win=False,
                       cornice="#ffffff"))
    base = (30, gy + 22, dz + 19)
    items.append((cam.dist(base) - 3, dome(cam, S, base, 19, 16)))
    for tx in (3, 49):
        items.append(house(cam, tx, tx + 8, dz - 4, dz + 4, gy + 20, 14, 0, "#f3eee6", "#c46a44", rng, win=False))
        tb = (tx + 4, gy + 34, dz)
        items.append((cam.dist(tb) - 4, dome(cam, S, tb, 4.6, 2, lantern=False)))
    S(draw_sorted(items))
    return S.html()


def terrace(S, y, w, stone="#efe6d6", shadow="#b9ab98"):
    out = [rect(0, y, w, 14, light(stone, 0.2)), rect(0, y + 14, w, 6, shadow)]
    bal = S.lin([(0, stone), (0.5, light(stone, 0.2)), (1, shadow)], 0, 0, 1, 0)
    k = int(w / 34)
    for i in range(k + 1):
        x = i * 34 + 6
        out.append(path(f"M{n(x)} {n(y + 20)} C{n(x - 5)} {n(y + 34)} {n(x + 5)} {n(y + 44)} {n(x - 3)} {n(y + 58)} "
                        f"L{n(x + 21)} {n(y + 58)} C{n(x + 13)} {n(y + 44)} {n(x + 23)} {n(y + 34)} {n(x + 18)} {n(y + 20)} Z", bal))
    out.append(rect(0, y + 58, w, 12, stone))
    out.append(rect(0, y + 70, w, 200, S.lin([(0, "#cbbba3"), (1, "#a8977f")])))
    return "".join(out)


def blossoms(rng, cx, cy, r, cols, count=60):
    out = []
    for _ in range(count):
        a = rng.uniform(0, 6.283)
        d = r * math.sqrt(rng.random())
        x, y = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.7
        out.append(circ(x, y, rng.uniform(2.5, 6.5), rng.choice(cols)))
    return "".join(out)


def reddit_4(p):
    """A miradouro: stone terrace, jacaranda overhead, the city falling to a wide river."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("reddit-4")
    hy = 150
    S(sky(S, [(0, "#8fb4d9"), (1, "#e6e6e8")], 0, hy + 10))
    S(ridge(S, rng, hy - 10, 10, "#b7bfd2", freq=1.5, bottom=hy + 6))
    S(ridge(S, rng, hy - 2, 5, "#a7b2c8", freq=2.5, bottom=hy + 6))
    S(rect(0, hy + 2, w, 200, S.lin([(0, "#b9cddd"), (0.5, "#8fb0cc"), (1, "#7699ba")])))
    S(water_glints(rng, 0, w, hy + 8, hy + 150, "#e8f1f8", 60, 0.6, 30))
    for bx, by, bs in ((560, hy + 40, 0.8), (320, hy + 70, 0.6)):
        S(sailboat(bx, by, 30 * bs, "#f5f2ec"))
    cam = Cam((0, 45, -20), yaw=6, pitch=8, f=720, cx=w / 2, cy=hy + 101, light=(0.8, 0.8, -0.35),
              shadow="#6a6d9a", shadow_k=0.45, lit="#fff1dc", lit_k=0.25, fog="#c9d3e0", fogd=260, fogmax=0.85)

    def ground(x, z):
        return -0.08 * z + 0.02 * x
    S(rect(0, hy + 150, w, h, S.lin([(0, "#cfd3da"), (1, "#c8a88e")])))
    items = city_grid(cam, rng, (-200, 230), (40, 300), ground, 9, 19, gap=0.1, skip=0.05, win_w=0.3,
                      lot=(14, 26),
                      walls=lambda r: r.choice(["#f4efe6", "#f1e6cf", "#efe0c4", "#e9d7cf", "#f6f2ea", "#e3ddc8"]))
    S(draw_sorted(items))
    # the jacaranda over the terrace
    br = "#4a3a3a"
    for d in ("M-10 60 C120 90 210 70 330 30", "M60 -10 C90 50 150 80 240 110", "M-10 180 C40 140 80 110 150 90"):
        S(path(d, "none", stroke=br, stroke_width=7, stroke_linecap="round"))
    cols = ["#8a78c8", "#9d8ad6", "#b3a3e6", "#7563b4", "#c6b9f0"]
    for cx, cy, r in ((70, 40, 90), (220, 70, 80), (330, 20, 60), (30, 150, 60), (150, 110, 50)):
        S(blossoms(rng, cx, cy, r, cols, 45))
    S(terrace(S, 480, w))
    S(lamp_post(700, 490, 250, "#26272c", "#efe7cf", "#fff0c0", S, on=False))
    for i in range(24):
        x, y = rng.uniform(0, w), rng.uniform(520, 600)
        S(ell(x, y, 3.5, 2, rng.choice(cols), opacity=0.8))
    return S.html()


def ig_photo_2(p):
    """A yellow tram climbing a steep Lisbon street, morning, seen side-on."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-photo-2")
    ang = 18
    t = math.tan(math.radians(ang))

    def sy(x, y0=640):
        return y0 - t * x
    S(sky(S, [(0, "#8fc3e6"), (1, "#f4e7cf")], 0, 360))
    # facades stepping up the hill
    x = -30
    facs = [("#f1d7c3", 330), ("#f4ecd8", 360), ("#e9c46a", 300), ("#dfe6e0", 380), ("#f2cfc0", 320), ("#f4ecd8", 340)]
    i = 0
    while x < w + 40:
        col, H = facs[i % len(facs)]
        fw = rng.uniform(110, 150)
        base = sy(x + fw) - 26
        top = base - H
        S(rect(x, top, fw + 2, base - top + 60, col))
        S(rect(x, top - 6, fw + 2, 8, light(col, 0.3)))
        S(rect(x + fw - 4, top, 6, base - top + 60, dark(col, 0.12)))
        rows = int((base - top - 40) / 62)
        for r_ in range(rows):
            wy = top + 26 + r_ * 62
            for k in range(2):
                wx = x + fw * (0.2 + k * 0.42)
                S(rect(wx - 4, wy - 4, fw * 0.2 + 8, 44, light(col, 0.45)))
                S(rect(wx, wy, fw * 0.2, 38, "#34404c"))
                S(rect(wx, wy, fw * 0.1, 38, "#4b6b7a", opacity=0.45))
                if r_ % 2 == 0:
                    S(rect(wx - 6, wy + 36, fw * 0.2 + 12, 4, "#2b2b2f"))
                    for b in range(6):
                        S(rect(wx - 5 + b * (fw * 0.2 + 10) / 5, wy + 22, 1.6, 14, "#2b2b2f"))
                    S(rect(wx - 6, wy + 21, fw * 0.2 + 12, 2, "#2b2b2f"))
        x += fw
        i += 1
    # the opposite side's shadow falls across the lower facades
    S(poly([(0, 380), (w, 170), (w, h), (0, h)], "#3b4a78", opacity=0.28))
    # pavement and street
    S(poly([(0, sy(0) - 26), (w, sy(w) - 26), (w, sy(w) + 4), (0, sy(0) + 4)], "#d9d0c3"))
    S(poly([(0, sy(0) + 4), (w, sy(w) + 4), (w, h), (0, h)], S.lin([(0, "#7b7a80"), (1, "#4a4a52")])))
    for k in range(8):
        yy = sy(0) + 40 + k * 22
        S(line(0, yy, w, yy - t * w, "#3c3c44", 1, opacity=0.25))
    for off in (28, 70):
        S(line(0, sy(0) + off, w, sy(w) + off, "#c9c9cf", 2.2, opacity=0.8))
    # the tram, level with its rails
    L = 360
    tx = 150
    ty = sy(tx) + 70 - L * 0.44 * 0.93
    S(g(tram_side(tx, ty, L), transform=f"rotate({-ang} {tx} {sy(tx) + 70})"))
    # the wire the pole runs on
    ox, oy = tx, sy(tx) + 70
    px, py = tx + L * 0.25 - ox, ty - L * 0.44 * 0.55 - oy
    a = math.radians(-ang)
    wx, wy = ox + px * math.cos(a) - py * math.sin(a), oy + px * math.sin(a) + py * math.cos(a)
    for off in (0, -7):
        S(line(0, wy + off + t * wx, w, wy + off - t * (w - wx), "#2a2a30", 1.4, opacity=0.85))
    S(line(0, 60, w, 30, "#2a2a30", 1, opacity=0.5))
    # a walker on the pavement
    S(person(560, sy(560) - 22, 64, "#2c3040"))
    S(rect(0, 0, w, h, S.lin([(0, "#fff3d6", 0.12), (0.5, "#fff3d6", 0), (1, "#1b1e2e", 0.2)])))
    return S.html()


def tram_front(cx, yb, W, col="#f3b61f", roof="#f1ece0", glass="#26303c", lampglow=True):
    """A Lisbon-style tram seen head-on; bottom-centre at (cx, yb), width W."""
    H = W * 1.45
    x0 = cx - W / 2
    top = yb - H
    out = []
    out.append(line(cx + W * 0.1, top + H * 0.02, cx + W * 0.35, top - H * 0.5, "#222", max(1, W * 0.03)))
    out.append(path(f"M{n(x0 + W * 0.04)} {n(top + H * 0.08)} Q{n(cx)} {n(top - H * 0.03)} {n(x0 + W * 0.96)} {n(top + H * 0.08)} Z", roof))
    out.append(rect(x0, top + H * 0.07, W, H * 0.83, col, rx=W * 0.08))
    out.append(rect(x0 + W * 0.62, top + H * 0.07, W * 0.38, H * 0.83, "#b07a00", opacity=0.25, rx=W * 0.08))
    out.append(rect(cx - W * 0.28, top + H * 0.1, W * 0.56, H * 0.08, "#1e1e22", rx=W * 0.02))
    out.append(rect(x0 + W * 0.1, top + H * 0.22, W * 0.37, H * 0.3, glass, rx=W * 0.03))
    out.append(rect(cx + W * 0.03, top + H * 0.22, W * 0.37, H * 0.3, glass, rx=W * 0.03))
    out.append(poly([(x0 + W * 0.12, top + H * 0.24), (x0 + W * 0.26, top + H * 0.24), (x0 + W * 0.14, top + H * 0.5),
                     (x0 + W * 0.12, top + H * 0.5)], "#ffffff", opacity=0.14))
    out.append(rect(x0, top + H * 0.56, W, H * 0.02, dark(col, 0.35)))
    if lampglow:
        out.append(circ(cx, top + H * 0.68, W * 0.2, "#fff4c0", opacity=0.25))
    out.append(circ(cx, top + H * 0.68, W * 0.065, "#fffbe8"))
    for sx in (-1, 1):
        out.append(circ(cx + sx * W * 0.34, top + H * 0.74, W * 0.035, "#ffe7a8"))
    out.append(rect(x0 - W * 0.02, top + H * 0.84, W * 1.04, H * 0.06, "#2a2a2e", rx=W * 0.02))
    out.append(rect(x0 + W * 0.08, top + H * 0.9, W * 0.84, H * 0.1, "#18181b"))
    return "".join(out)


def reddit_5(p):
    """A tram stop with a queue, the yellow tram coming head-on up the street, afternoon."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("reddit-5")
    cam = Cam((1.5, 1.7, 0), yaw=-3, pitch=-1, f=560, cx=w / 2, cy=300, light=(-0.55, 0.75, 0.35),
              shadow="#4a4f7a", shadow_k=0.4, lit="#fff0d0", lit_k=0.25, fog="#e9e2d6", fogd=160, fogmax=0.75)
    S(sky(S, [(0, "#4f8fd1"), (1, "#cfe2f2")], 0, 320))
    far = 170
    S(rect(0, 300, w, h - 300, "#6f6a66"))
    # ground: street and pavements
    S(cam.face([(-3.6, 0, 2), (3.6, 0, 2), (3.6, 0, far), (-3.6, 0, far)], "#8a8580"))
    S(cam.face([(-6, 0.15, 2), (-3.6, 0.15, 2), (-3.6, 0.15, far), (-6, 0.15, far)], "#d8cfc0"))
    S(cam.face([(3.6, 0.15, 2), (6.5, 0.15, 2), (6.5, 0.15, far), (3.6, 0.15, far)], "#e2d9ca"))
    S(cam.face([(-3.6, 0.01, 2), (-1.4, 0.01, 2), (-1.4, 0.01, far), (-3.6, 0.01, far)], "#3e3f5c", opacity=0.35))
    for rx in (-0.72, 0.72):
        a, b = cam.p((rx, 0.02, 2)), cam.p((rx, 0.02, far))
        S(line(a[0], a[1], b[0], b[1], "#d8d8de", 2.4))
    items = []
    walls = ["#e7b98a", "#f0dcc0", "#d98f6a", "#e9d8a8", "#c8d4d8", "#f2e6d8", "#e6c3b0"]
    for side, x0, x1 in ((-1, -18, -6), (1, 6.5, 19)):
        z = 2
        while z < far:
            L = rng.uniform(7, 13)
            H = rng.uniform(11, 18)
            items.append(house(cam, x0, x1, z, z + L, 0, H, 0, rng.choice(walls), "#b55", rng, win_w=0.3,
                               floor_h=3.4, shutters=rng.choice(["#3f6b5a", "#5b6f8c", None]), cornice="#f6efe2"))
            z += L
    S(draw_sorted(items))
    # wires
    for z in (10, 30, 55, 90):
        a, b = cam.p((-6, 7.5, z)), cam.p((6.5, 7.5, z))
        S(line(a[0], a[1], b[0], b[1], "#2a2a30", 1, opacity=0.6))
    for wx in (-0.6, 0.6):
        a, b = cam.p((wx, 6.2, 3)), cam.p((wx, 6.2, far))
        S(line(a[0], a[1], b[0], b[1], "#2a2a30", 1.2, opacity=0.7))
    # the tram
    tp = (0.2, 0, 15)
    x, y = cam.p(tp)
    S(ell(x + cam.scale(tp) * 0.3, y, cam.scale(tp) * 1.6, cam.scale(tp) * 0.12, "#2a2a3a", opacity=0.35))
    S(tram_front(x, y, cam.scale(tp) * 2.5))
    # the queue on the near pavement
    stop = (4.0, 0.15, 7.5)
    a, b = cam.p(stop), cam.p((4.0, 3.1, 7.5))
    S(line(a[0], a[1], b[0], b[1], "#2e2e33", 3))
    S(circ(b[0], b[1], 10, "#f3b61f"))
    S(circ(b[0], b[1], 6, "#fff4d0"))
    cloth = ["#2d3a52", "#7a3b2e", "#4a5a3a", "#2b2b30", "#8a6a4a", "#34466a", "#5a2e3e", "#6b6f78"]
    people = []
    zz = 6.2
    for i in range(13):
        pz = zz + i * 1.05 + rng.uniform(-0.2, 0.2)
        px = 5.0 + rng.uniform(-0.45, 0.6)
        hh = rng.uniform(1.62, 1.85)
        people.append((pz, px, hh))
    for pz, px, hh in sorted(people, key=lambda q: -q[0]):
        base = cam.p((px, 0.15, pz))
        sc = cam.scale((px, 0.15, pz))
        sh = cam.p((px + 1.1, 0.15, pz - 0.5))
        S(line(base[0], base[1], sh[0], sh[1], "#3a3f60", sc * 0.45, opacity=0.35, stroke_linecap="round"))
        S(person(base[0], base[1], hh * sc, rng.choice(cloth)))
    S(rect(0, 0, w, h, S.lin([(0, "#fff", 0), (0.7, "#fff", 0), (1, "#20202a", 0.25)])))
    return S.html()


def azulejo(S, size, ink="#1f4c9c", ground="#f3f0e8", kind=0):
    """A repeating tile; `kind` picks the motif. Returns a pattern url."""
    s = size
    c = s / 2
    if kind == 0:  # four-petal star with corner quarter-circles
        inner = (rect(0, 0, s, s, ground)
                 + "".join(circ(x, y, s * 0.28, ink) for x, y in ((0, 0), (s, 0), (0, s), (s, s)))
                 + "".join(circ(x, y, s * 0.2, ground) for x, y in ((0, 0), (s, 0), (0, s), (s, s)))
                 + path(f"M{n(c)} {n(s * 0.14)} Q{n(c + s * 0.1)} {n(c - s * 0.1)} {n(s * 0.86)} {n(c)} "
                        f"Q{n(c + s * 0.1)} {n(c + s * 0.1)} {n(c)} {n(s * 0.86)} Q{n(c - s * 0.1)} {n(c + s * 0.1)} "
                        f"{n(s * 0.14)} {n(c)} Q{n(c - s * 0.1)} {n(c - s * 0.1)} {n(c)} {n(s * 0.14)} Z", ink)
                 + circ(c, c, s * 0.07, ground))
    elif kind == 1:  # lozenge
        inner = (rect(0, 0, s, s, ground)
                 + poly([(c, s * 0.1), (s * 0.9, c), (c, s * 0.9), (s * 0.1, c)], ink)
                 + poly([(c, s * 0.28), (s * 0.72, c), (c, s * 0.72), (s * 0.28, c)], ground)
                 + circ(c, c, s * 0.1, ink))
    elif kind == 2:  # relief squares
        inner = (rect(0, 0, s, s, ground) + rect(s * 0.12, s * 0.12, s * 0.76, s * 0.76, ink)
                 + rect(s * 0.3, s * 0.3, s * 0.4, s * 0.4, ground, opacity=0.6))
    else:  # quatrefoil across the joints
        inner = (rect(0, 0, s, s, ground)
                 + "".join(ell(x, y, s * 0.18, s * 0.34, ink) for x, y in ((c, 0), (c, s)))
                 + "".join(ell(x, y, s * 0.34, s * 0.18, ink) for x, y in ((0, c), (s, c)))
                 + circ(c, c, s * 0.12, ink))
    inner += rect(0, 0, s, s, "none", stroke=dark(ground, 0.12), stroke_width=max(0.6, s * 0.03))
    return S.pattern(s, s, inner)


def trello_2(p):
    """A Lisbon street elevation: tiled facades, iron balconies, noon shadows."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("trello-2")
    S(rect(0, 0, w, h, "#9cc7ea"))
    facades = [
        (0, 150, azulejo(S, 46, "#3a66b0", "#f2efe6", 0), 0),
        (150, 165, None, "#efc75e"),
        (315, 170, azulejo(S, 42, "#3f8a6a", "#eef0e6", 1), 0),
        (485, 160, None, "#e8a79c"),
    ]
    for x, fw, pat, plain in facades:
        top = rng.choice([-20, 14, 26])
        S(rect(x, top, fw, h, plain or "#fff"))
        if pat:
            S(rect(x, top, fw, h, pat))
        S(rect(x, top, fw, 10, "#f7f3ea"))
        S(rect(x, top + 10, fw, 4, "#cfc6b6"))
        S(rect(x, top, 7, h, "#f4efe4"))
        S(rect(x + fw - 7, top, 7, h, "#e2dbcd"))
        for r_, wy in enumerate((top + 42, top + 150)):
            for k in range(2):
                wx = x + fw * (0.17 + k * 0.42)
                ww = fw * 0.25
                wh = 78
                S(rect(wx - 5, wy - 7, ww + 10, wh + 7, "#f6f2ea"))
                S(rect(wx, wy, ww, wh, "#2e3a44"))
                S(rect(wx + ww / 2 - 1, wy, 2, wh, "#e8e2d6"))
                S(rect(wx + 2, wy + 2, ww * 0.35, wh - 4, "#5d7684", opacity=0.4))
                # balcony: slab, railing, and the shadow they throw down-right
                S(poly([(wx - 8, wy + wh), (wx + ww + 8, wy + wh), (wx + ww + 26, wy + wh + 30), (wx + 10, wy + wh + 30)],
                       "#1b2340", opacity=0.22))
                S(rect(wx - 10, wy + wh - 3, ww + 20, 6, "#e9e3d8"))
                S(rect(wx - 10, wy + wh - 30, ww + 20, 2.5, "#1f2226"))
                for b in range(6):
                    S(rect(wx - 9 + b * (ww + 17) / 5, wy + wh - 29, 2, 27, "#1f2226"))
                if rng.random() < 0.5:
                    S(blob(wx + ww * 0.8, wy + wh - 30, 11, rng, "#4c7a3c"))
                    for _ in range(5):
                        S(circ(wx + ww * 0.8 + rng.uniform(-9, 9), wy + wh - 32 + rng.uniform(-7, 5), 2.4, "#d8453a"))
    # the pavement
    S(rect(0, h - 36, w, 36, "#e6e0d4"))
    for i in range(0, w + 20, 20):
        S(path(f"M{i} {h - 26} q5 -6 10 0 t10 0", "none", stroke="#3a3a40", stroke_width=2.2, opacity=0.8))
    S(rect(0, h - 36, w, 4, "#c7bfb0"))
    S(poly([(0, 0), (w, 0), (w, 60), (0, 140)], "#fff4d8", opacity=0.08))
    return S.html()


def ig_save_6(p):
    """A small shop's wall of blue-and-white tiles; loose tiles on a shelf and counter."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-save-6")
    # the wall sits behind the shelf, a touch out of focus
    S(rect(-10, -10, w + 20, 560, azulejo(S, 120, "#24529e", "#f3f0e6", 0), filter=S.blur(1.8)))
    # warm window light falling across the wall
    S(poly([(-40, 60), (280, 0), (430, 520), (60, 640)], "#fff1c8", opacity=0.22))
    S(rect(0, 0, w, h, S.lin([(0, "#0b1a3a", 0.0), (0.55, "#0b1a3a", 0.12), (1, "#0b1a3a", 0.45)], 0, 0, 1, 0.6)))
    # shelf with tiles propped on it
    sy_ = 330
    S(rect(20, sy_ + 14, w - 40, 22, "#1a1a28", opacity=0.3))
    S(rect(10, sy_, w - 20, 16, "#b5793f"))
    S(rect(10, sy_ + 12, w - 20, 5, "#7d4f27"))
    specs = [(0, "#1d4d9e", 96), (1, "#2c7a5a", 84), (3, "#c9892b", 90), (2, "#3a6fc4", 80), (0, "#6a4aa0", 88)]
    x = 40
    for i, (k, ink, s) in enumerate(specs):
        ang = rng.uniform(-8, 8)
        pat = azulejo(S, s / 2, ink, "#f7f4ec", k)
        t = f"rotate({n(ang)} {n(x + s / 2)} {n(float(sy_))})"
        S(rect(x + 4, sy_ - s + 6, s, s, "#000", opacity=0.18, transform=t))
        S(rect(x, sy_ - s, s, s, pat, transform=t))
        S(rect(x, sy_ - s, s, s, S.lin([(0, "#fff", 0.25), (1, "#000", 0.1)], 0, 0, 1, 1), transform=t))
        x += s + rng.uniform(12, 24)
    # counter
    cy_ = 540
    S(rect(0, cy_, w, h - cy_, S.lin([(0, "#9a6536"), (1, "#6e4526")])))
    S(rect(0, cy_, w, 10, "#c38a52"))
    for i in range(4):
        S(line(0, cy_ + 30 + i * 30, w, cy_ + 32 + i * 30, "#5a371d", 1, opacity=0.35))
    S(rect(0, cy_ + 150, w, h - cy_ - 150, "#5e3a20"))
    S(rect(0, cy_ + 150, w, 8, "#3e2412"))
    for x in (30, 330):
        S(rect(x, cy_ + 180, 280, 90, "#6e4526", rx=4))
        S(rect(x + 8, cy_ + 188, 264, 74, "#633d21", rx=3))
        S(circ(x + 140, cy_ + 225, 5, "#c9a060"))
    # loose tiles lying flat, and a paper parcel
    for i, (tx, k, ink) in enumerate(((70, 0, "#1d4d9e"), (160, 1, "#1d4d9e"), (250, 3, "#2c7a5a"))):
        pat = azulejo(S, 38, ink, "#f7f4ec", k)
        pts_ = [(tx, cy_ + 60), (tx + 80, cy_ + 50), (tx + 96, cy_ + 92), (tx + 12, cy_ + 104)]
        S(poly([(a + 5, b + 6) for a, b in pts_], "#000", opacity=0.2))
        S(poly(pts_, pat))
    S(poly([(420, cy_ + 40), (580, cy_ + 30), (600, cy_ + 110), (430, cy_ + 124)], "#d9c29a"))
    S(poly([(420, cy_ + 40), (580, cy_ + 30), (582, cy_ + 42), (422, cy_ + 52)], "#e8d6b2"))
    S(line(505, cy_ + 34, 512, cy_ + 118, "#8a3a2a", 2))
    S(line(424, cy_ + 84, 596, cy_ + 70, "#8a3a2a", 2))
    return S.html()


def prism(cam, base, y0, y1, col, **kw):
    """A vertical prism over any convex base polygon [(x, z), …] → (distance, svg)."""
    c = (sum(b[0] for b in base) / len(base), (y0 + y1) / 2, sum(b[1] for b in base) / len(base))
    m = len(base)
    faces = []
    for i in range(m):
        a, b = base[i], base[(i + 1) % m]
        faces.append([(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])])
    faces.append([(q[0], y1, q[1]) for q in base])
    faces.append([(q[0], y0, q[1]) for q in base])
    return cam.dist(c), "".join(cam.face(f, col, centre=c, **kw) for f in faces)


def ig_save_9(p):
    """A red suspension bridge at blue hour from the shore, the near tower overhead."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-save-9")
    cam = Cam((0, 6, 0), yaw=0, pitch=-10, f=560, cx=w / 2, cy=540, light=(-0.6, 0.3, 1),
              shadow="#141c3c", shadow_k=0.62, lit="#ff9a6a", lit_k=0.3, fog="#4a5f90", fogd=1100, fogmax=0.85)
    hz = cam.p((0, 6, 1e6))[1]
    S(sky(S, [(0, "#0c1636"), (0.45, "#213d78"), (0.8, "#5876a6"), (0.94, "#d49c88"), (1, "#eab48c")], 0, hz + 2))
    for _ in range(40):
        S(circ(rng.uniform(0, w), rng.uniform(0, hz * 0.4), rng.uniform(0.5, 1.3), "#ffffff", opacity=round(rng.uniform(0.2, 0.7), 2)))
    S(ridge(S, rng, hz - 12, 9, "#27335c", freq=1.2, bottom=hz + 2))
    S(rect(0, hz, w, h - hz, S.lin([(0, "#3a5584"), (0.35, "#1f3060"), (1, "#0d1633")])))
    for _ in range(170):
        x = rng.uniform(0, w)
        y = hz - rng.uniform(0, 14) * rng.random()
        S(circ(x, y, rng.uniform(0.6, 1.4), rng.choice(["#ffd38a", "#ffe8b8", "#ffb870"]), opacity=round(rng.uniform(0.5, 1), 2)))
    th = math.radians(33)
    X0, Z0 = 72.0, 240.0
    deck, top = 70.0, 190.0
    span = 1000.0

    def B(s, u, y):
        return (X0 - math.sin(th) * s + math.cos(th) * u, y, Z0 + math.cos(th) * s + math.sin(th) * u)

    def base(s0, s1, u0, u1):
        return [(B(s, u, 0)[0], B(s, u, 0)[2]) for s, u in ((s0, u0), (s1, u0), (s1, u1), (s0, u1))]

    red = "#c43a26"

    def tower(s, legs=(-14, 14), beams=True):
        out = []
        for u in legs:
            out.append(prism(cam, base(s - 4, s + 4, u - 4, u + 4), 0, top, red))
        if beams:
            for by in (deck - 12, 128, top - 9):
                out.append(prism(cam, base(s - 3, s + 3, -12, 12), by, by + 7, red))
        return out

    def cable_y(s):
        if 0 <= s <= span:
            u = (s - span / 2) / (span / 2)
            return deck + 7 + (top - deck - 7) * u * u
        d = -s if s < 0 else s - span
        return max(deck + 3, top - (top - deck) * (d / 470) ** 1.2)

    S(draw_sorted(tower(span)))
    S(draw_sorted(tower(0, legs=(14,), beams=False)))
    # the deck: its underside, its lit edge
    S(prism(cam, base(-140, 2800, -15, 15), deck - 4, deck + 4, "#3a2230")[1])
    for side in (-14, 14):
        ss = [(-140 + i * 12) for i in range(int((span + 500 + 140) / 12))]
        S(pline([cam.p(B(s, side, cable_y(s))) for s in ss], "#c8412c", 3, stroke_linejoin="round"))
        s = 20.0
        while s < span:
            a, b = cam.p(B(s, side, cable_y(s))), cam.p(B(s, side, deck + 4))
            S(line(a[0], a[1], b[0], b[1], "#a83626", max(0.5, min(2.2, cam.scale(B(s, side, deck)) * 0.45)), opacity=0.85))
            s += 22
    S(draw_sorted(tower(0, legs=(-14,), beams=True)))
    # deck lights, and their long reflections on the water
    for s in range(-120, 2800, 28):
        for side in (-15, 15):
            q = B(s, side, deck + 5)
            x, y = cam.p(q)
            sc = cam.scale(q)
            if x < -10 or x > w + 10 or y < -10:
                continue
            S(circ(x, y, max(0.8, min(3.5, sc * 1.1)), "#ffdca6"))
            if sc > 1.0:
                S(circ(x, y, min(14, sc * 4), "#ffc070", opacity=0.18))
            rx_, ry_ = cam.p((q[0], -q[1] + 12, q[2]))
            if hz < ry_ < h + 40:
                S(rect(rx_ - max(0.6, sc * 0.7), ry_ - sc * 12, max(1.2, sc * 1.4), max(6, sc * 40), "#ffc070",
                       opacity=0.2, rx=1))
    for s in (0, span):
        for u in (-14, 14):
            x, y = cam.p(B(s, u, top + 1))
            S(circ(x, y, 7, "#ff3a2a", opacity=0.3))
            S(circ(x, y, 2.2, "#ff7060"))
    S(water_glints(rng, 0, w, hz + 4, h, "#8fb0e0", 60, 0.3, 40))
    S(rect(0, 0, w, h, S.lin([(0, "#000", 0.15), (0.3, "#000", 0), (0.8, "#000", 0), (1, "#000", 0.3)])))
    return S.html()


def dayone_11(p):
    """From a plane window: the river below, the red bridge, the city on one bank."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("dayone-11")
    S(rect(0, 0, w, h, S.lin([(0, "#e4e2de"), (1, "#bdbab4")], 0, 0, 1, 1)))
    S(rect(0, 0, w, h, S.rad([(0, "#ffffff", 0.35), (1, "#ffffff", 0)], 0.5, 0.45, 0.6)))
    cx, cy, ww, wh = 400, 300, 330, 420
    x0, y0 = cx - ww / 2, cy - wh / 2
    S(rect(x0 - 26, y0 - 26, ww + 52, wh + 52, S.lin([(0, "#f2f0ec"), (1, "#c9c6c0")]), rx=150))
    S(rect(x0 - 12, y0 - 12, ww + 24, wh + 24, S.lin([(0, "#a8a5a0"), (1, "#dedbd6")]), rx=140))
    win = rect(x0, y0, ww, wh, "#000", rx=130)
    view = []
    view.append(rect(x0, y0, ww, wh, "#b9a57c"))
    # patchwork on the far bank
    for _ in range(90):
        fx, fy = rng.uniform(x0 - 40, x0 + ww), rng.uniform(y0 - 20, y0 + wh)
        view.append(poly([(fx, fy), (fx + rng.uniform(20, 60), fy - 8), (fx + rng.uniform(30, 70), fy + rng.uniform(20, 40)),
                          (fx + 4, fy + rng.uniform(20, 36))], rng.choice(["#a7a071", "#c1ad7d", "#8e9a66", "#b3946a", "#9fa678"]),
                         opacity=0.9))
    # the river, a broad diagonal band
    river = f"M{x0 - 20} {y0 + 110} C{x0 + 120} {y0 + 150} {x0 + 230} {y0 + 170} {x0 + ww + 20} {y0 + 150} L{x0 + ww + 20} {y0 + 330} C{x0 + 230} {y0 + 360} {x0 + 100} {y0 + 310} {x0 - 20} {y0 + 300} Z"
    view.append(path(river, S.lin([(0, "#3a78a8"), (1, "#5a9ac4")], 0, 0, 1, 1)))
    view.append(path(river, "none", stroke="#e8e0cc", stroke_width=3, opacity=0.4))
    # the city on the near bank: blocks in a grid, terracotta and cream
    view.append(path(f"M{x0 - 20} {y0 + 300} C{x0 + 100} {y0 + 310} {x0 + 230} {y0 + 360} {x0 + ww + 20} {y0 + 330} "
                     f"L{x0 + ww + 20} {y0 + wh + 20} L{x0 - 20} {y0 + wh + 20} Z", "#d9c7a8"))
    for i in range(150):
        bx = rng.uniform(x0 - 10, x0 + ww)
        by = rng.uniform(y0 + 335, y0 + wh + 10)
        view.append(rect(bx, by, rng.uniform(10, 22), rng.uniform(7, 13), rng.choice(["#e9dcc4", "#d58a64", "#c9765a", "#f1e7d4", "#cfa27e"]),
                         transform=f"rotate(-8 {n(bx)} {n(by)})"))
    for i in range(6):
        yy = y0 + 350 + i * 22
        view.append(line(x0 - 10, yy, x0 + ww + 10, yy - 30, "#9d917c", 2, opacity=0.6))
    # the bridge: a thin red deck with two towers and their shadows on the water
    ax, ay, bx2, by2 = x0 + 40, y0 + 318, x0 + 250, y0 + 135
    view.append(line(ax + 8, ay + 6, bx2 + 8, by2 + 6, "#1d3a55", 6, opacity=0.5))
    view.append(line(ax, ay, bx2, by2, "#d4432a", 6.5))
    for t in (0.33, 0.66):
        tx, ty = ax + (bx2 - ax) * t, ay + (by2 - ay) * t
        view.append(line(tx + 3, ty + 2, tx + 22, ty + 10, "#1d3a55", 3, opacity=0.45))
        view.append(rect(tx - 3, ty - 3, 6, 6, "#e0563c"))
    # a ship's wake
    view.append(path(f"M{x0 + 260} {y0 + 280} q-60 10 -120 30", "none", stroke="#e8f1f6", stroke_width=2, opacity=0.7))
    view.append(rect(x0 + 256, y0 + 276, 10, 5, "#f4f4f2"))
    # haze and a cloud wisp below us
    view.append(rect(x0, y0, ww, wh, S.lin([(0, "#dfe8f2", 0.35), (0.5, "#dfe8f2", 0.05), (1, "#dfe8f2", 0.0)])))
    view.append(ell(x0 + 70, y0 + 60, 120, 26, "#ffffff", opacity=0.75, filter=S.blur(10)))
    view.append(ell(x0 + 290, y0 + 400, 90, 20, "#ffffff", opacity=0.6, filter=S.blur(9)))
    # the shade, pulled a third of the way down
    view.append(rect(x0, y0 - 10, ww, 118, S.lin([(0, "#e9e7e2"), (1, "#d6d3cd")])))
    view.append(rect(x0, y0 + 102, ww, 8, "#bcb8b1"))
    view.append(rect(cx - 22, y0 + 104, 44, 7, "#a9a59e", rx=3))
    S(g(view, clip_path=S.clip(win)))
    S(rect(x0, y0, ww, wh, "none", rx=130, stroke="#8f8b85", stroke_width=3, opacity=0.6))
    S(rect(x0 + 10, y0 + 120, ww * 0.35, wh * 0.5, "#ffffff", opacity=0.06, rx=60))
    return S.html()


def ig_notice_3(p):
    """Looking up steep stone stairs in Alfama; laundry strung between the walls."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-notice-3")
    cam = Cam((0.4, 1.6, -2.5), yaw=-3, pitch=-13, f=430, cx=w / 2, cy=470, light=(0.75, 0.9, 0.25),
              shadow="#5a4a80", shadow_k=0.33, lit="#fff2dc", lit_k=0.3, fog="#eef1f6", fogd=140, fogmax=0.55)
    S(sky(S, [(0, "#3f86d6"), (1, "#bfdcf5")], 0, 460))
    rise, run = 0.18, 0.36

    def gnd(z):
        return max(0.0, math.floor(z / run) * rise)
    items = []
    for side, xa, xb in ((-1, -9, -2.3), (1, 2.3, 9)):
        z = -3
        while z < 40:
            L = rng.uniform(3.2, 5.5)
            y0 = gnd(z) - 0.5
            H = rng.uniform(7, 10)
            wall = rng.choice(["#eaa27a", "#f2cf8a", "#9fc0c8", "#f4efe4", "#d98a78", "#b8cfa8", "#f0dcc0"])
            items.append(house(cam, xa, xb, z, z + L, y0, H, 0, wall, "#b55", rng, win_w=0.22, win_h=0.45,
                               floor_h=2.6, shutters=rng.choice(["#3f6e5a", "#8a3f2e", "#4f6e9a", None]),
                               frame="#f7f3ea", win="#3a4452", sill_plants=0.25, cornice="#f4efe6"))
            z += L
    items.append(house(cam, -9, 9, 22, 28, gnd(22) - 0.5, 9, 1.6, "#f3e6c8", "#c4623a", rng, win_w=0.22,
                       floor_h=2.6, frame="#ffffff", win="#3a4452", shutters="#3f6e5a", sill_plants=0.3))
    walls_svg = draw_sorted(items)
    steps = []
    k = 0
    while k * run < 22:
        z0 = k * run
        y = k * rise
        steps.append((cam.dist((0, y, z0)), cam.face([(-2.3, y, z0), (2.3, y, z0), (2.3, y + rise, z0), (-2.3, y + rise, z0)],
                                                     "#c2b29c", centre=(0, y, z0 + 1), flat=False)
                      + cam.face([(-2.3, y + rise, z0), (2.3, y + rise, z0), (2.3, y + rise, z0 + run), (-2.3, y + rise, z0 + run)],
                                 "#ece6da", centre=(0, y, z0 + run / 2), stroke="#f6f1e8", stroke_width=1.1)))
        k += 1
    S(draw_sorted(steps))
    # the handrail up the middle
    rail = [cam.p((0, gnd(z) + rise + 0.9, z)) for z in (1.5, 21.5)]
    S(line(rail[0][0], rail[0][1], rail[1][0], rail[1][1], "#2a2b30", 2.2))
    for z in (1.5, 5, 10, 16):
        a, b = cam.p((0, gnd(z) + rise, z)), cam.p((0, gnd(z) + rise + 0.9, z))
        S(line(a[0], a[1], b[0], b[1], "#2a2b30", max(1.0, cam.scale((0, 0, z)) * 0.05)))
    S(walls_svg)
    # laundry lines, near to far drawn far first
    cloth = ["#e84a3a", "#ffffff", "#f4c84a", "#3a74c8", "#f29ab0", "#5cb88a", "#ffffff", "#2f3d5a"]
    for z in (16, 10, 5.5, 2.5):
        yl = gnd(z) + rng.uniform(3.8, 4.6)
        pts_ = []
        for i in range(21):
            t = i / 20
            x = -2.3 + 4.6 * t
            sag = 0.35 * (1 - (2 * t - 1) ** 2)
            pts_.append((x, yl - sag, z))
        S(pline([cam.p(q) for q in pts_], "#3a3a40", max(0.8, cam.scale((0, yl, z)) * 0.015)))
        t = 0.08
        while t < 0.9:
            cw = rng.uniform(0.28, 0.5)
            ch = rng.uniform(0.35, 0.7)
            x = -2.3 + 4.6 * t
            sag = 0.35 * (1 - (2 * t - 1) ** 2)
            ytop = yl - sag
            col = rng.choice(cloth)
            q = [(x, ytop, z), (x + cw, ytop - 0.02, z), (x + cw, ytop - ch, z), (x, ytop - ch, z)]
            pp = [cam.p(v) for v in q]
            S(poly(pp, cam.fogged(col, q[0], 0.7)))
            S(poly([pp[0], pp[1], (pp[1][0], pp[1][1] + (pp[2][1] - pp[1][1]) * 0.25), (pp[0][0], pp[0][1] + (pp[3][1] - pp[0][1]) * 0.25)],
                   "#000", opacity=0.1))
            t += cw / 4.6 + rng.uniform(0.03, 0.08)
    S(rect(0, 0, w, h, S.lin([(0, "#000", 0), (0.8, "#000", 0), (1, "#1a1530", 0.25)])))
    return S.html()


def calcada_waves(cam, x0, x1, z0, z1, step=0.9, amp=0.35, col="#2b2b30", wl=2.4):
    out = []
    z = z0
    while z < z1:
        p3 = [(x, 0.001, z + amp * math.sin(x / wl * 6.283)) for x in [x0 + (x1 - x0) * i / 60 for i in range(61)]]
        s = cam.scale((0, 0, z))
        out.append(pline([cam.p(q) for q in p3], cam.fogged(col, (0, 0, z)), max(0.4, s * 0.07), stroke_linejoin="round"))
        z += step
    return "".join(out)


def journal_1(p):
    """A café table on a Lisbon square in low autumn sun; wave-pattern pavement, turning trees."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("journal-1")
    cam = Cam((0, 1.25, 0), yaw=8, pitch=3, f=640, cx=w / 2, cy=300, light=(-0.9, 0.35, -0.1),
              shadow="#5a4a7a", shadow_k=0.42, lit="#ffd9a0", lit_k=0.35, fog="#f1d9b8", fogd=90, fogmax=0.6)
    S(sky(S, [(0, "#7fb0d8"), (1, "#f4dcb4")], 0, 300))
    S(rect(0, 240, w, h - 240, "#efe4cf"))
    items = []
    for i, x in enumerate(range(-40, 50, 11)):
        wall = rng.choice(["#efce7a", "#f2d690", "#eac46a"])
        items.append(house(cam, x, x + 11, 40, 52, 0, 16, 1.8, wall, "#c46a44", rng, win_w=0.3, win_h=0.55, floor_h=3.6,
                           cornice="#f7f1e2", win="#3a4450"))
    S(draw_sorted(items))
    S(cam.face([(-60, 0, 2), (60, 0, 2), (60, 0, 40), (-60, 0, 40)], "#efe6d4"))
    S(calcada_waves(cam, -40, 40, 3, 40, step=1.25, col="#77737a"))
    # trees: their long shadows first, then the trees
    trees_ = [(-9, 24), (-2, 30), (6, 22), (13, 28), (20, 25)]
    for tx, tz in trees_:
        b = cam.p((tx, 0, tz))
        e = cam.p((tx + 14, 0, tz + 3))
        s = cam.scale((tx, 0, tz))
        S(poly([(b[0], b[1] - s * 0.15), (e[0], e[1] - s * 2.5), (e[0] + s * 2, e[1] + s * 1.5), (b[0], b[1] + s * 0.15)],
               "#6a5a86", opacity=0.28))
    for tx, tz in sorted(trees_, key=lambda t: -t[1]):
        b = cam.p((tx, 0, tz))
        s = cam.scale((tx, 0, tz))
        S(tree(b[0], b[1], s * 8, rng, cam.fogged(rng.choice(["#d9892e", "#e0a33a", "#c8642a"]), (tx, 0, tz), 0.6),
               "#5a4034", hi="#f0b84e", lightx=-1))
    # the table in the foreground, its shadow long across the stones
    tx, ty = 560, 470
    S(poly([(tx - 30, ty + 88), (tx + 240, ty + 60), (tx + 300, ty + 110), (tx + 10, ty + 120)], "#6a5a86", opacity=0.3))
    S(rect(tx - 6, ty + 10, 12, 80, "#2d2d33"))
    S(ell(tx, ty + 92, 46, 9, "#2d2d33"))
    S(ell(tx, ty + 6, 118, 26, "#1f1f24"))
    S(ell(tx, ty, 118, 26, S.lin([(0, "#fffaf0"), (1, "#d9cfc0")], 0, 0, 1, 0)))
    S(ell(tx - 20, ty - 4, 32, 9, "#ffffff"))
    S(ell(tx - 20, ty - 5, 24, 6, "#e8e2d8"))
    S(path(f"M{tx - 34} {ty - 26} L{tx - 32} {ty - 8} Q{tx - 20} {ty - 2} {tx - 8} {ty - 8} L{tx - 6} {ty - 26} Z", "#ffffff"))
    S(ell(tx - 20, ty - 26, 14, 4, "#5a3320"))
    S(path(f"M{tx - 6} {ty - 22} q10 2 0 10", "none", stroke="#ffffff", stroke_width=3))
    S(poly([(tx + 20, ty - 2), (tx + 70, ty - 8), (tx + 76, ty + 4), (tx + 26, ty + 9)], "#f6f1e6"))
    # a chair back at left
    for cxp in (140,):
        S(path(f"M{cxp} 600 L{cxp + 6} 420 Q{cxp + 60} 400 {cxp + 116} 420 L{cxp + 122} 600", "none", stroke="#26262c", stroke_width=6))
        S(path(f"M{cxp + 10} 450 Q{cxp + 60} 432 {cxp + 110} 450", "none", stroke="#26262c", stroke_width=4))
    S(rect(0, 0, w, h, S.lin([(0, "#ffcf80", 0.18), (0.5, "#ffcf80", 0)], 0, 0, 1, 0)))
    return S.html()


def loaves(rng, x0, x1, y, scale=1.0):
    out = []
    x = x0 + 6
    while x < x1 - 30 * scale:
        kind = rng.random()
        c = rng.choice(["#b8672c", "#c9803e", "#a65a27", "#d49350"])
        if kind < 0.45:
            r = rng.uniform(18, 24) * scale
            out.append(ell(x + r, y - r * 0.55, r, r * 0.62, c))
            out.append(ell(x + r * 0.8, y - r * 0.8, r * 0.55, r * 0.25, light(c, 0.3), opacity=0.6))
            out.append(path(f"M{n(x + r * 0.5)} {n(y - r * 0.9)} q{n(r * 0.5)} {n(-r * 0.2)} {n(r)} 0", "none",
                            stroke=light(c, 0.55), stroke_width=2))
            x += r * 2 + 6
        elif kind < 0.8:
            L = rng.uniform(56, 80) * scale
            out.append(rect(x, y - 14 * scale, L, 14 * scale, c, rx=7 * scale))
            for i in range(3):
                out.append(line(x + L * (0.2 + i * 0.25), y - 11 * scale, x + L * (0.3 + i * 0.25), y - 5 * scale,
                                light(c, 0.5), 2))
            x += L + 8
        else:
            r = 12 * scale
            out.append(path(f"M{n(x)} {n(y)} Q{n(x + r)} {n(y - r * 2)} {n(x + r * 2.4)} {n(y)} Q{n(x + r * 1.2)} {n(y - r * 0.7)} {n(x)} {n(y)} Z", "#d99a4a"))
            x += r * 2.6 + 6
    return "".join(out)


def ig_save_3(p):
    """A bakery window at six: warm inside, the street still blue."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-save-3")
    S(rect(0, 0, w, h, S.lin([(0, "#3a4a78"), (1, "#26325a")])))
    # upper storey: dark windows, one lit
    for i, x in enumerate((70, 270, 470)):
        lit = i == 2
        S(rect(x - 8, 40, 116, 150, "#4a5a88"))
        S(rect(x, 48, 100, 136, "#ffcf8a" if lit else "#1c2440"))
        if lit:
            S(glow(S, x + 50, 110, 120, "#ffc070", 0.25))
        S(rect(x + 48, 48, 4, 136, "#4a5a88"))
    # awning
    S(rect(20, 250, w - 40, 36, "#1f4a3e"))
    for i in range(16):
        x = 20 + i * (w - 40) / 16
        S(path(f"M{n(x)} 286 q{n((w - 40) / 32)} 16 {n((w - 40) / 16)} 0 Z", "#1f4a3e"))
    S(rect(20, 250, w - 40, 6, "#2d6a58"))
    # shopfront frame
    S(rect(20, 300, w - 40, 420, "#17332c"))
    wx, wy, ww_, wh_ = 44, 322, 380, 330
    inside = S.lin([(0, "#ffd89a"), (0.6, "#f4a860"), (1, "#c9733a")])
    S(rect(wx, wy, ww_, wh_, inside))
    S(glow(S, wx + ww_ / 2, wy + 40, 220, "#fff2cc", 0.5))
    S(line(wx + ww_ / 2, wy, wx + ww_ / 2, wy + 40, "#3a2a20", 1.5))
    S(path(f"M{wx + ww_ / 2 - 26} {wy + 58} Q{wx + ww_ / 2} {wy + 30} {wx + ww_ / 2 + 26} {wy + 58} Z", "#2b2b30"))
    S(ell(wx + ww_ / 2, wy + 58, 16, 5, "#fffbe8"))
    for sy_ in (wy + 140, wy + 222, wy + 300):
        S(rect(wx + 10, sy_, ww_ - 20, 7, "#8a5a36"))
        S(rect(wx + 10, sy_ + 7, ww_ - 20, 8, "#000", opacity=0.12))
        S(loaves(rng, wx + 10, wx + ww_ - 10, sy_, 1.3))
    S(poly([(wx + 40, wy), (wx + 120, wy), (wx + 20, wy + wh_), (wx - 60, wy + wh_)], "#ffffff", opacity=0.08))
    # the door
    dx = wx + ww_ + 24
    S(rect(dx, wy, 150, 370, "#0f2520"))
    S(rect(dx + 14, wy + 14, 122, 200, S.lin([(0, "#ffd08a"), (1, "#d88a4a")])))
    S(circ(dx + 124, wy + 250, 5, "#d8b56a"))
    # step, pavement, the light spilling out
    S(rect(0, 720, w, 80, "#2b3558"))
    S(rect(20, 716, w - 40, 10, "#3c4870"))
    S(poly([(wx, 726), (wx + ww_, 726), (wx + ww_ + 90, h), (wx - 70, h)], "#ffb866", opacity=0.3))
    S(poly([(dx + 14, 726), (dx + 136, 726), (dx + 170, h), (dx - 10, h)], "#ffb866", opacity=0.22))
    # plant by the door
    S(rect(w - 60, 660, 40, 60, "#6a4a3a"))
    S(blob(w - 40, 640, 34, rng, "#2f5a44"))
    S(blob(w - 50, 628, 18, rng, "#3f7258"))
    S(rect(0, 0, w, h, S.lin([(0, "#f6b4a8", 0.18), (0.25, "#f6b4a8", 0)])))
    return S.html()


def x_photo_0(p):
    """A Berlin canal at dusk: a brick bridge of three arches, lamps just coming on."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("x-photo-0")
    hy = 300
    S(sky(S, [(0, "#232a58"), (0.45, "#5f4f86"), (0.8, "#d4808a"), (1, "#f2a878")], 0, hy))
    S(glow(S, 520, hy - 10, 300, "#ffb57a", 0.35))
    # far buildings, flat-roofed, a few windows lit
    x = -10
    while x < w:
        bw = rng.uniform(50, 110)
        bh = rng.uniform(70, 150)
        S(rect(x, hy - bh, bw, bh + 2, "#3a3558"))
        for r_ in range(int(bh / 18)):
            for c_ in range(int(bw / 16)):
                if rng.random() < 0.18:
                    S(rect(x + 6 + c_ * 16, hy - bh + 10 + r_ * 18, 6, 8, rng.choice(["#ffcf7a", "#ffe0a8"]), opacity=0.9))
        x += bw
    # trees along both banks
    for i in range(14):
        tx = rng.uniform(-20, w + 20)
        if 180 < tx < 620:
            continue
        S(blob(tx, hy - rng.uniform(20, 50), rng.uniform(30, 55), rng, "#1f2440"))
    # water with the sky in it
    S(rect(0, hy, w, h - hy, S.lin([(0, "#e39a7e"), (0.25, "#8a5f86"), (1, "#1c2448")])))
    # quays converging
    S(poly([(0, hy + 10), (190, hy + 4), (120, h), (0, h)], "#2b2a44"))
    S(poly([(w, hy + 10), (610, hy + 4), (690, h), (w, h)], "#2b2a44"))
    S(poly([(190, hy + 4), (196, hy + 4), (130, h), (120, h)], "#4a4468"))
    S(poly([(604, hy + 4), (610, hy + 4), (690, h), (680, h)], "#4a4468"))
    # the bridge
    top, deck, base = 238, 262, 338
    brick = S.lin([(0, "#8a4a3a"), (1, "#5a2e2a")])
    arches = [(160, 90), (400, 110), (640, 90)]
    d = f"M-10 {top} L{w + 10} {top} L{w + 10} {base} "
    for ax, aw in reversed(arches):
        d += f"L{ax + aw} {base} L{ax + aw} {deck + 40} A{aw} {aw * 0.62} 0 0 0 {ax - aw} {deck + 40} L{ax - aw} {base} "
    d += f"L-10 {base} Z"
    S(path(d, brick))
    # its reflection: arches close into ovals
    rd = f"M-10 {base} L{w + 10} {base} L{w + 10} {base + 40} "
    for ax, aw in reversed(arches):
        rd += f"L{ax + aw} {base + 40} L{ax + aw} {base + 18} A{aw} {aw * 0.5} 0 0 1 {ax - aw} {base + 18} L{ax - aw} {base + 40} "
    rd += f"L-10 {base + 40} Z"
    S(path(rd, "#3a2440", opacity=0.75))
    for i in range(10):
        yy = base + 44 + i * 9
        S(rect(rng.uniform(-50, 200), yy, rng.uniform(200, 500), 2, "#f0b08a", opacity=0.18))
    S(rect(-10, top - 8, w + 20, 10, "#6a3a30"))
    for i in range(40):
        S(rect(i * 21, top - 22, 3, 14, "#2a2230"))
    S(rect(-10, top - 24, w + 20, 3, "#2a2230"))
    for ax, aw in arches:
        S(path(f"M{ax - aw} {deck + 40} A{aw} {aw * 0.62} 0 0 1 {ax + aw} {deck + 40}", "none", stroke="#c07a5a",
               stroke_width=5, opacity=0.5))
    # lamps on the parapet
    for lx in (40, 280, 520, 760):
        S(lamp_post(lx, top - 8, 70, "#1e1a28", "#fff0c8", "#ffc877", S, glow_r=60))
        S(rect(lx - 3, base + 10, 6, 70, "#ffcf80", opacity=0.3, rx=3))
    # a moored boat along the left quay
    S(path(f"M20 {hy + 120} L150 {hy + 110} L140 {hy + 128} L30 {hy + 140} Z", "#1c1a2c"))
    S(rect(50, hy + 96, 60, 18, "#26233a"))
    S(rect(58, hy + 100, 10, 6, "#ffcf7a", opacity=0.8))
    S(water_glints(rng, 150, 650, base + 40, h, "#f6c09a", 40, 0.3, 50))
    return S.html()


def bicycle(frame="#3fb8a0", tyre="#1e1e22", metal="#c9ccd2", saddle="#6a4028", basket="#b0824a", mono=None,
            spokes=True, fender=None, chain=False):
    """A city bike in its own frame: rear hub at (0, 0), front hub at (290, 0), wheels r=88, facing right."""
    def c(col):
        return mono or col
    R = 88
    out = []
    for hx_ in (0, 290):
        out.append(circ(hx_, 0, R, "none", stroke=c(tyre), stroke_width=9))
        out.append(circ(hx_, 0, R - 7, "none", stroke=c(metal), stroke_width=2.5))
        if spokes and not mono:
            for i in range(12):
                a = i / 12 * 6.283
                out.append(line(hx_, 0, hx_ + math.cos(a) * (R - 8), math.sin(a) * (R - 8), metal, 0.8, opacity=0.7))
        out.append(circ(hx_, 0, 6, c(metal)))
        if fender:
            out.append(path(f"M{hx_ - R - 8} {0} A{R + 8} {R + 8} 0 0 1 {hx_ + (R + 8) * 0.7} {-(R + 8) * 0.7}", "none",
                            stroke=c(fender), stroke_width=6))
    fw = 8
    tubes = [((0, 0), (105, 12)), ((0, 0), (80, -150)), ((105, 12), (80, -150)), ((80, -140), (250, -150)),
             ((105, 12), (258, -118)), ((250, -150), (262, -110)), ((262, -110), (290, 0))]
    for (a, b) in tubes:
        out.append(line(a[0], a[1], b[0], b[1], c(frame), fw, stroke_linecap="round"))
    if not mono:
        for (a, b) in tubes[:5]:
            out.append(line(a[0], a[1] - 2, b[0], b[1] - 2, "#ffffff", 1.6, opacity=0.35, stroke_linecap="round"))
    out.append(line(80, -150, 72, -180, c(metal), 5))
    out.append(path("M44 -186 Q70 -196 102 -186 Q96 -176 70 -178 Q52 -178 44 -186 Z", c(saddle)))
    out.append(line(250, -150, 244, -192, c(metal), 5))
    out.append(path("M244 -192 Q232 -200 206 -196", "none", stroke=c(metal), stroke_width=5, stroke_linecap="round"))
    out.append(path("M206 -196 L196 -196", "none", stroke=c("#2a2a2e"), stroke_width=8, stroke_linecap="round"))
    out.append(circ(105, 12, 20, "none", stroke=c(metal), stroke_width=4))
    out.append(line(105, 12, 128, 50, c(metal), 5, stroke_linecap="round"))
    out.append(rect(118, 48, 22, 7, c("#2a2a2e"), rx=2))
    if chain:
        out.append(path("M105 -8 L0 -7 A7 7 0 0 0 0 7 L105 32", "none", stroke=c("#55565c"), stroke_width=3,
                        stroke_dasharray="3 2"))
    if basket:
        out.append(line(262, -140, 312, -140, c(metal), 3))
        out.append(path("M258 -186 L326 -186 L318 -138 L266 -138 Z", c(basket)))
        if not mono:
            for i in range(1, 6):
                out.append(line(258 + i * 11.3, -186, 266 + i * 8.7, -138, dark(basket, 0.25), 1.2))
            for j in range(1, 4):
                yy = -186 + j * 12
                out.append(line(258 + j * 2, yy, 326 - j * 2, yy, dark(basket, 0.25), 1.2))
    return "".join(out)


def x_photo_2(p):
    """A bicycle against a pastel wall in hard sun; its shadow thrown big across the plaster."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("x-photo-2")
    wall = "#f4c3b4"
    S(rect(0, 0, w, h, S.lin([(0, "#f7cfc2"), (1, "#eeb5a5")], 0, 0, 1, 1)))
    # a shuttered window and a drainpipe for scale
    S(rect(560, -20, 150, 190, "#f8e6dc"))
    S(rect(575, -20, 120, 176, "#34424e"))
    S(rect(540, -20, 36, 186, "#4f8a74"))
    S(rect(694, -20, 36, 186, "#4f8a74"))
    for i in range(12):
        S(line(540, i * 15, 576, i * 15, "#3c6e5c", 2))
        S(line(694, i * 15, 730, i * 15, "#3c6e5c", 2))
    S(rect(556, 166, 158, 12, "#f9ece4"))
    S(poly([(556, 178), (714, 178), (760, 230), (602, 230)], "#b86f68", opacity=0.3))
    S(rect(40, 0, 14, 470, "#e2a898"))
    S(rect(36, 120, 22, 8, "#cf9384"))
    S(rect(36, 330, 22, 8, "#cf9384"))
    S(poly([(54, 0), (68, 0), (100, 470), (86, 470)], "#b86f68", opacity=0.25))
    # baseboard and pavement
    S(rect(0, 470, w, 26, "#dba194"))
    S(rect(0, 496, w, h - 496, "#d9d3cb"))
    for i in range(9):
        S(line(0, 520 + i * 12, w, 520 + i * 12, "#c2bbb2", 1.2, opacity=0.6))
    for i in range(20):
        x = i * 46 + (i % 2) * 20
        S(line(x, 496, x - 30, h, "#c2bbb2", 1.2, opacity=0.5))
    # the bike's shadow: the same bike, sheared up and to the right
    bx, by = 190, 405
    c_, d_ = -0.62, 0.92
    S(g(bicycle(mono="#b8736c", spokes=False, basket="#b8736c"),
        transform=f"matrix(1 0 {c_} {d_} {bx + 34 - c_ * 88} {490 - d_ * 88})", opacity=0.6))
    S(poly([(bx - 90, 496), (bx + 330, 496), (bx + 360, 470), (bx - 40, 470)], "#b8736c", opacity=0.3))
    S(g(bicycle(frame="#3fae9a", fender="#e9e6de"), transform=f"translate({bx} {by}) rotate(-3)"))
    return S.html()


def tt_save_2(p):
    """A bike up on a repair stand in a garage, chain off, tools laid out, one warm lamp."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("tt-save-2")
    S(rect(0, 0, w, h, S.lin([(0, "#3a4650"), (1, "#2a333b")])))
    for i in range(9):
        S(line(0, 60 + i * 64, w, 60 + i * 64, "#2c363f", 2, opacity=0.6))
    # window high on the wall, and the light it throws
    S(rect(40, 70, 170, 120, "#f4e2b8"))
    S(rect(40, 70, 170, 120, S.lin([(0, "#fff6da"), (1, "#f0c98a")])))
    S(line(125, 70, 125, 190, "#3a4650", 5))
    S(line(40, 130, 210, 130, "#3a4650", 5))
    S(poly([(40, 190), (210, 190), (420, 760), (140, 800)], "#ffd79a", opacity=0.12))
    # shelf with tins
    S(rect(250, 150, 190, 8, "#8a6040"))
    for i, col in enumerate(("#c9523a", "#e2b04a", "#4a7aa8", "#9aa3a8")):
        S(rect(262 + i * 44, 104, 34, 46, col, rx=3))
        S(rect(262 + i * 44, 104, 34, 6, dark(col, 0.25), rx=2))
    # hanging bulb
    S(line(330, 0, 330, 250, "#1a1a1e", 1.5))
    S(glow(S, 330, 262, 190, "#ffcf80", 0.35))
    S(circ(330, 262, 11, "#fff4cf"))
    # floor
    S(rect(0, 650, w, h - 650, S.lin([(0, "#56585a"), (1, "#3c3e40")])))
    S(ell(260, 700, 200, 40, "#ffcf80", opacity=0.12))
    # the stand: tripod, mast, clamp arm to the seat post
    S(line(250, 690, 170, 780, "#26262a", 7, stroke_linecap="round"))
    S(line(250, 690, 330, 780, "#26262a", 7, stroke_linecap="round"))
    S(line(250, 690, 262, 770, "#1e1e22", 6, stroke_linecap="round"))
    S(line(250, 690, 250, 420, "#303036", 9))
    S(line(250, 430, 196, 408, "#303036", 8, stroke_linecap="round"))
    S(rect(184, 396, 26, 24, "#c43a2a", rx=4))
    # the bike on it: scaled to the portrait, rear wheel off the floor
    S(g(bicycle(frame="#d9642e", basket=None, chain=True, saddle="#2a2a2e", fender=None),
        transform="translate(52 540) scale(0.95) rotate(-4)"))
    # the chain off, draped over the top tube
    S(path("M190 405 q14 40 30 4", "none", stroke="#6a6b70", stroke_width=3, stroke_dasharray="3 2"))
    # a mat with tools laid out
    S(poly([(40, 720), (300, 712), (320, 790), (30, 800)], "#1f2a26"))
    for i, (x, y, a, L) in enumerate(((70, 740, -10, 70), (90, 765, 8, 60), (170, 736, 4, 50))):
        t = f"rotate({a} {x} {y})"
        S(g(rect(x, y - 4, L, 8, "#b9bec5", rx=3) + circ(x, y, 9, "#b9bec5") + circ(x, y, 4, "#1f2a26")
            + circ(x + L, y, 7, "#b9bec5"), transform=t))
    S(path("M220 760 q30 -20 60 0 q-30 20 -60 0 Z", "none", stroke="#6a6b70", stroke_width=3, stroke_dasharray="3 2"))
    S(rect(370, 560, 16, 190, "#c43a2a", rx=6))
    S(rect(356, 744, 44, 10, "#1a1a1e", rx=3))
    S(circ(378, 552, 12, "#2a2a2e"))
    S(path("M378 562 q40 40 10 110", "none", stroke="#1a1a1e", stroke_width=3))
    S(rect(0, 0, w, h, S.rad([(0, "#000", 0), (0.7, "#000", 0.05), (1, "#000", 0.45)], 0.55, 0.45, 0.75)))
    return S.html()


def canal_tree(cam, rng, x, z, H, leaf, bark="#8a8a7a"):
    b = cam.p((x, 0, z))
    s = cam.scale((x, 0, z))
    return tree(b[0], b[1], H * s, rng, cam.fogged(leaf, (x, 0, z)), cam.fogged(bark, (x, 0, z)),
                hi=cam.fogged(light(leaf, 0.25), (x, 0, z)), spread=1.25)


def dayone_0(p):
    """A Berlin canal path at first light: plane trees, still water, mist taking the far end."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("dayone-0")
    cam = Cam((0, 1.7, 0), yaw=-8, pitch=0, f=560, cx=w / 2, cy=300, fog="#e6e4da", fogd=38, fogmax=0.96)
    S(sky(S, [(0, "#cfd6d8"), (1, "#ece8dc")], 0, 310))
    S(glow(S, 330, 170, 260, "#fff6dc", 0.7))
    S(circ(330, 170, 34, "#fbf6e8", opacity=0.9))
    far = 400
    S(rect(0, 298, w, h - 298, "#dcdccf"))
    # water, left
    wq = [cam.p(q) for q in ((-18, -0.9, 1), (-3, -0.9, 1), (-3, -0.9, far), (-18, -0.9, far))]
    S(poly(wq, S.lin([(0, "#4f6a6c"), (0.75, "#8fa4a0"), (1, "#dcdcd2")], 0, 1, 0, 0)))
    # quay edge, path, verge
    S(cam.face([(-3, -0.9, 1), (-3, 0, 1), (-3, 0, far), (-3, -0.9, far)], "#8f8c84", flat=True))
    S(cam.face([(-3.4, 0, 1), (-2.4, 0, 1), (-2.4, 0, far), (-3.4, 0, far)], "#b9b5aa", flat=True))
    S(cam.face([(-2.4, 0, 1), (2.2, 0, 1), (2.2, 0, far), (-2.4, 0, far)], "#d6cdb8", flat=True))
    S(cam.face([(2.2, 0, 1), (9, 0, 1), (9, 0, far), (2.2, 0, far)], "#8fa27a", flat=True))
    S(rect(0, 296, w, 30, "#e6e4da", opacity=0.7))
    # far bank: faint trees and buildings in mist
    for z in range(20, 200, 7):
        x = -20 - rng.uniform(0, 3)
        S(canal_tree(cam, rng, x, z, rng.uniform(13, 17), "#5f7458"))
    # railing posts along the quay
    for z in range(2, 120, 3):
        a, b = cam.p((-3.1, 0, z)), cam.p((-3.1, 1.0, z))
        S(line(a[0], a[1], b[0], b[1], cam.fogged("#3a3d3a", (-3, 0, z)), max(0.5, cam.scale((0, 0, z)) * 0.05)))
    rl = [cam.p((-3.1, 1.0, z)) for z in (2, 120)]
    S(line(rl[0][0], rl[0][1], rl[1][0], rl[1][1], "#3a3d3a", 2, opacity=0.8))
    # plane trees lining the path, far to near
    for z in list(range(130, 2, -9)):
        S(canal_tree(cam, rng, 3.4 + rng.uniform(-0.3, 0.3), z + rng.uniform(-1, 1), rng.uniform(14, 17), "#6c8a5a",
                     bark="#9a9886"))
    # reflections on the water
    for z in range(8, 120, 9):
        a = cam.p((-20, -0.9, z))
        S(rect(a[0] - 10, a[1], 20, cam.scale((0, 0, z)) * 6, "#5f7458", opacity=0.15))
    # a bench-less, walker-less path: just a lamp
    S(lamp_post(*cam.p((2.6, 0, 9)), cam.scale((0, 0, 9)) * 4.2, "#2e3230", "#f4f0e0", "#fff6dc", S, on=False))
    S(rect(0, 0, w, h, S.lin([(0, "#f4efe0", 0.35), (0.5, "#f4efe0", 0.0), (1, "#2f3a34", 0.15)])))
    return S.html()


def journal_11(p):
    """A Berlin street in the rain at evening: wet asphalt, lit shopfronts, umbrellas."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("journal-11")
    cam = Cam((-1.0, 1.7, 0), yaw=14, pitch=0, f=560, cx=w / 2, cy=290, light=(-0.3, 0.9, 0.2),
              shadow="#2a3048", shadow_k=0.5, lit="#b8c4d6", lit_k=0.1, fog="#8e98aa", fogd=60, fogmax=0.9)
    S(sky(S, [(0, "#5f6a80"), (1, "#a2aabb")], 0, 300))
    far = 260
    S(rect(0, 280, w, h - 280, "#2a3040"))
    S(cam.face([(-5, 0, 1), (5, 0, 1), (5, 0, far), (-5, 0, far)], "#3a4256", flat=True))
    S(cam.face([(5, 0.15, 1), (8, 0.15, 1), (8, 0.15, far), (5, 0.15, far)], "#4a5266", flat=True))
    S(cam.face([(-8, 0.15, 1), (-5, 0.15, 1), (-5, 0.15, far), (-8, 0.15, far)], "#4a5266", flat=True))
    # the sky's light lying on the wet road
    road = [cam.p(q) for q in ((-5, 0, 6), (5, 0, 6), (5, 0, far), (-5, 0, far))]
    S(poly(road, S.lin([(0, "#aab3c4", 0.0), (0.7, "#aab3c4", 0.25), (1, "#c3cad6", 0.6)], 0, 1, 0, 0)))
    items = []
    walls = ["#c9b79a", "#b7a898", "#d6c7a8", "#a8b0a8", "#c4a898", "#bfb9ae"]
    shops = []
    for x0, x1 in ((-20, -8), (8, 20)):
        z = 1
        while z < far:
            L = rng.uniform(14, 22)
            items.append(house(cam, x0, x1, z, z + L, 0, rng.uniform(17, 21), 0, rng.choice(walls), "#555", rng,
                               win_w=0.28, win_h=0.55, floor_h=3.6, lit_windows=0.22, lit_col="#ffcf85",
                               cornice="#d8d0c0", frame="#e2dccf"))
            xf = x1 if x0 < 0 else x0
            shops.append((xf, z + 1.5, z + L - 1.5))
            z += L
    S(draw_sorted(items))
    # lit shopfronts at street level, and their reflections running down the wet road
    streaks = []
    for xf, za, zb in shops:
        if cam.depth((xf, 0, za)) < 1:
            continue
        col = rng.choice(["#ffc878", "#ffe0a8", "#ffb56a"])
        z = za
        while z + 1.2 < zb:
            z1 = min(zb, z + rng.uniform(2.2, 3.4))
            q = [(xf, 0.4, z), (xf, 0.4, z1), (xf, 3.0, z1), (xf, 3.0, z)]
            S(poly([cam.p(v) for v in q], cam.fogged(col, q[0], 0.45)))
            inward = -0.6 if xf > 0 else 0.6
            r0, r1 = cam.p((xf + inward, 0, z)), cam.p((xf + inward * 2.5, 0, z1))
            sc = cam.scale((xf, 0, (z + z1) / 2))
            streaks.append(rect(min(r0[0], r1[0]), r0[1], abs(r1[0] - r0[0]) * 0.7 + 1, sc * 1.8, col, opacity=0.3))
            z = z1 + 0.5
    S(g(streaks, filter=S.blur(1.5, 5)))
    # car tail lights far up the street
    for zc in (70, 120):
        for dx in (-0.7, 0.7):
            a = cam.p((-2.2 + dx, 0.8, zc))
            S(circ(a[0], a[1], 2.2, "#ff4a3a"))
            S(rect(a[0] - 1.2, a[1] + 2, 2.4, 26, "#ff4a3a", opacity=0.3))
    # people with umbrellas on the right pavement
    brolly = ["#c8352c", "#f2b632", "#1f2e4a", "#2f6a5a", "#e8e4dc"]
    for i, (px, pz) in enumerate(((6.4, 30), (5.6, 20), (6.8, 13), (-6.0, 24), (6.0, 7.5))):
        b = cam.p((px, 0.15, pz))
        sc = cam.scale((px, 0.15, pz))
        S(rect(b[0] - sc * 0.3, b[1], sc * 0.6, sc * 1.2, "#20263a", opacity=0.25))
        S(person(b[0], b[1], sc * 1.75, "#1c2030"))
        S(umbrella(b[0] + sc * 0.08, b[1] - sc * 1.95, sc * 0.62, brolly[i % len(brolly)], hi="#ffffff"))
    S(rain(S, rng, 420, angle=0.12, length=(16, 34), col="#dfe6f2", op=0.35, sw=1.0))
    S(rect(0, 0, w, h, S.lin([(0, "#1a2030", 0.1), (0.5, "#1a2030", 0), (1, "#10141f", 0.35)])))
    return S.html()


def dayone_18(p):
    """An unfamiliar residential street at dusk: gardens, hedges, windows lighting up."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("dayone-18")
    cam = Cam((0.5, 1.7, 0), yaw=-6, pitch=-1, f=560, cx=w / 2, cy=320, light=(0.6, 0.35, 1),
              shadow="#20284a", shadow_k=0.72, lit="#e89a8a", lit_k=0.3, fog="#6a6f96", fogd=90, fogmax=0.7)
    S(sky(S, [(0, "#1e3860"), (0.5, "#4a6a9a"), (0.82, "#c88c98"), (1, "#f0b48c")], 0, 330))
    S(circ(640, 70, 1.6, "#ffffff"))
    S(circ(180, 40, 1.2, "#ffffff", opacity=0.8))

    def cx_(z):
        return 0.0028 * z * z - 0.02 * z
    far = 150
    S(rect(0, 300, w, h - 300, "#262b44"))
    zs = [1 + i * 2 for i in range(int(far / 2))]
    road_l = [cam.p((cx_(z) - 3.2, 0, z)) for z in zs]
    road_r = [cam.p((cx_(z) + 3.2, 0, z)) for z in zs]
    S(poly(road_l + road_r[::-1], "#3a3f5a"))
    kerb_l = [cam.p((cx_(z) - 5.2, 0.1, z)) for z in zs]
    kerb_r = [cam.p((cx_(z) + 5.2, 0.1, z)) for z in zs]
    S(poly(kerb_l + road_l[::-1], "#4a4f6a"))
    S(poly(road_r + kerb_r[::-1], "#4a4f6a"))
    centre = [cam.p((cx_(z), 0.01, z)) for z in zs[2:]]
    S(pline(centre, "#8a8fa8", 1.2, stroke_dasharray="10 12", opacity=0.6))
    items = []
    for side in (-1, 1):
        z = 3
        while z < far:
            L = rng.uniform(8, 11)
            xc = cx_(z + L / 2) + side * rng.uniform(13, 15)
            wall = rng.choice(["#c9b8a6", "#b8a898", "#d6c2a8", "#a8a8b0", "#c4a48c"])
            items.append(house(cam, xc - 4, xc + 4, z, z + L - 2.5, 0, 5.8, 3.4, wall, "#5a4a52", rng, win_w=0.3,
                               win_h=0.5, floor_h=2.9, lit_windows=0.45, lit_col="#ffc877", frame="#d8d2c8"))
            # hedge along the front garden
            hx0 = cx_(z) + side * 6.5
            items.append(prism(cam, [(hx0 - 0.5, z), (hx0 + 0.5, z), (hx0 + 0.5, z + L - 1), (hx0 - 0.5, z + L - 1)],
                               0, 1.2, "#2f4a3e"))
            z += L
    S(draw_sorted(items))
    # street lamps, one on each side, and their pools of light
    for zl, sx in ((12, 1), (28, -1), (48, 1), (75, -1)):
        x = cx_(zl) + sx * 5.6
        b = cam.p((x, 0.1, zl))
        sc = cam.scale((x, 0, zl))
        S(ell(b[0] - sx * sc * 1.5, b[1] + sc * 0.2, sc * 3.2, sc * 0.7, "#ffcf80", opacity=0.18))
        S(lamp_post(b[0], b[1], sc * 5, "#1a1e30", "#fff0c8", "#ffc877", S, glow_r=sc * 2.6, style="round"))
    # trees in silhouette against the sky, and a parked car
    for tx, tz in ((-9, 20), (10, 36), (-8, 60), (13, 90)):
        b = cam.p((cx_(tz) + tx, 0, tz))
        sc = cam.scale((0, 0, tz))
        S(tree(b[0], b[1], sc * 11, rng, cam.fogged("#1f2a3a", (tx, 0, tz), 0.5), "#1a1f2a", hi="#2a3448"))
    b = cam.p((cx_(18) + 4.2, 0, 18))
    sc = cam.scale((0, 0, 18))
    S(path(f"M{n(b[0] - sc * 1)} {n(b[1])} l0 {n(-sc * 0.9)} q{n(sc * 0.4)} {n(-sc * 0.1)} {n(sc * 0.8)} {n(-sc * 0.6)} "
           f"l{n(sc * 1.5)} 0 q{n(sc * 0.5)} {n(sc * 0.4)} {n(sc * 0.9)} {n(sc * 0.6)} l0 {n(sc * 0.9)} Z", "#141828"))
    S(rect(0, 0, w, h, S.lin([(0, "#000", 0), (0.7, "#000", 0), (1, "#0a0c18", 0.4)])))
    return S.html()


def snap_3(p):
    """A snowy street at night: lamps, soft falling snow, one line of footprints."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("snap-3")
    cam = Cam((0, 1.6, 0), yaw=3, pitch=4, f=420, cx=w / 2, cy=330, light=(0.2, 0.5, -1),
              shadow="#161c34", shadow_k=0.75, lit="#ffcf90", lit_k=0.3, fog="#2c3558", fogd=70, fogmax=0.85)
    S(sky(S, [(0, "#0b1024"), (0.7, "#1f2748"), (1, "#3a3a5a")], 0, 320))
    far = 160
    S(rect(0, 290, w, h - 290, "#9aa6c4"))
    S(cam.face([(-9, 0, 0.5), (9, 0, 0.5), (9, 0, far), (-9, 0, far)], "#dfe6f4", flat=True))
    items = []
    for x0, x1 in ((-18, -6), (6, 18)):
        z = 2
        while z < far:
            L = rng.uniform(8, 13)
            items.append(house(cam, x0, x1, z, z + L, 0, rng.uniform(8, 12), 3.2, rng.choice(["#4a4a6a", "#5a4a58", "#3f4a66"]),
                               "#eef2fa", rng, win_w=0.3, floor_h=3.2, lit_windows=0.4, lit_col="#ffc877", tiles=False))
            z += L
    S(draw_sorted(items))
    # lamps down the left side, pools of warm light on the snow
    for zl in (7, 19, 34, 56, 90):
        b = cam.p((-4.8, 0, zl))
        sc = cam.scale((-4.8, 0, zl))
        pool = cam.p((-3.8, 0, zl))
        S(ell(pool[0], pool[1], sc * 3.6, sc * 0.9, "#ffd08a", opacity=0.35))
        S(lamp_post(b[0], b[1], sc * 4.6, "#141828", "#fff0c8", "#ffc877", S, glow_r=sc * 3))
    # footprints: one walker, heading away
    z = 1.2
    k = 0
    while z < 60:
        x = 0.6 * math.sin(z / 9) + (0.16 if k % 2 else -0.16)
        a = cam.p((x, 0.01, z))
        sc = cam.scale((x, 0, z))
        S(ell(a[0], a[1], sc * 0.11, sc * 0.06, "#6f7ca4", opacity=0.9))
        z += 0.72
        k += 1
    # snow falling: small far flakes, a few big soft ones near
    for _ in range(260):
        S(circ(rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.8, 2.2), "#ffffff", opacity=round(rng.uniform(0.4, 0.9), 2)))
    bl = S.blur(2.5)
    for _ in range(22):
        S(circ(rng.uniform(0, w), rng.uniform(0, h), rng.uniform(4, 8), "#ffffff", opacity=0.6, filter=bl))
    S(rect(0, 0, w, h, S.rad([(0, "#000", 0), (0.7, "#000", 0.1), (1, "#05060f", 0.5)], 0.5, 0.45, 0.75)))
    return S.html()


def pylon(x, yb, h, col, sw=1.6):
    """A lattice transmission tower, base-centre (x, yb)."""
    bw = h * 0.22
    tw = h * 0.05
    out = []
    L = [(x - bw, yb), (x - tw, yb - h * 0.78), (x - tw * 0.6, yb - h)]
    R = [(x + bw, yb), (x + tw, yb - h * 0.78), (x + tw * 0.6, yb - h)]
    out.append(pline(L, col, sw * 1.4))
    out.append(pline(R, col, sw * 1.4))
    k = 7
    for i in range(k):
        t0, t1 = i / k * 0.78, (i + 1) / k * 0.78
        def at(side, t):
            return (x + side * (bw + (tw - bw) * t / 0.78), yb - h * t)
        a, b, c, d = at(-1, t0), at(1, t0), at(-1, t1), at(1, t1)
        out.append(line(a[0], a[1], d[0], d[1], col, sw * 0.7))
        out.append(line(b[0], b[1], c[0], c[1], col, sw * 0.7))
        out.append(line(c[0], c[1], d[0], d[1], col, sw * 0.7))
    for ay, aw in ((0.78, 0.42), (0.9, 0.3)):
        y = yb - h * ay
        out.append(line(x - h * aw, y, x + h * aw, y, col, sw * 1.2))
        out.append(line(x - h * aw, y, x - tw, y - h * 0.05, col, sw * 0.7))
        out.append(line(x + h * aw, y, x + tw, y - h * 0.05, col, sw * 0.7))
    return "".join(out)


def x_video_0(p):
    """From a train window: fields and pylons streaking past, the near bank a blur."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("x-video-0")
    view = []
    hy = 190
    view.append(sky(S, [(0, "#6fa2d4"), (1, "#e8e4cf")], 0, hy + 10))
    view.append(cloud(S, 120, 90, 180, rng, shade="#d2dbe6"))
    view.append(cloud(S, 520, 60, 130, rng, shade="#d2dbe6"))
    view.append(ridge(S, rng, hy - 16, 10, "#8fa6b8", freq=1.3))
    view.append(ridge(S, rng, hy - 2, 7, "#9cad8a", freq=2.2))
    bands = ["#b9b26a", "#8fa35a", "#d4be72", "#7d9a52", "#c9a860", "#94aa5e"]
    y = hy + 4
    k = 0
    while y < h:
        bh = 8 + (y - hy) * 0.22
        view.append(rect(-10, y, w + 20, bh + 1, bands[k % len(bands)]))
        view.append(line(-10, y, w + 10, y, "#4f6a3a", 1 + (y - hy) * 0.02, opacity=0.6))
        y += bh
        k += 1
    # hedgerow trees along the field lines
    for _ in range(26):
        tx = rng.uniform(0, w)
        ty = rng.uniform(hy + 6, hy + 60)
        view.append(blob(tx, ty - 5, 5 + (ty - hy) * 0.12, rng, "#4a6a3a"))
    # pylons and their lines, crossing the frame
    tops = []
    for px, pb, ph, blur in ((110, 268, 150, 1.2), (470, 232, 88, 0), (720, 214, 52, 0)):
        view.append(g(pylon(px, pb, ph, "#4a5058", 1.4 + ph / 150), filter=S.blur(blur, 0) if blur else None))
        tops.append((px, pb - ph * 0.9, ph))
    for dy in (0, 0.12):
        pts_ = []
        for (x1, y1, h1), (x2, y2, h2) in zip(tops, tops[1:]):
            for i in range(11):
                t = i / 10
                pts_.append((x1 + (x2 - x1) * t, y1 + h1 * dy + (y2 - y1) * t + 16 * (1 - (2 * t - 1) ** 2)))
        view.append(pline([(-10, tops[0][1] + 30)] + pts_ + [(w + 10, tops[-1][1] + 6)], "#3a3f46", 1.1))
    # the embankment rushing past, blurred along the track
    near = []
    near.append(rect(-60, 330, w + 120, 140, "#5f7a3a"))
    for _ in range(90):
        x = rng.uniform(-40, w + 40)
        y = rng.uniform(320, 440)
        near.append(rect(x, y, rng.uniform(40, 160), rng.uniform(3, 10), rng.choice(["#86a04a", "#4a6230", "#a9b86a", "#394a26"])))
    view.append(g(near, filter=S.blur(22, 1.5)))
    view.append(rect(0, 0, w, h, S.lin([(0, "#ffffff", 0.08), (0.5, "#ffffff", 0)], 0, 0, 1, 0)))
    win = rect(70, 34, 660, 356, "#000", rx=34)
    S(rect(0, 0, w, h, S.lin([(0, "#2a2e36"), (1, "#1c1f25")])))
    S(g(view, clip_path=S.clip(win)))
    S(rect(70, 34, 660, 356, "none", rx=34, stroke="#40454e", stroke_width=10))
    S(rect(62, 26, 676, 372, "none", rx=40, stroke="#15171c", stroke_width=6))
    S(poly([(200, 34), (300, 34), (150, 390), (50, 390)], "#ffffff", opacity=0.05))
    # the ledge and a paper cup
    S(rect(0, 404, w, 46, S.lin([(0, "#4a4f58"), (1, "#2e3238")])))
    S(rect(0, 400, w, 8, "#5a606a"))
    S(path("M600 404 L604 360 L636 360 L640 404 Z", "#efe9dc"))
    S(rect(600, 354, 40, 8, "#d8d0c0", rx=2))
    S(rect(603, 374, 34, 14, "#b87a4a"))
    return S.html()


def leaf(x, y, s, col, rot):
    return ell(x, y, s, s * 0.5, col, transform=f"rotate({n(rot)} {n(x)} {n(y)})")


def ig_like_0(p):
    """A park bench under a big tree in autumn; leaves on the grass and falling."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-like-0")
    S(sky(S, [(0, "#f6d9a8"), (1, "#f2c48a")], 0, 420))
    S(glow(S, 470, 260, 380, "#fff4d8", 0.6))
    # far trees, soft
    far = []
    for i in range(14):
        far.append(blob(rng.uniform(-40, w + 40), rng.uniform(300, 380), rng.uniform(60, 110), rng,
                        rng.choice(["#e0a454", "#d88a3c", "#c9b060", "#e8b86a"])))
    S(g(far, filter=S.blur(6), opacity=0.8))
    S(rect(0, 400, w, h - 400, S.lin([(0, "#b9a45a"), (0.4, "#8f8a44"), (1, "#6a6a36")])))
    S(path("M640 430 C520 470 380 520 300 800 L460 800 C500 600 560 500 640 470 Z", "#d9c49a"))
    # the big tree at left: trunk, limbs, and a roof of leaves
    S(path("M60 800 C80 640 90 520 70 380 C60 300 40 200 10 0 L120 0 C120 160 140 300 150 400 C160 520 170 660 190 800 Z",
           "#3a2a22"))
    S(path("M150 330 C220 260 330 220 460 150", "none", stroke="#3a2a22", stroke_width=22, stroke_linecap="round"))
    S(path("M120 160 C200 120 300 90 380 40", "none", stroke="#3a2a22", stroke_width=16, stroke_linecap="round"))
    S(path("M95 700 C110 600 118 520 110 420", "none", stroke="#5a4232", stroke_width=10, opacity=0.6))
    cols = ["#d9642e", "#e8903a", "#c94a28", "#f2b24a", "#b8402a"]
    clusters = ((120, 60, 190), (330, 80, 170), (500, 40, 150), (260, 200, 120), (600, 150, 100))
    for cx, cy, r in clusters:
        S(blob(cx, cy + r * 0.1, r * 0.9, rng, "#8a3a22"))
    for layer, k in ((0.3, 0), (0.0, 1), (-0.25, 2)):
        for cx, cy, r in clusters:
            for _ in range(14):
                a = rng.uniform(0, 6.283)
                d = r * math.sqrt(rng.random()) * 0.85
                bx_, by_ = cx + math.cos(a) * d, cy + math.sin(a) * d * 0.75 + layer * r * 0.3
                c = cols[rng.randrange(len(cols))]
                c = [dark(c, 0.25), c, light(c, 0.2)][k]
                S(blob(bx_, by_, r * rng.uniform(0.14, 0.26), rng, c))
    # the bench, three-quarter view, its shadow long toward us
    bx, by = 330, 560
    S(poly([(bx - 20, by + 50), (bx + 230, by + 10), (bx + 330, by + 150), (bx + 40, by + 210)], "#4a4a2a", opacity=0.28))
    frame = "#2f4a3a"
    for lx, ly in ((bx, by + 40), (bx + 200, by + 4)):
        S(line(lx, ly, lx - 4, ly + 60, frame, 7))
        S(line(lx + 30, ly + 10, lx + 34, ly + 62, frame, 7))
        S(line(lx - 2, ly - 10, lx - 6, ly - 110, frame, 7))
    for i in range(4):
        dy = i * 9
        S(poly([(bx - 12 + i * 4, by + 30 - dy * 0.1 + i * 4), (bx + 212 + i * 4, by - 6 + i * 4),
                (bx + 214 + i * 4, by + 1 + i * 4), (bx - 10 + i * 4, by + 37 + i * 4)], rng.choice(["#8a5a34", "#9a6a3e"])))
    for i in range(4):
        S(poly([(bx - 8, by - 20 - i * 22), (bx + 206, by - 58 - i * 22), (bx + 206, by - 44 - i * 22), (bx - 8, by - 6 - i * 22)],
               rng.choice(["#8a5a34", "#9a6a3e", "#7a4e2e"])))
    # leaves: on the bench, the grass, and in the air
    for _ in range(95):
        x, y = rng.uniform(-10, w + 10), rng.uniform(430, h)
        s = 3 + (y - 430) / 40
        S(leaf(x, y, s, rng.choice(cols), rng.uniform(0, 180)))
    for _ in range(8):
        S(leaf(bx + rng.uniform(0, 200), by + rng.uniform(-4, 30), 5, rng.choice(cols), rng.uniform(0, 180)))
    for _ in range(22):
        S(leaf(rng.uniform(0, w), rng.uniform(200, 520), rng.uniform(4, 8), rng.choice(cols), rng.uniform(0, 180)))
    S(rect(0, 0, w, h, S.lin([(0, "#fff0c8", 0.12), (0.6, "#fff0c8", 0), (1, "#2a1a10", 0.2)])))
    return S.html()


def boat(x, y, L, hull, stripe, inside, trim="#f4f0e6", flip=False, cabin=False):
    """A small wooden fishing boat, three-quarter view from above; waterline at y."""
    s = -1 if flip else 1
    def X(u):
        return x + s * u * L
    out = []
    rim_back = (X(0.0), y - L * 0.13)
    bow = (X(1.0), y - L * 0.3)
    out.append(path(f"M{n(rim_back[0])} {n(rim_back[1])} Q{n(X(0.5))} {n(y - L * 0.08)} {n(bow[0])} {n(bow[1])} "
                    f"Q{n(X(0.93))} {n(y - L * 0.02)} {n(X(0.78))} {n(y)} L{n(X(0.1))} {n(y)} "
                    f"Q{n(X(0.0))} {n(y - L * 0.02)} {n(rim_back[0])} {n(rim_back[1])} Z", hull))
    out.append(path(f"M{n(rim_back[0])} {n(rim_back[1])} Q{n(X(0.5))} {n(y - L * 0.08)} {n(bow[0])} {n(bow[1])} "
                    f"Q{n(X(0.55))} {n(y - L * 0.22)} {n(X(0.04))} {n(y - L * 0.22)} Z", inside))
    out.append(path(f"M{n(rim_back[0])} {n(rim_back[1])} Q{n(X(0.5))} {n(y - L * 0.08)} {n(bow[0])} {n(bow[1])}", "none",
                    stroke=stripe, stroke_width=max(2, L * 0.03)))
    out.append(path(f"M{n(X(0.06))} {n(y - L * 0.06)} Q{n(X(0.5))} {n(y - L * 0.0)} {n(X(0.86))} {n(y - L * 0.12)}", "none",
                    stroke=trim, stroke_width=max(1.5, L * 0.018)))
    for u in (0.35, 0.6):
        out.append(line(X(u), y - L * 0.1, X(u + 0.05), y - L * 0.2, dark(inside, 0.25), max(1, L * 0.02)))
    if cabin:
        out.append(rect(min(X(0.12), X(0.3)), y - L * 0.36, L * 0.18, L * 0.2, trim))
        out.append(rect(min(X(0.12), X(0.3)) + L * 0.03, y - L * 0.32, L * 0.12, L * 0.06, "#3a4a5a"))
    out.append(line(X(0.2), y - L * 0.2, X(0.2), y - L * 0.55, "#3a3a3a", max(1, L * 0.012)))
    return "".join(out)


def ig_notice_0(p):
    """Small painted fishing boats moored in a harbour, still water, early morning."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("ig-notice-0")
    hy = 250
    S(sky(S, [(0, "#bcd6d8"), (0.7, "#f2dcc4"), (1, "#f6e2c6")], 0, hy + 5))
    S(glow(S, 140, hy - 40, 220, "#fff2d8", 0.6))
    # the town across the water
    S(ridge(S, rng, hy - 40, 14, "#b9b8b0", freq=1.1, bottom=hy + 2))
    for _ in range(70):
        x = rng.uniform(0, w)
        y = hy - rng.uniform(4, 40) * (0.4 + 0.6 * (1 - abs(x - 380) / 400))
        S(rect(x, y, rng.uniform(6, 12), rng.uniform(5, 9), rng.choice(["#f4f0e8", "#ece2cc", "#e8d8c8"])))
        S(rect(x - 1, y - 2, rng.uniform(7, 13), 3, rng.choice(["#c98a6a", "#b8785a"]), opacity=0.8))
    # breakwater with a small light
    S(poly([(300, hy + 6), (w, hy - 6), (w, hy + 16), (300, hy + 14)], "#8f8c86"))
    S(rect(560, hy - 50, 16, 46, "#f4f2ec"))
    S(rect(560, hy - 50, 16, 10, "#c8402e"))
    # water
    S(rect(0, hy + 2, w, h - hy, S.lin([(0, "#cfe0da"), (0.3, "#8fbcb8"), (1, "#3f7a80")])))
    boats = [(60, 380, 150, "#2f6fb0", "#f2c230", "#e9e0cc", False, False),
             (380, 350, 130, "#c8402e", "#f4f0e6", "#e0d6c2", True, False),
             (250, 470, 210, "#2f8a6a", "#f28a2e", "#efe6d2", False, True),
             (120, 640, 300, "#f4f0e6", "#2f6fb0", "#dcd0b8", False, False),
             (560, 600, 220, "#e8b83a", "#2f4a8a", "#efe6d2", True, True)]
    for bx, by, L, hull, stripe, inside, flip, cabin in boats:
        refl = g(boat(bx, by, L, hull, stripe, inside, flip=flip, cabin=cabin),
                 transform=f"translate(0 {n(2 * by)}) scale(1 -1)")
        S(g(refl, opacity=0.35, filter=S.blur(2, 4)))
    for bx, by, L, hull, stripe, inside, flip, cabin in boats:
        S(boat(bx, by, L, hull, stripe, inside, flip=flip, cabin=cabin))
        tie = bx + (-1 if flip else 1) * L * 0.02
        S(path(f"M{n(tie)} {n(by - L * 0.12)} Q{n(tie + 10)} {n(by + 30)} {n(tie - 30)} {n(by + 60)}", "none",
               stroke="#efe6d2", stroke_width=1.4, opacity=0.55))
    # ripples and a buoy
    for _ in range(60):
        x, y = rng.uniform(0, w), rng.uniform(hy + 20, h)
        S(rect(x, y, rng.uniform(10, 40) * (y / h), 1.5, "#ffffff", opacity=0.22))
    S(circ(470, 470, 10, "#f25a2e"))
    S(ell(470, 482, 16, 3, "#2f6a70", opacity=0.4))
    return S.html()


def bsky_4b(p):
    """An empty park path in the rain: puddles, wet grass, dark trees, one lamp."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("bsky-4b")
    cam = Cam((0, 1.6, 0), yaw=0, pitch=2, f=580, cx=w / 2, cy=300, fog="#aab4b2", fogd=45, fogmax=0.85)
    S(sky(S, [(0, "#8d9896"), (1, "#c3cac6")], 0, 290))
    S(rect(0, 270, w, h - 270, "#5f7454"))
    far = 120

    def px(z):
        return 2.6 * math.sin(z / 14) - 0.8
    # distant trees
    for i in range(24):
        x = rng.uniform(-60, 60)
        z = rng.uniform(40, 110)
        b = cam.p((x, 0, z))
        sc = cam.scale((x, 0, z))
        S(tree(b[0], b[1], sc * rng.uniform(10, 15), rng, cam.fogged("#3f5a44", (x, 0, z)), cam.fogged("#2a2e2a", (x, 0, z)),
               hi=cam.fogged("#56705a", (x, 0, z)), spread=1.2))
    zs = [0.8 + i * 0.8 for i in range(int(far / 0.8))]
    left = [cam.p((px(z) - 1.4, 0, z)) for z in zs]
    right = [cam.p((px(z) + 1.4, 0, z)) for z in zs]
    S(poly(left + right[::-1], "#8f9290"))
    S(poly(left + right[::-1], S.lin([(0, "#6f7472"), (0.6, "#9aa09e"), (1, "#b9bfbc")], 0, 1, 0, 0)))
    # puddles holding the sky
    for zc, off, rr in ((4, 0.2, 0.9), (9, -0.5, 0.7), (15, 0.4, 0.8), (26, 0, 0.9)):
        pts_ = [cam.p((px(zc) + off + math.cos(a) * rr, 0.01, zc + math.sin(a) * rr * 1.6)) for a in
                [i / 16 * 6.283 for i in range(16)]]
        S(path(smooth(pts_, closed=True), "#c6ccca"))
        c = cam.p((px(zc) + off, 0.01, zc))
        sc = cam.scale((0, 0, zc))
        for k in range(3):
            S(ell(c[0] + rng.uniform(-sc * 0.4, sc * 0.4), c[1] + rng.uniform(-sc * 0.1, sc * 0.1), sc * 0.14 * (k + 1),
                  sc * 0.03 * (k + 1), "none", stroke="#8a908e", stroke_width=1))
    # near trees framing, and a lamp
    for x, z in ((-7, 10), (6.5, 16), (-5.5, 26), (7, 34)):
        b = cam.p((x, 0, z))
        sc = cam.scale((x, 0, z))
        S(tree(b[0], b[1], sc * 12, rng, cam.fogged("#2f4a36", (x, 0, z)), "#241e1a", hi=cam.fogged("#48664e", (x, 0, z)),
               spread=1.3))
    b = cam.p((px(12) + 2.2, 0, 12))
    S(lamp_post(b[0], b[1], cam.scale((0, 0, 12)) * 4.2, "#242826", "#f4f0e0", "#fff6dc", S, on=False))
    S(rain(S, rng, 520, angle=-0.08, length=(14, 30), col="#e8eef0", op=0.38, sw=1.0))
    S(rect(0, 0, w, h, S.lin([(0, "#dfe4e2", 0.15), (0.5, "#dfe4e2", 0), (1, "#1c2420", 0.3)])))
    return S.html()


def radio_mast(x, yb, h, col, sw=1.4):
    """A tall narrow guyed lattice mast."""
    wd = max(3, h * 0.03)
    out = [line(x - wd, yb, x - wd * 0.6, yb - h, col, sw), line(x + wd, yb, x + wd * 0.6, yb - h, col, sw)]
    k = int(h / (wd * 2.4))
    for i in range(k):
        y0, y1 = yb - h * i / k, yb - h * (i + 1) / k
        out.append(line(x - wd, y0, x + wd, y1, col, sw * 0.6))
        out.append(line(x - wd, y0, x + wd, y0, col, sw * 0.6))
    for t, spread in ((0.45, 0.55), (0.8, 0.9)):
        y = yb - h * t
        for sgn in (-1, 1):
            out.append(line(x, y, x + sgn * h * spread * 0.6, yb + 6, col, 0.7, opacity=0.8))
    return "".join(out)


def nostr_0(p):
    """Radio masts on a hilltop at dusk, their red lights just visible."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("nostr-0")
    S(sky(S, [(0, "#151c42"), (0.4, "#3f3f78"), (0.7, "#b0607a"), (0.88, "#ec8a5a"), (1, "#f6b672")], 0, 470))
    for _ in range(60):
        S(circ(rng.uniform(0, w), rng.uniform(0, 200), rng.uniform(0.5, 1.4), "#ffffff", opacity=round(rng.uniform(0.2, 0.8), 2)))
    S(path("M660 90 a26 26 0 1 0 22 40 a20 20 0 1 1 -22 -40 Z", "#fdf1d6"))
    S(ridge(S, rng, 430, 18, "#6a4a72", freq=1.6))
    S(ridge(S, rng, 470, 14, "#4a3558", freq=2.2))
    # the hill
    S(path(f"M-10 600 L-10 430 C120 400 240 330 380 320 C520 310 640 370 810 420 L810 600 Z", "#1c1830"))
    for x, h_, blink in ((330, 280, 3), (430, 220, 2), (520, 150, 2)):
        yb = 322 + abs(x - 380) * 0.18
        S(radio_mast(x, yb, h_, "#141226", 1.6))
        for k in range(blink):
            y = yb - h_ * (k + 1) / blink
            S(circ(x, y, 12, "#ff3a2a", opacity=0.3))
            S(circ(x, y, 2.6, "#ff5a48"))
    # a small hut at the foot of the masts, one window lit
    S(rect(360, 318, 44, 26, "#141226"))
    S(poly([(356, 318), (408, 318), (382, 304)], "#141226"))
    S(rect(390, 326, 8, 7, "#ffcf7a"))
    # grass stalks against the sky, foreground
    for _ in range(90):
        x = rng.uniform(-10, w + 10)
        hh = rng.uniform(20, 70)
        S(path(f"M{n(x)} 600 Q{n(x + rng.uniform(-8, 8))} {n(600 - hh * 0.6)} {n(x + rng.uniform(-14, 14))} {n(600 - hh)}",
               "none", stroke="#0e0c1a", stroke_width=1.6))
    return S.html()


def pines(S, rng, y, amp, fill, dens=1.0, hmin=20, hmax=60):
    """A tree line of conifers along y."""
    out = []
    x = -10
    while x < S.w + 10:
        th = rng.uniform(hmin, hmax)
        tw = th * 0.28
        top = y - th - amp * math.sin(x / 90)
        out.append(poly([(x - tw, y + 2), (x, top), (x + tw, y + 2)], fill))
        x += rng.uniform(5, 14) / dens
    out.append(rect(0, y, S.w, 6, fill))
    return "".join(out)


def nostr_2a(p):
    """A still lake at dawn: mist on the water, pines across it, a jetty."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("nostr-2a")
    hy = 280
    S(sky(S, [(0, "#a9aed4"), (0.6, "#efc2bc"), (1, "#fbdcbc")], 0, hy))
    S(glow(S, 520, hy - 10, 260, "#ffe8c8", 0.8))
    S(circ(520, hy - 4, 22, "#fff4e0"))
    lines_ = [(hy - 20, "#c8b8c8", 0.6, 26, 40), (hy - 8, "#a898b0", 0.9, 22, 54), (hy, "#7a6e8e", 1.1, 18, 60)]
    S(rect(0, hy, w, h - hy, S.lin([(0, "#f6d6c0"), (0.5, "#d9bcc8"), (1, "#9a9ec4")])))
    for y, col, dens, a, b in lines_:
        S(pines(S, rng, y, 6, col, dens, a, b))
    # reflections: the tree lines, flipped and softened
    refl = "".join(pines(S, random.Random(f"r{y}"), y, 6, col, dens, a, b) for y, col, dens, a, b in lines_)
    S(g(refl, transform=f"translate(0 {2 * hy + 8}) scale(1 -1)", opacity=0.35, filter=S.blur(1.5, 3)))
    # mist lying on the water
    bl = S.blur(14)
    for y, op in ((hy + 4, 0.8), (hy + 26, 0.5), (hy + 60, 0.35)):
        S(ell(w * 0.45, y, w * 0.7, 16, "#fff4ec", opacity=op, filter=bl))
    S(water_glints(rng, 380, 660, hy + 10, h, "#fff2e0", 36, 0.5, 60, center=520, spread=40))
    # the jetty running out from the bottom left
    planks = []
    for i in range(18):
        t0, t1 = i / 18, (i + 0.85) / 18
        def P(t, side):
            x = -40 + t * 330 + side * (70 - t * 55)
            y = h + 10 - t * 240
            return (x, y)
        planks.append(poly([P(t0, -1), P(t0, 1), P(t1, 1), P(t1, -1)], mix("#6a5048", "#b09088", i / 18)))
    S(g(planks))
    for t in (0.3, 0.6, 0.9):
        x = -40 + t * 330
        y = h + 10 - t * 240
        for side in (-1, 1):
            xx = x + side * (70 - t * 55)
            S(rect(xx - 3, y - 6, 6, 40 * (1 - t) + 14, "#4a3838"))
    # reeds at the right edge
    for _ in range(40):
        x = rng.uniform(690, 810)
        hh = rng.uniform(40, 130)
        S(path(f"M{n(x)} {h} Q{n(x - 6)} {n(h - hh * 0.5)} {n(x + rng.uniform(-18, 6))} {n(h - hh)}", "none",
               stroke="#5a4e58", stroke_width=2))
    return S.html()


def snap_0(p):
    """A beach at golden hour: a striped towel, a parasol's long shadow, the sun on the sea."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("snap-0")
    hy = 230
    S(sky(S, [(0, "#f2b474"), (0.6, "#f9d08c"), (1, "#fde6b0")], 0, hy))
    S(glow(S, 110, hy - 30, 260, "#fff0c0", 0.8))
    S(circ(110, hy - 28, 24, "#fffae8"))
    S(rect(0, hy, w, 110, S.lin([(0, "#e0b27a"), (0.5, "#5aa6a8"), (1, "#2f8a92")])))
    S(water_glints(rng, 0, w, hy + 4, hy + 100, "#fff2c8", 60, 0.9, 40, center=110, spread=30))
    for i in range(4):
        y = hy + 104 + i * 8
        S(path(f"M-10 {y} Q{w * 0.3} {y - 6} {w * 0.6} {y + 2} T{w + 10} {y}", "none", stroke="#ffffff",
               stroke_width=3 - i * 0.6, opacity=0.7 - i * 0.15))
    S(rect(0, hy + 132, w, 60, S.lin([(0, "#c8a07a"), (1, "#e2b886")])))
    S(rect(0, hy + 190, w, h - hy - 190, S.lin([(0, "#ecc48e"), (1, "#f2d2a0")])))
    for i in range(22):
        y = hy + 200 + i * 18
        S(path(f"M-10 {y} q60 -5 120 0 t120 0 t120 0 t120 0", "none", stroke="#d8ae7a", stroke_width=1.4, opacity=0.5))
    # the parasol, its shadow thrown long to the right
    S(poly([(70, 470), (84, 470), (470, 640), (470, 690)], "#b9875a", opacity=0.45))
    S(ell(400, 650, 120, 40, "#b9875a", opacity=0.45, transform="rotate(24 400 650)"))
    S(line(76, 470, 60, 300, "#e8e0cc", 4))
    S(path("M-40 330 Q60 230 170 280 Q60 300 -40 330 Z", "#e8553a"))
    S(path("M-40 330 Q20 262 60 250 Q40 292 -40 330 Z", "#f4efe2"))
    S(path("M60 250 Q120 250 170 280 Q110 285 60 250 Z", "#f4efe2"))
    # the towel in perspective, and what's on it
    tw = [(150, 560), (360, 540), (420, 720), (180, 750)]
    S(poly([(x + 18, y + 10) for x, y in tw], "#b9875a", opacity=0.4))
    S(poly(tw, "#f4efe2"))
    for i in range(5):
        t0, t1 = i / 5, (i + 0.5) / 5
        def P(a, t):
            return (a[0][0] + (a[1][0] - a[0][0]) * t, a[0][1] + (a[1][1] - a[0][1]) * t)
        e0 = [tw[0], tw[1]]
        e1 = [tw[3], tw[2]]
        S(poly([P(e0, t0), P(e0, t1), P(e1, t1), P(e1, t0)], ["#e8553a", "#2f8a92", "#f2b632"][i % 3]))
    S(poly([(360, 540), (420, 720), (392, 700), (352, 572)], "#d9d0bc"))
    S(ell(230, 650, 24, 10, "#2a2a30", transform="rotate(-10 230 650)"))
    S(ell(262, 648, 24, 10, "#2a2a30", transform="rotate(-10 262 648)"))
    S(rect(300, 610, 56, 40, "#6a8ac4", rx=4, transform="rotate(-8 328 630)"))
    # flip-flops and footprints
    for x, y in ((120, 700), (140, 716)):
        S(ell(x, y, 10, 22, "#2f8a92", transform=f"rotate(20 {x} {y})"))
    for i in range(9):
        x = 60 + i * 34 + (i % 2) * 10
        y = 790 - i * 30
        S(ell(x, y, 6, 10, "#c79a68", opacity=0.6))
    S(rect(0, 0, w, h, S.lin([(0, "#ffb060", 0.15), (0.5, "#ffb060", 0), (1, "#ffb060", 0.1)], 0, 0, 1, 1)))
    return S.html()


def snap_1(p):
    """From the back of a concert: heads and hands, beams cutting through haze."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("snap-1")
    S(rect(0, 0, w, h, S.lin([(0, "#0a0716"), (0.45, "#1c0f30"), (1, "#07050c")])))
    S(glow(S, 225, 360, 360, "#7a3aa8", 0.55))
    S(glow(S, 225, 380, 140, "#ffb8e8", 0.45))
    # beams from the rig, fanning down into the haze
    beams = []
    for i, (lx, col) in enumerate(((50, "#39c6ff"), (130, "#ff3aa8"), (225, "#ffd26a"), (320, "#ff3aa8"), (400, "#39c6ff"))):
        for tx in (lx - 160 + i * 20, lx + 90 - i * 30):
            beams.append(poly([(lx - 3, 110), (lx + 3, 110), (tx + 50, 700), (tx - 50, 700)], col, opacity=0.16))
    S(g(beams, filter=S.blur(6)))
    S(rect(0, 100, w, 12, "#16121e"))
    for lx, col in ((50, "#39c6ff"), (130, "#ff3aa8"), (225, "#ffd26a"), (320, "#ff3aa8"), (400, "#39c6ff")):
        S(circ(lx, 114, 16, col, opacity=0.35))
        S(circ(lx, 114, 6, "#ffffff"))
    # the stage: a lit edge and one small figure at the mic
    S(rect(0, 400, w, 14, "#2a1a3a"))
    S(rect(0, 398, w, 3, "#ff9ad8", opacity=0.7))
    S(person(225, 398, 70, "#0c0812"))
    S(line(240, 398, 244, 344, "#0c0812", 2))
    # the crowd, back to front, rim-lit by the stage
    for row in range(5):
        y = 470 + row * 70
        sc = 0.8 + row * 0.35
        x = -20 + rng.uniform(0, 20)
        while x < w + 30:
            hr = 14 * sc
            col = mix("#1a0f26", "#040308", row / 4)
            yy = y + rng.uniform(-8, 8)
            S(path(f"M{n(x - hr * 2.2)} {n(h + 10)} L{n(x - hr * 2)} {n(yy + hr * 1.8)} Q{n(x)} {n(yy + hr * 0.9)} "
                   f"{n(x + hr * 2)} {n(yy + hr * 1.8)} L{n(x + hr * 2.2)} {n(h + 10)} Z", col))
            S(circ(x, yy, hr, col))
            S(path(f"M{n(x - hr * 0.8)} {n(yy - hr * 0.55)} A{n(hr)} {n(hr)} 0 0 1 {n(x + hr * 0.8)} {n(yy - hr * 0.55)}", "none",
                   stroke=rng.choice(["#ff7ac8", "#6ad6ff", "#ffc86a"]), stroke_width=1.2 + row * 0.3, opacity=0.6 - row * 0.1))
            if rng.random() < 0.18 and row < 4:
                ax = x + rng.uniform(-10, 10)
                S(path(f"M{n(x + hr * 0.6)} {n(yy + hr)} L{n(ax + hr * 1.5)} {n(yy - hr * 3)}", "none", stroke=col,
                       stroke_width=hr * 0.55, stroke_linecap="round"))
                if rng.random() < 0.5:
                    S(rect(ax + hr * 1.2, yy - hr * 4.3, hr * 0.8, hr * 1.3, "#dff2ff", rx=2, opacity=0.9))
                    S(glow(S, ax + hr * 1.6, yy - hr * 3.7, hr * 2.5, "#bfe6ff", 0.3))
            x += hr * rng.uniform(3.2, 4.2)
    return S.html()


def snap_4(p):
    """A climbing gym wall looking up: angled panels, routes in colours, a rope hanging."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("snap-4")
    S(rect(0, 0, w, h, "#2a2f38"))
    S(rect(0, 0, w, 60, "#1a1d24"))
    for x in range(20, w, 90):
        S(rect(x, 16, 50, 10, "#fff6e0", rx=4))
        S(glow(S, x + 25, 30, 90, "#fff6e0", 0.25))
    panels = [
        ([(0, 60), (200, 60), (170, 330), (0, 360)], "#8ea4b8"),
        ([(200, 60), (450, 60), (450, 300), (170, 330)], "#a9b8c6"),
        ([(0, 360), (170, 330), (220, 560), (0, 600)], "#6f86a0"),
        ([(170, 330), (450, 300), (450, 580), (220, 560)], "#90a6ba"),
        ([(0, 600), (220, 560), (240, 800), (0, 800)], "#a2b4c4"),
        ([(220, 560), (450, 580), (450, 800), (240, 800)], "#7f97ae"),
    ]
    for pp, col in panels:
        S(poly(pp, col))
        xs = [q[0] for q in pp]
        ys = [q[1] for q in pp]
        clip = S.clip(poly(pp, "#000"))
        dots = []
        for yy in range(int(min(ys)) + 10, int(max(ys)), 26):
            for xx in range(int(min(xs)) + 10, int(max(xs)), 26):
                dots.append(circ(xx, yy, 1.6, dark(col, 0.35)))
        S(g(dots, clip_path=clip, opacity=0.6))
        S(poly(pp, "none", stroke=dark(col, 0.3), stroke_width=2))
    # a big volume
    S(poly([(240, 420), (330, 380), (360, 470)], "#e9dcc4"))
    S(poly([(240, 420), (360, 470), (280, 500)], "#c9b494"))
    # routes of holds, each its own colour
    routes = {"#f2508a": [(60, 700), (90, 620), (70, 540), (110, 470), (90, 400), (130, 330), (110, 250), (150, 170), (130, 100)],
              "#f2c230": [(330, 740), (300, 660), (340, 590), (300, 520), (340, 440), (380, 370), (350, 290), (390, 210), (360, 130)],
              "#3fbf7a": [(200, 760), (230, 690), (190, 610), (250, 540), (220, 460), (260, 390), (230, 300), (270, 220)],
              "#3a8ae8": [(420, 700), (400, 620), (430, 540), (410, 450)],
              "#f27a2e": [(20, 480), (40, 420), (20, 300), (50, 200)]}
    for col, holds in routes.items():
        for x, y in holds:
            r = rng.uniform(9, 17) * (0.7 + y / 800 * 0.5)
            S(blob(x + 3, y + 4, r, rng, "#1a1d24", opacity=0.3))
            S(blob(x, y, r, rng, col))
            S(blob(x - r * 0.25, y - r * 0.3, r * 0.4, rng, light(col, 0.35)))
    # the rope from the top anchor, clipped through quickdraws down the pink route
    S(rect(120, 62, 30, 12, "#c9ccd2", rx=3))
    rope = [(135, 74), (128, 110), (150, 180), (118, 260), (140, 340), (100, 420), (120, 500), (140, 600), (150, 700), (160, 810)]
    S(path(smooth(rope), "none", stroke="#1e1e22", stroke_width=7, opacity=0.3, transform="translate(4 4)"))
    S(path(smooth(rope), "none", stroke="#6a3ac8", stroke_width=6))
    S(path(smooth(rope), "none", stroke="#b89af0", stroke_width=2, transform="translate(-1.5 0)", opacity=0.7))
    for x, y in ((150, 180), (118, 260), (140, 340), (100, 420)):
        S(rect(x - 3, y - 16, 6, 16, "#d0d4da", rx=2))
    S(rect(0, 0, w, h, S.lin([(0, "#fff6e0", 0.12), (0.4, "#fff6e0", 0), (1, "#000", 0.3)])))
    return S.html()


def snap_5(p):
    """A picnic from above: a checked blanket on the grass, fruit, bread, dappled shade."""
    w, h = p["size"]
    S = Svg(w, h)
    rng = random.Random("snap-5")
    S(rect(0, 0, w, h, "#6fa04a"))
    blades = []
    for _ in range(160):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        blades.append(line(x, y, x + rng.uniform(-3, 3), y - rng.uniform(5, 11), rng.choice(["#5a8a3a", "#86b85a", "#4f7a32"]), 1.4))
    S(g(blades, opacity=0.8))
    check = S.pattern(40, 40, rect(0, 0, 40, 40, "#f6f1e6") + rect(0, 0, 20, 40, "#d9453a", opacity=0.55)
                      + rect(0, 0, 40, 20, "#d9453a", opacity=0.55), tf="rotate(-9)")
    bl = [(40, 170), (420, 110), (440, 660), (60, 720)]
    S(poly([(x + 10, y + 12) for x, y in bl], "#2f4a22", opacity=0.3))
    S(poly(bl, check))
    # items with their shadows down-right
    def shadowed(el_fn, dx=7, dy=9):
        S(g(el_fn("#2a3a20"), transform=f"translate({dx} {dy})", opacity=0.3))
        S(el_fn(None))
    # board with bread and cheese
    shadowed(lambda c: rect(110, 250, 170, 100, c or "#c89458", rx=10, transform="rotate(-9 195 300)"))
    S(ell(160, 300, 44, 26, "#c9803e", transform="rotate(-9 160 300)"))
    for i in range(4):
        S(line(135 + i * 14, 286, 145 + i * 14, 312, "#e8b870", 2))
    S(poly([(210, 280), (262, 272), (240, 316)], "#f2d06a"))
    S(poly([(210, 280), (262, 272), (262, 280), (212, 288)], "#e0b84a"))
    # bowl of oranges and grapes
    shadowed(lambda c: circ(330, 400, 62, c or "#f2ede2"))
    S(circ(330, 400, 54, "#e2dccf"))
    for ox, oy in ((310, 382), (348, 388), (322, 420), (356, 424)):
        S(circ(ox, oy, 18, "#f28a2a"))
        S(circ(ox - 5, oy - 6, 5, "#f8b060"))
    for _ in range(9):
        S(circ(300 + rng.uniform(-8, 8), 420 + rng.uniform(-8, 8), 6, "#6a3a7a"))
    # watermelon slices
    for i, (x, y, a) in enumerate(((120, 480, -20), (170, 510, 10), (110, 560, 35))):
        def slice_(c, x=x, y=y, a=a):
            return path(f"M{x - 40} {y} A40 40 0 0 0 {x + 40} {y} Z", c or "#2f8a3a", transform=f"rotate({a} {x} {y})")
        shadowed(slice_)
        S(path(f"M{x - 34} {y} A34 34 0 0 0 {x + 34} {y} Z", "#e8453a", transform=f"rotate({a} {x} {y})"))
        for sx in (-12, 0, 12):
            S(ell(x + sx, y + 12, 1.8, 3, "#2a1a1a", transform=f"rotate({a} {x} {y})"))
    # two glasses of lemonade, a book, sunglasses
    for gx, gy in ((340, 230), (380, 270)):
        shadowed(lambda c, gx=gx, gy=gy: circ(gx, gy, 20, c or "#f6f0d8"))
        S(circ(gx, gy, 15, "#f6e07a"))
        S(circ(gx - 5, gy - 5, 4, "#ffffff", opacity=0.7))
    shadowed(lambda c: rect(250, 540, 120, 84, c or "#2f5a8a", rx=4, transform="rotate(12 310 582)"))
    S(rect(254, 544, 112, 76, "#f4efe4", rx=2, transform="rotate(12 310 582)", opacity=0.0))
    S(line(310, 540, 300, 626, "#23456a", 2, transform="rotate(12 310 582)"))
    S(ell(96, 620, 16, 12, "#1e1e22"))
    S(ell(132, 624, 16, 12, "#1e1e22"))
    S(line(112, 620, 116, 621, "#1e1e22", 3))
    # dappled shade from the tree overhead
    shade = []
    for _ in range(26):
        shade.append(blob(rng.uniform(-60, w + 60), rng.uniform(-60, 360), rng.uniform(30, 80), rng, "#12240c"))
    S(g(shade, opacity=0.28, filter=S.blur(8)))
    S(rect(0, 0, w, h, S.lin([(0, "#fff6d0", 0.1), (1, "#fff6d0", 0)], 1, 1, 0, 0)))
    return S.html()


PICS = {
    "shot-13": shot_13,
    "ig-photo-0": ig_photo_0,
    "reddit-4": reddit_4,
    "ig-photo-2": ig_photo_2,
    "reddit-5": reddit_5,
    "trello-2": trello_2,
    "ig-save-6": ig_save_6,
    "ig-save-9": ig_save_9,
    "dayone-11": dayone_11,
    "ig-notice-3": ig_notice_3,
    "journal-1": journal_1,
    "ig-save-3": ig_save_3,
    "x-photo-0": x_photo_0,
    "x-photo-2": x_photo_2,
    "tt-save-2": tt_save_2,
    "dayone-0": dayone_0,
    "journal-11": journal_11,
    "dayone-18": dayone_18,
    "snap-3": snap_3,
    "x-video-0": x_video_0,
    "ig-like-0": ig_like_0,
    "ig-notice-0": ig_notice_0,
    "bsky-4b": bsky_4b,
    "nostr-0": nostr_0,
    "nostr-2a": nostr_2a,
    "snap-0": snap_0,
    "snap-1": snap_1,
    "snap-4": snap_4,
    "snap-5": snap_5,
}


def html(p):
    fn = PICS.get(p["key"])
    if fn is None:
        S = Svg(*p["size"], bg="#777")
        return S.html()
    return fn(p)
