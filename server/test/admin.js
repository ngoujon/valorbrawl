// Administration hors ligne de la base (service arrêté) : node test/admin.js delete-account <pseudo>
'use strict';
const fs = require('fs');
const path = require('path');
const DATA = process.env.DATA_DIR || path.join(__dirname, '..', 'var');
const FILE = path.join(DATA, 'db.json');
const db = JSON.parse(fs.readFileSync(FILE, 'utf8'));
const [cmd, name] = process.argv.slice(2);
if (cmd !== 'delete-account' || !name) { console.log('usage : delete-account <pseudo>'); process.exit(1); }
const acc = Object.values(db.accounts).find((a) => a.name.toLowerCase() === name.toLowerCase());
if (!acc) { console.log('compte introuvable'); process.exit(1); }
for (const id of acc.brutes) {
  delete db.brutes[id];
  for (const p of Object.values(db.parties || {})) p.members = p.members.filter((m) => m.brute !== id);
}
for (const [t, a] of Object.entries(db.tokens)) if (a === acc.id) delete db.tokens[t];
for (const a of Object.values(db.accounts)) {
  a.friends = (a.friends || []).filter((x) => x !== acc.id);
  a.friendReqs = (a.friendReqs || []).filter((x) => x !== acc.id);
}
db.reports = (db.reports || []).filter((r) => r.author !== acc.id);
delete db.accounts[acc.id];
fs.writeFileSync(FILE, JSON.stringify(db));
console.log('compte supprimé :', acc.name, '-', acc.brutes.length, 'brute(s)');
