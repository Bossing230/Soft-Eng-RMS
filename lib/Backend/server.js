require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const http = require('http');
const { Server } = require('socket.io');

const { notificationSubject, SocketNotificationObserver } = require('./patterns/observers/NotificationSubject');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: '*' } });

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection (server stayed alive):', reason);
});

// Wire the Socket.IO broadcaster into the Observer chain so every
// notification event also pushes to connected Flutter clients live.
notificationSubject.subscribe(new SocketNotificationObserver(io));

io.on('connection', (socket) => {
  // Flutter clients join a room named after their role/employee right after login.
  socket.on('join', ({ role, employeeId }) => {
    if (role) socket.join(`role:${role}`);
    if (employeeId) socket.join(`employee:${employeeId}`);
  });
});

app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.get('/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

app.use('/api/auth', require('./routes/authRoutes'));
app.use('/api/employees', require('./routes/employeeRoutes'));
app.use('/api/menu', require('./routes/menuRoutes'));
app.use('/api/inventory', require('./routes/inventoryRoutes'));
app.use('/api/reservations', require('./routes/reservationRoutes'));
app.use('/api/orders', require('./routes/orderRoutes'));
app.use('/api/payments', require('./routes/paymentRoutes'));
app.use('/api/tables', require('./routes/tableRoutes'));
app.use('/api/notifications', require('./routes/notificationRoutes'));
app.use('/api/reports', require('./routes/reportRoutes'));
app.use('/uploads', express.static(require('path').join(__dirname, 'uploads')));

app.use((req, res) => res.status(404).json({ error: 'Route not found' }));

// Central error handler — never leak stack traces to the client.
app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

const PORT = process.env.PORT || 4000;
server.listen(PORT, () => console.log(`RMS backend running on port ${PORT}`));

module.exports = { app, server, io };