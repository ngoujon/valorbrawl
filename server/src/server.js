// Serveur de Brutes & Légendes : API REST (/api/...) + WebSocket du lobby (/api/ws).
// Derrière nginx : /test-labrute/api/  ->  http://127.0.0.1:8097/api/
// Redémarrage sans perte : à l'arrêt (SIGTERM) la base et les salons sont écrits sur disque ; au retour,
// les clients se reconnectent automatiquement et retrouvent leur salon.
'use strict';
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');
const content = require('./content');
const { simulate } = require('./fight');
const B = require('./brutes');
const P = require('./progress');
const { db, save, flush, newId, storeFight, loadFight, DATA } = require('./store');

const PORT = +process.env.PORT || 8097;
const HOST = process.env.HOST || '127.0.0.1';
const FIGHTS_PER_DAY = 20;
const MAX_BRUTES = 3;
const VERSION_FILE = process.env.VERSION_FILE || path.join(DATA, 'version.json');
const ADMINS = (process.env.ADMINS || '').split(',').filter(Boolean);
const today = P.today;

for (const a of Object.values(db.accounts)) P.ensure(a);

// ------------------------------------------------------------------ utilitaires
const hashPass = (pass, salt) => crypto.scryptSync(pass, salt, 32).toString('hex');
const validName = (s) => typeof s === 'string' && /^[\p{L}\p{N} _'\-]{3,16}$/u.test(s.trim());
const findAccount = (name) => Object.values(db.accounts).find((a) => a.name.toLowerCase() === String(name || '').trim().toLowerCase());

function energy(b) {
  if (b.day !== today()) { b.day = today(); b.fightsToday = 0; }
  return FIGHTS_PER_DAY - (b.fightsToday || 0);
}

function bruteView(b, full) {
  const acc = db.accounts[b.owner];
  const v = {
    id: b.id, name: b.name, hero: b.hero, level: b.level, wins: b.wins, losses: b.losses, title: b.title || null,
    stats: b.stats, weapons: b.weapons, skills: b.skills, pets: b.pets, owner: acc ? acc.name : '?',
    ownerTitle: acc && acc.profile.title, aura: acc && acc.profile.aura, online: !!(acc && presence.has(acc.id)),
  };
  if (full) Object.assign(v, {
    xp: b.xp, xpNext: B.xpToNext(b.level), levelup: b.levelup, campaign: b.campaign, energy: energy(b),
    energyMax: FIGHTS_PER_DAY, history: (b.history || []).slice(-25).reverse(),
  });
  return v;
}

function accountView(a) {
  P.ensure(a);
  return {
    id: a.id, name: a.name, gold: a.gold, items: a.items, profile: a.profile, cosmetics: a.cosmetics,
    quests: a.quests.list, pass: P.passView(a), auras: P.AURAS, admin: ADMINS.includes(a.name),
    friendRequests: a.friendReqs.length, brutes: a.brutes.map((id) => bruteView(db.brutes[id], true)),
  };
}

function publicProfile(a) {
  P.ensure(a);
  const brutes = a.brutes.map((id) => db.brutes[id]);
  return {
    id: a.id, name: a.name, avatar: a.profile.avatar, motto: a.profile.motto, title: a.profile.title, aura: a.profile.aura,
    online: presence.has(a.id), created: a.created, wins: brutes.reduce((t, b) => t + b.wins, 0),
    losses: brutes.reduce((t, b) => t + b.losses, 0), brutes: brutes.map((b) => bruteView(b)),
    activeBrute: presence.has(a.id) ? presence.get(a.id).brute : null,
  };
}

// ------------------------------------------------------------------ combats
function pushHistory(b, entry) {
  b.history = b.history || [];
  b.history.push(entry);
  if (b.history.length > 50) b.history.shift();
}

// Résout un combat entre deux équipes. Chaque membre de joueur reçoit XP, écus, passe et quêtes.
// teams: [[brute...], [brute...]] (brutes de joueurs = objets de db.brutes ; IA/boss = objets temporaires)
function resolveFight(teams, mode, opts = {}) {
  const seed = crypto.randomInt(1, 2 ** 31);
  const withAura = (b) => (b.id && db.brutes[b.id] && db.accounts[b.owner] ? { ...b, aura: db.accounts[b.owner].profile.aura || null } : b);
  const res = simulate(teams[0].map(withAura), teams[1].map(withAura), seed);
  const multi = !!opts.multi;
  const fight = {
    id: newId('f'), mode, date: Date.now(), seed, winner: res.winner, fighters: res.fighters, log: res.log,
    teams: teams.map((t) => t.map((b) => ({ id: b.id || null, name: b.name, bot: !!b.bot, boss: b.boss || null }))),
    arena: opts.arena || content.data.arenas[crypto.randomInt(0, 4)], stage: opts.stage || null, rewards: {},
  };
  teams.forEach((team, side) => team.forEach((b) => {
    if (!b.id || !db.brutes[b.id]) return; // IA ou boss
    const won = res.winner === side;
    const acc = db.accounts[b.owner];
    const r = { xp: 0, levelup: false };
    const defender = opts.defender === b.id;
    const foes = teams[1 - side];
    const foeLevel = foes.reduce((t, f) => t + f.level, 0) / foes.length;
    const isCampaign = mode === 'campaign' || mode === 'coop_campaign';
    if (!isCampaign) {
      r.xp = won ? B.XP_WIN + (foeLevel > b.level + 0.5 ? 1 : 0) : B.XP_LOSS;
      if (defender) r.xp = won ? 1 : 0;
    } else if (won && !b.campaign[opts.stage]) r.xp = 4;
    if (r.xp) r.levelup = B.gainXp(b, r.xp, seed + side * 7 + b.level);
    if (!isCampaign && !defender) b.fightsToday = (b.fightsToday || 0) + 1;
    if (won) b.wins++; else b.losses++;
    if (isCampaign && won && !b.campaign[opts.stage]) {
      const st = content.stage(opts.stage);
      const idx = content.data.campaign.indexOf(st);
      if (idx === 0 || b.campaign[content.data.campaign[idx - 1].id]) {
        b.campaign[opts.stage] = true;
        r.reward = st.reward;
        if (st.reward.type === 'stat') b.stats[st.reward.id] += st.reward.v;
        else if (st.reward.type === 'title') b.title = st.reward.id;
        else B.applyChoice(b, st.reward);
      }
    }
    if (!defender) Object.assign(r, P.fightRewards(acc, won, mode, multi));
    const foeNames = foes.map((f) => f.name).join(', ');
    pushHistory(b, { id: fight.id, mode: defender ? mode + '_def' : mode, foe: foeNames, won, date: fight.date });
    fight.rewards[b.id] = r;
  }));
  db.fightCount++;
  storeFight(fight);
  save();
  return fight;
}

// ------------------------------------------------------------------ HTTP
function send(res, code, obj) {
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(obj));
}
class HttpError extends Error { constructor(code, msg) { super(msg); this.code = code; } }
const fail = (code, msg) => { throw new HttpError(code, msg); };

function auth(req) {
  const h = req.headers.authorization || '';
  const tok = h.startsWith('Bearer ') ? h.slice(7) : null;
  const acc = tok && db.tokens[tok] && db.accounts[db.tokens[tok]];
  if (!acc) fail(401, 'Session expirée, reconnecte-toi.');
  return P.ensure(acc);
}
function ownBrute(acc, id) {
  const b = db.brutes[id];
  if (!b || b.owner !== acc.id) fail(404, 'Brute introuvable.');
  return b;
}
function needEnergy(b) {
  if (b.levelup) fail(400, `${b.name} doit d'abord choisir son bonus de niveau !`);
  if (energy(b) <= 0) fail(400, `${b.name} est épuisée pour aujourd'hui. Utilise une potion d'énergie ou reviens demain !`);
}
function newSession(acc) {
  const token = crypto.randomBytes(24).toString('hex');
  db.tokens[token] = acc.id;
  save();
  return { token, account: accountView(acc) };
}
function readVersion() {
  try { return JSON.parse(fs.readFileSync(VERSION_FILE, 'utf8')); } catch { return { version: '1.0.0' }; }
}
const friendView = (a) => ({ id: a.id, name: a.name, avatar: a.profile.avatar, title: a.profile.title, online: presence.has(a.id),
  brute: presence.has(a.id) && presence.get(a.id).brute ? bruteView(db.brutes[presence.get(a.id).brute]) : null });

function reportView(r, acc) {
  return { id: r.id, type: r.type, title: r.title, text: r.text, author: (db.accounts[r.author] || {}).name || '?',
    date: r.date, status: r.status, votes: r.votes.length, voted: r.votes.includes(acc.id), comments: r.comments,
    platform: r.platform, version: r.version };
}

const routes = {
  'GET /api/health': () => ({ ok: true }),
  'GET /api/version': () => readVersion(),
  'GET /api/content': () => content.data,
  'POST /api/register': (req, body) => {
    const name = String(body.user || '').trim();
    if (!validName(name)) fail(400, 'Pseudo invalide (3 à 16 lettres, chiffres, espaces).');
    if (String(body.pass || '').length < 4) fail(400, 'Mot de passe trop court (4 caractères minimum).');
    if (findAccount(name)) fail(400, 'Ce pseudo est déjà pris.');
    const salt = crypto.randomBytes(16).toString('hex');
    const acc = P.ensure({ id: newId('a'), name, salt, hash: hashPass(String(body.pass), salt), brutes: [], created: Date.now() });
    db.accounts[acc.id] = acc;
    return newSession(acc);
  },
  'POST /api/login': (req, body) => {
    const acc = findAccount(body.user);
    if (!acc || hashPass(String(body.pass || ''), acc.salt) !== acc.hash) fail(400, 'Pseudo ou mot de passe incorrect.');
    return newSession(P.ensure(acc));
  },
  'GET /api/me': (req) => ({ account: accountView(auth(req)) }),

  // --- brutes
  'POST /api/brute/create': (req, body) => {
    const acc = auth(req);
    if (acc.brutes.length >= MAX_BRUTES) fail(400, `${MAX_BRUTES} brutes maximum par compte.`);
    const name = String(body.name || '').trim();
    if (!validName(name)) fail(400, 'Nom invalide (3 à 16 caractères).');
    if (Object.values(db.brutes).some((b) => b.name.toLowerCase() === name.toLowerCase())) fail(400, 'Une brute porte déjà ce nom.');
    if (!content.hero(body.hero)) fail(400, 'Apparence inconnue.');
    const b = B.newBrute(name, body.hero, crypto.randomInt(1, 2 ** 31));
    b.id = newId('b');
    b.owner = acc.id;
    db.brutes[b.id] = b;
    acc.brutes.push(b.id);
    if (acc.brutes.length === 1) acc.profile.avatar = body.hero;
    save();
    return { brute: bruteView(b, true) };
  },
  'POST /api/brute/levelup': (req, body) => {
    const b = ownBrute(auth(req), body.brute);
    if (!b.levelup) fail(400, 'Aucun bonus à choisir.');
    const ch = b.levelup[body.choice === 1 ? 1 : 0];
    B.applyChoice(b, ch);
    b.levelup = null;
    save();
    return { brute: bruteView(b, true), chosen: ch };
  },
  'POST /api/brute/opponents': (req, body) => {
    const b = ownBrute(auth(req), body.brute);
    const others = Object.values(db.brutes).filter((o) => o.owner !== b.owner);
    let near = others.filter((o) => Math.abs(o.level - b.level) <= 3);
    if (near.length < 6) near = others.sort((x, y) => Math.abs(x.level - b.level) - Math.abs(y.level - b.level)).slice(0, 12);
    near.sort(() => Math.random() - 0.5);
    return { opponents: near.slice(0, 6).map((o) => bruteView(o)) };
  },
  'POST /api/brute/search': (req, body) => {
    auth(req);
    const q = String(body.q || '').trim().toLowerCase();
    if (q.length < 2) return { results: [] };
    return { results: Object.values(db.brutes).filter((o) => o.name.toLowerCase().includes(q) || (db.accounts[o.owner] || {}).name?.toLowerCase().includes(q)).slice(0, 12).map((o) => bruteView(o)) };
  },
  'POST /api/item/energy': (req, body) => {
    const acc = auth(req);
    const b = ownBrute(acc, body.brute);
    if ((acc.items.energy || 0) <= 0) fail(400, "Tu n'as plus de potion d'énergie.");
    energy(b);
    if (!b.fightsToday) fail(400, 'Ta brute est déjà en pleine forme !');
    acc.items.energy--;
    b.fightsToday = Math.max(0, b.fightsToday - 5);
    save();
    return { brute: bruteView(b, true), account: accountView(acc) };
  },

  // --- combats solo
  'POST /api/fight/player': (req, body) => {
    const b = ownBrute(auth(req), body.brute);
    needEnergy(b);
    const foe = db.brutes[body.opponent];
    if (!foe || foe.owner === b.owner) fail(400, 'Adversaire invalide.');
    return { fight: resolveFight([[b], [foe]], 'arena', { defender: foe.id }), brute: bruteView(b, true), account: accountView(db.accounts[b.owner]) };
  },
  'POST /api/fight/ai': (req, body) => {
    const b = ownBrute(auth(req), body.brute);
    needEnergy(b);
    const diff = { facile: -2, normal: 0, difficile: 2, legendaire: 5 }[body.difficulty] ?? 0;
    const bot = B.makeBot(Math.max(1, b.level + diff), crypto.randomInt(1, 2 ** 31));
    return { fight: resolveFight([[b], [bot]], 'ai'), brute: bruteView(b, true), account: accountView(db.accounts[b.owner]) };
  },
  'POST /api/fight/campaign': (req, body) => {
    const b = ownBrute(auth(req), body.brute);
    if (b.levelup) fail(400, "Choisis d'abord ton bonus de niveau !");
    const stage = content.stage(body.stage);
    if (!stage) fail(400, 'Étape inconnue.');
    const idx = content.data.campaign.indexOf(stage);
    if (idx > 0 && !b.campaign[content.data.campaign[idx - 1].id]) fail(400, "Termine d'abord le chapitre précédent.");
    const fight = resolveFight([[b], [B.makeBoss(stage)]], 'campaign', { stage: stage.id, arena: stage.arena });
    return { fight, brute: bruteView(b, true), account: accountView(db.accounts[b.owner]) };
  },
  'GET /api/fight': (req, body, q) => {
    const f = loadFight(q.get('id') || '');
    if (!f) fail(404, 'Combat introuvable.');
    return { fight: f };
  },
  'GET /api/leaderboard': () => {
    const list = Object.values(db.brutes).sort((x, y) => y.level - x.level || y.wins - x.wins || x.losses - y.losses).slice(0, 50);
    return { brutes: list.map((b) => bruteView(b)) };
  },
  'GET /api/stats': () => ({
    players: Object.keys(db.accounts).length, brutes: Object.keys(db.brutes).length, fights: db.fightCount, online: presence.size,
    parties: Object.values(db.parties).length, season: P.SEASON.name, version: readVersion().version,
    top: Object.values(db.brutes).sort((x, y) => y.level - x.level || y.wins - x.wins).slice(0, 10).map((b) => bruteView(b)),
  }),

  // --- profil
  'GET /api/profile': (req, body, q) => {
    auth(req);
    const a = findAccount(q.get('name'));
    if (!a) fail(404, 'Joueur introuvable.');
    return { profile: publicProfile(a) };
  },
  'POST /api/profile': (req, body) => {
    const acc = auth(req);
    if (body.avatar !== undefined) {
      if (!content.hero(body.avatar) && !content.data.bosses[body.avatar]) fail(400, 'Avatar inconnu.');
      if (content.data.bosses[body.avatar] && !acc.brutes.some((id) => Object.keys(db.brutes[id].campaign || {}).some((s) => content.stage(s).boss === body.avatar)))
        fail(400, 'Bats ce boss en campagne pour débloquer son avatar.');
      acc.profile.avatar = body.avatar;
    }
    if (body.motto !== undefined) acc.profile.motto = String(body.motto).slice(0, 80);
    if (body.aura !== undefined) {
      if (body.aura !== null && !acc.cosmetics.auras.includes(body.aura)) fail(400, 'Aura non débloquée.');
      acc.profile.aura = body.aura;
    }
    if (body.title !== undefined) {
      if (body.title !== null && !acc.cosmetics.titles.includes(body.title)) fail(400, 'Titre non débloqué.');
      acc.profile.title = body.title;
    }
    save();
    return { account: accountView(acc) };
  },
  'POST /api/profile/password': (req, body) => {
    const acc = auth(req);
    if (hashPass(String(body.old || ''), acc.salt) !== acc.hash) fail(400, 'Ancien mot de passe incorrect.');
    if (String(body.new || '').length < 4) fail(400, 'Nouveau mot de passe trop court.');
    acc.salt = crypto.randomBytes(16).toString('hex');
    acc.hash = hashPass(String(body.new), acc.salt);
    save();
    return { ok: true };
  },

  // --- passe de combat
  'POST /api/pass/claim': (req, body) => {
    const acc = auth(req);
    const err = P.claim(acc, body.track, +body.tier);
    if (err) fail(400, err);
    save();
    return { account: accountView(acc) };
  },
  'POST /api/pass/claimall': (req) => {
    const acc = auth(req);
    let n = 0;
    for (const t of P.TIERS) for (const track of ['free', 'premium']) if (!P.claim(acc, track, t.tier)) n++;
    save();
    return { account: accountView(acc), claimed: n };
  },
  'POST /api/pass/premium': (req) => {
    const acc = auth(req);
    if (acc.pass.premium) fail(400, 'Piste Légendaire déjà débloquée.');
    if (acc.gold < P.SEASON.premiumCost) fail(400, `Il te faut ${P.SEASON.premiumCost} écus d'or.`);
    acc.gold -= P.SEASON.premiumCost;
    acc.pass.premium = true;
    save();
    return { account: accountView(acc) };
  },

  // --- amis
  'GET /api/friends': (req) => {
    const acc = auth(req);
    return {
      friends: acc.friends.map((id) => db.accounts[id]).filter(Boolean).map(friendView).sort((x, y) => y.online - x.online),
      requests: acc.friendReqs.map((id) => db.accounts[id]).filter(Boolean).map(friendView),
    };
  },
  'POST /api/friends/add': (req, body) => {
    const acc = auth(req);
    const other = findAccount(body.name);
    if (!other) fail(404, 'Aucun joueur ne porte ce pseudo.');
    if (other.id === acc.id) fail(400, 'Tu es déjà ton meilleur ami.');
    if (acc.friends.includes(other.id)) fail(400, 'Vous êtes déjà amis.');
    P.ensure(other);
    if (acc.friendReqs.includes(other.id)) {
      acc.friendReqs = acc.friendReqs.filter((x) => x !== other.id);
      acc.friends.push(other.id);
      other.friends.push(acc.id);
      notify(other.id, { t: 'friends', text: `${acc.name} a accepté ta demande d'ami !` });
      save();
      return { ok: true, text: `${other.name} est maintenant ton ami !` };
    }
    if (!other.friendReqs.includes(acc.id)) other.friendReqs.push(acc.id);
    notify(other.id, { t: 'friends', text: `${acc.name} veut devenir ton ami.` });
    save();
    return { ok: true, text: `Demande envoyée à ${other.name}.` };
  },
  'POST /api/friends/accept': (req, body) => {
    const acc = auth(req);
    const other = db.accounts[body.id];
    if (!other || !acc.friendReqs.includes(other.id)) fail(400, 'Demande introuvable.');
    acc.friendReqs = acc.friendReqs.filter((x) => x !== other.id);
    if (!acc.friends.includes(other.id)) acc.friends.push(other.id);
    P.ensure(other);
    if (!other.friends.includes(acc.id)) other.friends.push(acc.id);
    notify(other.id, { t: 'friends', text: `${acc.name} a accepté ta demande d'ami !` });
    save();
    return { ok: true };
  },
  'POST /api/friends/decline': (req, body) => {
    const acc = auth(req);
    acc.friendReqs = acc.friendReqs.filter((x) => x !== body.id);
    save();
    return { ok: true };
  },
  'POST /api/friends/remove': (req, body) => {
    const acc = auth(req);
    const other = db.accounts[body.id];
    acc.friends = acc.friends.filter((x) => x !== body.id);
    if (other) { P.ensure(other); other.friends = other.friends.filter((x) => x !== acc.id); notify(other.id, { t: 'friends' }); }
    save();
    return { ok: true };
  },

  // --- bugs & suggestions
  'GET /api/reports': (req, body, q) => {
    const acc = auth(req);
    const type = q.get('type');
    const list = db.reports.filter((r) => !type || r.type === type)
      .sort((x, y) => (x.status === 'résolu') - (y.status === 'résolu') || y.votes.length - x.votes.length || y.date - x.date);
    return { reports: list.slice(0, 100).map((r) => reportView(r, acc)) };
  },
  'POST /api/report': (req, body) => {
    const acc = auth(req);
    const type = body.type === 'suggestion' ? 'suggestion' : 'bug';
    const title = String(body.title || '').trim().slice(0, 80);
    const text = String(body.text || '').trim().slice(0, 2000);
    if (title.length < 4) fail(400, 'Donne un titre un peu plus précis.');
    if (text.length < 10) fail(400, 'Décris le problème en quelques mots de plus.');
    const recent = db.reports.filter((r) => r.author === acc.id && Date.now() - r.date < 60000).length;
    if (recent >= 3) fail(429, 'Doucement ! Attends une minute avant un nouveau signalement.');
    const r = { id: newId('r'), type, title, text, author: acc.id, date: Date.now(), status: 'nouveau', votes: [acc.id], comments: [],
      platform: String(body.platform || '').slice(0, 30), version: String(body.version || '').slice(0, 20) };
    db.reports.push(r);
    save();
    console.log(`[signalement] ${type} de ${acc.name} : ${title}`);
    return { report: reportView(r, acc) };
  },
  'POST /api/report/vote': (req, body) => {
    const acc = auth(req);
    const r = db.reports.find((x) => x.id === body.id);
    if (!r) fail(404, 'Signalement introuvable.');
    r.votes = r.votes.includes(acc.id) ? r.votes.filter((x) => x !== acc.id) : [...r.votes, acc.id];
    save();
    return { report: reportView(r, acc) };
  },
  'POST /api/report/comment': (req, body) => {
    const acc = auth(req);
    const r = db.reports.find((x) => x.id === body.id);
    if (!r) fail(404, 'Signalement introuvable.');
    const text = String(body.text || '').trim().slice(0, 500);
    if (!text) fail(400, 'Commentaire vide.');
    r.comments.push({ author: acc.name, text, date: Date.now(), admin: ADMINS.includes(acc.name) });
    save();
    return { report: reportView(r, acc) };
  },
  'POST /api/report/status': (req, body) => {
    const acc = auth(req);
    if (!ADMINS.includes(acc.name)) fail(403, 'Réservé aux administrateurs.');
    const r = db.reports.find((x) => x.id === body.id);
    if (!r) fail(404, 'Signalement introuvable.');
    r.status = String(body.status || 'nouveau').slice(0, 20);
    save();
    return { report: reportView(r, acc) };
  },
};

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return send(res, 204, {});
  const url = new URL(req.url, 'http://x');
  const handler = routes[req.method + ' ' + url.pathname];
  if (!handler) return send(res, 404, { error: 'Route inconnue.' });
  try {
    let body = {};
    if (req.method === 'POST') {
      let raw = '';
      for await (const chunk of req) { raw += chunk; if (raw.length > 1e5) fail(413, 'Requête trop grosse.'); }
      body = raw ? JSON.parse(raw) : {};
    }
    send(res, 200, handler(req, body, url.searchParams));
  } catch (e) {
    if (e instanceof HttpError) send(res, e.code, { error: e.message });
    else { console.error(e); send(res, 500, { error: 'Erreur serveur.' }); }
  }
});

// ------------------------------------------------------------------ lobby (WebSocket)
// presence : accountId -> { sockets:Set, brute } ; sockets : ws -> { acc, brute }
const wss = new WebSocketServer({ noServer: true });
const presence = new Map();
const sockets = new Map();
const chatLog = [];
const invites = new Map(); // bruteId -> Set(bruteId) défis en direct reçus
const leaveTimers = new Map();

const wsSend = (ws, obj) => { if (ws.readyState === 1) ws.send(JSON.stringify(obj)); };
function notify(accId, obj) {
  const p = presence.get(accId);
  if (p) for (const ws of p.sockets) wsSend(ws, obj);
}
function broadcast(obj) { for (const ws of sockets.keys()) wsSend(ws, obj); }
function socketOfBrute(bruteId) {
  for (const [ws, s] of sockets) if (s.brute === bruteId) return ws;
  return null;
}
const sendToBrute = (bruteId, obj) => { const ws = socketOfBrute(bruteId); if (ws) wsSend(ws, obj); };
function partyOf(bruteId) { return Object.values(db.parties).find((p) => p.members.some((m) => m.brute === bruteId)); }

function lobbyList() {
  const out = [];
  for (const s of sockets.values()) {
    if (!s.brute || !db.brutes[s.brute] || out.some((o) => o.id === s.brute)) continue;
    const p = partyOf(s.brute);
    out.push({ ...bruteView(db.brutes[s.brute]), party: p ? p.id : null, busy: !!s.busy });
  }
  return out;
}
let lobbyTimer = null;
function lobbyChanged() {
  if (lobbyTimer) return;
  lobbyTimer = setTimeout(() => {
    lobbyTimer = null;
    broadcast({ t: 'lobby', players: lobbyList(), parties: partiesList() });
  }, 150);
}

// ------------------------------------------------------------------ salons de partie hébergés par le serveur
const MODES = {
  pvp: { name: 'PvP en équipes', max: 6 },
  coop_ai: { name: "Coop contre l'IA", max: 3 },
  coop_campaign: { name: 'Campagne en coop', max: 3 },
};
function partyView(p) {
  return {
    id: p.id, host: p.host, mode: p.mode, modeName: MODES[p.mode].name, stage: p.stage, difficulty: p.difficulty, public: p.public,
    max: MODES[p.mode].max, state: p.state, lastFight: p.lastFight || null,
    members: p.members.map((m) => ({ ...bruteView(db.brutes[m.brute]), side: m.side, ready: m.ready, connected: !!socketOfBrute(m.brute) })),
  };
}
function partiesList() {
  return Object.values(db.parties).filter((p) => p.public && p.state === 'waiting' && p.members.length < MODES[p.mode].max).map((p) => ({
    id: p.id, mode: p.mode, modeName: MODES[p.mode].name, stage: p.stage, difficulty: p.difficulty, size: p.members.length, max: MODES[p.mode].max,
    host: db.brutes[p.host] ? db.brutes[p.host].name : '?', level: Math.round(p.members.reduce((t, m) => t + db.brutes[m.brute].level, 0) / p.members.length),
  }));
}
function partyUpdate(p) {
  for (const m of p.members) sendToBrute(m.brute, { t: 'party', party: partyView(p) });
  save();
  lobbyChanged();
}
function leaveParty(bruteId, reason) {
  const p = partyOf(bruteId);
  if (!p) return;
  p.members = p.members.filter((m) => m.brute !== bruteId);
  sendToBrute(bruteId, { t: 'party', party: null, text: reason });
  if (!p.members.length) { delete db.parties[p.id]; save(); lobbyChanged(); return; }
  if (p.host === bruteId) p.host = p.members[0].brute;
  partyUpdate(p);
}
function joinParty(p, bruteId) {
  const cur = partyOf(bruteId);
  if (cur && cur.id === p.id) return partyUpdate(p);
  if (cur) leaveParty(bruteId);
  if (p.members.length >= MODES[p.mode].max) return 'Le salon est complet.';
  let side = 0;
  if (p.mode === 'pvp') side = p.members.filter((m) => m.side === 0).length <= p.members.filter((m) => m.side === 1).length ? 0 : 1;
  p.members.push({ brute: bruteId, side, ready: false });
  p.invited = (p.invited || []).filter((x) => x !== bruteId);
  partyUpdate(p);
  return null;
}
function startParty(p) {
  const members = p.members.map((m) => ({ ...m, b: db.brutes[m.brute] }));
  if (members.some((m) => !m.ready && m.brute !== p.host)) return 'Tous les joueurs doivent être prêts.';
  for (const m of members) {
    if (m.b.levelup) return `${m.b.name} doit d'abord choisir son bonus de niveau.`;
    if (p.mode !== 'coop_campaign' && energy(m.b) <= 0) return `${m.b.name} n'a plus d'énergie aujourd'hui.`;
  }
  let teams, opts = { multi: members.length > 1 };
  if (p.mode === 'pvp') {
    teams = [members.filter((m) => m.side === 0).map((m) => m.b), members.filter((m) => m.side === 1).map((m) => m.b)];
    if (!teams[0].length || !teams[1].length) return 'Il faut au moins un joueur dans chaque équipe.';
  } else if (p.mode === 'coop_ai') {
    const avg = members.reduce((t, m) => t + m.b.level, 0) / members.length;
    const diff = { facile: -2, normal: 0, difficile: 2, legendaire: 5 }[p.difficulty] ?? 0;
    const bots = members.map((m, i) => B.makeBot(Math.max(1, Math.round(avg + diff)), crypto.randomInt(1, 2 ** 31) + i));
    teams = [members.map((m) => m.b), bots];
  } else {
    const stage = content.stage(p.stage);
    if (!stage) return 'Chapitre inconnu.';
    const idx = content.data.campaign.indexOf(stage);
    const prev = idx > 0 ? content.data.campaign[idx - 1].id : null;
    if (prev && !db.brutes[p.host].campaign[prev]) return "L'hôte doit d'abord avoir terminé le chapitre précédent.";
    const boss = B.makeBoss(stage);
    const n = members.length;
    boss.stats.hp = Math.round(boss.stats.hp * (0.4 + 0.6 * n));
    boss.stats.str = Math.round(boss.stats.str * (1 + 0.12 * (n - 1)));
    teams = [members.map((m) => m.b), [boss]];
    opts = { ...opts, stage: stage.id, arena: stage.arena };
  }
  const fight = resolveFight(teams, p.mode, opts);
  p.lastFight = fight.id;
  for (const m of p.members) m.ready = false;
  for (const m of members) {
    const side = teams[0].includes(m.b) ? 0 : 1;
    sendToBrute(m.brute, { t: 'fight', fight, side, brute: bruteView(m.b, true), account: accountView(db.accounts[m.b.owner]) });
  }
  partyUpdate(p);
  return null;
}

function handleWs(ws, m) {
  const me = sockets.get(ws);
  const acc = me.acc;
  const myBrute = me.brute && db.brutes[me.brute];
  switch (m.t) {
    case 'hello': {
      const b = db.brutes[m.brute];
      if (!b || b.owner !== acc.id) return;
      const old = socketOfBrute(b.id);
      if (old && old !== ws) { sockets.get(old).brute = null; wsSend(old, { t: 'info', text: 'Ta brute est jouée depuis un autre appareil.' }); }
      me.brute = b.id;
      presence.get(acc.id).brute = b.id;
      if (leaveTimers.has(b.id)) { clearTimeout(leaveTimers.get(b.id)); leaveTimers.delete(b.id); }
      wsSend(ws, { t: 'welcome', players: lobbyList(), parties: partiesList(), chat: chatLog, version: readVersion().version });
      const p = partyOf(b.id);
      if (p) partyUpdate(p); else wsSend(ws, { t: 'party', party: null });
      lobbyChanged();
      return;
    }
    case 'ping': return wsSend(ws, { t: 'pong' });
  }
  if (!myBrute) return;
  switch (m.t) {
    case 'chat': {
      const text = String(m.text || '').slice(0, 200).trim();
      if (!text) return;
      const msg = { from: myBrute.name, text, date: Date.now() };
      chatLog.push(msg);
      if (chatLog.length > 50) chatLog.shift();
      broadcast({ t: 'chat', ...msg });
      return;
    }
    case 'pchat': {
      const p = partyOf(myBrute.id);
      const text = String(m.text || '').slice(0, 200).trim();
      if (p && text) for (const x of p.members) sendToBrute(x.brute, { t: 'pchat', from: myBrute.name, text });
      return;
    }
    // --- duel en direct (défi rapide)
    case 'challenge': {
      const target = db.brutes[m.to];
      if (!target || !socketOfBrute(m.to)) return wsSend(ws, { t: 'info', text: "Ce joueur n'est pas connecté." });
      if (target.owner === acc.id) return wsSend(ws, { t: 'info', text: 'Tu ne peux pas défier ta propre brute.' });
      if (!invites.has(m.to)) invites.set(m.to, new Set());
      invites.get(m.to).add(myBrute.id);
      sendToBrute(m.to, { t: 'challenge', from: bruteView(myBrute) });
      return wsSend(ws, { t: 'info', text: `Défi envoyé à ${target.name} !` });
    }
    case 'decline': {
      if (invites.has(myBrute.id)) invites.get(myBrute.id).delete(m.from);
      return sendToBrute(m.from, { t: 'info', text: `${myBrute.name} a refusé ton défi.` });
    }
    case 'accept': {
      if (!invites.has(myBrute.id) || !invites.get(myBrute.id).has(m.from)) return;
      invites.get(myBrute.id).delete(m.from);
      const att = db.brutes[m.from];
      if (!att || !socketOfBrute(att.id)) return wsSend(ws, { t: 'info', text: 'Le challenger est parti.' });
      if (att.levelup || myBrute.levelup) return wsSend(ws, { t: 'info', text: "Un des deux combattants doit d'abord choisir son bonus de niveau." });
      const fight = resolveFight([[att], [myBrute]], 'live', { multi: true });
      sendToBrute(att.id, { t: 'fight', fight, side: 0, brute: bruteView(att, true), account: accountView(db.accounts[att.owner]) });
      wsSend(ws, { t: 'fight', fight, side: 1, brute: bruteView(myBrute, true), account: accountView(acc) });
      broadcast({ t: 'chat', from: 'Héraut', text: `${att.name} affronte ${myBrute.name} en duel !`, date: Date.now() });
      return;
    }
    case 'busy': me.busy = !!m.busy; return lobbyChanged();
    // --- salons
    case 'party_create': {
      if (!MODES[m.mode]) return;
      leaveParty(myBrute.id);
      const p = { id: newId('p'), host: myBrute.id, mode: m.mode, stage: m.stage || 'c1', difficulty: m.difficulty || 'normal',
        public: m.public !== false, members: [], invited: [], state: 'waiting', created: Date.now() };
      db.parties[p.id] = p;
      joinParty(p, myBrute.id);
      return;
    }
    case 'party_join': {
      const p = db.parties[m.id];
      if (!p) return wsSend(ws, { t: 'info', text: "Ce salon n'existe plus." });
      if (!p.public && !(p.invited || []).includes(myBrute.id)) return wsSend(ws, { t: 'info', text: 'Ce salon est privé : il faut une invitation.' });
      const err = joinParty(p, myBrute.id);
      if (err) wsSend(ws, { t: 'info', text: err });
      return;
    }
    case 'party_leave': return leaveParty(myBrute.id, 'Tu as quitté le salon.');
    case 'party_invite': {
      const p = partyOf(myBrute.id);
      const target = db.brutes[m.to];
      if (!p || !target) return;
      if (!socketOfBrute(m.to)) return wsSend(ws, { t: 'info', text: `${target.name} n'est pas connecté.` });
      p.invited = [...new Set([...(p.invited || []), m.to])];
      sendToBrute(m.to, { t: 'invite', party: p.id, mode: MODES[p.mode].name, from: bruteView(myBrute) });
      save();
      return wsSend(ws, { t: 'info', text: `Invitation envoyée à ${target.name}.` });
    }
    case 'party_settings': {
      const p = partyOf(myBrute.id);
      if (!p || p.host !== myBrute.id) return;
      if (m.mode && MODES[m.mode] && p.members.length <= MODES[m.mode].max) p.mode = m.mode;
      if (m.stage && content.stage(m.stage)) p.stage = m.stage;
      if (m.difficulty) p.difficulty = m.difficulty;
      if (m.public !== undefined) p.public = !!m.public;
      if (p.mode !== 'pvp') for (const x of p.members) x.side = 0;
      for (const x of p.members) x.ready = false;
      return partyUpdate(p);
    }
    case 'party_side': {
      const p = partyOf(myBrute.id);
      if (!p || p.mode !== 'pvp') return;
      const mem = p.members.find((x) => x.brute === (m.brute && p.host === myBrute.id ? m.brute : myBrute.id));
      if (mem) { mem.side = m.side === 1 ? 1 : 0; mem.ready = false; }
      return partyUpdate(p);
    }
    case 'party_ready': {
      const p = partyOf(myBrute.id);
      if (!p) return;
      const mem = p.members.find((x) => x.brute === myBrute.id);
      mem.ready = !!m.ready;
      return partyUpdate(p);
    }
    case 'party_kick': {
      const p = partyOf(myBrute.id);
      if (p && p.host === myBrute.id && m.brute !== myBrute.id) leaveParty(m.brute, "Tu as été exclu du salon par l'hôte.");
      return;
    }
    case 'party_start': {
      const p = partyOf(myBrute.id);
      if (!p || p.host !== myBrute.id) return;
      const err = startParty(p);
      if (err) wsSend(ws, { t: 'info', text: err });
      return;
    }
  }
}

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname !== '/api/ws') return socket.destroy();
  const acc = db.accounts[db.tokens[url.searchParams.get('token')]];
  if (!acc) return socket.destroy();
  P.ensure(acc);
  wss.handleUpgrade(req, socket, head, (ws) => {
    sockets.set(ws, { acc, brute: null, busy: false });
    if (!presence.has(acc.id)) presence.set(acc.id, { sockets: new Set(), brute: null });
    presence.get(acc.id).sockets.add(ws);
    for (const f of acc.friends) notify(f, { t: 'friends' });
    ws.on('message', (raw) => {
      let m;
      try { m = JSON.parse(raw); } catch { return; }
      try { handleWs(ws, m); } catch (e) { console.error(e); }
    });
    ws.on('close', () => {
      const s = sockets.get(ws);
      sockets.delete(ws);
      const pr = presence.get(acc.id);
      if (pr) { pr.sockets.delete(ws); if (!pr.sockets.size) { presence.delete(acc.id); for (const f of acc.friends) notify(f, { t: 'friends' }); } }
      // Une déconnexion n'exclut pas tout de suite du salon (reconnexion après une mise à jour du serveur, réseau...).
      if (s && s.brute && partyOf(s.brute)) {
        const id = s.brute;
        leaveTimers.set(id, setTimeout(() => { leaveTimers.delete(id); if (!socketOfBrute(id)) leaveParty(id); }, 120000));
        partyUpdate(partyOf(id));
      }
      lobbyChanged();
    });
  });
});

// Au démarrage, les salons restaurés attendent la reconnexion de leurs membres (2 minutes).
for (const p of Object.values(db.parties)) {
  for (const m of p.members) {
    const id = m.brute;
    if (!db.brutes[id]) { p.members = p.members.filter((x) => x.brute !== id); continue; }
    leaveTimers.set(id, setTimeout(() => { leaveTimers.delete(id); if (!socketOfBrute(id)) leaveParty(id); }, 120000));
  }
  if (!p.members.length) delete db.parties[p.id];
}

server.listen(PORT, HOST, () => console.log(`Brutes & Légendes : serveur sur ${HOST}:${PORT}`));
function shutdown() {
  flush();
  // 1012 = « service restart » : les clients se reconnectent automatiquement.
  for (const ws of sockets.keys()) try { ws.close(1012, 'Mise à jour du serveur'); } catch { /* */ }
  setTimeout(() => process.exit(0), 200);
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
