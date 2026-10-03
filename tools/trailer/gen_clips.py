"""Génère les plans vidéo (avec son) de la bande-annonce via ComfyUI + MiniMax H3 (image -> vidéo).

Usage : python tools/trailer/gen_clips.py [id ...]
Workflow : tools/comfy/workflows/video.json ; images de départ : illustrations du jeu copiées dans l'input ComfyUI.
Sortie : tools/trailer/clips/<id>.mp4
"""
import json
import os
import shutil
import sys
import time
import urllib.parse

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
COMFY = "http://127.0.0.1:8188"
sys.path.insert(0, os.path.join(ROOT, "tools", "comfy"))
from generate import fill  # noqa: E402

STYLE = "2D cartoon animation, hand-drawn medieval fantasy style, thick ink outlines, cel shading, vibrant colors. "
CLIPS = {
    "clip_arena": ("labrute/key_art.jpg", "A horned barbarian and a green orc brawl in a sandy tournament arena, trading huge comical punches, dust clouds and sparks fly, the crowd in the wooden stands cheers and waves banners, camera slowly pushes in. Sound: punches, crowd roaring, no speech, no music.", 1234),
    "clip_tavern": ("labrute/key_tavern.jpg", "Inside a crowded medieval tavern, elves, dwarves and orcs laugh, slam their mugs on the table and point at fighter posters on the wall, candles flicker, camera slowly dollies forward. Sound: tavern chatter, laughter, mugs clinking, no clear speech, no music.", 2345),
    "clip_campaign": ("labrute/key_campaign.jpg", "A party of cartoon heroes marches along a winding road toward a dark castle and a smoking volcano at sunrise, banners flapping in the wind, birds fly across the sky, camera slowly pans right. Sound: wind, footsteps, distant thunder, no speech, no music.", 3456),
    "clip_dragon": ("labrute/key_dragon.jpg", "A gigantic red dragon king spreads its wings and roars, breathing a huge torrent of fire toward a tiny brave knight who raises his shield, embers and lava everywhere, camera shakes. Sound: dragon roar, roaring fire, no speech, no music.", 4567),
    "clip_brawl": ("labrute/menu_bg.jpg", "Two muscular brawlers arm wrestle at a wooden table in a cozy tavern by the fireplace, veins popping, sweat flying, onlookers cheer, one finally slams the other's arm down. Sound: grunts, crowd cheering, crackling fire, no speech, no music.", 5678),
}


def run(graph, timeout=2400):
    r = requests.post(COMFY + "/prompt", json={"prompt": graph}, timeout=30)
    r.raise_for_status()
    pid = r.json()["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        h = requests.get(COMFY + "/history/" + pid, timeout=30).json()
        if pid in h:
            if h[pid].get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(h[pid]["status"])[:800])
            for out in h[pid]["outputs"].values():
                for key in ("images", "videos", "gifs"):
                    for f in out.get(key, []):
                        if f["filename"].endswith(".mp4"):
                            return f
        time.sleep(3)
    raise TimeoutError(pid)


def main():
    wf = json.load(open(os.path.join(ROOT, "tools", "comfy", "workflows", "video.json"), encoding="utf-8"))
    wf = {k: v for k, v in wf.items() if not k.startswith("_")}
    ids = sys.argv[1:] or list(CLIPS)
    os.makedirs(os.path.join(HERE, "clips"), exist_ok=True)
    for cid in ids:
        dest = os.path.join(HERE, "clips", cid + ".mp4")
        if os.path.exists(dest) and not sys.argv[1:]:
            continue
        image, prompt, seed = CLIPS[cid]
        t0 = time.time()
        f = run(fill(wf, {"image": image, "prompt": STYLE + prompt, "width": 1280, "height": 704, "length": 124, "seed": seed, "prefix": "labrute/trailer/" + cid}))
        q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": f.get("type", "output")})
        data = requests.get(COMFY + "/view?" + q, timeout=300).content
        open(dest, "wb").write(data)
        print("OK", cid, "(%.0fs)" % (time.time() - t0), flush=True)


if __name__ == "__main__":
    main()
