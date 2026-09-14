const db = require('../patterns/singletons/DatabaseManager');

class MenuRepository {
  async findAll({ categoryId, availability, search } = {}) {
    let sql = `SELECT m.*, c.category_name FROM menu_items m
               JOIN menu_categories c ON m.category_id = c.category_id WHERE 1=1`;
    const params = [];
    if (categoryId) { sql += ' AND m.category_id = ?'; params.push(categoryId); }
    if (availability) { sql += ' AND m.availability = ?'; params.push(availability); }
    if (search) { sql += ' AND m.food_name LIKE ?'; params.push(`%${search}%`); }
    sql += ' ORDER BY c.category_name, m.food_name';
    return db.query(sql, params);
  }

  async findById(id) {
    const rows = await db.query('SELECT * FROM menu_items WHERE menu_id = ?', [id]);
    return rows[0] || null;
  }

  async create(data) {
    const { categoryId, foodName, description, price, image } = data;
    const result = await db.query(
      `INSERT INTO menu_items (category_id, food_name, description, price, image) VALUES (?, ?, ?, ?, ?)`,
      [categoryId, foodName, description, price, image || null]
    );
    return this.findById(result.insertId);
  }

  async update(id, fields) {
    const keys = Object.keys(fields);
    if (!keys.length) return this.findById(id);
    const setClause = keys.map((k) => `${k} = ?`).join(', ');
    await db.query(`UPDATE menu_items SET ${setClause} WHERE menu_id = ?`, [...Object.values(fields), id]);
    return this.findById(id);
  }

  async delete(id) {
    await db.query('DELETE FROM menu_items WHERE menu_id = ?', [id]);
  }

  async setAvailability(id, availability) {
    await db.query('UPDATE menu_items SET availability = ? WHERE menu_id = ?', [availability, id]);
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