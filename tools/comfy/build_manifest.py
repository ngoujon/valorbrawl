"""Construit tools/comfy/manifest.json (toutes les images, musiques et SFX du jeu générés avec ComfyUI).

Usage : python tools/comfy/build_manifest.py   puis   python tools/comfy/generate.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

STYLES = {
    "char": "side view facing right, full body, funny caricature with big head and short legs, 2D flash game cartoon style, "
            "thick black ink outlines, flat cel shading, warm medieval fantasy colors, centered, single subject, "
            "isolated on plain white background, no ground, no shadow, no text",
    "icon": "medieval fantasy game item icon, 2D cartoon style, thick black ink outlines, flat cel shading, warm saturated colors, "
            "single object centered, isolated on plain white background, no shadow, no text",
    "skill": "round medieval fantasy skill badge icon, 2D cartoon style, thick black ink outlines, flat cel shading, "
             "vibrant colors, centered emblem, isolated on plain white background, no text, no letters",
    "scene": "wide 2D side-view video game fighting arena background, flat ground in the lower third, empty stage, no characters, "
             "hand-drawn cartoon illustration, thick ink outlines, cel shading, warm medieval fantasy colors, detailed, no text",
    "art": "epic medieval fantasy key art, 2D cartoon illustration, thick ink outlines, cel shading, dramatic lighting, vibrant colors, detailed",
}
NEG = "blurry, photo, photorealistic, 3d render, text, letters, words, watermark, signature, logo, frame, border, cropped, multiple characters, duplicate"

HEROES = {
    "barbare": "a stocky muscular barbarian brawler with a horned helmet, braided red beard, fur loincloth, bare fists raised in fighting stance",
    "chevalier": "a chubby human knight in dented shiny plate armor with a plumed helmet, visor up showing a proud mustache, fists raised in fighting stance",
    "elfe": "a slender haughty female elf warrior with long blond hair, pointy ears, green leather armor and cape, fists raised in fighting stance",
    "naine": "a short chubby young woman warrior with a pretty clean-shaven girl face, freckles, rosy cheeks, two long thick orange pigtail braids, small iron viking helmet, chainmail tunic, big leather boots, fists raised in fighting stance",
    "orc": "a huge green-skinned orc brute with tusks, mohawk, spiked shoulder pad, ragged trousers, fists raised in fighting stance",
    "mage": "an old wizard brawler with a long white beard, tall pointy blue star hat, blue robe with rolled-up sleeves, fists raised in fighting stance",
    "voleuse": "a sly female rogue thief with a dark hood, red scarf, leather vest, mischievous grin, fists raised in fighting stance",
    "minotaure": "a burly minotaur fighter with a bull head, big horns, nose ring, brown fur, leather kilt, fists raised in fighting stance",
}
BOSSES = {
    "gobelin": "a small mean goblin king wearing a dented cooking pot as a crown, green skin, big ears, red cape, holding a dagger",
    "bandit": "a masked forest bandit archer with a green hood, black mask over the eyes, leather armor, holding a longbow",
    "sorciere": "an ugly swamp witch with green skin, crooked nose, ragged black dress, pointy hat with toads, holding a gnarled staff",
    "troll": "an enormous bridge troll with grey mossy skin, tiny head, giant arms, holding a huge tree trunk club",
    "chevalier_noir": "a menacing black knight in spiky dark armor with glowing red eyes in the helmet visor, holding a giant two-handed sword",
    "minotaure_roi": "a gigantic minotaur king with a golden crown on his horns, scarred red fur, heavy armor, holding a double axe",
    "geant": "a gigantic frost giant with icy blue skin, frozen beard, fur armor, holding a massive ice hammer",
    "liche": "a terrifying lich skeleton sorcerer with a golden crown, tattered purple robes, glowing green eyes, holding a scythe",
    "demon": "a huge red demon lord with bat wings, curved horns, flaming eyes, holding a burning trident",
    "dragon": "a fearsome red dragon king standing on hind legs, golden crown, big wings spread, fire in its mouth",
}
PETS = {
    "loup": "a fierce grey wolf snarling, running pose",
    "ours": "a huge angry brown bear standing on its hind legs, roaring",
    "dragonnet": "a cute baby red dragon with small wings, flying, puffing a little flame",
    "golem": "a massive stone golem made of mossy rocks, glowing blue runes",
}
WEAPONS = {
    "epee": "a short steel sword with a leather grip", "hache": "a big double-bladed war axe", "masse": "a spiked iron mace",
    "lance": "a long wooden spear with a steel tip and a red ribbon", "fleau": "a flail with a spiked iron ball on a chain",
    "marteau": "a giant two-handed war hammer", "dague": "a curved dagger with a jeweled hilt", "claymore": "one single huge two-handed claymore sword, vertical, only one sword",
    "faux": "a single farming scythe weapon with a long wooden handle and a curved steel blade, object only, no person", "trident": "a golden trident", "gourdin": "a lone wooden cudgel tilted diagonally, thick rounded end with iron nails, thin handle, a single object",
    "cimeterre": "a curved scimitar sword", "arc": "a wooden longbow with an arrow", "arbalete": "a heavy wooden crossbow",
    "baton": "a magic wizard staff with a glowing blue crystal", "fouet": "a spiked leather whip coiled",
}
SKILLS = {
    "force": "a flexing muscular arm, red background", "agilite": "a leaping cat silhouette, green background",
    "velocite": "a winged boot, yellow background", "vitalite": "a glowing red heart, pink background",
    "peau": "a cracked stone skin fist, grey background", "bouclier": "a round oak wooden shield, brown background",
    "contre": "two crossed swords with a curved arrow, orange background", "maitre": "a golden sword with laurels, gold background",
    "ombre": "a dark hooded shadow silhouette, purple background", "vampire": "a vampire fang dripping blood, dark red background",
    "survie": "a skull with a small flame of life, black background", "potion": "a red healing potion bottle, teal background",
    "feu": "a blazing fireball, orange background", "eclair": "a lightning bolt, blue background",
    "cri": "a screaming barbarian mouth with sound waves, red background", "sabotage": "a single sword blade snapped in half with flying broken metal pieces, grey background",
    "charme": "a pink heart with a spiral, magenta background", "fureur": "an angry red face with flames, crimson background",
}
ARENAS = {
    "arene": "a medieval tournament arena with wooden stands full of colorful banners, sandy ground, sunny sky",
    "arene_foret": "a forest clearing with giant oak trees, mushrooms and a goblin camp, grassy ground",
    "arene_marais": "a misty swamp with twisted trees, a witch hut on stilts, green fog, muddy ground",
    "arene_pont": "an old stone bridge over a river with mountains in the background, stone ground",
    "arene_chateau": "a dark castle courtyard at dusk with towers and torches, cobblestone ground",
    "arene_labyrinthe": "an ancient underground stone labyrinth with torches and bones, stone floor",
    "arene_glace": "frozen snowy mountains pass with ice crystals and a blizzard, snowy ground",
    "arene_crypte": "a spooky crypt with tombs, candles and green ghostly light, stone floor",
    "arene_enfer": "hell with lava rivers, black rocks and demonic statues, volcanic ground",
    "arene_dragon": "a volcano summit with a dragon gold treasure hoard, fiery sky, rocky ground",
}
SCENES = {
    "menu_bg": ("a cozy medieval fantasy tavern interior with brawlers arm wrestling, barrels, fireplace, warm candle light, cartoon, no text", 1600, 896),
    "map_bg": ("a hand-drawn fantasy board game map of one single invented kingdom island seen from above on old parchment, a winding dotted road crossing it from left to right through a green forest, a misty swamp, a stone bridge over a river, a dark castle, snowy mountains, a graveyard, a lava hell region and a volcano with a dragon at the far right, cartoon style, no text, no labels, not planet earth, no real continents", 1600, 896),
    "key_art": ("two cartoon brawlers, a horned barbarian and a green orc, clashing fists in a medieval arena, crowd cheering, dust and sparks, dynamic composition", 1600, 896),
    "key_dragon": ("a tiny brave cartoon knight facing a gigantic red dragon king on a volcano summit, fire everywhere, epic", 1600, 896),
    "key_tavern": ("a crowded medieval tavern with cartoon warriors, elves, dwarves and orcs challenging each other, posters of fighters on the wall", 1600, 896),
    "key_campaign": ("a cartoon hero party walking on a winding road through a fantasy kingdom toward a dark castle and a volcano, sunrise", 1600, 896),
}
UI = {
    "logo": ("game logo, the words \"BRUTES & LÉGENDES\" in big bold medieval golden letters with a crossed sword and axe behind, shield emblem, "
             "cartoon style, thick black outlines, isolated on plain white background", 1344, 768),
    "coin": ("a single shiny gold coin with an engraved crown, medieval fantasy game icon, cartoon style, thick black outlines, isolated on plain white background", 1024, 1024),
    "icon": ("game app icon, a cartoon angry barbarian face with a horned helmet in front of a crossed sword and axe on a red heraldic shield, "
             "thick black outlines, flat cel shading, centered, isolated on plain white background, no text", 1024, 1024),
}

MUSIC = [
    {"id": "menu", "out": "assets/music/menu.ogg", "duration": 90, "bpm": 100, "key": "D minor",
     "prompt": "medieval tavern folk music, lute, hurdy-gurdy, fiddle, bodhran drum, cheerful, humorous, instrumental, loopable"},
    {"id": "combat", "out": "assets/music/combat.ogg", "duration": 90, "bpm": 140, "key": "E minor",
     "prompt": "epic medieval battle music, fast war drums, brass fanfare, bagpipes, energetic, heroic, comedic fantasy fight, instrumental"},
    {"id": "campagne", "out": "assets/music/campagne.ogg", "duration": 90, "bpm": 90, "key": "C major",
     "prompt": "adventurous fantasy orchestral music, flute melody, strings, harp, horns, journey, hopeful, instrumental"},
    {"id": "boss", "out": "assets/music/boss.ogg", "duration": 90, "bpm": 150, "key": "C minor",
     "prompt": "dark epic boss battle music, choir, pipe organ, heavy drums, orchestral, intense, dramatic, instrumental"},
    {"id": "victoire", "out": "assets/music/victoire.ogg", "duration": 12, "bpm": 120, "key": "C major",
     "prompt": "short triumphant medieval victory fanfare, trumpets, drums, joyful, instrumental"},
    {"id": "defaite", "out": "assets/music/defaite.ogg", "duration": 10, "bpm": 70, "key": "A minor",
     "prompt": "short sad comedic defeat jingle, sad trombone, slow lute, instrumental"},
    {"id": "trailer", "out": "tools/trailer/music.ogg", "duration": 75, "bpm": 128, "key": "D minor",
     "prompt": "epic cinematic medieval fantasy trailer music, slow mysterious intro then war drums build up, choir, brass, bagpipes, powerful climax, instrumental"},
]
SFX = {
    "hit_sharp": ("sword slash cutting flesh impact, sharp metal swing hit", 1.0),
    "hit_blunt": ("heavy blunt club punch impact thud", 1.0),
    "punch": ("cartoon fist punch impact, whack", 0.8),
    "whoosh": ("fast weapon swing whoosh through air", 0.7),
    "block": ("sword hitting wooden shield, block clang", 0.9),
    "dodge": ("quick swoosh dodge, cloth movement", 0.6),
    "crit": ("massive critical hit impact with metal crash and bone crunch", 1.2),
    "arrow": ("bow string twang and arrow flying whoosh", 1.0),
    "fire": ("fireball spell cast, fire whoosh and explosion", 1.6),
    "lightning": ("lightning bolt thunder crack electric zap", 1.6),
    "heal": ("magic healing spell shimmer, sparkling chime", 1.5),
    "growl_wolf": ("angry wolf growl and snarl", 1.2),
    "roar_bear": ("big bear roar", 1.5),
    "roar_dragon": ("dragon roar with fire breath", 2.0),
    "crowd_cheer": ("medieval crowd cheering and applauding in arena", 3.0),
    "crowd_ooh": ("crowd gasping ooh in arena", 1.8),
    "levelup": ("magical level up chime, ascending harp and bells", 2.0),
    "click": ("short wooden button click", 0.3),
    "coins": ("gold coins jingling", 1.0),
    "death": ("body falling to the ground thud with armor clatter", 1.3),
    "draw": ("sword unsheathed from scabbard, metal ring", 0.9),
    "break": ("wooden weapon snapping and breaking, metal shatter", 1.0),
    "shout": ("loud angry battle cry of a barbarian warrior", 1.5),
    "gong": ("big gong hit, start of the fight", 2.5),
}


def main():
    images = []
    for k, v in HEROES.items():
        images.append({"id": f"hero_{k}", "wf": "sprite", "style": "char", "prompt": v, "w": 832, "h": 1024, "size": 512, "out": f"assets/characters/{k}.png"})
    for k, v in BOSSES.items():
        images.append({"id": f"boss_{k}", "wf": "sprite", "style": "char", "prompt": v, "w": 1024, "h": 1024, "size": 640, "out": f"assets/bosses/{k}.png"})
    for k, v in PETS.items():
        images.append({"id": f"pet_{k}", "wf": "sprite", "style": "char", "prompt": v, "w": 1024, "h": 1024, "size": 384, "out": f"assets/pets/{k}.png"})
    for k, v in WEAPONS.items():
        images.append({"id": f"weapon_{k}", "wf": "sprite", "style": "icon", "prompt": v, "w": 1024, "h": 1024, "size": 256, "out": f"assets/weapons/{k}.png"})
    for k, v in SKILLS.items():
        images.append({"id": f"skill_{k}", "wf": "sprite", "style": "skill", "prompt": v, "w": 1024, "h": 1024, "size": 192, "out": f"assets/skills/{k}.png"})
    for k, v in ARENAS.items():
        images.append({"id": f"bg_{k}", "wf": "image", "style": "scene", "prompt": v, "w": 1600, "h": 896, "size": 1600, "out": f"assets/bg/{k}.jpg"})
    for k, (v, w, h) in SCENES.items():
        images.append({"id": f"scene_{k}", "wf": "image", "style": "art", "prompt": v, "w": w, "h": h, "size": 1600, "out": f"assets/bg/{k}.jpg"})
    for k, (v, w, h) in UI.items():
        images.append({"id": f"ui_{k}", "wf": "sprite", "style": "none", "prompt": v, "w": w, "h": h, "size": {"logo": 1024, "coin": 128}.get(k, 512), "keep_ratio": k == "logo", "out": f"assets/ui/{k}.png"})
    sfx = [{"id": k, "prompt": v[0], "duration": v[1], "out": f"assets/sfx/{k}.wav"} for k, v in SFX.items()]
    man = {"styles": dict(STYLES, none=""), "negative": {"image": NEG, "sfx": "music, melody, speech, voice, background noise, hiss, long silence"},
           "images": images, "music": MUSIC, "sfx": sfx}
    with open(os.path.join(HERE, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=1)
    print(len(images), "images,", len(MUSIC), "musiques,", len(sfx), "sfx")


if __name__ == "__main__":
    main()
