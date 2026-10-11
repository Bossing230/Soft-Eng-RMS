const TableRepository = require('../repositories/TableRepository');

const VALID_STATUSES = ['available', 'occupied', 'reserved', 'cleaning'];
const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });

exports.list = async (req, res) => {
  try {
    res.json(await TableRepository.findAll({ status: req.query.status }));
  } catch (err) {
    fail(res, err);
  }
};

/** Feeds the Tables board: every table plus whoever is currently seated there. */
exports.board = async (req, res) => {
  try {
    res.json(await TableRepository.findBoard());
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const tableNumber = typeof req.body.tableNumber === 'string' ? req.body.tableNumber.trim() : '';
    const capacity = Number(req.body.capacity);
    const location = typeof req.body.location === 'string' && req.body.location.trim() ? req.body.location.trim() : 'indoor';

    if (!tableNumber) return res.status(400).json({ error: 'tableNumber is required' });
    if (!Number.isInteger(capacity) || capacity < 1) {
      return res.status(400).json({ error: 'capacity must be a whole number of 1 or more' });
    }

    res.status(201).json(await TableRepository.create({ tableNumber, capacity, location }));
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: `Table "${req.body.tableNumber}" already exists` });
    }
    fail(res, err);
  }
};

exports.update = async (req, res) => {
  try {
    const tableNumber = req.body.tableNumber === undefined ? undefined : String(req.body.tableNumber).trim();
    const capacity = req.body.capacity === undefined ? undefined : Number(req.body.capacity);
    const location = req.body.location === undefined ? undefined : String(req.body.location).trim();

    if (capacity !== undefined && (!Number.isInteger(capacity) || capacity < 1)) {
      return res.status(400).json({ error: 'capacity must be a whole number of 1 or more' });
    }

    const updated = await TableRepository.update(req.params.id, { tableNumber, capacity, location });
    if (!updated) return res.status(404).json({ error: 'Table not found' });
    res.json(updated);
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: `Table "${req.body.tableNumber}" already exists` });
    }
    fail(res, err);
  }
};

exports.setStatus = async (req, res) => {
  try {
    const { status } = req.body;
    if (!VALID_STATUSES.includes(status)) {
      return res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` });
    }
    const updated = await TableRepository.setStatus(req.params.id, status);
    if (!updated) return res.status(404).json({ error: 'Table not found' });
    res.json(updated);
  } catch (err) {
    fail(res, err);
  }
};