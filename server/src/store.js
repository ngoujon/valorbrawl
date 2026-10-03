// Stockage JSON sur disque (écriture atomique différée) : comptes, brutes, signalements, parties en cours.
'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DATA = process.env.DATA_DIR || path.join(__dirname, '..', 'var');
const FIGHTS_DIR = path.join(DATA, 'fights');
const DB_FILE = path.join(DATA, 'db.json');
fs.mkdirSync(FIGHTS_DIR, { recursive: true });

const db = Object.assign(
  { accounts: {}, brutes: {}, tokens: {}, reports: [], parties: {}, fightCount: 0, seq: 1 },
  fs.existsSync(DB_FILE) ? JSON.parse(fs.readFileSync(DB_FILE, 'utf8')) : {},
);

let timer = null;
function flush() {
  if (timer) { clearTimeout(timer); timer = null; }
  fs.writeFileSync(DB_FILE + '.tmp', JSON.stringify(db));
  fs.renameSync(DB_FILE + '.tmp', DB_FILE);
}
function save() {
  if (!timer) timer = setTimeout(flush, 400);
}
const newId = (p) => p + (db.seq++).toString(36) + crypto.randomBytes(3).toString('hex');

function storeFight(fight) {
  fs.writeFileSync(path.join(FIGHTS_DIR, fight.id + '.json'), JSON.stringify(fight));
}
function loadFight(id) {
  if (!/^[a-z0-9]+$/i.test(id)) return null;
  const f = path.join(FIGHTS_DIR, id + '.json');
  return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null;
}

module.exports = { db, save, flush, newId, storeFight, loadFight, DATA };
