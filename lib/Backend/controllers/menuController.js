const MenuRepository = require('../repositories/MenuRepository');
const RecipeRepository = require('../repositories/RecipeRepository');
const STATIONS = require('../constants/stations');
const { logAction } = require('../middleware/activityLogger');

// App field name -> database column. Only these can be edited.
const EDITABLE_FIELDS = {
  categoryId: 'category_id',
  foodName: 'food_name',
  description: 'description',
  price: 'price',
  image: 'image',
  station: 'station',
};

exports.list = async (req, res) => {
  const { categoryId, availability, search } = req.query;
  const items = await MenuRepository.findAll({ categoryId, availability, search });
  res.json(items);
};

exports.getOne = async (req, res) => {
  const item = await MenuRepository.findById(req.params.id);
  if (!item) return res.status(404).json({ error: 'Menu item not found' });
  res.json(item);
};

exports.create = async (req, res) => {
  try {
    const { categoryId, foodName, description, price, image, station, ingredients } = req.body;
    if (station && !STATIONS.includes(station)) {
      return res.status(400).json({ error: `station must be one of: ${STATIONS.join(', ')}` });
    }

    // Check the recipe first so a bad ingredient list never leaves a half-made dish behind.
    const recipe = await RecipeRepository.normalize(ingredients);

    const item = await MenuRepository.create({ categoryId, foodName, description, price, image, station });
    if (recipe.length) {
      try {
        await RecipeRepository.replaceForMenu(item.menu_id, recipe);
      } catch (err) {
        await MenuRepository.delete(item.menu_id); // undo, so the dish and recipe go in together
        throw err;
      }
    }

    await logAction(req.user.employeeId, `Added menu item "${foodName}"`, 'menu');
    res.status(201).json(item);
  } catch (err) {
    res.status(err.status || 500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  try {
    const existing = await MenuRepository.findById(req.params.id);
    if (!existing) return res.status(404).json({ error: 'Menu item not found' });

    const body = req.body || {};

    if (body.station && !STATIONS.includes(body.station)) {
      return res.status(400).json({ error: `station must be one of: ${STATIONS.join(', ')}` });
    }

    // Translate app field names to columns, ignoring anything not on the list.
    const fields = {};
    for (const [key, column] of Object.entries(EDITABLE_FIELDS)) {
      if (body[key] !== undefined) fields[column] = body[key];
    }

    if (fields.food_name !== undefined && !String(fields.food_name).trim()) {
      return res.status(400).json({ error: 'Food name cannot be empty' });
    }
    if (fields.price !== undefined) {
      const price = Number(fields.price);
      if (Number.isNaN(price) || price < 0) {
        return res.status(400).json({ error: 'Price must be a number that is 0 or more' });
      }
      fields.price = price;
    }

    const item = await MenuRepository.update(req.params.id, fields);
    await logAction(req.user.employeeId, `Updated menu item "${item.food_name}" (#${req.params.id})`, 'menu');
    res.json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.remove = async (req, res) => {
  try {
    const item = await MenuRepository.findById(req.params.id);
    if (!item) return res.status(404).json({ error: 'Menu item not found' });

    await MenuRepository.delete(req.params.id);
    await logAction(req.user.employeeId, `Deleted menu item "${item.food_name}" (#${req.params.id})`, 'menu');
    res.json({ message: 'Menu item deleted' });
  } catch (err) {
    // MySQL "row is referenced by a foreign key": the dish is in past orders.
    if (err.code === 'ER_ROW_IS_REFERENCED_2' || err.errno === 1451) {
      return res.status(409).json({
        error: 'This dish is part of existing orders or records and cannot be deleted. Mark it as Sold out instead.',
      });
    }
    res.status(500).json({ error: err.message });
  }
};

exports.setAvailability = async (req, res) => {
  const { availability } = req.body; // 'available' | 'unavailable'
  const item = await MenuRepository.setAvailability(req.params.id, availability);
  res.json(item);
};

/** Which kitchen station this dish belongs to (Grill / Pasta / Salad / Desserts / Drinks). */
exports.setStation = async (req, res) => {
  try {
    const { station } = req.body;
    if (!STATIONS.includes(station)) {
      return res.status(400).json({ error: `station must be one of: ${STATIONS.join(', ')}` });
    }
    const item = await MenuRepository.setStation(req.params.id, station);
    if (!item) return res.status(404).json({ error: 'Menu item not found' });
    await logAction(req.user.employeeId, `Set menu item #${req.params.id} to ${station} station`, 'menu');
    res.json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.listCategories = async (req, res) => {
  res.json(await MenuRepository.findAllCategories());
};

exports.createCategory = async (req, res) => {
  const category = await MenuRepository.createCategory(req.body.categoryName);
  res.status(201).json(category);
};

exports.deleteCategory = async (req, res) => {
  await MenuRepository.deleteCategory(req.params.id);
  res.json({ message: 'Category deleted' });
};

exports.uploadImage = async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'No image file was uploaded' });
  }
  // With Cloudinary storage, req.file.path IS already the full,
  // permanent https URL — no need to build one ourselves anymore.
  res.status(201).json({ imageUrl: req.file.path });
};