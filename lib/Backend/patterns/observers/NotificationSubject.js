/**
 * Observer Pattern — a central subject that event sources (order
 * status changes, low-stock, new reservations, payments) publish to.
 * Registered observers (DB logger, Socket.IO broadcaster, FCM pusher)
 * react without the publisher needing to know who's listening.
 */

const db = require('../singletons/DatabaseManager');

class NotificationSubject {
  constructor() {
    this.observers = [];
  }

  subscribe(observer) {
    this.observers.push(observer);
  }

  async notify(event) {
    for (const observer of this.observers) {
      await observer.update(event);
    }
  }
}

/** Persists every notification event to the `notifications` table. */
class DatabaseNotificationObserver {
  async update(event) {
    await db.query(
      `INSERT INTO notifications (employee_id, role_id, title, message, notification_type)
       VALUES (?, ?, ?, ?, ?)`,
      [event.employeeId || null, event.roleId || null, event.title, event.message, event.type]
    );
  }
}

/** Broadcasts the event over Socket.IO to connected clients, if configured. */
class SocketNotificationObserver {
  constructor(io) {
    this.io = io;
  }

  async update(event) {
    if (!this.io) return;
    const room = event.roleId ? `role:${event.roleId}` : `employee:${event.employeeId}`;
    this.io.to(room).emit('notification', event);
  }
}

/** Sends a push notification via Firebase Cloud Messaging, if configured. */
class FcmNotificationObserver {
  constructor(fcmAdmin) {
    this.fcmAdmin = fcmAdmin;
  }

  async update(event) {
    if (!this.fcmAdmin || !event.fcmToken) return;
    try {
      await this.fcmAdmin.messaging().send({
        token: event.fcmToken,
        notification: { title: event.title, body: event.message },
        data: { type: event.type },
      });
    } catch (err) {
      console.error('FCM push failed:', err.message);
    }
  }
}

const notificationSubject = new NotificationSubject();
notificationSubject.subscribe(new DatabaseNotificationObserver());

module.exports = {
  notificationSubject,
  DatabaseNotificationObserver,
  SocketNotificationObserver,
  FcmNotificationObserver,
};