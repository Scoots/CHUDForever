"""Draws the textures for CombatHUD's charge bars, in Media/Charges/.

Orbs, one pair per theme: orb_<theme>_full.tga (lit) and orb_<theme>_empty.tga
(spent, a grayscale ball with faint traces of the same pattern).
Gems, one cut gem per color: gem_<color>.tga, plus gem_empty.tga for spent charges.
Shield segments: pill_h.tga and pill_v.tga, a white capsule lying down and
standing up, which the game tints (Absorb.lua).

Orbs and gems are 128x128, pills 128x32 and 32x128: 32-bit TGA with alpha,
which the game can load. Also writes tools/preview.png with every charge style,
as the bar shows them with a charge used, and tools/shield_preview.png with a
few shield bar shapes.

Run from the addon folder:  python tools/make_charge_art.py
Needs Pillow and numpy. The game only notices new texture files after a full
restart; changed ones need just a /reload.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 128          # output size (a power of two, as the game wants)
SUPER = 4           # drawn this many times larger, then scaled down for smooth edges
S = SIZE * SUPER
UNIT = S / 2        # pixels per unit: coordinates run from -1 to 1 across the texture
BODY = 0.70         # sphere radius, as a fraction of half the texture
SEED = 7            # same patterns every run

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "Media", "Charges")


# Basics --------------------------------------------------------------------------------------

def px(value):
    """A coordinate from -1..1 in pixels."""
    return (value + 1) * UNIT


def point(x, y):
    return (px(x), px(y))


def polar(angle, radius, cx=0.0, cy=0.0):
    return (cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)


def grid():
    """x, y from -1 to 1 across the texture (y down), and the distance from the center."""
    axis = (np.arange(S) + 0.5) / UNIT - 1
    x, y = np.meshgrid(axis, axis)
    return x, y, np.sqrt(x * x + y * y)


def lerp_colors(t, stops):
    """Colour at t (0..1) along a gradient of (position, (r, g, b)) stops."""
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        mask = (t >= p0) & (t <= p1)
        f = ((t - p0) / (p1 - p0))[mask][:, None]
        out[mask] = np.array(c0) * (1 - f) + np.array(c1) * f
    out[t > stops[-1][0]] = stops[-1][1]
    return out


def layer(rgb, alpha):
    data = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255]).astype(np.uint8)
    return Image.fromarray(data)  # four 8-bit channels: RGBA


def solid(color, alpha):
    """One color over the whole texture, with the given alpha (0..1) per pixel."""
    return layer(np.broadcast_to(np.array(color, float), alpha.shape + (3,)), alpha)


def from_mask(mask, color, strength=1.0):
    """A grayscale mask painted in one color."""
    return solid(color, np.asarray(mask, float) / 255 * strength)


def canvas():
    """A blank grayscale mask to draw shapes on, and its pen."""
    image = Image.new("L", (S, S), 0)
    return image, ImageDraw.Draw(image)


def inside_ball(image, margin=0.03):
    """Cuts an RGBA layer down to the inside of the ball."""
    data = np.array(image)
    _, _, r = grid()
    data[..., 3] = (data[..., 3] * (r <= BODY - margin)).astype(np.uint8)
    return Image.fromarray(data)


def sphere(stops, shade):
    """A shaded ball: gradient from the center out, darker toward the lower right."""
    x, y, r = grid()
    rgb = lerp_colors(np.clip(r / BODY, 0, 1), stops)
    light = 1 - shade * np.clip((x + y) / math.sqrt(2), 0, 1)
    rgb = rgb * light[..., None]
    return layer(rgb, (r <= BODY).astype(float))


def ring(color, inner, outer, strength):
    _, _, r = grid()
    return solid(color, ((r >= inner) & (r <= outer)).astype(float) * strength)


def highlight(strength):
    """A soft white spot on the upper left."""
    x, y, _ = grid()
    d = np.sqrt((x + 0.30 * BODY) ** 2 + (y + 0.34 * BODY) ** 2) / (0.26 * BODY)
    alpha = np.clip(1 - d, 0, 1) ** 1.6 * strength
    return solid((255, 255, 255), alpha)


def glowing(mask, glow, color, glow_blur=10, line_blur=1.2, glow_strength=0.9):
    """A shape in one color over a soft, wider glow of another."""
    wide = mask.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(glow_blur))
    return [from_mask(wide, glow, glow_strength), from_mask(mask.filter(ImageFilter.GaussianBlur(line_blur)), color)]


def trace(mask, strength=0.32):
    """Faint gray traces of a shape, for a spent orb."""
    return from_mask(mask.filter(ImageFilter.GaussianBlur(1.5)), (175, 175, 180), strength)


# Lightning --------------------------------------------------------------------------------------

def bolts():
    """Jagged lines from near the center outward, with a few branches, in pixels."""
    rng = random.Random(SEED)
    lines = []

    def walk(x, y, angle, reach, depth):
        points = [(x, y)]
        step = 0.07 * UNIT
        while math.hypot(points[-1][0] - UNIT, points[-1][1] - UNIT) < reach:
            angle += rng.uniform(-0.55, 0.55)
            x, y = points[-1]
            points.append((x + math.cos(angle) * step, y + math.sin(angle) * step))
            if depth < 1 and rng.random() < 0.18:
                walk(*points[-1], angle + rng.choice((-1, 1)) * rng.uniform(0.5, 1.0), reach * 0.92, depth + 1)
        lines.append(points)

    count = 6
    for index in range(count):
        angle = index * 2 * math.pi / count + rng.uniform(-0.3, 0.3)
        start = rng.uniform(0.02, 0.08) * UNIT
        walk(UNIT + math.cos(angle) * start, UNIT + math.sin(angle) * start, angle,
             rng.uniform(0.62, 0.80) * UNIT, 0)
    return lines


def draw_lines(lines, color, width, blur):
    image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    for points in lines:
        draw.line(points, fill=color, width=width, joint="curve")
    return image.filter(ImageFilter.GaussianBlur(blur)) if blur else image


def lightning_full():
    lines = bolts()
    return [draw_lines(lines, (150, 215, 255, 230), 30, 12), draw_lines(lines, (255, 255, 255, 255), 9, 1.2)]


def lightning_trace():
    return draw_lines(bolts(), (175, 175, 180, 80), 7, 1.5)


# Water: a wave across the ball, deeper water under it, and rising bubbles ------------------------

def wave_points():
    points = []
    for index in range(101):
        t = index / 100
        points.append((-0.66 + 1.32 * t, 0.06 + 0.07 * math.sin(t * 3 * math.pi + 0.6)))
    return points


def water_mask():
    image, draw = canvas()
    draw.line([point(x, y) for x, y in wave_points()], fill=255, width=int(0.05 * UNIT), joint="curve")
    for x, y, radius in ((-0.24, 0.36, 0.085), (0.18, 0.30, 0.06), (0.02, 0.50, 0.045), (0.32, 0.45, 0.035),
                         (-0.06, -0.22, 0.05), (0.24, -0.34, 0.035), (-0.32, -0.10, 0.03)):
        draw.ellipse([px(x - radius), px(y - radius), px(x + radius), px(y + radius)],
                     outline=255, width=int(0.022 * UNIT))
    return image


def water_full():
    deep, draw = canvas()
    draw.polygon([point(x, y) for x, y in wave_points()] + [point(0.7, 0.75), point(-0.7, 0.75)], fill=255)
    under = inside_ball(from_mask(deep.filter(ImageFilter.GaussianBlur(4)), (10, 60, 160), 0.5), 0)
    return [under] + glowing(water_mask(), (110, 215, 255), (235, 250, 255))


# Fire: tongues of flame rising from the bottom of the ball ----------------------------------------

def fire_mask(shrink=1.0):
    image, draw = canvas()
    rng = random.Random(SEED)
    # center x, base y, half width, height
    for cx, base, half, height in ((-0.30, 0.42, 0.20, 0.55), (0.0, 0.50, 0.27, 0.88), (0.29, 0.42, 0.20, 0.60),
                                   (-0.14, 0.47, 0.16, 0.46), (0.15, 0.48, 0.15, 0.52)):
        lean = rng.uniform(-0.10, 0.10)
        half, height = half * shrink, height * shrink
        left, right = [], []
        for index in range(31):
            t = index / 30
            width = half * (1 - t) ** 0.7 * (1 + 0.12 * math.sin(t * 9 + cx * 7))
            x = cx + lean * t * t + 0.03 * math.sin(t * 6 + cx * 5)
            y = base - height * t
            left.append(point(x - width, y))
            right.append(point(x + width, y))
        draw.polygon(left + right[::-1], fill=255)
    return image


def fire_full():
    pieces = glowing(fire_mask(), (255, 120, 20), (255, 215, 110), glow_blur=12, line_blur=3)
    core = fire_mask(0.6).filter(ImageFilter.GaussianBlur(5))
    return pieces + [from_mask(core, (255, 250, 225), 0.85)]


# Nature: three leaves turning around a small curl ------------------------------------------------

LEAVES = [(k * 2 * math.pi / 3 - math.pi / 2 + 0.35) for k in range(3)]


def leaf_outline(angle):
    """An almond-shaped leaf starting near the center, curving with the swirl."""
    cx, cy = polar(angle, 0.10)
    direction = angle + 0.55
    left, right = [], []
    for index in range(41):
        t = index / 40
        along = 0.50 * t
        half = 0.15 * math.sin(math.pi * t) ** 0.85 * (1 - 0.25 * t)
        bend = direction + 0.35 * t
        x, y = polar(bend, along, cx, cy)
        normal = bend + math.pi / 2
        left.append(point(*polar(normal, half, x, y)))
        right.append(point(*polar(normal, -half, x, y)))
    return left + right[::-1], (cx, cy, direction)


def nature_mask():
    image, draw = canvas()
    for angle in LEAVES:
        outline, _ = leaf_outline(angle)
        draw.polygon(outline, fill=255)
    curl = [point(*polar(t * 2.4 * math.pi, 0.02 + 0.07 * t)) for t in (i / 40 for i in range(41))]
    draw.line(curl, fill=255, width=int(0.035 * UNIT), joint="curve")
    return image


def nature_full():
    veins, draw = canvas()
    for angle in LEAVES:
        _, (cx, cy, direction) = leaf_outline(angle)
        rib = [point(*polar(direction + 0.35 * t, 0.46 * t, cx, cy)) for t in (i / 20 for i in range(21))]
        draw.line(rib, fill=255, width=int(0.018 * UNIT), joint="curve")
    return glowing(nature_mask(), (100, 225, 80), (205, 255, 165)) + [from_mask(veins, (45, 125, 40), 0.75)]


# Arcane: a four-pointed star with sparkles, inside a thin rune circle ---------------------------

def star(draw, cx, cy, radius, inner, points=4, rotation=-math.pi / 2):
    corners = []
    for index in range(points * 2):
        length = radius if index % 2 == 0 else inner
        corners.append(point(*polar(rotation + index * math.pi / points, length, cx, cy)))
    draw.polygon(corners, fill=255)


def arcane_mask():
    image, draw = canvas()
    star(draw, 0, 0, 0.44, 0.075)
    star(draw, -0.30, -0.28, 0.13, 0.025)
    star(draw, 0.33, 0.22, 0.10, 0.02)
    star(draw, 0.25, -0.31, 0.07, 0.015)
    radius = 0.55
    draw.ellipse([px(-radius), px(-radius), px(radius), px(radius)], outline=255, width=int(0.018 * UNIT))
    for index in range(12):
        angle = index * math.pi / 6
        draw.line([point(*polar(angle, radius - 0.05)), point(*polar(angle, radius + 0.03))],
                  fill=255, width=int(0.016 * UNIT))
    return image


def arcane_full():
    return glowing(arcane_mask(), (225, 110, 255), (255, 235, 255))


# Shadow: smoke curling out from a faint light in the middle ------------------------------------

def shadow_mask():
    image, draw = canvas()
    for k in range(3):
        base = k * 2 * math.pi / 3
        steps = 60
        previous = None
        for index in range(steps + 1):
            t = index / steps
            current = point(*polar(base + 2.6 * t, 0.08 + 0.50 * t))
            if previous:
                draw.line([previous, current], fill=255, width=max(2, int(0.07 * UNIT * (1 - 0.75 * t))))
            previous = current
    return image.filter(ImageFilter.GaussianBlur(5))


def shadow_full():
    return glowing(shadow_mask(), (140, 50, 220), (210, 165, 255), glow_blur=14, line_blur=3)


# Holy: rays of light around a bright center ------------------------------------------------------

def holy_mask():
    image, draw = canvas()
    for index in range(12):
        angle = index * math.pi / 6 - math.pi / 2
        length, spread = (0.62, 0.20) if index % 2 == 0 else (0.42, 0.24)
        draw.polygon([point(*polar(angle - spread, 0.09)), point(*polar(angle, length)),
                      point(*polar(angle + spread, 0.09))], fill=255)
    radius = 0.13
    draw.ellipse([px(-radius), px(-radius), px(radius), px(radius)], fill=255)
    return image


def holy_full():
    return glowing(holy_mask(), (255, 195, 70), (255, 250, 225), line_blur=2)


# Frost: a six-armed snowflake -----------------------------------------------------------------

def frost_mask():
    image, draw = canvas()
    width = int(0.03 * UNIT)
    for k in range(6):
        angle = k * math.pi / 3 - math.pi / 2
        draw.line([point(0, 0), point(*polar(angle, 0.54))], fill=255, width=width)
        for at, length in ((0.22, 0.14), (0.38, 0.10)):
            x, y = polar(angle, at)
            for side in (-1, 1):
                draw.line([point(x, y), point(*polar(angle + side * math.pi / 3, length, x, y))],
                          fill=255, width=int(width * 0.8))
    hexagon = [point(*polar(k * math.pi / 3, 0.08)) for k in range(6)]
    draw.polygon(hexagon, outline=255, width=int(width * 0.8))
    return image


def frost_full():
    return glowing(frost_mask(), (130, 205, 255), (255, 255, 255))


# Orbs -------------------------------------------------------------------------------------------

THEMES = {
    "lightning": dict(glow=(60, 140, 255), rim=(150, 210, 255), full=lightning_full, trace=lightning_trace,
                      stops=[(0.0, (235, 250, 255)), (0.35, (120, 190, 255)), (0.75, (40, 100, 235)), (1.0, (20, 50, 190))]),
    "water": dict(glow=(40, 170, 235), rim=(140, 220, 255), full=water_full, mask=water_mask, core=0.5,
                  stops=[(0.0, (200, 245, 255)), (0.4, (70, 175, 230)), (0.8, (20, 95, 180)), (1.0, (10, 55, 140))]),
    "fire": dict(glow=(255, 110, 20), rim=(255, 170, 80), full=fire_full, mask=fire_mask, core=0.6,
                 core_color=(255, 240, 190),
                 stops=[(0.0, (255, 230, 150)), (0.35, (250, 160, 50)), (0.75, (215, 70, 15)), (1.0, (140, 25, 10))]),
    "nature": dict(glow=(80, 210, 70), rim=(170, 240, 140), full=nature_full, mask=nature_mask, core=0.5,
                   stops=[(0.0, (215, 255, 190)), (0.4, (115, 205, 85)), (0.8, (40, 135, 50)), (1.0, (20, 80, 30))]),
    "arcane": dict(glow=(215, 90, 255), rim=(240, 170, 255), full=arcane_full, mask=arcane_mask, core=0.7,
                   stops=[(0.0, (255, 225, 255)), (0.4, (215, 125, 255)), (0.8, (135, 45, 205)), (1.0, (75, 20, 145))]),
    "shadow": dict(glow=(120, 40, 210), rim=(165, 105, 235), full=shadow_full, mask=shadow_mask, core=0.55,
                   core_color=(215, 180, 255), shade=0.4,
                   stops=[(0.0, (170, 120, 230)), (0.35, (95, 40, 160)), (0.8, (40, 12, 75)), (1.0, (18, 5, 38))]),
    "holy": dict(glow=(255, 200, 80), rim=(255, 235, 160), full=holy_full, mask=holy_mask, core=0.9,
                 stops=[(0.0, (255, 255, 235)), (0.4, (255, 220, 115)), (0.8, (215, 155, 40)), (1.0, (145, 90, 15))]),
    "frost": dict(glow=(140, 210, 255), rim=(220, 245, 255), full=frost_full, mask=frost_mask, core=0.6,
                  stops=[(0.0, (245, 252, 255)), (0.4, (185, 230, 255)), (0.8, (90, 165, 225)), (1.0, (40, 95, 165))]),
}


def full_orb(theme):
    _, _, r = grid()
    # Outer glow, beyond the ball.
    image = solid(theme["glow"], np.clip(1 - (r - 0.45) / 0.55, 0, 1) ** 1.8 * 0.95)
    image = Image.alpha_composite(image, sphere(theme["stops"], theme.get("shade", 0.30)))
    # A bright core, then the theme's pattern, a rim and a shine.
    core = np.clip(1 - r / 0.32, 0, 1) ** 1.5 * theme.get("core", 0.9)
    image = Image.alpha_composite(image, solid(theme.get("core_color", (255, 255, 255)), core))
    for piece in theme["full"]():
        image = Image.alpha_composite(image, piece)
    image = Image.alpha_composite(image, ring(theme["rim"], BODY - 0.035, BODY, 0.65))
    return Image.alpha_composite(image, highlight(0.55))


def empty_orb(theme):
    image = sphere([(0.0, (140, 140, 145)), (0.6, (88, 88, 93)), (1.0, (48, 48, 52))], 0.35)
    traces = theme["trace"]() if "trace" in theme else trace(theme["mask"]())
    image = Image.alpha_composite(image, inside_ball(traces))
    image = Image.alpha_composite(image, ring((15, 15, 18), BODY - 0.04, BODY, 0.9))
    return Image.alpha_composite(image, highlight(0.22))


# Gems: a round cut seen from above --------------------------------------------------------------

GEMS = {
    "red": (225, 35, 45),
    "yellow": (255, 200, 35),
    "green": (45, 200, 75),
    "blue": (45, 115, 255),
    "purple": (165, 65, 240),
    "white": (215, 228, 255),
}
LIGHT = -3 * math.pi / 4  # the light comes from the upper left


def tone(color, brightness):
    """The color darker (brightness under 1) or toward white (over 1)."""
    if brightness <= 1:
        return tuple(int(c * brightness) for c in color)
    mix = min(1.0, brightness - 1)
    return tuple(int(c + (255 - c) * mix) for c in color)


def gem(color, lit):
    sides, outer, table = 8, 0.66, 0.34
    offset = math.pi / sides
    rim = [polar(offset + k * 2 * math.pi / sides, outer) for k in range(sides)]
    top = [polar(offset + k * 2 * math.pi / sides, table) for k in range(sides)]
    _, _, r = grid()
    if lit:
        image = solid(color, np.clip(1 - (r - 0.5) / 0.45, 0, 1) ** 2 * 0.75)
    else:
        image = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        color = (105, 105, 112)
    facets = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(facets)
    edge = tone(color, 1.35 if lit else 1.15) + (160,)
    for k in range(sides):
        nxt = (k + 1) % sides
        middle = offset + (k + 0.5) * 2 * math.pi / sides
        facing = math.cos(middle - LIGHT)
        for shape, base in (([top[k], rim[k], rim[nxt]], 0.70), ([top[k], rim[nxt], top[nxt]], 0.58)):
            brightness = base + 0.38 * facing + (0.08 if k % 2 else -0.05)
            if not lit:
                brightness *= 0.75
            draw.polygon([point(*p) for p in shape], fill=tone(color, brightness) + (255,))
            draw.line([point(*p) for p in shape + [shape[0]]], fill=edge, width=int(0.012 * UNIT))
    draw.polygon([point(*p) for p in top], fill=tone(color, 1.05 if lit else 0.8) + (255,))
    draw.line([point(*p) for p in top + [top[0]]], fill=edge, width=int(0.014 * UNIT))
    draw.line([point(*p) for p in rim + [rim[0]]], fill=(10, 10, 12, 255), width=int(0.03 * UNIT))
    image = Image.alpha_composite(image, facets)
    # Light across the table, and a sparkle on a lit gem.
    x, y, _ = grid()
    sheen = np.clip(1 - np.sqrt((x + 0.12) ** 2 + (y + 0.14) ** 2) / 0.30, 0, 1) ** 1.5 * (0.45 if lit else 0.18)
    image = Image.alpha_composite(image, solid((255, 255, 255), sheen * (np.abs(x) + np.abs(y) < 0.5)))
    if lit:
        sparkle, pen = canvas()
        star(pen, -0.20, -0.22, 0.17, 0.025)
        image = Image.alpha_composite(image, from_mask(sparkle.filter(ImageFilter.GaussianBlur(4)), (255, 255, 255), 0.7))
        image = Image.alpha_composite(image, from_mask(sparkle.filter(ImageFilter.GaussianBlur(1)), (255, 255, 255)))
    return image


# Shield segments --------------------------------------------------------------------------------

def capsule(width, height):
    """A white capsule, width x height texture pixels, lit from the top (or the left when standing)."""
    sw, sh = width * SUPER, height * SUPER
    x, y = np.meshgrid(np.arange(sw) + 0.5, np.arange(sh) + 0.5)
    radius = min(sw, sh) / 2 - SUPER  # a pixel of room at the edge
    if sw >= sh:
        spine_x, spine_y = np.clip(x, sh / 2, sw - sh / 2), np.full_like(y, sh / 2)
        across = (y - sh / 2) / radius  # -1 at the top, 1 at the bottom
    else:
        spine_x, spine_y = np.full_like(x, sw / 2), np.clip(y, sw / 2, sh - sw / 2)
        across = (x - sw / 2) / radius  # -1 at the left, 1 at the right
    d = np.hypot(x - spine_x, y - spine_y) / radius  # 0 on the middle line, 1 at the edge
    # Round like a tube: a bright band near the lit side, darker toward the other, a darker rim.
    brightness = 0.82 - 0.18 * across + 0.22 * np.exp(-((across + 0.45) / 0.22) ** 2)
    brightness = brightness * np.where(d > 0.78, 0.62 + 0.38 * np.clip((1 - d) / 0.22, 0, 1), 1)
    rgb = np.clip(brightness, 0, 1)[..., None] * np.full(3, 255.0)
    return layer(rgb, (d <= 1).astype(float)).resize((width, height), Image.LANCZOS)


def shield_pieces(length, thickness, count, gap, bend_degrees, vertical, flip):
    """Where each segment goes: (x, y, rotation in radians, width, height), y up, from the
    bar's middle. The same layout as Absorb.lua: along a straight line, or bent around a
    circle; unflipped, a standing bar bulges right and a lying one bulges down."""
    bend = math.radians(bend_degrees)
    piece = (length - (count - 1) * gap) / count
    sign = -1 if flip else 1
    pieces = []
    for index in range(count):
        s = index * (piece + gap) + piece / 2 - length / 2
        if bend > 0:
            radius = length / bend
            angle = s / radius
            along, side = radius * math.sin(angle), radius * (1 - math.cos(angle))
        else:
            angle, along, side = 0.0, s, 0.0
        if vertical:
            pieces.append((-side * sign, along, angle * sign, thickness, piece))
        else:
            pieces.append((along, side * sign, angle * sign, piece, thickness))
    return pieces


def shield_preview(pill_h, pill_v):
    gold = np.array((1.0, 0.82, 0.25))
    examples = [
        ("Straight, 16 segments", dict(length=170, thickness=24, count=16, gap=3, bend_degrees=0, vertical=True, flip=False), 12),
        ("Bent 70 degrees", dict(length=190, thickness=22, count=16, gap=3, bend_degrees=70, vertical=True, flip=False), 11),
        ("Lying down, bent 60", dict(length=230, thickness=18, count=18, gap=3, bend_degrees=60, vertical=False, flip=False), 13),
    ]
    cell_w, cell_h = 280, 290
    sheet = Image.new("RGBA", (cell_w * len(examples), cell_h), (25, 22, 20, 255))
    pen = ImageDraw.Draw(sheet)

    def tinted(image, color, alpha):
        data = np.array(image).astype(float)
        data[..., :3] *= color
        data[..., 3] *= alpha
        return Image.fromarray(np.clip(data, 0, 255).astype(np.uint8))

    for column, (label, shape, lit) in enumerate(examples):
        cx, cy = column * cell_w + cell_w / 2, 125
        pieces = shield_pieces(**shape)
        art = pill_h if shape["vertical"] else pill_v
        for index, (x, y, rotation, width, height) in enumerate(pieces):
            on = index < lit
            piece = tinted(art.resize((max(1, round(width)), max(1, round(height))), Image.LANCZOS),
                           gold if on else gold * 0.22, 1 if on else 0.75)
            piece = piece.rotate(math.degrees(rotation), resample=Image.BICUBIC, expand=True)
            sheet.alpha_composite(piece, (round(cx + x - piece.width / 2), round(cy - y - piece.height / 2)))
        bottom = max(-y + h / 2 for _, y, _, _, h in pieces) if shape["vertical"] else max(-y for _, y, _, _, _ in pieces) + shape["thickness"] / 2
        number = "302"
        size = font(18)
        pen.text((cx - pen.textlength(number, font=size) / 2, cy + bottom + 6), number, fill=(255, 255, 255, 255), font=size)
        pen.text((column * cell_w + 12, cell_h - 26), label, fill=(225, 220, 210, 255), font=font(15))
    sheet.save(os.path.join(HERE, "shield_preview.png"))


# Saving --------------------------------------------------------------------------------------------

def save(image, name):
    small = image.resize((SIZE, SIZE), Image.LANCZOS)
    small.save(os.path.join(MEDIA, name + ".tga"), format="TGA")
    return small


def font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # older Pillow
        return ImageFont.load_default()


def preview(groups):
    """Every style as three charges with one used (lit, lit, spent), labeled, on a dark background."""
    tile, gap, columns = 64, 6, 4
    width = 3 * tile + 2 * gap
    cell_w, cell_h = width + 24, tile + 34
    rows = (len(groups) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * cell_w + 12, rows * cell_h + 12), (25, 22, 20, 255))
    pen = ImageDraw.Draw(sheet)
    for index, (label, lit, spent) in enumerate(groups):
        left = 12 + (index % columns) * cell_w
        top = 12 + (index // columns) * cell_h
        for slot, piece in enumerate((lit, lit, spent)):
            sheet.alpha_composite(piece.resize((tile, tile), Image.LANCZOS), (left + slot * (tile + gap), top))
        pen.text((left, top + tile + 6), label, fill=(225, 220, 210, 255), font=font(15))
    sheet.save(os.path.join(HERE, "preview.png"))


if __name__ == "__main__":
    os.makedirs(MEDIA, exist_ok=True)
    groups = []
    for name, theme in THEMES.items():
        lit, spent = save(full_orb(theme), f"orb_{name}_full"), save(empty_orb(theme), f"orb_{name}_empty")
        groups.append((f"Orbs: {name}", lit, spent))
    spent = save(gem(None, False), "gem_empty")
    for name, color in GEMS.items():
        groups.append((f"Gems: {name}", save(gem(color, True), f"gem_{name}"), spent))
    preview(groups)
    pill_h, pill_v = capsule(128, 32), capsule(32, 128)
    pill_h.save(os.path.join(MEDIA, "pill_h.tga"), format="TGA")
    pill_v.save(os.path.join(MEDIA, "pill_v.tga"), format="TGA")
    shield_preview(pill_h, pill_v)
    print(f"Wrote {len(THEMES) * 2 + len(GEMS) + 3} textures to Media/Charges, tools/preview.png and tools/shield_preview.png")
