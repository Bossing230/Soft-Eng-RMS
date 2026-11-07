const SupplierRepository = require('../repositories/SupplierRepository');
const { logAction } = require('../middleware/activityLogger');

const PHONE_RE = /^[0-9+()\-\s]*$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const fail = (res, err) => res.status(err.status || 500).json({ error: err.message });
const bad = (res, message) => res.status(400).json({ error: message });

function read(body) {
  return {
    name: text(body.name, 100),
    contactPerson: text(body.contactPerson, 100) || null,
    phone: text(body.phone, 30) || null,
    email: text(body.email, 100) || null,
    address: text(body.address, 255) || null,
    notes: text(body.notes, 500) || null,
  };
}

function validate(d) {
  if (!d.name) return 'Supplier name is required';
  if (d.phone && !PHONE_RE.test(d.phone)) return 'Phone can only have digits, spaces and + ( ) -';
  if (d.email && !EMAIL_RE.test(d.email)) return 'Enter a valid email address';
  return null;
}

exports.list = async (req, res) => {
  try {
    res.json(await SupplierRepository.findAll());
  } catch (err) {
    fail(res, err);
  }
};

exports.create = async (req, res) => {
  try {
    const data = read(req.body);
    const error = validate(data);
    if (error) return bad(res, error);
    if (await SupplierRepository.findByName(data.name)) {
      return res.status(409).json({ error: `"${data.name}" is already in the supplier list` });
    }
    const supplier = await SupplierRepository.create(data);
    await logAction(req.user.employeeId, `Added supplier "${data.name}"`, 'suppliers');
    res.status(201).json(supplier);
  } catch (err) {
    fail(res, err);
  }
};

exports.update = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const data = read(req.body);
    const error = validate(data);
    if (error) return bad(res, error);
    if (!(await SupplierRepository.findById(id))) return res.status(404).json({ error: 'Supplier not found' });
    if (await SupplierRepository.findByName(data.name, id)) {
      return res.status(409).json({ error: `"${data.name}" is already in the supplier list` });
    }
    const supplier = await SupplierRepository.update(id, data);
    await logAction(req.user.employeeId, `Edited supplier "${data.name}"`, 'suppliers');
    res.json(supplier);
  } catch (err) {
    fail(res, err);
  }
};

exports.remove = async (req, res) => {
  try {
    const id = Number(req.params.id);
    const existing = await SupplierRepository.findById(id);
    if (!existing) return res.status(404).json({ error: 'Supplier not found' });
    await SupplierRepository.remove(id);
    await logAction(req.user.employeeId, `Deleted supplier "${existing.name}"`, 'suppliers');
    res.json({ deleted: true });
  } catch (err) {
    fail(res, err);
  }
};