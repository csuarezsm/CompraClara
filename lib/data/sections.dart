/// Plantilla de secciones con la que nace cada supermercado.
const List<String> defaultSections = [
  'Fruta y verdura',
  'Panadería y bollería',
  'Carnicería y aves',
  'Pescadería',
  'Charcutería y quesos',
  'Lácteos y huevos',
  'Congelados',
  'Conservas y salsas',
  'Pasta, arroz y legumbres',
  'Desayuno y dulces',
  'Aceites, especias y condimentos',
  'Bebidas',
  'Snacks y aperitivos',
  'Limpieza del hogar',
  'Droguería e higiene',
  'Bebés',
  'Mascotas',
  'Otros',
];

const String otherSection = 'Otros';

/// Palabras clave (nombre en español o etiquetas de Open Food Facts).
/// El orden importa: gana la primera sección que coincida.
const Map<String, List<String>> _rules = {
  'Charcutería y quesos': [
    'queso', 'cheese', 'jamón', 'jamon', 'chorizo', 'salchichón', 'salchichon',
    'fuet', 'mortadela', 'embutido', 'charcuter', 'lomo embuchado', 'pavo',
    'salchicha', 'bacon', 'panceta',
  ],
  'Lácteos y huevos': [
    'leche', 'milk', 'yogur', 'yogurt', 'huevo', 'eggs', 'mantequilla', 'butter',
    'nata', 'cream', 'flan', 'natilla', 'kéfir', 'kefir', 'dairy', 'lácteo',
  ],
  'Fruta y verdura': [
    'fruta', 'verdura', 'manzana', 'plátano', 'platano', 'banana', 'naranja',
    'limón', 'limon', 'tomate', 'lechuga', 'patata', 'cebolla', 'zanahoria',
    'pimiento', 'pepino', 'calabac', 'ajo', 'aguacate', 'uva', 'pera', 'fresa',
    'melón', 'melon', 'sandía', 'sandia', 'fruits', 'vegetables', 'ensalada',
  ],
  'Panadería y bollería': [
    'pan ', 'pan de', 'barra de pan', 'panader', 'baguette', 'bollo', 'croissant',
    'magdalena', 'tostada', 'bread', 'bollería', 'bolleria',
  ],
  'Carnicería y aves': [
    'carne', 'pollo', 'ternera', 'cerdo', 'cordero', 'hamburguesa', 'solomillo',
    'chuleta', 'filete', 'pechuga', 'muslo', 'conejo', 'meat', 'poultry', 'picada',
  ],
  'Pescadería': [
    'pescado', 'merluza', 'salmón', 'salmon', 'atún fresco', 'gamba', 'calamar',
    'sepia', 'pulpo', 'mejillón', 'mejillon', 'dorada', 'lubina', 'fish', 'seafood',
    'bacalao',
  ],
  'Congelados': [
    'congelad', 'helado', 'frozen', 'pizza', 'croqueta', 'nugget', 'ice cream',
  ],
  'Bebés': [
    'pañal', 'panal', 'toallitas', 'potito', 'papilla', 'biberón', 'biberon',
    'baby', 'infantil',
  ],
  'Mascotas': [
    'perro', 'gato', 'pienso', 'mascota', 'arena para gato', 'pet food',
  ],
  'Bebidas': [
    'agua', 'refresco', 'cerveza', 'vino', 'zumo', 'cola', 'fanta', 'sprite',
    'tónica', 'tonica', 'licor', 'whisky', 'ron ', 'ginebra', 'vodka', 'cava',
    'beverages', 'water', 'juice', 'beer', 'wine', 'bebida', 'isotónic',
  ],
  'Aceites, especias y condimentos': [
    'aceite', 'oil', 'vinagre', 'sal ', 'pimienta', 'especia', 'orégano', 'oregano',
    'pimentón', 'pimenton', 'comino', 'azafrán', 'azafran', 'condiment',
  ],
  'Conservas y salsas': [
    'conserva', 'lata', 'atún', 'atun', 'sardina', 'tomate frito', 'salsa',
    'mayonesa', 'ketchup', 'mostaza', 'sauce', 'canned', 'mejillones en',
  ],
  'Pasta, arroz y legumbres': [
    'pasta', 'espagueti', 'macarron', 'fideo', 'arroz', 'lenteja', 'garbanzo',
    'alubia', 'judía', 'judia', 'rice', 'legumes', 'harina', 'cuscús', 'cuscus',
  ],
  'Desayuno y dulces': [
    'cereal', 'galleta', 'café', 'cafe', 'cacao', 'colacao', 'mermelada', 'miel',
    'chocolate', 'azúcar', 'azucar', 'infusión', 'infusion', 'té ', 'bizcocho',
    'dulce', 'turrón', 'turron', 'breakfast', 'sweet',
  ],
  'Snacks y aperitivos': [
    'patatas fritas', 'snack', 'frutos secos', 'almendra', 'cacahuete', 'pipas',
    'aceituna', 'aperitivo', 'palomitas', 'nachos', 'chips', 'gusanitos',
  ],
  'Limpieza del hogar': [
    'detergente', 'lejía', 'lejia', 'fregasuelos', 'limpia', 'suavizante',
    'lavavajillas', 'friegaplatos', 'estropajo', 'bayeta', 'ambientador',
    'bolsas de basura', 'cleaning', 'desinfectante',
  ],
  'Droguería e higiene': [
    'champú', 'champu', 'gel de ducha', 'gel ', 'jabón', 'jabon', 'pasta de dientes',
    'dentífrico', 'dentifrico', 'cepillo', 'desodorante', 'papel higiénico',
    'papel higienico', 'compresa', 'tampón', 'tampon', 'colonia', 'crema',
    'afeitar', 'hygiene', 'pañuelo', 'panuelo', 'algodón', 'algodon',
  ],
};

/// Propone la sección general de un artículo a partir de su nombre y,
/// si hay, de las categorías de Open Food Facts.
String guessSection(String text, {List<String> tags = const []}) {
  final haystack = ' ${text.toLowerCase()} ${tags.join(' ').toLowerCase()} ';
  for (final entry in _rules.entries) {
    for (final kw in entry.value) {
      if (haystack.contains(kw)) return entry.key;
    }
  }
  return otherSection;
}
