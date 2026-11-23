import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local (todo en el móvil en el MVP).
/// Todos los registros usan id de texto único para poder sincronizar después.
class AppDb {
  static Future<Database> open() async {
    final path = p.join(await getDatabasesPath(), 'compraclara.db');
    return openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stores (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            chain TEXT NOT NULL DEFAULT '',
            lat REAL,
            lng REAL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('''
          CREATE TABLE store_sections (
            id TEXT PRIMARY KEY,
            store_id TEXT NOT NULL,
            name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            hidden INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT NOT NULL DEFAULT '',
            size TEXT NOT NULL DEFAULT '',
            section TEXT NOT NULL DEFAULT 'Otros',
            notes TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE barcodes (
            ean TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE product_store (
            product_id TEXT NOT NULL,
            store_id TEXT NOT NULL,
            section_id TEXT NOT NULL,
            PRIMARY KEY (product_id, store_id),
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
            FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
            FOREIGN KEY (section_id) REFERENCES store_sections(id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE lists (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            store_id TEXT,
            budget REAL,
            archived INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL
          )''');
        await db.execute('''
          CREATE TABLE list_items (
            id TEXT PRIMARY KEY,
            list_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            qty REAL NOT NULL DEFAULT 1,
            note TEXT NOT NULL DEFAULT '',
            status INTEGER NOT NULL DEFAULT 0,
            price REAL,
            position INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (list_id) REFERENCES lists(id) ON DELETE CASCADE,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
          )''');
        await db.execute('''
          CREATE TABLE prices (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            store_id TEXT NOT NULL,
            price REAL NOT NULL,
            date TEXT NOT NULL,
            is_offer INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'manual',
            created_at INTEGER NOT NULL,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
            FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
          )''');
        await db.execute('CREATE INDEX idx_items_list ON list_items(list_id)');
        await db.execute('CREATE INDEX idx_prices_ps ON prices(product_id, store_id)');
        await db.execute('CREATE INDEX idx_sections_store ON store_sections(store_id)');
        await _v3(db);
        await _v4(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE stores ADD COLUMN lat REAL');
          await db.execute('ALTER TABLE stores ADD COLUMN lng REAL');
          await db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
        }
        if (oldVersion < 3) await _v3(db);
        if (oldVersion < 4) await _v4(db);
      },
    );
  }

  /// Versión 3: historial de compras, plantillas, cantidades parciales,
  /// precio por unidad, alias de tickets, recorrido, tarjetas y cupones.
  static Future<void> _v3(Database db) async {
    await db.execute('ALTER TABLE lists ADD COLUMN is_template INTEGER NOT NULL DEFAULT 0');
    await db.execute('ALTER TABLE list_items ADD COLUMN picked_qty REAL');
    await db.execute('ALTER TABLE list_items ADD COLUMN picked_at INTEGER');
    await db.execute('ALTER TABLE products ADD COLUMN unit_qty REAL');
    await db.execute('ALTER TABLE products ADD COLUMN unit TEXT');
    await db.execute("ALTER TABLE products ADD COLUMN allergens TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE products ADD COLUMN nutriscore TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE products ADD COLUMN labels TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE prices ADD COLUMN valid_until TEXT');
    await db.execute('''
      CREATE TABLE purchases (
        id TEXT PRIMARY KEY,
        list_id TEXT,
        store_id TEXT,
        store_name TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        total REAL NOT NULL DEFAULT 0,
        items_count INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'compra',
        image_path TEXT,
        warranty_until TEXT,
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE SET NULL
      )''');
    await db.execute('''
      CREATE TABLE purchase_items (
        id TEXT PRIMARY KEY,
        purchase_id TEXT NOT NULL,
        product_id TEXT,
        raw_text TEXT NOT NULL DEFAULT '',
        qty REAL NOT NULL DEFAULT 1,
        unit_price REAL,
        amount REAL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )''');
    await db.execute('''
      CREATE TABLE aliases (
        store_key TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        product_id TEXT NOT NULL,
        PRIMARY KEY (store_key, raw_text),
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE route_log (
        id TEXT PRIMARY KEY,
        store_id TEXT NOT NULL,
        section_id TEXT NOT NULL,
        rank REAL NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
      )''');
    await db.execute('''
      CREATE TABLE cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        format TEXT NOT NULL DEFAULT 'ean13',
        notes TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE coupons (
        id TEXT PRIMARY KEY,
        store_name TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL,
        code TEXT NOT NULL DEFAULT '',
        expires TEXT,
        used INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('CREATE INDEX idx_pitems_product ON purchase_items(product_id)');
    await db.execute('CREATE INDEX idx_purchases_date ON purchases(date)');
  }

  /// Versión 4: supermercados enlazados al catálogo común (id global, cadena y dirección).
  static Future<void> _v4(Database db) async {
    await db.execute('ALTER TABLE stores ADD COLUMN global_id TEXT');
    await db.execute("ALTER TABLE stores ADD COLUMN chain_key TEXT NOT NULL DEFAULT ''");
    await db.execute("ALTER TABLE stores ADD COLUMN address TEXT NOT NULL DEFAULT ''");
    await db.execute('CREATE INDEX idx_stores_global ON stores(global_id)');
  }
}
