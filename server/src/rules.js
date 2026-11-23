'use strict';

/** Reglas de calidad de los precios compartidos (sin dependencias, probadas en test/). */

const DAILY_LIMIT = 300; // aportaciones por persona y día
const TRUSTED_SOURCES = new Set(['ticket', 'etiqueta']);

function distanceKm(lat1, lng1, lat2, lng2) {
  const r = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(lat2 - lat1);
  const dLng = rad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normName(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/\(.*?\)/g, ' ')
    .replace(/[^a-z0-9 ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Mismo supermercado si comparten la primera palabra significativa del nombre. */
function similarNames(a, b) {
  const first = (s) => (s.split(' ').find((w) => w.length >= 3) || s);
  return first(a) === first(b) || a.includes(b) || b.includes(a);
}

function median(nums) {
  if (nums.length === 0) return null;
  const s = [...nums].sort((x, y) => x - y);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function isDate(s) {
  return typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s));
}

/** Comprueba y normaliza una aportación. */
function validateContribution(it, today) {
  if (!it || typeof it !== 'object') return { ok: false };
  const ean = String(it.ean || '').trim();
  if (!/^\d{8,14}$/.test(ean)) return { ok: false, reason: 'ean' };
  const price = Math.round(Number(it.price) * 100) / 100;
  if (!Number.isFinite(price) || price <= 0 || price > 2000) return { ok: false, reason: 'price' };
  const st = it.store || {};
  const lat = Number(st.lat);
  const lng = Number(st.lng);
  const name = String(st.name || '').trim();
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || name.length < 2) {
    return { ok: false, reason: 'store' };
  }
  const date = isDate(it.date) ? it.date : today;
  if (date > today) return { ok: false, reason: 'future' };
  const age = (Date.parse(today) - Date.parse(date)) / 86_400_000;
  if (age > 90) return { ok: false, reason: 'old' };
  const source = ['manual', 'ticket', 'etiqueta'].includes(it.source) ? it.source : 'manual';
  return {
    ok: true,
    ean,
    price,
    date,
    source,
    isOffer: Boolean(it.is_offer),
    validUntil: isDate(it.valid_until) ? it.valid_until : null,
    store: {
      name,
      lat,
      lng,
      globalId: Number.isInteger(Number(st.global_id)) && Number(st.global_id) > 0 ? Number(st.global_id) : null,
      chain: typeof st.chain === 'string' ? st.chain.slice(0, 30) : null,
    },
    name: String(it.name || '').trim().slice(0, 160),
    brand: String(it.brand || '').trim().slice(0, 80),
    size: String(it.size || '').trim().slice(0, 40),
  };
}

/**
 * Estado inicial: fuera de rango (x3 o /3 de la mediana reciente) -> rejected;
 * de ticket o etiqueta y dentro de rango -> validated; resto -> pending
 * hasta que otra persona lo confirme.
 */
function initialStatus(v, recentPrices) {
  const m = median(recentPrices);
  if (m != null && recentPrices.length >= 3 && (v.price > m * 3 || v.price < m / 3)) return 'rejected';
  if (TRUSTED_SOURCES.has(v.source)) return 'validated';
  return 'pending';
}

/**
 * Agrupa por código y tienda: mediana de los datos de los últimos 30 días
 * (o el último si no hay), ofertas caducadas fuera, con nº de personas.
 */
function aggregate(rows, today) {
  const groups = new Map();
  for (const r of rows) {
    if (r.reports >= 3) continue;
    const vu = r.valid_until ? new Date(r.valid_until).toISOString().slice(0, 10) : null;
    const obs = new Date(r.observed_on).toISOString().slice(0, 10);
    if (r.is_offer) {
      if (vu && vu < today) continue;
      if (!vu && (Date.parse(today) - Date.parse(obs)) / 86_400_000 > 7) continue;
    }
    const k = `${r.ean}|${r.store_id}`;
    if (!groups.has(k)) groups.set(k, { r, items: [] });
    groups.get(k).items.push({ price: Number(r.price), date: obs, key: r.contributor_key, offer: r.is_offer });
  }
  const out = [];
  for (const { r, items } of groups.values()) {
    items.sort((a, b) => (a.date < b.date ? 1 : -1));
    const last = items[0].date;
    const recent = items.filter((x) => (Date.parse(last) - Date.parse(x.date)) / 86_400_000 <= 30);
    out.push({
      ean: r.ean,
      store: { id: Number(r.store_id), name: r.store_name, lat: r.lat, lng: r.lng, chain: r.chain_key || 'otro' },
      price: Math.round(median(recent.map((x) => x.price)) * 100) / 100,
      date: last,
      offer: items[0].offer,
      confirmations: new Set(recent.map((x) => x.key)).size,
    });
  }
  return out;
}

module.exports = {
  DAILY_LIMIT,
  distanceKm,
  normName,
  similarNames,
  median,
  validateContribution,
  initialStatus,
  aggregate,
};
