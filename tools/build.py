"""Construit Brutes & Légendes avec Godot 4.7.

Usage : python tools/build.py [--web] [--windows] [--update] [--all]

  --web      version navigateur (sans threads : aucun en-tête COOP/COEP requis) -> build/web/
  --windows  exe + pck -> build/windows/, copie dans le dossier « ValorBrawl » du bureau
             (avec LISEZMOI.txt et la bande-annonce) et archive build/BrutesEtLegendes-Windows.zip
  --update   pack de mise à jour seul -> build/update/brutes-<version>.pck (publié par tools/deploy.py --update)
"""
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"C:\Users\goujo\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe")
DESKTOP_DIR = os.path.join(os.path.expanduser("~"), "Desktop", "ValorBrawl")
EXE = "BrutesEtLegendes"

README = """BRUTES & LÉGENDES — combats de brutes en ligne, version médiéval fantastique
==========================================================================

Lancer : double-cliquer sur BrutesEtLegendes.exe (garder BrutesEtLegendes.pck à côté).
Site du jeu : http://51.254.211.144/test-labrute/   (jouable aussi dans le navigateur)

PRINCIPE
- Crée un compte puis ta brute : nom + apparence. Ses caractéristiques et un premier bonus
  (arme, compétence ou familier) sont tirés au sort.
- Les combats sont automatiques, comme dans La Brute : regarde ta brute se battre !
- À chaque niveau, choisis un bonus parmi deux.

MODES
- Arène : défie les brutes des autres joueurs (ou cherche-les par nom).
- Défier l'IA : Facile, Normal, Difficile ou Légendaire.
- Campagne : la Quête du Roi-Dragon, 10 chapitres et 10 boss (en solo ou en coop).
- Multijoueur : salons hébergés sur le serveur (PvP jusqu'à 3 contre 3, coop contre l'IA,
  campagne en coop). Invite tes amis ou n'importe quel joueur en ligne, ou rends ton salon public.
  Duel direct possible depuis la liste des joueurs connectés.
- Passe de combat : 30 paliers par saison (gratuit + Légendaire), quêtes du jour.
- Amis, profil (avatar, devise, titre, aura), classement.
- « Signaler » (en haut à droite) : bugs et suggestions, votes et commentaires.

EN LIGNE
- Toute la progression est sauvegardée sur le serveur : même compte sur PC et dans le navigateur.
- 20 combats par brute et par jour (hors campagne), plus avec les potions d'énergie.
- Mises à jour : le jeu les télécharge en arrière-plan sans te déconnecter, puis propose
  de redémarrer (sinon elles s'installent au lancement suivant).

Options : volumes, plein écran, déconnexion.
"""


def godot(*args):
    print(">", "godot", " ".join(args))
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    errors = [l for l in (r.stdout + r.stderr).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if r.returncode != 0 or errors:
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("Échec Godot.")


def version():
    for line in open(os.path.join(ROOT, "project.godot"), encoding="utf-8"):
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"')
    return "1.0.0"


def build_web():
    out = os.path.join(ROOT, "build", "web")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    godot("--export-release", "Web", "build/web/index.html")
    print("Web :", sorted(os.listdir(out)))


def build_windows():
    out = os.path.join(ROOT, "build", "windows")
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    godot("--export-release", "Windows", "build/windows/%s.exe" % EXE)
    with open(os.path.join(out, "LISEZMOI.txt"), "w", encoding="utf-8") as f:
        f.write(README)
    trailer = os.path.join(ROOT, "build", "trailer", "brutes_et_legendes_trailer.mp4")
    if os.path.exists(trailer):
        shutil.copy(trailer, os.path.join(out, "Brutes et Légendes - bande-annonce.mp4"))
    # dossier exportable sur le bureau
    os.makedirs(DESKTOP_DIR, exist_ok=True)
    for n in os.listdir(out):
        shutil.copy(os.path.join(out, n), os.path.join(DESKTOP_DIR, n))
    shutil.copy(os.path.join(ROOT, "icon.ico"), os.path.join(DESKTOP_DIR, "BrutesEtLegendes.ico"))
    z = os.path.join(ROOT, "build", "%s-Windows.zip" % EXE)
    with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
        for n in os.listdir(out):
            if not n.endswith(".mp4"):
                zf.write(os.path.join(out, n), "Brutes et Légendes/" + n)
    print("Windows :", sorted(os.listdir(out)), "->", DESKTOP_DIR, "+", z)


def build_update():
    out = os.path.join(ROOT, "build", "update")
    os.makedirs(out, exist_ok=True)
    name = "brutes-%s.pck" % version()
    godot("--export-pack", "Windows", "build/update/" + name)
    print("Pack de mise à jour :", name, os.path.getsize(os.path.join(out, name)) // 1024, "Ko")


def main():
    args = sys.argv[1:] or ["--all"]
    every = "--all" in args
    godot("--import")
    if every or "--web" in args: build_web()
    if every or "--windows" in args: build_windows()
    if every or "--update" in args: build_update()


if __name__ == "__main__":
    main()
