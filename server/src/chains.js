'use strict';

/**
 * Cadenas de supermercados (lista común con la app, lib/data/chains.dart).
 * `match`: palabras que identifican la cadena en el nombre o la marca de OpenStreetMap.
 */
const CHAINS = [
  { key: 'mercadona', name: 'Mercadona', match: ['mercadona'] },
  { key: 'hiperdino', name: 'HiperDino', match: ['hiperdino', 'hiper dino'] },
  { key: 'superdino', name: 'SuperDino', match: ['superdino', 'super dino'] },
  { key: 'spar', name: 'SPAR', match: ['spar'] },
  { key: 'lidl', name: 'Lidl', match: ['lidl'] },
  { key: 'aldi', name: 'ALDI', match: ['aldi'] },
  { key: 'carrefour', name: 'Carrefour', match: ['carrefour'] },
  { key: 'alcampo', name: 'Alcampo', match: ['alcampo', 'auchan'] },
  { key: 'dia', name: 'Dia', match: ['dia %', 'dia', 'supermercados dia'] },
  { key: 'eroski', name: 'Eroski', match: ['eroski'] },
  { key: 'coviran', name: 'Covirán', match: ['coviran', 'covirán'] },
  { key: 'bm', name: 'BM Supermercados', match: ['bm supermercados'] },
  { key: 'otro', name: 'Otro', match: [] },
];

function normalize(s) {
  return String(s || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9% ]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Cadena a partir de la marca o el nombre (null si no se reconoce). */
function detectChain(...texts) {
  const words = ` ${texts.map(normalize).join(' ')} `;
  for (const c of CHAINS) {
    for (const m of c.match) {
      if (words.includes(` ${normalize(m)} `)) return c.key;
    }
  }
  return null;
}

module.exports = { CHAINS, detectChain, normalize };
