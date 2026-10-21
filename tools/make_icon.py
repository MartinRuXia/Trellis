#!/usr/bin/env python3
"""Generate the macOS app icon for 目录模板."""
import json
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "DirTemplate", "Assets.xcassets", "AppIcon.appiconset")
S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_mask(size, inset, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([inset, inset, size - inset, size - inset], radius=radius, fill=255)
    return mask


def star(draw, cx, cy, outer, inner, fill):
    import math
    points = []
    for i in range(8):
        r = outer if i % 2 == 0 else inner
        a = -math.pi / 2 + i * math.pi / 4
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(points, fill=fill)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    # soft drop shadow
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([96, 112, S - 96, S - 80], radius=196, fill=(16, 28, 92, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(34))
    img = Image.alpha_composite(img, shadow)

    # gradient body
    inset, radius = 92, 196
    grad = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(grad)
    top, bottom = (95, 128, 255), (28, 63, 214)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp(top, bottom, y / (S - 1)))
    body = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    body.paste(grad, (0, 0), rounded_mask(S, inset, radius))

    # subtle top gloss
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gld = ImageDraw.Draw(gloss)
    gld.rounded_rectangle([inset, inset, S - inset, inset + 300], radius=radius, fill=(255, 255, 255, 26))
    body = Image.alpha_composite(body, gloss)

    draw = ImageDraw.Draw(body)

    # folder: back tab
    draw.rounded_rectangle([306, 312, 604, 470], radius=36, fill=(214, 224, 255, 255))
    # folder: body
    draw.rounded_rectangle([268, 424, 776, 748], radius=54, fill=(255, 255, 255, 255))
    # folder: subtle inner line (front flap)
    draw.rounded_rectangle([268, 530, 776, 748], radius=54, fill=(232, 239, 255, 255))

    # sparkle
    star(draw, 742, 330, 96, 30, (255, 255, 255, 255))
    star(draw, 820, 232, 40, 13, (190, 208, 255, 255))

    img = Image.alpha_composite(img, body)
    img.save(os.path.join(OUT, "icon_1024.png"))

    sizes = {16: [16, 32], 32: [32, 64], 128: [128, 256], 256: [256, 512], 512: [512, 1024]}
    images = []
    for base, scales in sizes.items():
        for i, px in enumerate(scales):
            scale = "1x" if i == 0 else "2x"
            name = f"icon_{px}.png"
            resized = img.resize((px, px), Image.LANCZOS)
            resized.save(os.path.join(OUT, name))
            images.append({"idiom": "mac", "scale": scale, "size": f"{base}x{base}", "filename": name})

    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)

    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

    print("icon written to", OUT)


if __name__ == "__main__":
    main()
