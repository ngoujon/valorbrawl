"""Bande-annonce de Brutes & Légendes (~72 s, 1280 × 720, 30 i/s).

Sources :
- plans vidéo + son générés par ComfyUI / MiniMax H3 (tools/trailer/gen_clips.py) -> tools/trailer/clips/*.mp4
- séquences de gameplay filmées avec le Movie Maker de Godot :
    godot --path . --write-movie tools/trailer/rec/<combat>.avi --fixed-fps 30 -- --play-fight=tools/trailer/<combat>.json
  (combats choisis par server/test/pick_trailer_fights.js)
- musique : tools/trailer/music.ogg (ComfyUI, ACE-Step) ; textes en MedievalSharp.
Sortie : build/trailer/brutes_et_legendes_trailer.mp4 (+ copie dans website/assets/trailer.mp4)
"""
import os
import shutil
import subprocess

import imageio_ffmpeg
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
FF = imageio_ffmpeg.get_ffmpeg_exe()
W, H, FPS = 1280, 720, 30
OUT_DIR = os.path.join(ROOT, "build", "trailer")
OUT = os.path.join(OUT_DIR, "brutes_et_legendes_trailer.mp4")
FONT = os.path.join(ROOT, "assets", "fonts", "MedievalSharp.ttf")
FONT_B = os.path.join(ROOT, "assets", "fonts", "AlegreyaSans-ExtraBold.ttf")
GOLD, CREAM = (242, 193, 78), (248, 236, 210)

# (type, source, début dans la source, durée, texte, volume du son de la source)
TIMELINE = [
    ("card_logo", None, 0, 3.5, None, 0),
    ("clip", "clips/clip_tavern.mp4", 0.2, 4.8, "Dans les tavernes du royaume...", 0.55),
    ("clip", "clips/clip_arena.mp4", 0.0, 5.0, "... les brutes règlent leurs comptes dans l'arène !", 0.7),
    ("card_heroes", None, 0, 3.5, "Forge ta brute", 0),
    ("clip", "rec/fight_duel.avi", 4.0, 9.0, "Des combats automatiques spectaculaires", 0.8),
    ("clip", "clips/clip_brawl.mp4", 0.0, 4.8, "Défie les joueurs du monde entier... ou l'IA", 0.6),
    ("clip", "rec/fight_team.avi", 6.0, 8.0, "PvP en équipes, coopération, salons en ligne", 0.8),
    ("clip", "clips/clip_campaign.mp4", 0.0, 5.0, "Une campagne épique en 10 chapitres", 0.5),
    ("card_bosses", None, 0, 3.5, "10 boss légendaires", 0),
    ("clip", "rec/fight_dragon.avi", 30.0, 9.0, "Affronte le Roi-Dragon... à plusieurs !", 0.8),
    ("clip", "clips/clip_dragon.mp4", 0.0, 5.0, None, 0.8),
    ("card_features", None, 0, 4.5, None, 0),
    ("card_end", None, 0, 6.5, None, 0),
]


def font(size, bold=False):
    return ImageFont.truetype(FONT_B if bold else FONT, size)


def cover(im):
    r = max(W / im.width, H / im.height)
    im = im.resize((int(im.width * r + 0.5), int(im.height * r + 0.5)), Image.LANCZOS)
    x, y = (im.width - W) // 2, (im.height - H) // 2
    return im.crop((x, y, x + W, y + H))


def read_frames(path, start, dur):
    cmd = [FF, "-loglevel", "error", "-ss", str(start), "-t", str(dur), "-i", path,
           "-vf", "scale=%d:%d:force_original_aspect_ratio=increase,crop=%d:%d,fps=%d" % (W, H, W, H, FPS),
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    n = int(round(dur * FPS))
    last = None
    for _ in range(n):
        raw = p.stdout.read(W * H * 3)
        if len(raw) < W * H * 3:
            break
        last = Image.frombytes("RGB", (W, H), raw)
        yield last
        n -= 1
    p.stdout.close()
    p.wait()
    while n > 0 and last is not None:  # source trop courte : on fige la dernière image
        n -= 1
        yield last


def caption(im, text, t, dur, size=46):
    """Texte doré en bas de l'image, fondu d'entrée/sortie."""
    if not text:
        return im
    a = min(1.0, t / 0.4, (dur - t) / 0.4)
    if a <= 0:
        return im
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    grad = Image.new("L", (1, 200))
    for y in range(200):
        grad.putpixel((0, y), int(170 * y / 199 * a))
    layer.paste((0, 0, 0, 255), (0, H - 200), grad.resize((W, 200)))
    f = font(size)
    tw = d.textlength(text, font=f)
    off = int((1 - min(1.0, t / 0.5)) * 20)
    d.text(((W - tw) / 2, H - 100 + off), text, font=f, fill=GOLD + (int(255 * a),), stroke_width=4, stroke_fill=(20, 10, 5, int(255 * a)))
    out = im.convert("RGBA")
    out.alpha_composite(layer)
    return out.convert("RGB")


_cache = {}


def asset(path, h=None):
    key = (path, h)
    if key not in _cache:
        im = Image.open(os.path.join(ROOT, path)).convert("RGBA")
        if h:
            im = im.resize((int(im.width * h / im.height), h), Image.LANCZOS)
        _cache[key] = im
    return _cache[key]


def ease(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


def background(name, t, zoom=0.04, dark=0.45):
    bg = asset("assets/bg/%s.jpg" % name)
    k = 1.0 + zoom * t
    im = cover(bg.convert("RGB").resize((int(bg.width * k), int(bg.height * k))))
    return Image.blend(im, Image.new("RGB", (W, H), (0, 0, 0)), dark)


def card(kind, t, dur, text):
    if kind == "card_logo":
        im = Image.new("RGB", (W, H), (12, 7, 4))
        logo = asset("assets/ui/logo.png", 330)
        a = ease(t / 1.2) * min(1.0, (dur - t) / 0.4)
        s = 0.85 + 0.15 * ease(t / 1.5)
        lg = logo.resize((int(logo.width * s), int(logo.height * s)))
        lg.putalpha(lg.getchannel("A").point(lambda v: int(v * a)))
        im.paste(lg, ((W - lg.width) // 2, (H - lg.height) // 2 - 20), lg)
        return im
    if kind == "card_heroes":
        im = background("arene", t)
        heroes = ["barbare", "chevalier", "elfe", "naine", "orc", "mage", "voleuse", "minotaure"]
        for i, h in enumerate(heroes):
            sp = asset("assets/characters/%s.png" % h, 270)
            p = ease((t - i * 0.12) / 0.5)
            x = int(40 + i * 150 - (1 - p) * 300)
            y = int(H - 330 + (1 - p) * 60)
            if p > 0:
                im.paste(sp, (x, y), sp)
        return caption(im, text, t, dur, 58)
    if kind == "card_bosses":
        im = background("arene_enfer", t)
        bosses = ["gobelin", "bandit", "sorciere", "troll", "chevalier_noir", "minotaure_roi", "geant", "liche", "demon", "dragon"]
        for i, b in enumerate(bosses):
            sp = asset("assets/bosses/%s.png" % b, 240 if i < 9 else 330)
            p = ease((t - i * 0.15) / 0.4)
            if p <= 0:
                continue
            x = 10 + i * 122 - (40 if i == 9 else 0)
            y = H - sp.height - 120 + int((1 - p) * 80)
            s = sp.copy()
            s.putalpha(s.getchannel("A").point(lambda v: int(v * p)))
            im.paste(s, (x, y), s)
        return caption(im, text, t, dur, 58)
    if kind == "card_features":
        im = background("key_tavern", t, dark=0.62)
        d = ImageDraw.Draw(im)
        lines = ["Arène PvP  -  Défis contre l'IA", "Campagne solo et en coopération", "Salons en ligne jusqu'à 3 contre 3",
                 "Amis, profil, passe de combat", "Progression sauvegardée sur le serveur"]
        for i, l in enumerate(lines):
            p = ease((t - i * 0.35) / 0.4)
            if p <= 0:
                continue
            f = font(44)
            tw = d.textlength(l, font=f)
            col = tuple(int(c * p) for c in GOLD if True)
            d.text(((W - tw) / 2 + (1 - p) * 60, 140 + i * 92), l, font=f, fill=col, stroke_width=3, stroke_fill=(15, 8, 4))
        return im
    if kind == "card_end":
        im = background("key_dragon", t, dark=0.6)
        logo = asset("assets/ui/logo.png", 300)
        a = ease(t / 0.8)
        lg = logo.copy()
        lg.putalpha(lg.getchannel("A").point(lambda v: int(v * a)))
        im.paste(lg, ((W - lg.width) // 2, 70), lg)
        d = ImageDraw.Draw(im)
        for i, (l, f, c) in enumerate([("Télécharge gratuitement le jeu pour Windows", font(34, True), CREAM),
                                        ("51.254.211.144/test-labrute", font(46), GOLD)]):
            p = ease((t - 0.8 - i * 0.4) / 0.5)
            if p <= 0:
                continue
            tw = d.textlength(l, font=f)
            d.text(((W - tw) / 2, 430 + i * 70), l, font=f, fill=tuple(int(x * p) for x in c), stroke_width=3, stroke_fill=(15, 8, 4))
        fade = min(1.0, (dur - t) / 0.8)
        return Image.blend(Image.new("RGB", (W, H)), im, max(0.0, fade))
    raise ValueError(kind)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    silent = os.path.join(OUT_DIR, "video_only.mp4")
    enc = subprocess.Popen([FF, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS),
                            "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-pix_fmt", "yuv420p", silent], stdin=subprocess.PIPE)
    audio_parts = []  # (fichier, début source, durée, position dans la bande-annonce, volume)
    pos = 0.0
    for kind, src, start, dur, text, vol in TIMELINE:
        print("%5.1fs  %s %s" % (pos, kind, src or ""), flush=True)
        n = int(round(dur * FPS))
        if kind == "clip":
            path = os.path.join(HERE, src)
            for i, fr in enumerate(read_frames(path, start, dur)):
                t = i / FPS
                fade = min(1.0, t / 0.25, (dur - t) / 0.25)
                if fade < 1:
                    fr = Image.blend(Image.new("RGB", (W, H)), fr, max(0.0, fade))
                enc.stdin.write(caption(fr, text, t, dur).tobytes())
            if vol > 0:
                audio_parts.append((path, start, dur, pos, vol))
        else:
            for i in range(n):
                enc.stdin.write(card(kind, i / FPS, dur, text).tobytes())
        pos += dur
    enc.stdin.close()
    enc.wait()
    total = pos
    # mixage : musique + sons des plans (MiniMax H3) et du gameplay
    music = os.path.join(HERE, "music.ogg")
    inputs = ["-i", silent, "-i", music]
    filters = ["[1:a]atrim=0:%.2f,afade=t=in:d=1.5,afade=t=out:st=%.2f:d=2.5,volume=0.85[m]" % (total, total - 2.5)]
    labels = ["[m]"]
    for k, (path, start, dur, at, vol) in enumerate(audio_parts):
        inputs += ["-ss", str(start), "-t", str(dur), "-i", path]
        idx = k + 2
        ms = int(at * 1000)
        filters.append("[%d:a]afade=t=in:d=0.2,afade=t=out:st=%.2f:d=0.3,volume=%.2f,adelay=%d|%d[a%d]" % (idx, dur - 0.3, vol, ms, ms, k))
        labels.append("[a%d]" % k)
    filters.append("%samix=inputs=%d:duration=first:normalize=0,alimiter=limit=0.95[aout]" % ("".join(labels), len(labels)))
    subprocess.run([FF, "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(filters), "-map", "0:v", "-map", "[aout]",
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", OUT], check=True)
    os.remove(silent)
    shutil.copy(OUT, os.path.join(ROOT, "website", "assets", "trailer.mp4"))
    print("Bande-annonce : %s (%.1f s, %.1f Mo)" % (OUT, total, os.path.getsize(OUT) / 1e6))


if __name__ == "__main__":
    main()
