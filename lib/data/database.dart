import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base de datos local (todo en el móvil en el MVP).
/// Todos los registros usan id de texto único para poder sincronizar después.
class AppDb {
  static Future<Database> open() async {
    final path = p.join(await getDatabasesPath(), 'compraclara.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stores (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            chain TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL
          )''');
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
      },
    );
  }
}
