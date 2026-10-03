// Accès au contenu du jeu (data/content.json, partagé avec le client Godot).
'use strict';
const fs = require('fs');
const path = require('path');

const FILE = process.env.CONTENT_FILE || path.join(__dirname, '..', '..', 'data', 'content.json');
const data = JSON.parse(fs.readFileSync(FILE, 'utf8'));
const index = (arr) => Object.fromEntries(arr.map((x) => [x.id, x]));
const weapons = index(data.weapons), pets = index(data.pets), skills = index(data.skills), heroes = index(data.heroes);
const campaign = index(data.campaign);

module.exports = {
  data,
  weapon: (id) => weapons[id],
  pet: (id) => pets[id],
  skill: (id) => skills[id],
  hero: (id) => heroes[id],
  stage: (id) => campaign[id],
};
