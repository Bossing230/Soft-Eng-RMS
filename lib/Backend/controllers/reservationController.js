const ReservationRepository = require('../repositories/ReservationRepository');
const { notificationSubject } = require('../patterns/observers/NotificationSubject');
const { logAction } = require('../middleware/activityLogger');

exports.list = async (req, res) => {
  const { date, status } = req.query;
  res.json(await ReservationRepository.findAll({ date, status }));
};

exports.getOne = async (req, res) => {
  const reservation = await ReservationRepository.findById(req.params.id);
  if (!reservation) return res.status(404).json({ error: 'Reservation not found' });
  res.json(reservation);
};

exports.availableTables = async (req, res) => {
  const { date, time, guestCount } = req.query;
  res.json(await ReservationRepository.findAvailableTables(date, time, Number(guestCount) || 1));
};

exports.create = async (req, res) => {
  try {
    const { tableId, customerName, contactNumber, date, time, guestCount } = req.body;

    // Double-booking guard, enforced here in addition to the DB unique constraint.
    const taken = await ReservationRepository.isTableTaken(tableId, date, time);
    if (taken) {
      return res.status(409).json({ error: 'This table is already reserved for that date and time' });
    }

    const reservation = await ReservationRepository.create({
      tableId, customerName, contactNumber, date, time, guestCount, createdBy: req.user.employeeId,
    });

    await logAction(req.user.employeeId, `Created reservation for ${customerName}`, 'reservations');
    await notificationSubject.notify({
      title: 'New Reservation',
      message: `${customerName} reserved table for ${guestCount} on ${date} ${time}.`,
      type: 'new_reservation',
    });

    res.status(201).json(reservation);
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'This table is already reserved for that date and time' });
    }
    res.status(500).json({ error: err.message });
  }
};

exports.update = async (req, res) => {
  try {
    const { tableId, date, time } = req.body;
    if (tableId && date && time) {
      const taken = await ReservationRepository.isTableTaken(tableId, date, time, req.params.id);
      if (taken) return res.status(409).json({ error: 'This table is already reserved for that date and time' });
    }
    const updated = await ReservationRepository.update(req.params.id, {
      table_id: tableId, reservation_date: date, reservation_time: time,
      customer_name: req.body.customerName, contact_number: req.body.contactNumber, guest_count: req.body.guestCount,
    });
    await logAction(req.user.employeeId, `Updated reservation #${req.params.id}`, 'reservations');
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.setStatus = async (req, res) => {
  try {
    const { status } = req.body;
    const valid = ['pending', 'confirmed', 'seated', 'completed', 'cancelled', 'no_show'];
    if (!valid.includes(status)) return res.status(400).json({ error: `status must be one of ${valid.join(', ')}` });

    const updated = await ReservationRepository.setStatus(req.params.id, status);
    await logAction(req.user.employeeId, `Set reservation #${req.params.id} to ${status}`, 'reservations');
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};