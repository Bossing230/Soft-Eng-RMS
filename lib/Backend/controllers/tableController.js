const TableRepository = require('../repositories/TableRepository');

exports.list = async (req, res) => {
  try {
    res.json(await TableRepository.findAll({ status: req.query.status }));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.create = async (req, res) => {
  try {
    const { tableNumber, capacity } = req.body;
    if (!tableNumber) return res.status(400).json({ error: 'tableNumber is required' });
    res.status(201).json(await TableRepository.create({ tableNumber, capacity }));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  try {
    res.json(await TableRepository.update(req.params.id, req.body));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.setStatus = async (req, res) => {
  try {
    const { status } = req.body;
    if (!['available', 'occupied', 'reserved'].includes(status)) {
      return res.status(400).json({ error: "status must be 'available', 'occupied' or 'reserved'" });
    }
    res.json(await TableRepository.setStatus(req.params.id, status));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};