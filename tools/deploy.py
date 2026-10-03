"""Déploie Brutes & Légendes sur le VPS sans couper les joueurs connectés.

Usage : python tools/deploy.py [--server] [--site] [--web] [--downloads] [--update] [--all] [--notes="..."]

  --server     code du serveur (Node) + contenu du jeu, puis redémarrage en douceur : la base et les salons sont
               écrits sur disque, les clients se reconnectent automatiquement en ~1 s et retrouvent leur salon.
  --site       site vitrine (website/) -> /var/www/test-labrute/
  --web        version navigateur (build/web) -> /test-labrute/jouer/
  --downloads  archive Windows (build/BrutesEtLegendes-Windows.zip) -> /test-labrute/downloads/
  --update     publie le pack de mise à jour (build/update/brutes-<version>.pck) et version.json : les clients PC
               le téléchargent en arrière-plan pendant qu'ils jouent, les clients web voient « Recharger ».
Prérequis : alias SSH « arcanes-vps » (~/.ssh/config) ; builds produits par tools/build.py.
"""
import json
import os
import subprocess
import sys
import tarfile
import io
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST = os.environ.get("LABRUTE_HOST", "arcanes-vps")
PUBLIC = "http://51.254.211.144/test-labrute"


def ssh(cmd, data=None):
    r = subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, cmd], input=data, capture_output=True)
    if r.returncode != 0:
        sys.exit("ÉCHEC : %s\n%s%s" % (cmd, r.stdout.decode(errors="replace"), r.stderr.decode(errors="replace")))
    return r.stdout.decode(errors="replace").strip()


def push_tree(local_items, remote_dir, clean=False):
    """Envoie des fichiers/dossiers (liste de (chemin local, nom dans l'archive)) via une archive tar."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for src, arc in local_items:
            tar.add(src, arcname=arc, filter=lambda ti: None if "node_modules" in ti.name or "/var" in ti.name or ti.name.endswith(".import") else ti)
    pre = "rm -rf %s/* && " % remote_dir if clean else ""
    ssh("mkdir -p %s && %star -xzf - -C %s" % (remote_dir, pre, remote_dir), buf.getvalue())


def version():
    for line in open(os.path.join(ROOT, "project.godot"), encoding="utf-8"):
        if line.startswith("config/version="):
            return line.split("=", 1)[1].strip().strip('"')
    return "1.0.0"


def deploy_server():
    print("Serveur : envoi du code...")
    srv = os.path.join(ROOT, "server")
    push_tree([(os.path.join(srv, "src"), "server/src"), (os.path.join(srv, "package.json"), "server/package.json"),
               (os.path.join(ROOT, "data", "content.json"), "data/content.json")], "/opt/test-labrute")
    ssh("cd /opt/test-labrute/server && npm install --omit=dev --no-audit --no-fund --silent")
    ssh("sudo systemctl daemon-reload && sudo systemctl enable test-labrute -q && sudo systemctl restart test-labrute")
    ssh("for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf http://127.0.0.1:8097/api/health && exit 0; sleep 0.5; done; exit 1")
    print("Serveur redémarré :", ssh("systemctl is-active test-labrute"))


def deploy_site():
    print("Site vitrine...")
    site = os.path.join(ROOT, "website")
    push_tree([(os.path.join(site, n), n) for n in os.listdir(site)], "/var/www/test-labrute")


def deploy_web():
    print("Version navigateur...")
    web = os.path.join(ROOT, "build", "web")
    push_tree([(os.path.join(web, n), n) for n in os.listdir(web)], "/var/www/test-labrute/jouer", clean=True)


def deploy_downloads():
    print("Téléchargements...")
    z = os.path.join(ROOT, "build", "BrutesEtLegendes-Windows.zip")
    subprocess.run(["scp", "-q", z, "%s:/var/www/test-labrute/downloads/" % HOST], check=True)


def deploy_update(notes):
    v = version()
    pck = os.path.join(ROOT, "build", "update", "brutes-%s.pck" % v)
    if not os.path.exists(pck):
        sys.exit("Pack introuvable : %s (lance tools/build.py --update)" % pck)
    print("Mise à jour %s..." % v)
    subprocess.run(["scp", "-q", pck, "%s:/var/www/test-labrute/updates/" % HOST], check=True)
    info = {"version": v, "pck": "updates/brutes-%s.pck" % v, "size": os.path.getsize(pck), "notes": notes}
    ssh("cat > /var/lib/test-labrute/version.json", json.dumps(info, ensure_ascii=False).encode("utf-8"))
    print("version.json publié :", info)


def main():
    args = sys.argv[1:]
    every = "--all" in args
    notes = next((a.split("=", 1)[1] for a in args if a.startswith("--notes=")), "")
    if every or "--server" in args: deploy_server()
    if every or "--site" in args: deploy_site()
    if every or "--web" in args: deploy_web()
    if every or "--downloads" in args: deploy_downloads()
    if every or "--update" in args: deploy_update(notes)
    ssh("sudo nginx -t -q && sudo systemctl reload nginx")
    try:
        with urllib.request.urlopen(PUBLIC + "/api/stats", timeout=10) as r:
            print("En ligne :", json.loads(r.read())["version"], "-", PUBLIC + "/")
    except Exception as e:  # noqa: BLE001
        print("Vérification publique impossible :", e)


if __name__ == "__main__":
    main()
