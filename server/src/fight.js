// Moteur de combat de Brutes & Légendes : simulation automatique (façon La Brute), reproductible par graine.
// Le serveur simule, le client rejoue le journal d'événements renvoyé par simulate().
'use strict';
const content = require('./content');

function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  next.range = (lo, hi) => lo + next() * (hi - lo);
  next.int = (lo, hi) => Math.floor(lo + next() * (hi - lo + 1));
  next.pick = (arr) => arr[Math.floor(next() * arr.length)];
  next.chance = (p) => next() < p;
  return next;
}

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

// Statistiques effectives d'une brute (stats de base + compétences passives).
function effectiveStats(b) {
  const sk = new Set(b.skills || []);
  let { hp, str, agi, spd } = b.stats;
  if (sk.has('force')) str = Math.round((str + 3) * 1.5);
  if (sk.has('agilite')) agi = Math.round((agi + 3) * 1.5);
  if (sk.has('velocite')) spd = Math.round((spd + 3) * 1.5);
  if (sk.has('vitalite')) hp = Math.round(hp * 1.5);
  return { hp: Math.max(1, hp), str: Math.max(1, str), agi: Math.max(0, agi), spd: Math.max(0, spd) };
}

function makeFighters(brute, side, startId) {
  const st = effectiveStats(brute);
  const list = [];
  const main = {
    id: startId, side, kind: 'brute', name: brute.name, look: brute.boss || brute.hero, boss: !!brute.boss, aura: brute.aura || null,
    level: brute.level, hp: st.hp, maxHp: st.hp, str: st.str, agi: st.agi, spd: st.spd,
    weapons: [...(brute.weapons || [])], skills: new Set(brute.skills || []), weapon: null,
    used: new Set(), stun: 0, survived: false, alive: true,
  };
  list.push(main);
  let id = startId + 1;
  for (const p of brute.pets || []) {
    const def = content.pet(p);
    if (!def) continue;
    const scale = 1 + (brute.level - 1) * 0.06;
    const hp = Math.round(def.hp * scale);
    list.push({
      id: id++, side, kind: 'pet', name: def.name, look: p, level: brute.level, hp, maxHp: hp,
      str: Math.round(def.dmg * scale), agi: def.agi, spd: def.spd, weapons: [], skills: new Set(), weapon: null,
      used: new Set(), stun: 0, alive: true, master: startId, petDmg: Math.round(def.dmg * scale),
    });
  }
  return list;
}

function publicFighter(f) {
  return {
    id: f.id, side: f.side, kind: f.kind, name: f.name, look: f.look, boss: !!f.boss, level: f.level, aura: f.aura || null,
    hp: f.hp, maxHp: f.maxHp, str: f.str, agi: f.agi, spd: f.spd, weapons: [...f.weapons], skills: [...f.skills],
  };
}

// teamA / teamB : une brute ou une liste de brutes (coop / PvP en équipe).
function simulate(teamA, teamB, seed) {
  const r = rng(seed);
  const teams = [[].concat(teamA), [].concat(teamB)];
  const fighters = [];
  teams.forEach((team, side) => team.forEach((b, i) => fighters.push(...makeFighters(b, side, side * 100 + i * 10))));
  const initial = fighters.map(publicFighter);
  const log = [];
  const timers = new Map();

  const delay = (f) => {
    let d = 10 / (1 + f.spd * 0.07);
    if (f.weapon) d /= content.weapon(f.weapon).speed;
    if (f.skills.has('peau')) d *= 1.15;
    return d * r.range(0.85, 1.15);
  };
  for (const f of fighters) timers.set(f.id, r.range(0, 6) / (1 + f.spd * 0.07));

  const brutesOf = (side) => fighters.filter((f) => f.side === side && f.kind === 'brute');
  const enemies = (f) => fighters.filter((o) => o.alive && o.side !== f.side);
  const foeBrute = (f) => {
    const list = brutesOf(1 - f.side).filter((b) => b.alive);
    return list.length ? r.pick(list) : null;
  };
  let winner = null;

  const pickTarget = (f) => {
    const en = enemies(f);
    const brutes = en.filter((e) => e.kind === 'brute');
    const pets = en.filter((e) => e.kind === 'pet');
    if (!pets.length || (brutes.length && r.chance(0.55))) return brutes.length ? r.pick(brutes) : null;
    return r.pick(pets);
  };

  const kill = (d) => {
    if (d.kind === 'brute' && d.skills.has('survie') && !d.survived) {
      d.survived = true;
      d.hp = 1;
      log.push({ t: 'survive', d: d.id });
      return;
    }
    d.alive = false;
    log.push({ t: 'die', d: d.id });
    if (d.kind === 'brute' && !brutesOf(d.side).some((b) => b.alive)) winner = 1 - d.side;
  };

  const damage = (a, d, amount, extra) => {
    let dmg = Math.max(1, Math.round(amount));
    if (d.skills.has('peau')) dmg = Math.max(1, Math.round(dmg * 0.75));
    d.hp = Math.max(0, d.hp - dmg);
    log.push(Object.assign({ t: 'hit', a: a.id, d: d.id, dmg, hp: d.hp }, extra || {}));
    if (a.skills.has('vampire') && a.alive) {
      const heal = Math.max(1, Math.round(dmg * 0.25));
      a.hp = Math.min(a.maxHp, a.hp + heal);
      log.push({ t: 'heal', a: a.id, v: heal, hp: a.hp, src: 'vampire' });
    }
    if (d.hp <= 0) kill(d);
  };

  const weaponDmg = (a) => {
    if (a.kind === 'pet') return a.petDmg * r.range(0.8, 1.2);
    const w = a.weapon ? content.weapon(a.weapon) : null;
    let base = w ? w.dmg : 3;
    let dmg = (base + a.str * 0.6) * r.range(0.8, 1.2);
    if (w && w.type === 'sharp' && a.skills.has('maitre')) dmg *= 1.5;
    return dmg;
  };

  // Une attaque simple (renvoie true si elle a touché).
  const strike = (a, d, opts = {}) => {
    if (!a.alive || !d.alive) return false;
    const w = a.weapon ? content.weapon(a.weapon) : null;
    const acc = w ? w.acc : 0;
    if (d.stun <= 0 && !opts.unblockable) {
      let block = 0;
      if (d.kind === 'brute') {
        if (d.skills.has('bouclier')) block += 0.45;
        if (d.weapon) block += content.weapon(d.weapon).block;
        block = clamp(block - acc * 0.5, 0, 0.6);
      }
      const dodge = clamp(0.05 + (d.agi - a.agi) * 0.015 + (d.skills.has('ombre') ? 0.15 : 0) - acc, 0, 0.55);
      const how = r.chance(block) ? 'block' : r.chance(dodge) ? 'dodge' : null;
      if (how) {
        log.push({ t: 'miss', a: a.id, d: d.id, how, w: a.weapon || undefined, c: opts.counter ? 1 : undefined });
        if (!opts.counter && d.skills.has('contre') && d.alive && r.chance(0.7)) strike(d, a, { counter: true });
        return false;
      }
    }
    const crit = r.chance(0.05 + a.agi * 0.004);
    const extra = { w: a.weapon || undefined, crit: crit ? 1 : undefined, c: opts.counter ? 1 : undefined, combo: opts.combo ? 1 : undefined };
    damage(a, d, weaponDmg(a) * (crit ? 2 : 1), extra);
    if (w && w.stun && d.alive && r.chance(w.stun)) {
      d.stun = 1;
      log.push({ t: 'stun', d: d.id, n: 1 });
    }
    return true;
  };

  const attack = (a) => {
    let d = pickTarget(a);
    if (!d) return;
    strike(a, d);
    const w = a.weapon ? content.weapon(a.weapon) : null;
    const comboP = clamp(0.08 + a.agi * 0.012 + (w ? w.combo : 0), 0, 0.6);
    let n = 0;
    while (winner === null && a.alive && n < 3 && r.chance(comboP)) {
      n++;
      if (!d.alive) d = pickTarget(a);
      if (!d) break;
      strike(a, d, { combo: true });
    }
  };

  const trySuper = (a) => {
    const supers = [...a.skills].filter((s) => content.skill(s) && content.skill(s).kind === 'super' && !a.used.has(s));
    if (!supers.length) return false;
    const foe = foeBrute(a);
    if (!foe) return false;
    for (const s of supers) {
      let ok = false;
      switch (s) {
        case 'potion': ok = a.hp < a.maxHp * 0.45; break;
        case 'feu': ok = r.chance(0.22); break;
        case 'eclair': ok = r.chance(0.18) && enemies(a).length > 0; break;
        case 'cri': ok = foe.alive && foe.stun <= 0 && r.chance(0.18); break;
        case 'sabotage': ok = foe.alive && !!foe.weapon && r.chance(0.35); break;
        case 'charme': ok = enemies(a).some((e) => e.kind === 'pet') && r.chance(0.3); break;
        case 'fureur': ok = r.chance(0.16); break;
      }
      if (!ok) continue;
      a.used.add(s);
      switch (s) {
        case 'potion': {
          const v = Math.round(a.maxHp * 0.4);
          a.hp = Math.min(a.maxHp, a.hp + v);
          log.push({ t: 'super', a: a.id, s });
          log.push({ t: 'heal', a: a.id, v, hp: a.hp, src: 'potion' });
          break;
        }
        case 'feu': {
          const d = pickTarget(a);
          if (!d) break;
          log.push({ t: 'super', a: a.id, s, d: d.id });
          damage(a, d, (10 + a.str * 1.1 + a.level) * r.range(0.9, 1.1), { magic: 'feu' });
          break;
        }
        case 'eclair': {
          log.push({ t: 'super', a: a.id, s });
          for (const d of enemies(a)) {
            if (winner !== null) break;
            damage(a, d, (6 + a.str * 0.7 + a.level * 0.6) * r.range(0.9, 1.1), { magic: 'eclair' });
          }
          break;
        }
        case 'cri':
          log.push({ t: 'super', a: a.id, s, d: foe.id });
          foe.stun = 2;
          log.push({ t: 'stun', d: foe.id, n: 2 });
          break;
        case 'sabotage':
          log.push({ t: 'super', a: a.id, s, d: foe.id });
          log.push({ t: 'break', d: foe.id, w: foe.weapon });
          foe.weapons = foe.weapons.filter((w) => w !== foe.weapon);
          foe.weapon = null;
          break;
        case 'charme': {
          const pet = r.pick(enemies(a).filter((e) => e.kind === 'pet'));
          log.push({ t: 'super', a: a.id, s, d: pet.id });
          pet.side = a.side;
          pet.master = a.id;
          log.push({ t: 'charm', d: pet.id, side: a.side });
          break;
        }
        case 'fureur': {
          log.push({ t: 'super', a: a.id, s });
          const hits = r.int(3, 5);
          for (let i = 0; i < hits && winner === null; i++) {
            const d = pickTarget(a);
            if (!d) break;
            strike(a, d, { combo: i > 0 });
          }
          break;
        }
      }
      return true;
    }
    return false;
  };

  let actions = 0;
  while (winner === null && actions < 400) {
    actions++;
    let cur = null;
    for (const f of fighters) if (f.alive && (cur === null || timers.get(f.id) < timers.get(cur.id))) cur = f;
    if (!cur) break;
    timers.set(cur.id, timers.get(cur.id) + delay(cur));
    if (cur.stun > 0) {
      cur.stun--;
      log.push({ t: 'stunned', a: cur.id });
      continue;
    }
    if (cur.kind === 'pet') {
      attack(cur);
      continue;
    }
    if (trySuper(cur)) continue;
    // Gestion des armes : dégainer, ou parfois en changer.
    const available = cur.weapons.filter((w) => w !== cur.weapon);
    if (available.length && (!cur.weapon ? r.chance(0.6) : r.chance(0.08))) {
      cur.weapon = r.pick(available);
      log.push({ t: 'draw', a: cur.id, w: cur.weapon });
    }
    attack(cur);
  }
  if (winner === null) {
    // Limite de durée : victoire au pourcentage de PV restant.
    const ratio = (side) => brutesOf(side).reduce((t, b) => t + b.hp / b.maxHp, 0) / brutesOf(side).length;
    winner = ratio(0) >= ratio(1) ? 0 : 1;
    log.push({ t: 'timeout' });
  }
  log.push({ t: 'end', winner });
  return { fighters: initial, log, winner };
}

module.exports = { simulate, rng, effectiveStats };
