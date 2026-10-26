const db = require('../patterns/singletons/DatabaseManager');
const ensureMenuStation = require('../database/ensure-menu-station');

// The only columns update() may touch. Column names are put into the SQL text,
// so they must never come straight from a request.
const UPDATABLE_COLUMNS = ['category_id', 'food_name', 'description', 'price', 'image', 'station'];

class MenuRepository {
  /** Makes sure menu_items.station exists, once per server run. */
  _ready() {
    if (!this._schema) {
      this._schema = ensureMenuStation().catch((err) => {
        this._schema = null; // try again on the next request
        throw err;
      });
    }
    return this._schema;
  }

  async findAll({ categoryId, availability, search } = {}) {
    await this._ready();
    let sql = `SELECT m.*, c.category_name FROM menu_items m
               JOIN menu_categories c ON m.category_id = c.category_id WHERE 1=1`;
    const params = [];
    if (categoryId) { sql += ' AND m.category_id = ?'; params.push(categoryId); }
    if (availability) { sql += ' AND m.availability = ?'; params.push(availability); }
    if (search) { sql += ' AND m.food_name LIKE ?'; params.push(`%${search}%`); }
    sql += ' ORDER BY c.category_name, m.food_name';
    return db.query(sql, params);
  }

  /**
   * Dishes with this name (ignoring case and spaces), in any category. The ones
   * in [categoryId] come first. Pass [excludeId] when editing, so a dish does
   * not match itself.
   */
  async findByName(name, { excludeId = null, categoryId = null } = {}) {
    await this._ready();
    return db.query(
      `SELECT m.menu_id, m.food_name, m.category_id, c.category_name
         FROM menu_items m
         JOIN menu_categories c ON m.category_id = c.category_id
        WHERE LOWER(TRIM(m.food_name)) = LOWER(TRIM(?)) AND m.menu_id <> ?
        ORDER BY (m.category_id = ?) DESC, m.menu_id
        LIMIT 10`,
      [name, excludeId ?? 0, categoryId ?? 0]
    );
  }

  async findById(id) {
    await this._ready();
    const rows = await db.query('SELECT * FROM menu_items WHERE menu_id = ?', [id]);
    return rows[0] || null;
  }

  async create(data) {
    await this._ready();
    const { categoryId, foodName, description, price, image, station } = data;
    const result = await db.query(
      `INSERT INTO menu_items (category_id, food_name, description, price, image, station) VALUES (?, ?, ?, ?, ?, ?)`,
      [categoryId, foodName, description, price, image || null, station || null]
    );
    return this.findById(result.insertId);
  }

  /** [fields] uses DB column names (food_name, category_id, ...). Unknown keys are ignored. */
  async update(id, fields) {
    await this._ready();
    const keys = Object.keys(fields).filter((k) => UPDATABLE_COLUMNS.includes(k));
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(
      `UPDATE menu_items SET ${setClause} WHERE menu_id = ?`,
      [...keys.map((k) => fields[k]), id]
    );
    return this.findById(id);
  }

  async delete(id) {
    await db.query('DELETE FROM menu_items WHERE menu_id = ?', [id]);
  }

  async setAvailability(id, availability) {
    await db.query('UPDATE menu_items SET availability = ? WHERE menu_id = ?', [availability, id]);
    return this.findById(id);
  }

  /** Which kitchen station this dish is cooked at — see ../constants/stations.js. */
  async setStation(id, station) {
    await this._ready();
    await db.query('UPDATE menu_items SET station = ? WHERE menu_id = ?', [station, id]);
    return this.findById(id);
  }

  // Categories
  async findAllCategories() {
    return db.query('SELECT * FROM menu_categories ORDER BY category_name');
  }

  async createCategory(categoryName) {
    const result = await db.query('INSERT INTO menu_categories (category_name) VALUES (?)', [categoryName]);
    return { category_id: result.insertId, category_name: categoryName };
  }

  async deleteCategory(id) {
    await db.query('DELETE FROM menu_categories WHERE category_id = ?', [id]);
  }
}

module.exports = new MenuRepository();