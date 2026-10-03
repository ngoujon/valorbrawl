// Peuple un serveur (local, pour les tests) : quelques joueurs, brutes montées en niveau, amis, signalements.
// Usage : node test/seed.js [http://127.0.0.1:8097/api]
const base = process.argv[2] || 'http://127.0.0.1:8097/api';
async function call(method, p, body, token) {
  const r = await fetch(base + p, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
  return r.json();
}
const PLAYERS = [
  ['Ragnhild', 'Hache-Rouge', 'naine'], ['Gaspard', 'Sire Bedaine', 'chevalier'], ['Lysandre', 'Feuille-Vive', 'elfe'],
  ['Morg', 'Grokk', 'orc'], ['Merlinot', 'Barbe-Grise', 'mage'], ['Zélie', 'Ombre-Agile', 'voleuse'], ['Taurus', 'Corne-Folle', 'minotaure'],
];
(async () => {
  const sessions = [];
  for (const [user, brute, hero] of [['Testeur', 'Grobalaf', 'barbare'], ...PLAYERS]) {
    let s = await call('POST', '/login', { user, pass: 'testtest' });
    if (s.error) s = await call('POST', '/register', { user, pass: 'testtest' });
    if (!s.account.brutes.length) await call('POST', '/brute/create', { name: brute, hero }, s.token);
    sessions.push({ user, token: s.token });
  }
  for (const [i, s] of sessions.entries()) {
    const fights = 4 + i * 2;
    for (let k = 0; k < fights; k++) {
      const me = (await call('GET', '/me', null, s.token)).account;
      const b = me.brutes[0];
      if (b.levelup) await call('POST', '/brute/levelup', { brute: b.id, choice: k % 2 }, s.token);
      const r = await call('POST', '/fight/ai', { brute: b.id, difficulty: 'facile' }, s.token);
      if (r.error) break;
    }
    const me = (await call('GET', '/me', null, s.token)).account;
    if (me.brutes[0].levelup && s.user !== 'Testeur') await call('POST', '/brute/levelup', { brute: me.brutes[0].id, choice: 0 }, s.token);
    console.log(s.user, 'niveau', me.brutes[0].level);
  }
  const t = sessions[0];
  for (const n of ['Ragnhild', 'Gaspard', 'Zélie']) await call('POST', '/friends/add', { name: n }, t.token);
  for (const s of sessions.slice(1, 3)) {
    const fr = await call('GET', '/friends', null, s.token);
    for (const r of fr.requests) await call('POST', '/friends/accept', { id: r.id }, s.token);
  }
  await call('POST', '/friends/add', { name: 'Testeur' }, sessions[5].token);
  await call('POST', '/friends/add', { name: 'Testeur' }, sessions[6].token);
  await call('POST', '/report', { type: 'suggestion', title: 'Ajouter des tournois hebdomadaires', text: 'Ce serait génial d\'avoir un tournoi chaque semaine avec un classement et des récompenses.' }, sessions[2].token);
  await call('POST', '/report', { type: 'bug', title: 'Le dragonnet sort parfois de l\'écran', text: 'Quand il y a beaucoup de familiers, le dragonnet est poussé hors de l\'arène.' }, sessions[4].token);
  await call('POST', '/profile', { motto: 'Je cogne, donc je suis.' }, t.token);
  console.log('Peuplement terminé.');
})();
