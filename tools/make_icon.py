#!/usr/bin/env python3
"""生成应用图标：深绿毡布 + 金色边框 + 叠放的麻将牌（红中）+ 闪光。
输出：assets/icon/app_icon.png（1024）与 assets/icon/launcher_192.png（Android 启动图标）。
依赖：Pillow；字体使用项目内的 assets/fonts/NotoSerifSC.ttf。
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "icon")
FONT = os.path.join(ROOT, "assets", "fonts", "NotoSerifSC.ttf")
S = 1024          # 最终尺寸
SS = 2            # 超采样倍数
N = S * SS


def lerp(a, b, t):
    return a + (b - a) * t


def radial_bg(size, inner, outer):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c = size / 2
    maxd = math.hypot(c, c)
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / maxd
            t = min(1.0, d ** 0.9)
            px[x, y] = tuple(int(lerp(inner[i], outer[i], t)) for i in range(3))
    return img


def rounded_mask(size, box, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def tile_layer(width, height, radius, face_color, edge_color, char=None, char_color=None, font=None):
    """单张麻将牌（含下沿厚度），返回 RGBA 小图。"""
    thick = int(height * 0.085)
    w, h = width, height + thick
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, thick, w - 1, h - 1), radius=radius, fill=edge_color)
    d.rounded_rectangle((0, 0, w - 1, height - 1), radius=radius, fill=face_color)
    # 面上的柔和高光（白色径向渐变，叠在牌面上）
    hl = Image.new("L", (w, h), 0)
    ImageDraw.Draw(hl).ellipse((-w * 0.2, -height * 0.35, w * 0.9, height * 0.45), fill=85)
    hl = hl.filter(ImageFilter.GaussianBlur(radius * 0.6))
    face_mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(face_mask).rounded_rectangle((0, 0, w - 1, height - 1), radius=radius, fill=255)
    hl = Image.composite(hl, Image.new("L", (w, h), 0), face_mask)
    img = Image.composite(Image.new("RGBA", (w, h), (255, 255, 255, 255)), img, hl)
    d = ImageDraw.Draw(img)
    if char and font:
        bbox = d.textbbox((0, 0), char, font=font)
        cw, ch = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text(((w - cw) / 2 - bbox[0], (height - ch) / 2 - bbox[1]), char, font=font, fill=char_color,
               stroke_width=int(font.size * 0.028), stroke_fill=char_color)
    return img


def soft_shadow(alpha, pad, blur, opacity):
    """把牌的 alpha 通道扩大画布后模糊，避免模糊在画布边缘被裁切出硬边。"""
    w, h = alpha.size
    canvas = Image.new("L", (w + pad * 2, h + pad * 2), 0)
    canvas.paste(alpha.point(lambda v: int(v * opacity)), (pad, pad))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.putalpha(canvas)
    return out


def sparkle(draw, cx, cy, r, color):
    pts = []
    for i in range(8):
        ang = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    draw.polygon(pts, fill=color)


def main():
    os.makedirs(OUT, exist_ok=True)
    # 1) 背景：毡布径向渐变 + 圆角裁切
    base = radial_bg(N, (46, 139, 87), (8, 52, 33)).convert("RGBA")
    # 轻微纹理
    tex = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    for k in range(900):
        x = (k * 977) % N
        y = (k * 1531) % N
        td.point((x, y), fill=(255, 255, 255, 14))
    base = Image.alpha_composite(base, tex)
    mask = rounded_mask(N, (0, 0, N - 1, N - 1), int(N * 0.22))
    icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    icon.paste(base, (0, 0), mask)

    # 2) 金色边框（外圈 + 内细线）
    fd = ImageDraw.Draw(icon)
    inset = int(N * 0.035)
    fd.rounded_rectangle((inset, inset, N - inset, N - inset), radius=int(N * 0.19),
                         outline=(232, 193, 112, 255), width=int(N * 0.022))
    inset2 = inset + int(N * 0.035)
    fd.rounded_rectangle((inset2, inset2, N - inset2, N - inset2), radius=int(N * 0.16),
                         outline=(255, 236, 170, 110), width=int(N * 0.006))

    # 3) 背景两张斜放的牌（暗色）
    back_font = ImageFont.truetype(FONT, int(N * 0.2))
    tw, th = int(N * 0.36), int(N * 0.5)
    for ang, dx, dy, col in [(-19, -150, 30, (196, 210, 200)), (17, 150, 20, (196, 210, 200))]:
        t = tile_layer(tw, th, int(N * 0.05), col, (120, 140, 130))
        t = t.rotate(ang, resample=Image.BICUBIC, expand=True)
        pad = int(N * 0.06)
        shadow = soft_shadow(t.split()[3], pad, N * 0.012, 0.45)
        pos = (N // 2 + dx - t.size[0] // 2, N // 2 + dy - t.size[1] // 2 + 10)
        icon.alpha_composite(shadow, (pos[0] + 14 - pad, pos[1] + 18 - pad))
        icon.alpha_composite(t, pos)

    # 4) 前景：红中牌
    main_font = ImageFont.truetype(FONT, int(N * 0.36))
    tw, th = int(N * 0.44), int(N * 0.6)
    t = tile_layer(tw, th, int(N * 0.06), (252, 248, 236), (201, 182, 142), "中",
                   (198, 40, 40), main_font)
    t = t.rotate(-4, resample=Image.BICUBIC, expand=True)
    pad = int(N * 0.09)
    shadow = soft_shadow(t.split()[3], pad, N * 0.02, 0.6)
    pos = (N // 2 - t.size[0] // 2, N // 2 - t.size[1] // 2 + 18)
    icon.alpha_composite(shadow, (pos[0] + 6 - pad, pos[1] + 26 - pad))
    icon.alpha_composite(t, pos)

    # 5) 闪光
    glint = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glint)
    sparkle(gd, N * 0.80, N * 0.22, N * 0.075, (255, 236, 170, 255))
    sparkle(gd, N * 0.19, N * 0.78, N * 0.05, (255, 236, 170, 230))
    sparkle(gd, N * 0.84, N * 0.74, N * 0.03, (255, 255, 255, 220))
    gd.ellipse((N * 0.12, N * 0.14, N * 0.2, N * 0.22), fill=(255, 255, 255, 120))
    glint = glint.filter(ImageFilter.GaussianBlur(N * 0.004))
    icon = Image.alpha_composite(icon, glint)

    final = icon.resize((S, S), Image.LANCZOS)
    final.save(os.path.join(OUT, "app_icon.png"))
    final.resize((192, 192), Image.LANCZOS).save(os.path.join(OUT, "launcher_192.png"))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
