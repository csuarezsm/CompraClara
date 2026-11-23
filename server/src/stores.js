'use strict';

const rules = require('./rules');
const { detectChain, normalize } = require('./chains');

/** Distancia máxima para considerar dos tiendas de la misma cadena como la misma. */
const SAME_STORE_KM = 0.1;

/** Sigue las fusiones hasta el supermercado vigente. */
async function resolve(db, id) {
  let cur = Number(id);
  for (let i = 0; i < 10; i++) {
    const r = await db.query('SELECT merged_into FROM stores WHERE id = $1', [cur]);
    if (r.rowCount === 0) return null;
    if (r.rows[0].merged_into == null) return cur;
    cur = Number(r.rows[0].merged_into);
  }
  return cur;
}

function publicStore(s, lat, lng) {
  return {
    id: Number(s.id),
    name: s.name,
    chain: s.chain_key || 'otro',
    address: s.address || '',
    city: s.city || '',
    lat: s.lat,
    lng: s.lng,
    source: s.source,
    distance_km: lat == null ? undefined : Math.round(rules.distanceKm(lat, lng, s.lat, s.lng) * 1000) / 1000,
  };
}

async function nearby(db, lat, lng, radiusKm, limit = 40) {
  const dLat = radiusKm / 111;
  const dLng = radiusKm / (111 * Math.max(0.2, Math.cos((lat * Math.PI) / 180)));
  const r = await db.query(
    `SELECT id, name, chain_key, address, city, lat, lng, source FROM stores
     WHERE merged_into IS NULL AND lat BETWEEN $1 AND $2 AND lng BETWEEN $3 AND $4`,
    [lat - dLat, lat + dLat, lng - dLng, lng + dLng],
  );
  return r.rows
    .map((s) => publicStore(s, lat, lng))
    .filter((s) => s.distance_km <= radiusKm)
    .sort((a, b) => a.distance_km - b.distance_km)
    .slice(0, limit);
}

/**
 * Devuelve el supermercado existente (misma cadena a menos de 100 m, o mismo nombre
 * a menos de 150 m) o lo crea como «user».
 */
async function findOrCreate(db, { name, chain, lat, lng, address = '' }) {
  const chainKey = chain || detectChain(name) || 'otro';
  const near = await nearby(db, lat, lng, 0.2, 20);
  const norm = rules.normName(name);
  for (const s of near) {
    if (chainKey !== 'otro' && s.chain === chainKey && s.distance_km <= SAME_STORE_KM) return { id: s.id, created: false };
    if (s.distance_km <= 0.15 && rules.similarNames(norm, rules.normName(s.name))) return { id: s.id, created: false };
  }
  const ins = await db.query(
    `INSERT INTO stores (name, name_norm, lat, lng, chain_key, address, source)
     VALUES ($1, $2, $3, $4, $5, $6, 'user') RETURNING id`,
    [String(name).trim().slice(0, 120), norm, lat, lng, chainKey, String(address).slice(0, 160)],
  );
  return { id: Number(ins.rows[0].id), created: true };
}

/** Fusiona `fromId` en `toId`: precios, avisos y referencias pasan al bueno. */
async function merge(db, fromId, toId) {
  if (Number(fromId) === Number(toId)) return;
  await db.query(
    `DELETE FROM contributions c USING contributions d
     WHERE c.store_id = $1 AND d.store_id = $2 AND c.ean = d.ean
       AND c.observed_on = d.observed_on AND c.contributor_key = d.contributor_key`,
    [fromId, toId],
  );
  await db.query('UPDATE contributions SET store_id = $2 WHERE store_id = $1', [fromId, toId]);
  await db.query('UPDATE stores SET merged_into = $2 WHERE merged_into = $1', [fromId, toId]);
  await db.query('UPDATE stores SET merged_into = $2, updated_at = now() WHERE id = $1', [fromId, toId]);
}

/** Posibles duplicados para revisar: avisos de usuarios y pares muy cercanos. */
async function duplicateCandidates(db) {
  const reported = await db.query(`
    SELECT a.store_id, a.other_id, COUNT(*)::int AS votes
    FROM store_same_as a
    JOIN stores s1 ON s1.id = a.store_id AND s1.merged_into IS NULL
    JOIN stores s2 ON s2.id = a.other_id AND s2.merged_into IS NULL
    GROUP BY a.store_id, a.other_id ORDER BY votes DESC LIMIT 100`);
  const close = await db.query(`
    SELECT s1.id AS store_id, s2.id AS other_id, 0 AS votes
    FROM stores s1 JOIN stores s2
      ON s1.id < s2.id AND s1.merged_into IS NULL AND s2.merged_into IS NULL
     AND abs(s1.lat - s2.lat) < 0.0013 AND abs(s1.lng - s2.lng) < 0.0013
     AND (s1.source = 'user' OR s2.source = 'user')
     AND NOT EXISTS (SELECT 1 FROM store_distinct d WHERE d.a = s1.id AND d.b = s2.id)
    LIMIT 200`);
  const ids = new Set();
  const pairs = [];
  for (const p of [...reported.rows, ...close.rows]) {
    const k = [p.store_id, p.other_id].sort().join('-');
    if (ids.has(k)) continue;
    ids.add(k);
    pairs.push(p);
  }
  const out = [];
  for (const p of pairs) {
    const r = await db.query(
      `SELECT id, name, chain_key, address, city, lat, lng, source,
              (SELECT COUNT(*)::int FROM contributions c WHERE c.store_id = stores.id) AS prices
       FROM stores WHERE id = ANY($1)`,
      [[p.store_id, p.other_id]],
    );
    if (r.rowCount !== 2) continue;
    const [a, b] = r.rows;
    out.push({
      votes: p.votes,
      distance_m: Math.round(rules.distanceKm(a.lat, a.lng, b.lat, b.lng) * 1000),
      a: { ...publicStore(a), prices: a.prices },
      b: { ...publicStore(b), prices: b.prices },
    });
  }
  return out;
}

module.exports = { resolve, nearby, findOrCreate, merge, duplicateCandidates, publicStore, normalize, SAME_STORE_KM };
