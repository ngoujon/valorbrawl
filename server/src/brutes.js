// Création des brutes, montées de niveau, adversaires IA et boss de campagne.
'use strict';
const content = require('./content');
const { rng } = require('./fight');

const BOT_NAMES = [
  'Gromok', 'Bertrude', 'Sire Patapouf', 'Ulfrik', 'Morgana', 'Thorgal le Mou', 'Grizzla', 'Eldrin', 'Brunhild', 'Krogg',
  'Dame Pustule', 'Fendouille', 'Barnabé', 'Ysolde', 'Grognak', 'Mélusine', 'Torvald', 'Gertrude la Rouge', 'Pépin le Bref',
  'Hildegarde', 'Ragnar', 'Sigurd', 'Ombrelune', 'Bardolph', 'Zorglub', 'Frida', 'Kaelith', 'Grumbold', 'Isengrin', 'Mordred',
  'Cunégonde', 'Bjorn', 'Elowen', 'Gorgu', 'Tristan', 'Velma', 'Odon', 'Brakka', 'Sylvanor', 'Gudrun',
];

const XP_WIN = 2, XP_LOSS = 1;
const xpToNext = (level) => 3 + level * 2;

function newBrute(name, hero, seed) {
  const r = rng(seed);
  const stats = { hp: 50 + r.int(0, 10), str: 2, agi: 2, spd: 2 };
  for (let i = 0; i < 5; i++) stats[r.pick(['str', 'agi', 'spd'])]++;
  const h = content.hero(hero);
  for (const [k, v] of Object.entries((h && h.bonus) || {})) stats[k] = Math.max(1, stats[k] + v);
  const b = {
    name, hero, level: 1, xp: 0, stats, weapons: [], skills: [], pets: [], wins: 0, losses: 0,
    campaign: {}, title: null, levelup: null, created: Date.now(),
  };
  // Un premier bonus au hasard.
  applyChoice(b, randomChoice(b, r, true));
  return b;
}

function canTakePet(b, id) {
  const def = content.pet(id);
  return def && b.pets.filter((p) => p === id).length < def.max && b.pets.length < 4;
}

function randomChoice(b, r, noStat) {
  for (let tries = 0; tries < 30; tries++) {
    const roll = r();
    if (!noStat && roll < 0.5) {
      const stat = r.pick(['str', 'agi', 'spd', 'hp']);
      if (r.chance(0.35) && stat !== 'hp') {
        const other = r.pick(['str', 'agi', 'spd'].filter((s) => s !== stat));
        return { type: 'stat', bonus: { [stat]: 2, [other]: 1 } };
      }
      return { type: 'stat', bonus: { [stat]: stat === 'hp' ? 12 : 3 } };
    }
    const k = noStat ? roll : (roll - 0.5) * 2;
    if (k < 0.45) {
      const w = r.pick(content.data.weapons.map((x) => x.id).filter((id) => !b.weapons.includes(id)));
      if (w) return { type: 'weapon', id: w };
    } else if (k < 0.8) {
      const s = r.pick(content.data.skills.map((x) => x.id).filter((id) => !b.skills.includes(id)));
      if (s) return { type: 'skill', id: s };
    } else {
      const p = r.pick(content.data.pets.map((x) => x.id).filter((id) => canTakePet(b, id)));
      if (p) return { type: 'pet', id: p };
    }
  }
  return { type: 'stat', bonus: { hp: 12 } };
}

function sameChoice(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

function levelupChoices(b, seed) {
  const r = rng(seed);
  const a = randomChoice(b, r);
  let c = randomChoice(b, r);
  for (let i = 0; i < 10 && sameChoice(a, c); i++) c = randomChoice(b, r);
  return [a, c];
}

function applyChoice(b, ch) {
  if (ch.type === 'stat') for (const [k, v] of Object.entries(ch.bonus)) b.stats[k] += v;
  else if (ch.type === 'weapon' && !b.weapons.includes(ch.id)) b.weapons.push(ch.id);
  else if (ch.type === 'skill' && !b.skills.includes(ch.id)) b.skills.push(ch.id);
  else if (ch.type === 'pet' && canTakePet(b, ch.id)) b.pets.push(ch.id);
}

// Ajoute de l'XP ; renvoie true si la brute passe un niveau (choix à faire ensuite).
function gainXp(b, xp, seed) {
  if (b.levelup) {
    b.xp = Math.min(b.xp + xp, xpToNext(b.level));
    return false;
  }
  b.xp += xp;
  if (b.xp >= xpToNext(b.level)) {
    b.xp -= xpToNext(b.level);
    b.level++;
    b.stats.hp += 3;
    b.levelup = levelupChoices(b, seed);
    return true;
  }
  return false;
}

function makeBot(level, seed) {
  const r = rng(seed);
  const hero = r.pick(content.data.heroes).id;
  const b = newBrute(r.pick(BOT_NAMES), hero, seed + 1);
  for (let l = 1; l < level; l++) {
    b.level++;
    b.stats.hp += 3;
    applyChoice(b, r.pick(levelupChoices(b, seed + l * 31)));
  }
  b.bot = true;
  return b;
}

function makeBoss(stage) {
  return {
    name: content.data.bosses[stage.boss], boss: stage.boss, hero: stage.boss, level: stage.level,
    stats: { ...stage.stats }, weapons: [...stage.weapons], skills: [...stage.skills], pets: [...stage.pets],
  };
}

module.exports = { newBrute, levelupChoices, applyChoice, gainXp, makeBot, makeBoss, xpToNext, XP_WIN, XP_LOSS };
