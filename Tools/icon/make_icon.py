"""App icon: three screenshots fanned into a stack on the brand gradient (violet DSBrand → coral DSBrandSecondary).

    python3 Tools/icon/make_icon.py [out_dir]   # default: the app's AppIcon.appiconset

Writes AppIcon.png (light), AppIcon-Dark.png and AppIcon-Tinted.png at 1024 px. Drawn at 4x and scaled down for
clean edges. Needs Pillow.
"""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 4                       # supersampling
N = 1024 * S
VIOLET, CORAL = (0x5B, 0x3D, 0xF5), (0xF2, 0x54, 0x2D)
VIOLET_DARK, CORAL_DARK = (0x7A, 0x5C, 0xFF), (0xFF, 0x6A, 0x3D)
INK = (0x0E, 0x0C, 0x14)


def gradient(a, b, size=N):
    """Diagonal top-left → bottom-right, like Palette.brandGradient"""
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = min(1, max(0, (x + y) / 510))
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return small.resize((size, size), Image.BICUBIC)


def card(w, h, radius, fill, content=None):
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=fill)
    if content:
        content(d, w, h)
    return layer


def front_content(accent):
    def draw(d, w, h):
        pad = int(w * 0.13)
        # a photo block in the brand gradient, then lines of text: a screenshot, simplified
        top = int(h * 0.12)
        block_h = int(h * 0.36)
        block = gradient(*accent, size=max(w, h)).resize((w - 2 * pad, block_h))
        mask = Image.new("L", block.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, block.size[0] - 1, block.size[1] - 1), radius=int(w * 0.07), fill=255)
        d._image.paste(block, (pad, top), mask)
        y = top + block_h + int(h * 0.08)
        line_h = int(h * 0.05)
        for frac in (0.78, 0.56, 0.68):
            d.rounded_rectangle((pad, y, pad + int((w - 2 * pad) * frac), y + line_h), radius=line_h // 2,
                                fill=(0xD9, 0xD4, 0xE6, 255))
            y += int(line_h * 2.0)
    return draw


def place(base, layer, center, angle, shadow_alpha):
    rotated = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - rotated.size[0] / 2)
    y = int(center[1] - rotated.size[1] / 2)
    if shadow_alpha:
        alpha = rotated.split()[-1].point(lambda a: a * shadow_alpha // 255)
        shadow = Image.new("RGBA", rotated.size, (20, 8, 40, 0))
        shadow.putalpha(alpha)
        shadow = shadow.filter(ImageFilter.GaussianBlur(28 * S))
        base.alpha_composite(shadow, (x, y + 26 * S))
    base.alpha_composite(rotated, (x, y))


def icon(background, back_fill, middle_fill, front_fill, accent, shadow=110):
    base = background.convert("RGBA")
    # Inside the middle ~80%: iOS rounds the corners off
    w, h, r = 400 * S, 530 * S, 66 * S
    cx, cy = N // 2, int(N * 0.52)
    place(base, card(w, h, r, back_fill), (cx - 84 * S, cy + 8 * S), 15, shadow // 2)
    place(base, card(w, h, r, middle_fill), (cx + 80 * S, cy - 2 * S), -11, shadow // 2)
    place(base, card(w, h, r, front_fill, front_content(accent)), (cx, cy), 2, shadow)
    return base.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main(out):
    os.makedirs(out, exist_ok=True)
    # Solid back cards (lavender, peach): see-through ones turn grey where they overlap, and two colours read as
    # two different stacks
    light = icon(gradient(VIOLET, CORAL), (0xC9, 0xBE, 0xFF, 255), (0xFF, 0xC6, 0xB4, 255), (255, 255, 255, 255),
                 (VIOLET, CORAL))
    light.save(os.path.join(out, "AppIcon.png"))
    # Dark: the stack glows on near-black, the photo block keeps the brand colours
    dark_bg = Image.new("RGB", (N, N), INK)
    glow = gradient(VIOLET_DARK, CORAL_DARK).convert("RGBA")
    glow.putalpha(70)
    dark_bg = Image.alpha_composite(dark_bg.convert("RGBA"), glow).convert("RGB")
    dark = icon(dark_bg, (0x4B, 0x3C, 0x8F, 255), (0x8A, 0x45, 0x3A, 255), (0x26, 0x22, 0x33, 255),
                (VIOLET_DARK, CORAL_DARK), shadow=160)
    dark.save(os.path.join(out, "AppIcon-Dark.png"))
    # Tinted: iOS colours a grayscale icon; light shapes on black
    tinted = icon(Image.new("RGB", (N, N), (0, 0, 0)), (0x70, 0x70, 0x70, 255), (0xA8, 0xA8, 0xA8, 255), (255, 255, 255, 255),
                  ((120, 120, 120), (60, 60, 60)), shadow=0).convert("L")
    tinted.save(os.path.join(out, "AppIcon-Tinted.png"))
    print("wrote", out)


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "ScreenshotSorter/Resources/Assets.xcassets/AppIcon.appiconset"))
