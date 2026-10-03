const { simulate } = require('../src/fight');
const B = require('../src/brutes');
const content = require('../src/content');
let wins = 0, len = 0;
for (let i = 0; i < 2000; i++) {
  const a = B.makeBot(5, i * 3 + 1), b = B.makeBot(5, i * 7 + 2);
  const r = simulate(a, b, i);
  if (r.winner === 0) wins++; len += r.log.length;
}
console.log('lvl5 vs lvl5 winrate A', wins / 2000, 'avg events', len / 2000);
for (const lv of [1, 3, 6, 10, 15, 20]) {
  // brute "joueur" niveau lv contre chaque boss
  let row = [];
  for (const st of content.data.campaign) {
    let w = 0;
    for (let i = 0; i < 200; i++) if (simulate(B.makeBot(lv, i * 11 + 5), B.makeBoss(st), i).winner === 0) w++;
    row.push((w / 2).toFixed(0).padStart(3));
  }
  console.log('lvl', String(lv).padStart(2), row.join(' '));
}
const r = simulate(B.makeBot(8, 4), B.makeBoss(content.stage('c5')), 99);
console.log(JSON.stringify(r.log.slice(0, 12)));
