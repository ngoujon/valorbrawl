"""Planche contact des images d'un ou plusieurs dossiers : python tools/contact.py out.png dossier [dossier...]"""
import sys, os
from PIL import Image, ImageDraw
files = [os.path.join(d, f) for d in sys.argv[2:] for f in sorted(os.listdir(d)) if f.endswith(('.png', '.jpg'))]
cell, cols = 220, 6
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (60, 60, 70))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGBA"); im.thumbnail((cell - 8, cell - 8))
    x, y = (i % cols) * cell, (i // cols) * (cell + 18)
    sheet.paste(im, (x + 4, y + 4), im)
    dr.text((x + 4, y + cell), os.path.basename(f), fill=(255, 255, 255))
sheet.save(sys.argv[1])
