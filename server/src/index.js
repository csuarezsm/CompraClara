'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const rules = require('./rules');

const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET;
const CONTRIB_SECRET = process.env.CONTRIB_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32 || !CONTRIB_SECRET || CONTRIB_SECRET.length < 32) {
  console.error('Faltan JWT_SECRET y CONTRIB_SECRET (mínimo 32 caracteres cada uno).');
  process.exit(1);
}

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const app = express();
app.set('trust proxy', 1);
app.use(helmet());
app.use(express.json({ limit: '25mb' }));

const limiter = rateLimit({ windowMs: 60_000, limit: 120, standardHeaders: true, legacyHeaders: false });
const authLimiter = rateLimit({ windowMs: 15 * 60_000, limit: 20, standardHeaders: true, legacyHeaders: false });
app.use('/v1/', limiter);

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function token(userId) {
  return jwt.sign({ sub: String(userId) }, JWT_SECRET, { expiresIn: '180d' });
}

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const t = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!t) return res.status(401).json({ error: 'Falta iniciar sesión' });
  try {
    req.userId = Number(jwt.verify(t, JWT_SECRET).sub);
    next();
  } catch {
    res.status(401).json({ error: 'Sesión caducada' });
  }
}

/** Clave anónima de quien aporta: no se puede volver al usuario sin el secreto. */
function contributorKey(userId) {
  return crypto.createHmac('sha256', CONTRIB_SECRET).update(String(userId)).digest('hex').slice(0, 32);
}

// ------------------------------------------------------------------ Salud

app.get('/v1/health', wrap(async (_req, res) => {
  await pool.query('SELECT 1');
  res.json({ ok: true, service: 'compraclara', time: new Date().toISOString() });
}));

// ----------------------------------------------------------------- Cuentas

app.post('/v1/auth/register', authLimiter, wrap(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return res.status(400).json({ error: 'Correo no válido' });
  if (password.length < 8) return res.status(400).json({ error: 'La contraseña debe tener al menos 8 caracteres' });
  const hash = await bcrypt.hash(password, 12);
  try {
    const r = await pool.query('INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id', [email, hash]);
    res.status(201).json({ token: token(r.rows[0].id), email });
  } catch (e) {
    if (e.code === '23505') return res.status(409).json({ error: 'Ya existe una cuenta con ese correo' });
    throw e;
  }
}));

app.post('/v1/auth/login', authLimiter, wrap(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const r = await pool.query('SELECT id, password_hash FROM users WHERE email = $1', [email]);
  const ok = r.rowCount === 1 && (await bcrypt.compare(password, r.rows[0].password_hash));
  if (!ok) return res.status(401).json({ error: 'Correo o contraseña incorrectos' });
  res.json({ token: token(r.rows[0].id), email });
}));

/** Borra la cuenta y su copia. Las aportaciones de precios ya son anónimas y se quedan. */
app.delete('/v1/account', auth, wrap(async (req, res) => {
  await pool.query('DELETE FROM users WHERE id = $1', [req.userId]);
  res.json({ ok: true });
}));

// ------------------------------------------------------- Copia en la nube

app.put('/v1/backup', auth, wrap(async (req, res) => {
  const body = req.body;
  if (!body || body.app !== 'CompraClara' || typeof body.data !== 'object') {
    return res.status(400).json({ error: 'No es una copia de CompraClara' });
  }
  const json = JSON.stringify(body);
  await pool.query(
    `INSERT INTO backups (user_id, data, size_bytes, updated_at) VALUES ($1, $2, $3, now())
     ON CONFLICT (user_id) DO UPDATE SET data = EXCLUDED.data, size_bytes = EXCLUDED.size_bytes, updated_at = now()`,
    [req.userId, json, Buffer.byteLength(json)],
  );
  res.json({ ok: true, size: Buffer.byteLength(json) });
}));

app.get('/v1/backup', auth, wrap(async (req, res) => {
  const r = await pool.query('SELECT data, updated_at FROM backups WHERE user_id = $1', [req.userId]);
  if (r.rowCount === 0) return res.status(404).json({ error: 'No hay copia en la nube' });
  res.json({ updated_at: r.rows[0].updated_at, backup: r.rows[0].data });
}));

app.get('/v1/backup/info', auth, wrap(async (req, res) => {
  const r = await pool.query('SELECT size_bytes, updated_at FROM backups WHERE user_id = $1', [req.userId]);
  res.json(r.rowCount === 0 ? { exists: false } : { exists: true, ...r.rows[0] });
}));

// ------------------------------------------------------ Precios compartidos

/** Busca un supermercado de la comunidad a menos de 150 m con nombre parecido, o lo crea. */
async function findOrCreateStore(client, name, lat, lng) {
  const norm = rules.normName(name);
  const d = 0.002; // ~200 m
  const r = await client.query(
    'SELECT id, name_norm, lat, lng FROM stores WHERE lat BETWEEN $1 AND $2 AND lng BETWEEN $3 AND $4',
    [lat - d, lat + d, lng - d, lng + d],
  );
  let best = null;
  for (const s of r.rows) {
    const dist = rules.distanceKm(lat, lng, s.lat, s.lng);
    if (dist <= 0.15 && rules.similarNames(norm, s.name_norm) && (!best || dist < best.dist)) best = { id: s.id, dist };
  }
  if (best) return best.id;
  const ins = await client.query(
    'INSERT INTO stores (name, name_norm, lat, lng) VALUES ($1, $2, $3, $4) RETURNING id',
    [name.trim().slice(0, 120), norm, lat, lng],
  );
  return ins.rows[0].id;
}

/**
 * Recibe precios: [{ean, name, brand, size, store:{name,lat,lng}, price, is_offer, valid_until, date, source}]
 * Se guardan sin vincularlos a la cuenta.
 */
app.post('/v1/prices', auth, wrap(async (req, res) => {
  const items = Array.isArray(req.body.prices) ? req.body.prices.slice(0, 500) : [];
  const key = contributorKey(req.userId);
  const today = new Date().toISOString().slice(0, 10);
  const todays = await pool.query(
    'SELECT COUNT(*)::int AS n FROM contributions WHERE contributor_key = $1 AND created_at > now() - interval \'1 day\'',
    [key],
  );
  let budget = rules.DAILY_LIMIT - todays.rows[0].n;
  let accepted = 0;
  let rejected = 0;
  const client = await pool.connect();
  try {
    for (const it of items) {
      if (budget <= 0) break;
      const v = rules.validateContribution(it, today);
      if (!v.ok) { rejected++; continue; }
      const storeId = await findOrCreateStore(client, v.store.name, v.store.lat, v.store.lng);
      if (v.name) {
        await client.query(
          `INSERT INTO products (ean, name, brand, size) VALUES ($1, $2, $3, $4)
           ON CONFLICT (ean) DO NOTHING`,
          [v.ean, v.name, v.brand, v.size],
        );
      }
      const recent = await client.query(
        `SELECT price::float AS price FROM contributions
         WHERE ean = $1 AND store_id = $2 AND status <> 'rejected' AND observed_on > $3::date - 60
         ORDER BY observed_on DESC LIMIT 20`,
        [v.ean, storeId, v.date],
      );
      const status = rules.initialStatus(v, recent.rows.map((r) => r.price));
      const ins = await client.query(
        `INSERT INTO contributions (ean, store_id, price, is_offer, valid_until, observed_on, source, contributor_key, status)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         ON CONFLICT (ean, store_id, observed_on, contributor_key)
         DO UPDATE SET price = EXCLUDED.price, is_offer = EXCLUDED.is_offer, valid_until = EXCLUDED.valid_until,
                       source = EXCLUDED.source, status = EXCLUDED.status
         RETURNING id`,
        [v.ean, storeId, v.price, v.isOffer, v.validUntil, v.date, v.source, key, status],
      );
      if (status !== 'rejected') {
        // Confirmación cruzada: otra persona con el mismo precio (±5 %) en 7 días valida ambas.
        await client.query(
          `UPDATE contributions SET status = 'validated'
           WHERE ean = $1 AND store_id = $2 AND status = 'pending'
             AND observed_on BETWEEN $3::date - 7 AND $3::date + 7
             AND EXISTS (
               SELECT 1 FROM contributions c2
               WHERE c2.ean = $1 AND c2.store_id = $2 AND c2.id <> contributions.id
                 AND c2.contributor_key <> contributions.contributor_key AND c2.status <> 'rejected'
                 AND abs(c2.price - contributions.price) <= contributions.price * 0.05
                 AND c2.observed_on BETWEEN contributions.observed_on - 7 AND contributions.observed_on + 7)`,
          [v.ean, storeId, v.date],
        );
      }
      if (ins.rowCount) { accepted++; budget--; }
    }
  } finally {
    client.release();
  }
  res.json({ accepted, rejected, limited: budget <= 0 });
}));

/**
 * Precios de la comunidad cerca de un punto para unos códigos de barras.
 * GET /v1/prices?lat=..&lng=..&radius_km=20&eans=841...,842...
 */
app.get('/v1/prices', auth, wrap(async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const radius = Math.min(Math.max(Number(req.query.radius_km) || 20, 1), 100);
  const eans = String(req.query.eans || '').split(',').map((e) => e.trim()).filter((e) => /^\d{8,14}$/.test(e)).slice(0, 300);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || eans.length === 0) {
    return res.status(400).json({ error: 'Faltan lat, lng o eans' });
  }
  const dLat = radius / 111;
  const dLng = radius / (111 * Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  const r = await pool.query(
    `SELECT c.ean, c.price::float AS price, c.is_offer, c.valid_until, c.observed_on, c.status, c.contributor_key,
            s.id AS store_id, s.name AS store_name, s.lat, s.lng,
            (SELECT COUNT(*)::int FROM reports rp WHERE rp.contribution_id = c.id) AS reports
     FROM contributions c JOIN stores s ON s.id = c.store_id
     WHERE c.ean = ANY($1) AND c.status = 'validated'
       AND c.observed_on > CURRENT_DATE - 90
       AND s.lat BETWEEN $2 AND $3 AND s.lng BETWEEN $4 AND $5
     ORDER BY c.observed_on DESC`,
    [eans, lat - dLat, lat + dLat, lng - dLng, lng + dLng],
  );
  const rows = r.rows.filter((x) => rules.distanceKm(lat, lng, x.lat, x.lng) <= radius);
  res.json({ prices: rules.aggregate(rows, new Date().toISOString().slice(0, 10)) });
}));

/** «Este precio no es correcto»: con 3 avisos de personas distintas, se descarta. */
app.post('/v1/prices/report', auth, wrap(async (req, res) => {
  const { ean, store_id: storeId, price } = req.body || {};
  const key = contributorKey(req.userId);
  const c = await pool.query(
    `SELECT id FROM contributions WHERE ean = $1 AND store_id = $2 AND abs(price - $3) < 0.005
     ORDER BY observed_on DESC LIMIT 5`,
    [String(ean), Number(storeId), Number(price)],
  );
  for (const row of c.rows) {
    await pool.query('INSERT INTO reports (contribution_id, contributor_key) VALUES ($1,$2) ON CONFLICT DO NOTHING', [row.id, key]);
    await pool.query(
      `UPDATE contributions SET status = 'rejected'
       WHERE id = $1 AND (SELECT COUNT(*) FROM reports WHERE contribution_id = $1) >= 3`,
      [row.id],
    );
  }
  res.json({ ok: true, matched: c.rowCount });
}));

// ------------------------------------------------------------------ Errores

app.use((req, res) => res.status(404).json({ error: 'No encontrado' }));
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(err);
  if (err.type === 'entity.too.large') return res.status(413).json({ error: 'Demasiado grande' });
  res.status(500).json({ error: 'Error interno' });
});

async function start() {
  const schema = fs.readFileSync(path.join(__dirname, '..', 'db', 'schema.sql'), 'utf8');
  for (let i = 0; i < 30; i++) {
    try {
      await pool.query(schema);
      break;
    } catch (e) {
      if (i === 29) throw e;
      console.log('Esperando a la base de datos…');
      await new Promise((r) => setTimeout(r, 2000));
    }
  }
  app.listen(PORT, () => console.log(`CompraClara API escuchando en :${PORT}`));
}

if (require.main === module) {
  start().catch((e) => {
    console.error(e);
    process.exit(1);
  });
}

module.exports = { app };
