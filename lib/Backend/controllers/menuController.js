const MenuRepository = require('../repositories/MenuRepository');
const STATIONS = require('../constants/stations');
const { logAction } = require('../middleware/activityLogger');

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
    const { categoryId, foodName, description, price, image, station } = req.body;
    if (station && !STATIONS.includes(station)) {
      return res.status(400).json({ error: `station must be one of: ${STATIONS.join(', ')}` });
    }
    const item = await MenuRepository.create({ categoryId, foodName, description, price, image, station });
    await logAction(req.user.employeeId, `Added menu item "${foodName}"`, 'menu');
    res.status(201).json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  try {
    const item = await MenuRepository.update(req.params.id, req.body);
    await logAction(req.user.employeeId, `Updated menu item #${req.params.id}`, 'menu');
    res.json(item);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.remove = async (req, res) => {
  await MenuRepository.delete(req.params.id);
  await logAction(req.user.employeeId, `Deleted menu item #${req.params.id}`, 'menu');
  res.json({ message: 'Menu item deleted' });
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