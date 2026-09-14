import 'package:rms/Frontend/models/notification.dart';
import 'package:flutter/material.dart';

class NotificationCard extends StatelessWidget {
  final NotificationItem notification;
  final VoidCallback? onTap;

  const NotificationCard({super.key, required this.notification, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: notification.isRead ? Colors.grey[300] : Theme.of(context).colorScheme.primary.withOpacity(0.15),
        child: Icon(Icons.notifications, color: notification.isRead ? Colors.grey : Theme.of(context).colorScheme.primary, size: 18),
      ),
      title: Text(notification.title, style: TextStyle(fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold)),
      subtitle: Text(notification.message),
    );
  }
}