const TableRepository = require('../repositories/TableRepository');

exports.list = async (req, res) => res.json(await TableRepository.findAll());

exports.create = async (req, res) => {
  const { tableNumber, capacity } = req.body;
  res.status(201).json(await TableRepository.create({ tableNumber, capacity }));
};

exports.update = async (req, res) => res.json(await TableRepository.update(req.params.id, req.body));

exports.setStatus = async (req, res) => res.json(await TableRepository.setStatus(req.params.id, req.body.status));