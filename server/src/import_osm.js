'use strict';

/**
 * Carga o actualiza el catálogo de supermercados de Canarias desde OpenStreetMap
 * (datos © colaboradores de OpenStreetMap, licencia ODbL).
 *
 *   docker compose -p compraclara run --rm api node src/import_osm.js
 *
 * Es idempotente: actualiza por osm_id y no borra nada.
 */
const { Pool } = require('pg');
const { CHAINS, detectChain } = require('./chains');
const stores = require('./stores');

const BBOX = process.env.OSM_BBOX || '27.5,-18.3,29.5,-13.2'; // Canarias (sur, oeste, norte, este)
const OVERPASS = process.env.OVERPASS_URL || 'https://overpass-api.de/api/interpreter';

const query = `[out:json][timeout:180];
(
  nwr["shop"="supermarket"](${BBOX});
  nwr["shop"="convenience"]["brand"](${BBOX});
);
out center tags;`;

async function main() {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  for (const c of CHAINS) {
    await pool.query('INSERT INTO chains (key, name) VALUES ($1,$2) ON CONFLICT (key) DO UPDATE SET name = EXCLUDED.name', [c.key, c.name]);
  }
  console.log('Descargando supermercados de OpenStreetMap…');
  const r = await fetch(OVERPASS, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'CompraClara/1.0 (info@itcanarias.com)' },
    body: 'data=' + encodeURIComponent(query),
  });
  if (!r.ok) throw new Error(`Overpass respondió ${r.status}`);
  const data = await r.json();
  let inserted = 0;
  let updated = 0;
  for (const el of data.elements || []) {
    const t = el.tags || {};
    const lat = el.lat ?? el.center?.lat;
    const lng = el.lon ?? el.center?.lon;
    if (lat == null || lng == null) continue;
    const chain = detectChain(t.brand, t.name, t.operator) || 'otro';
    const name = t.name || t.brand || 'Supermercado';
    const street = [t['addr:street'], t['addr:housenumber']].filter(Boolean).join(' ');
    const city = t['addr:city'] || t['addr:place'] || '';
    const osmId = `${el.type}/${el.id}`;
    const res = await pool.query(
      `INSERT INTO stores (name, name_norm, lat, lng, chain_key, osm_id, address, city, source)
       VALUES ($1, lower($1), $2, $3, $4, $5, $6, $7, 'osm')
       ON CONFLICT (osm_id) WHERE osm_id IS NOT NULL DO UPDATE
         SET name = EXCLUDED.name, lat = EXCLUDED.lat, lng = EXCLUDED.lng, chain_key = EXCLUDED.chain_key,
             address = EXCLUDED.address, city = EXCLUDED.city, updated_at = now()
       RETURNING (xmax = 0) AS inserted`,
      [name.slice(0, 120), lat, lng, chain, osmId, street.slice(0, 160), city.slice(0, 80)],
    );
    if (res.rows[0].inserted) inserted++; else updated++;
  }
  // Supermercados creados por usuarios que coinciden con uno de OSM (misma cadena, < 100 m): se fusionan.
  const merged = await pool.query(`
    WITH pairs AS (
      SELECT u.id AS from_id, o.id AS to_id,
             row_number() OVER (PARTITION BY u.id ORDER BY (u.lat-o.lat)^2 + (u.lng-o.lng)^2) AS rn
      FROM stores u JOIN stores o
        ON o.source = 'osm' AND u.source = 'user' AND u.merged_into IS NULL AND o.merged_into IS NULL
       AND u.chain_key = o.chain_key AND u.chain_key <> 'otro'
       AND abs(u.lat - o.lat) < 0.001 AND abs(u.lng - o.lng) < 0.001
    )
    SELECT from_id, to_id FROM pairs WHERE rn = 1`);
  for (const m of merged.rows) {
    await stores.merge(pool, m.from_id, m.to_id);
  }
  console.log(`Catálogo: ${inserted} nuevos, ${updated} actualizados, ${merged.rowCount} duplicados fusionados.`);
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
