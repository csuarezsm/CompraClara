/// Cadenas de supermercados (misma lista que el servidor, server/src/chains.js).
/// Se eligen de esta lista, nunca se escriben: así no hay duplicados por el nombre.
const Map<String, String> chainNames = {
  'mercadona': 'Mercadona',
  'hiperdino': 'HiperDino',
  'superdino': 'SuperDino',
  'spar': 'SPAR',
  'lidl': 'Lidl',
  'aldi': 'ALDI',
  'carrefour': 'Carrefour',
  'alcampo': 'Alcampo',
  'dia': 'Dia',
  'eroski': 'Eroski',
  'coviran': 'Covirán',
  'bm': 'BM Supermercados',
  'otro': 'Otro',
};

String chainName(String key) => chainNames[key] ?? (key.isEmpty ? 'Sin cadena' : key);
