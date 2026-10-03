// Progression du compte : écus d'or, passe de combat (battle pass) saisonnier, quêtes du jour, cosmétiques.
'use strict';

const SEASON = { id: 's1', name: "Saison 1 : L'Éveil du Dragon", tiers: 30, xpPerTier: 100, premiumCost: 1000 };

const AURAS = {
  braise: { name: 'Aura de braise', color: '#ff7a2a' }, givre: { name: 'Aura de givre', color: '#6fd8ff' },
  sacree: { name: 'Aura sacrée', color: '#ffe066' }, sylve: { name: 'Aura sylvestre', color: '#6fdc5a' },
  neant: { name: 'Aura du néant', color: '#a35cff' }, sang: { name: 'Aura de sang', color: '#e0213a' },
  arcane: { name: 'Aura arcanique', color: '#ff5cd6' }, dragon: { name: 'Aura du Roi-Dragon', color: '#ffb000' },
};
const TITLES = [
  'Bagarreur de taverne', 'Écraseur de gobelins', 'Fléau des brigands', 'Briseur de boucliers', 'Champion du peuple',
  'Terreur des arènes', 'Tueur de trolls', 'Seigneur de guerre', 'Légende du Pass', 'Brute éternelle',
];

// Récompenses de chaque palier : piste gratuite et piste Légendaire.
function buildTiers() {
  const tiers = [];
  const freeSpecial = { 5: { type: 'title', id: TITLES[0] }, 10: { type: 'aura', id: 'braise' }, 15: { type: 'title', id: TITLES[1] },
    20: { type: 'aura', id: 'sylve' }, 25: { type: 'title', id: TITLES[3] }, 30: { type: 'aura', id: 'givre' } };
  const premSpecial = { 1: { type: 'aura', id: 'sang' }, 4: { type: 'title', id: TITLES[2] }, 8: { type: 'aura', id: 'sacree' },
    12: { type: 'title', id: TITLES[4] }, 16: { type: 'aura', id: 'arcane' }, 20: { type: 'title', id: TITLES[5] },
    24: { type: 'aura', id: 'neant' }, 27: { type: 'title', id: TITLES[7] }, 30: { type: 'aura', id: 'dragon' } };
  for (let t = 1; t <= SEASON.tiers; t++) {
    const free = freeSpecial[t] || (t % 3 === 0 ? { type: 'energy', v: 3 } : { type: 'gold', v: 40 + t * 5 });
    let premium = premSpecial[t] || (t % 2 === 0 ? { type: 'energy', v: 5 } : { type: 'gold', v: 80 + t * 10 });
    if (t === 29) premium = { type: 'title', id: TITLES[8] };
    tiers.push({ tier: t, free, premium });
  }
  return tiers;
}
const TIERS = buildTiers();

const QUEST_POOL = [
  { id: 'win3', text: 'Remporte 3 combats', goal: 3, ev: 'win' },
  { id: 'fight5', text: 'Livre 5 combats', goal: 5, ev: 'fight' },
  { id: 'arena2', text: 'Combats 2 fois en arène', goal: 2, ev: 'arena' },
  { id: 'ai3', text: "Affronte l'IA 3 fois", goal: 3, ev: 'ai' },
  { id: 'coop1', text: 'Joue une partie en coopération', goal: 1, ev: 'coop' },
  { id: 'party2', text: 'Joue 2 parties multijoueur (salon)', goal: 2, ev: 'party' },
  { id: 'camp1', text: 'Tente un chapitre de campagne', goal: 1, ev: 'campaign' },
  { id: 'duel1', text: 'Livre un duel en direct ou en PvP', goal: 1, ev: 'pvp' },
];
const QUEST_REWARD = { passXp: 120, gold: 30 };
const today = () => new Date().toISOString().slice(0, 10);

function ensure(acc) {
  if (acc.gold === undefined) acc.gold = 100;
  if (!acc.pass || acc.pass.season !== SEASON.id) acc.pass = { season: SEASON.id, xp: 0, premium: false, claimed: { free: [], premium: [] } };
  acc.cosmetics = acc.cosmetics || { auras: [], titles: [] };
  acc.profile = acc.profile || { avatar: 'barbare', motto: '', aura: null, title: null };
  acc.friends = acc.friends || [];
  acc.friendReqs = acc.friendReqs || [];
  acc.items = acc.items || { energy: 0 };
  if (!acc.quests || acc.quests.day !== today()) {
    const d = today();
    let h = 0;
    for (const c of d + acc.id) h = (h * 31 + c.charCodeAt(0)) >>> 0;
    const pool = [...QUEST_POOL];
    const list = [];
    for (let i = 0; i < 3; i++) list.push(pool.splice(h % pool.length, 1)[0]), h = (h * 1103515245 + 12345) >>> 0;
    acc.quests = { day: d, list: list.map((q) => ({ id: q.id, text: q.text, goal: q.goal, ev: q.ev, progress: 0, done: false })) };
  }
  return acc;
}

const passTier = (acc) => Math.min(SEASON.tiers, Math.floor(acc.pass.xp / SEASON.xpPerTier));

// Enregistre des événements de quête (ex: ['fight','win','arena']) ; renvoie les quêtes terminées.
function questEvents(acc, events) {
  ensure(acc);
  const done = [];
  for (const q of acc.quests.list) {
    if (q.done) continue;
    q.progress += events.filter((e) => e === q.ev).length;
    if (q.progress >= q.goal) {
      q.progress = q.goal;
      q.done = true;
      acc.pass.xp += QUEST_REWARD.passXp;
      acc.gold += QUEST_REWARD.gold;
      done.push(q.text);
    }
  }
  return done;
}

// Récompenses de compte après un combat.
function fightRewards(acc, won, mode, multi) {
  ensure(acc);
  const mult = multi ? 1.25 : 1;
  const gold = Math.round((won ? 20 : 8) * mult);
  const passXp = Math.round((won ? 40 : 20) * mult);
  acc.gold += gold;
  acc.pass.xp += passXp;
  const ev = ['fight'];
  if (won) ev.push('win');
  if (mode === 'arena') ev.push('arena');
  if (mode === 'ai') ev.push('ai');
  if (mode === 'campaign' || mode === 'coop_campaign') ev.push('campaign');
  if (mode === 'coop_ai' || mode === 'coop_campaign') ev.push('coop');
  if (multi) ev.push('party');
  if (mode === 'live' || mode === 'pvp' || mode === 'arena') ev.push('pvp');
  const quests = questEvents(acc, ev);
  return { gold, passXp, quests };
}

function grant(acc, rw) {
  switch (rw.type) {
    case 'gold': acc.gold += rw.v; break;
    case 'energy': acc.items.energy = (acc.items.energy || 0) + rw.v; break;
    case 'aura': if (!acc.cosmetics.auras.includes(rw.id)) acc.cosmetics.auras.push(rw.id); break;
    case 'title': if (!acc.cosmetics.titles.includes(rw.id)) acc.cosmetics.titles.push(rw.id); break;
  }
}

function claim(acc, track, tier) {
  ensure(acc);
  const t = TIERS[tier - 1];
  if (!t || (track !== 'free' && track !== 'premium')) return 'Palier inconnu.';
  if (passTier(acc) < tier) return 'Palier pas encore atteint.';
  if (track === 'premium' && !acc.pass.premium) return 'Débloque d\'abord la piste Légendaire.';
  if (acc.pass.claimed[track].includes(tier)) return 'Récompense déjà récupérée.';
  acc.pass.claimed[track].push(tier);
  grant(acc, t[track]);
  return null;
}

function passView(acc) {
  ensure(acc);
  return { season: SEASON, xp: acc.pass.xp, tier: passTier(acc), premium: acc.pass.premium, claimed: acc.pass.claimed, tiers: TIERS };
}

module.exports = { SEASON, AURAS, TITLES, TIERS, ensure, fightRewards, claim, passView, questEvents, today };
