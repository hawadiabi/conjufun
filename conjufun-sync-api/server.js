// server.js
const express = require('express');
const app = express();

app.use(express.json());

/**
 * Modèle en mémoire :
 * {
 *    remoteId: string,
 *    userId: number,
 *    name: string,
 *    schoolLevel: string | null,
 *    tenses: string[],
 *    verbs: string[],
 *    createdAt: Date,
 *    updatedAt: Date,
 *    maxQuestions: number | null,
 *    isDeleted: boolean,
 *    deletedAt: Date | null
 * }
 */
let customSets = [];
let nextId = 1;

function now() {
  return new Date();
}

function parseIsoOrNull(str) {
  if (!str) return null;
  const d = new Date(str);
  return isNaN(d.getTime()) ? null : d;
}

function toIso(d) {
  return d.toISOString();
}

function generateRemoteId() {
  return 'cs_' + (nextId++) + '_' + Math.random().toString(16).slice(2, 8);
}

/**
 * POST /sync/custom_sets
 * Body:
 * {
 *   user_id: number,
 *   since: string | null (ISO),
 *   custom_sets: [ ... ]
 * }
 */
app.post('/sync/custom_sets', (req, res) => {
  const body = req.body || {};
  const userId = body.user_id;
  const sinceStr = body.since;
  const clientSets = body.custom_sets || [];

  if (typeof userId !== 'number') {
    return res.status(400).json({ error: 'user_id must be a number' });
  }

  const since = sinceStr ? parseIsoOrNull(sinceStr) : null;
  const serverTime = now();

  // 1) Appliquer les modifications envoyées par le client
  for (const cs of clientSets) {
    const remoteId = cs.remote_id || null;

    const name = cs.name;
    const schoolLevel = cs.school_level ?? null;
    const tenses = Array.isArray(cs.tenses) ? cs.tenses : [];
    const verbs = Array.isArray(cs.verbs) ? cs.verbs : [];

    const createdAt = parseIsoOrNull(cs.created_at) || serverTime;
    const updatedAt = parseIsoOrNull(cs.updated_at) || serverTime;

    const maxQuestions =
      cs.max_questions === null || cs.max_questions === undefined
        ? null
        : Number(cs.max_questions);

    const isDeleted = !!cs.is_deleted;
    const deletedAt = cs.deleted_at ? parseIsoOrNull(cs.deleted_at) : null;

    if (!name || tenses.length === 0 || verbs.length === 0) {
      // on ignore les enregistrements incomplets
      continue;
    }

    // Chercher un set existant par userId + remoteId
    let existing = null;
    if (remoteId) {
      existing = customSets.find(
        (s) => s.userId === userId && s.remoteId === remoteId
      );
    }

    if (!existing && !remoteId) {
      // Nouveau set → créer un remoteId
      const newRemoteId = generateRemoteId();
      customSets.push({
        remoteId: newRemoteId,
        userId,
        name,
        schoolLevel,
        tenses,
        verbs,
        createdAt,
        updatedAt,
        maxQuestions,
        isDeleted,
        deletedAt,
      });
    } else if (!existing && remoteId) {
      // Le client a déjà un remoteId mais le serveur ne le connaît pas (ex: reset serveur) → on crée
      customSets.push({
        remoteId,
        userId,
        name,
        schoolLevel,
        tenses,
        verbs,
        createdAt,
        updatedAt,
        maxQuestions,
        isDeleted,
        deletedAt,
      });
    } else if (existing) {
      // Conflit : on compare updatedAt
      if (updatedAt > existing.updatedAt) {
        existing.name = name;
        existing.schoolLevel = schoolLevel;
        existing.tenses = tenses;
        existing.verbs = verbs;
        existing.createdAt = createdAt;
        existing.updatedAt = updatedAt;
        existing.maxQuestions = maxQuestions;
        existing.isDeleted = isDeleted;
        existing.deletedAt = deletedAt;
      }
      // sinon: la version serveur est plus récente → on ignore les données client
    }
  }

  // 2) Renvoyer les éléments mis à jour depuis "since"
  const updated = customSets
    .filter((s) => s.userId === userId)
    .filter((s) => {
      if (!since) return true;
      // si updatedAt ou deletedAt est après "since"
      if (s.updatedAt && s.updatedAt > since) return true;
      if (s.deletedAt && s.deletedAt > since) return true;
      return false;
    })
    .map((s) => ({
      remote_id: s.remoteId,
      name: s.name,
      school_level: s.schoolLevel,
      tenses: s.tenses,
      verbs: s.verbs,
      created_at: toIso(s.createdAt),
      updated_at: toIso(s.updatedAt),
      max_questions: s.maxQuestions,
      is_deleted: s.isDeleted,
      deleted_at: s.deletedAt ? toIso(s.deletedAt) : null,
    }));

  return res.json({
    server_time: toIso(serverTime),
    updated,
  });
});

// Petit endpoint pour tester que le serveur tourne
app.get('/health', (req, res) => {
  res.json({ status: 'ok', customSetsCount: customSets.length });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Sync server listening on http://localhost:${PORT}`);
});
