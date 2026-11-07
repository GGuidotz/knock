"""Disegna l'icona classica di Knock (Resources/Icon/AppIcon-1024.png): la griglia 2x2 della barra dei menu su un
fondo blu notte, con il quadrato in alto a destra acceso e due onde che partono dal tap.
Uso: python3 -I tools/render-icon.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")

# Fondo: forma arrotondata nella griglia delle icone macOS (824 px con margine), sfumatura verticale.
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
margin, size, radius = 100, 824, 185
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bottom = (44, 62, 120), (16, 22, 52)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([margin, margin, margin + size, margin + size], radius, fill=255)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([margin, margin + 12, margin + size, margin + size + 12], radius, fill=(0, 0, 0, 110))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
cell, gap = 190, 56
gx = (S - (2 * cell + gap)) // 2
gy = (S - (2 * cell + gap)) // 2 + 10
accent = (88, 200, 255, 255)
for row in range(2):
    for col in range(2):
        x0, y0 = gx + col * (cell + gap), gy + row * (cell + gap)
        box = [x0, y0, x0 + cell, y0 + cell]
        if row == 0 and col == 1:
            d.rounded_rectangle(box, 38, fill=accent)
        else:
            d.rounded_rectangle(box, 38, outline=(255, 255, 255, 215), width=22)

# Onde del tap intorno al quadrato acceso.
cx, cy = gx + cell + gap + cell // 2, gy + cell // 2
for r, a in ((150, 150), (205, 80)):
    d.arc([cx - r, cy - r, cx + r, cy + r], start=-80, end=-10, fill=accent[:3] + (a,), width=16)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print(OUT)
