// Cherche des combats spectaculaires (supers, familiers, critiques) pour la bande-annonce
// et les écrit dans tools/trailer/fight_<n>.json (rejoués par le jeu avec --play-fight=...).
const fs = require('fs');
const path = require('path');
const { simulate } = require('../src/fight');
const B = require('../src/brutes');
const content = require('../src/content');
const OUT = path.join(__dirname, '..', '..', 'tools', 'trailer');
fs.mkdirSync(OUT, { recursive: true });

function score(res, minLen, maxLen) {
  const n = res.log.length;
  if (n < minLen || n > maxLen) return -1;
  let s = 0;
  for (const e of res.log) {
    if (e.t === 'super') s += 6;
    if (e.crit) s += 3;
    if (e.t === 'draw') s += 1;
    if (e.t === 'charm' || e.t === 'survive' || e.t === 'break') s += 5;
  }
  s += res.fighters.filter((f) => f.kind === 'pet').length * 3;
  return s;
}
function best(make, minLen, maxLen, tries = 4000) {
  let top = null;
  for (let i = 1; i < tries; i++) {
    const [a, b, extra] = make(i);
    const res = simulate(a, b, i * 13 + 7);
    const sc = score(res, minLen, maxLen);
    if (sc > (top ? top.sc : -1)) top = { sc, res, a, b, extra };
  }
  return top;
}
function write(name, top, mode, arena) {
  const teams = [[].concat(top.a), [].concat(top.b)].map((t) => t.map((x) => ({ id: null, name: x.name, boss: x.boss || null })));
  const fight = { id: name, mode, winner: top.res.winner, fighters: top.res.fighters, log: top.res.log, teams, arena, rewards: {} };
  fs.writeFileSync(path.join(OUT, name + '.json'), JSON.stringify(fight));
  console.log(name, 'score', top.sc, 'événements', top.res.log.length, 'gagnant', top.res.winner);
}
// 1) duel 1 contre 1 de niveau élevé, victoire du côté gauche
write('fight_duel', best((i) => {
  const a = B.makeBot(14, i * 3 + 1), b = B.makeBot(14, i * 5 + 2);
  return [a, b];
}, 22, 34), 'ai', 'arene');
// 2) coop 2 contre le Roi-Dragon
const dragon = B.makeBoss(content.stage('c10'));
dragon.stats.hp = 420;
write('fight_dragon', best((i) => [[B.makeBot(20, i * 7 + 3), B.makeBot(20, i * 11 + 5)], dragon], 20, 60, 1500), 'coop_campaign', 'arene_dragon');
// 3) PvP 2 contre 2 dans le château
write('fight_team', best((i) => [[B.makeBot(10, i * 2 + 9), B.makeBot(10, i * 3 + 4)], [B.makeBot(10, i * 4 + 6), B.makeBot(10, i * 9 + 8)]], 24, 36, 2000), 'pvp', 'arene_chateau');
