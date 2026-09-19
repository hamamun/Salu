#!/usr/bin/env python3
"""Render the SALU main icon — Frost III · Prism — into every artifact.

Pure Pillow, deterministic. Design space is 100×100 units (same coordinates
as design/icons-preview/concepts3.html · Frost III · Prism), scaled to the
target pixel size.

Outputs:
  assets/images/salu_logo.png            1024  (in-app logo, 5 call sites)
  salu_app_icon.png                      1024  (branding)
  windows/runner/resources/app_icon.ico  16..256 (exe icon)
  design/iptv-channel-preview/assets/salu.png 160 (preview tooling)
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# ── design-space geometry (100×100) ─────────────────────────────────────
RADIUS = 22.5                      # tile corner radius
FACET_L = [(36, 30), (36, 70), (54, 50)]      # bright left facet
FACET_T = [(36, 30), (70, 50), (54, 50)]      # mid top-right facet
FACET_B = [(36, 70), (70, 50), (54, 50)]      # dim bottom facet
SIL     = [(36, 30), (70, 50), (36, 70)]      # full prism silhouette
BASE_TOP = (0x1C, 0x20, 0x27)      # tile gradient, top
BASE_BOT = (0x14, 0x16, 0x1A)      # tile gradient, bottom
INK = (0xF4, 0xF6, 0xF8)           # prism white


def render(S: int) -> Image.Image:
    u = S / 100.0
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # tile silhouette mask
    tile = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tile).rounded_rectangle(
        [0, 0, S - 1, S - 1], radius=int(RADIUS * u), fill=255)

    def clip_to_tile(layer: Image.Image) -> Image.Image:
        a = layer.getchannel("A")
        a = Image.frombytes("L", a.size,
                            bytes(min(x, y) for x, y in
                                  zip(a.tobytes(), tile.tobytes())))
        layer.putalpha(a)
        return layer

    # base: vertical dark gradient
    base = Image.new("RGBA", (S, S))
    px = base.load()
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(a + (b - a) * t) for a, b in zip(BASE_TOP, BASE_BOT))
        for x in range(S):
            px[x, y] = (*c, 255)
    base.putalpha(tile)
    img.alpha_composite(base)

    # top light: white sheen fading to 0 at 55% height
    sheen = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sp = sheen.load()
    for y in range(int(0.55 * S)):
        a = int(26 * (1 - y / (0.55 * S)))
        for x in range(S):
            sp[x, y] = (255, 255, 255, a)
    img.alpha_composite(clip_to_tile(sheen))

    # quiet horizontal glint line at y=24
    glint = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glint).rectangle(
        [0, int(23.5 * u), S, int(24.5 * u)], fill=(255, 255, 255, 18))
    img.alpha_composite(clip_to_tile(glint))

    # soft drop shadow under the prism
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon(
        [(x * u, (y + 1.8) * u) for x, y in SIL], fill=(0, 0, 0, 140))
    sh = sh.filter(ImageFilter.GaussianBlur(2.6 * u))
    img.alpha_composite(clip_to_tile(sh))

    # prism facets — one shape, three lights
    fac = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(fac)
    d.polygon([(x * u, y * u) for x, y in FACET_B], fill=(*INK, 71))   # .28
    d.polygon([(x * u, y * u) for x, y in FACET_T], fill=(*INK, 140))  # .55
    d.polygon([(x * u, y * u) for x, y in FACET_L], fill=(*INK, 242))  # .95
    img.alpha_composite(fac)

    # hairline border
    bw = max(1, int(1.2 * u))
    bord = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(bord).rounded_rectangle(
        [bw / 2, bw / 2, S - 1 - bw / 2, S - 1 - bw / 2],
        radius=int((RADIUS - 0.6) * u), outline=(255, 255, 255, 36), width=bw)
    img.alpha_composite(bord)
    return img


def main() -> None:
    master = render(1024)

    logo = os.path.join(ROOT, "assets", "images", "salu_logo.png")
    app = os.path.join(ROOT, "salu_app_icon.png")
    ico = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    prev = os.path.join(ROOT, "design", "iptv-channel-preview",
                        "assets", "salu.png")

    master.save(logo)
    master.save(app)
    master.resize((160, 160), Image.LANCZOS).save(prev)

    master.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48),
                            (64, 64), (128, 128), (256, 256)])

    for p in (logo, app, ico, prev):
        print("wrote", os.path.relpath(p, ROOT), os.path.getsize(p), "bytes")


if __name__ == "__main__":
    main()
