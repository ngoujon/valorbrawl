"""Prépare les assets du site vitrine (website/assets) à partir des assets du jeu : images en WebP, polices.

Usage : python tools/build_site.py [dossier_captures]
"""
import json
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "website", "assets")


def webp(src, dest, width=None, quality=82):
    im = Image.open(src)
    im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
    if width and im.width > width:
        im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    im.save(dest, "WEBP", quality=quality, method=6)


def main():
    content = json.load(open(os.path.join(ROOT, "data", "content.json"), encoding="utf-8"))
    a = lambda *p: os.path.join(ROOT, "assets", *p)
    o = lambda *p: os.path.join(OUT, *p)
    for name in ["key_art", "key_dragon", "key_tavern", "key_campaign", "menu_bg", "arene", "map_bg"]:
        webp(a("bg", name + ".jpg"), o("bg", name + ".webp"), 1600)
    webp(a("ui", "logo.png"), o("logo.webp"), 900)
    webp(a("ui", "icon.png"), o("icon.webp"), 256)
    Image.open(a("ui", "icon.png")).resize((64, 64), Image.LANCZOS).save(o("favicon.png"))
    for h in content["heroes"]:
        webp(a("characters", h["id"] + ".png"), o("heroes", h["id"] + ".webp"), 360)
    for c in content["campaign"]:
        webp(a("bosses", c["boss"] + ".png"), o("bosses", c["boss"] + ".webp"), 360)
    for p in content["pets"]:
        webp(a("pets", p["id"] + ".png"), o("pets", p["id"] + ".webp"), 220)
    for w in content["weapons"]:
        webp(a("weapons", w["id"] + ".png"), o("weapons", w["id"] + ".webp"), 128)
    for s in content["skills"]:
        webp(a("skills", s["id"] + ".png"), o("skills", s["id"] + ".webp"), 128)
    os.makedirs(o("fonts"), exist_ok=True)
    for f in ["MedievalSharp.ttf", "AlegreyaSans-Medium.ttf", "AlegreyaSans-ExtraBold.ttf"]:
        shutil.copy(a("fonts", f), o("fonts", f))
    if len(sys.argv) > 1:
        for f in sorted(os.listdir(sys.argv[1])):
            if f.endswith(".png"):
                webp(os.path.join(sys.argv[1], f), o("shots", f.replace(".png", ".webp")), 1280, 80)
    json.dump(content, open(o("content.json"), "w", encoding="utf-8"), ensure_ascii=False)
    print("Assets du site prêts dans", OUT)


if __name__ == "__main__":
    main()
