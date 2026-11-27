const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

// Asegurar directorio ./data
const dataDir = path.resolve(__dirname, '..', 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, 'links.db');
const db = new Database(dbPath);

// Configuración de rendimiento y concurrencia segura
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

// Crear tabla links e indice unico si no existen
db.exec(`
  CREATE TABLE IF NOT EXISTS links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    alias TEXT NOT NULL UNIQUE,
    destino TEXT NOT NULL,
    clics INTEGER NOT NULL DEFAULT 0,
    creado_en TEXT NOT NULL DEFAULT (datetime('now')),
    ultimo_acceso TEXT
  );

  CREATE UNIQUE INDEX IF NOT EXISTS idx_links_alias ON links(alias);
`);

// Sentencias preparadas para maximo rendimiento
const stmtFindByAlias = db.prepare('SELECT * FROM links WHERE alias = ?');
const stmtFindById = db.prepare('SELECT * FROM links WHERE id = ?');
const stmtInsertLink = db.prepare(`
  INSERT INTO links (alias, destino, clics, creado_en)
  VALUES (?, ?, 0, datetime('now'))
`);
const stmtRecordClick = db.prepare(`
  UPDATE links
  SET clics = clics + 1, ultimo_acceso = datetime('now')
  WHERE alias = ?
`);
const stmtListAll = db.prepare(`
  SELECT id, alias, destino, clics, creado_en, ultimo_acceso
  FROM links
  ORDER BY id DESC
`);
const stmtDeleteById = db.prepare('DELETE FROM links WHERE id = ?');

module.exports = {
  db,
  findByAlias: (alias) => stmtFindByAlias.get(alias),
  findById: (id) => stmtFindById.get(id),
  insertLink: (alias, destino) => {
    const info = stmtInsertLink.run(alias, destino);
    return info.lastInsertRowid;
  },
  recordClick: (alias) => stmtRecordClick.run(alias),
  listAll: () => stmtListAll.all(),
  deleteById: (id) => {
    const info = stmtDeleteById.run(id);
    return info.changes > 0;
  }
};
