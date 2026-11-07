const db = require('../patterns/singletons/DatabaseManager');
const ensureTables = require('../database/ensure-supplier-expense-tables');
const InventoryRepository = require('./InventoryRepository');

class SupplierRepository {
  _ready() {
    if (!this._schema) {
      this._schema = ensureTables().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  /** Every supplier, with how many active ingredients list them as their supplier. */
  async findAll() {
    await this._ready();
    await InventoryRepository._ready(); // makes sure inventory.is_archived exists
    return db.query(
      `SELECT s.*,
              (SELECT COUNT(*) FROM inventory i
                WHERE i.is_archived = 0
                  AND i.supplier_name IS NOT NULL
                  AND LOWER(i.supplier_name) = LOWER(s.name)) AS ingredient_count
         FROM suppliers s
        ORDER BY s.name`
    );
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query('SELECT * FROM suppliers WHERE supplier_id = ?', [id]);
    return rows[0] || null;
  }

  async findByName(name, excludeId = null) {
    await this._ready();
    const rows = await db.query(
      'SELECT supplier_id FROM suppliers WHERE LOWER(name) = LOWER(?) AND supplier_id <> ? LIMIT 1',
      [name, excludeId === null ? 0 : excludeId]
    );
    return rows[0] || null;
  }

  async create({ name, contactPerson, phone, email, address, notes }) {
    await this._ready();
    const result = await db.query(
      `INSERT INTO suppliers (name, contact_person, phone, email, address, notes) VALUES (?, ?, ?, ?, ?, ?)`,
      [name, contactPerson, phone, email, address, notes]
    );
    return this.findById(result.insertId);
  }

  async update(id, { name, contactPerson, phone, email, address, notes }) {
    await this._ready();
    await db.query(
      `UPDATE suppliers
          SET name = ?, contact_person = ?, phone = ?, email = ?, address = ?, notes = ?
        WHERE supplier_id = ?`,
      [name, contactPerson, phone, email, address, notes, id]
    );
    return this.findById(id);
  }

  async remove(id) {
    await this._ready();
    await db.query('DELETE FROM suppliers WHERE supplier_id = ?', [id]);
  }
}

module.exports = new SupplierRepository();