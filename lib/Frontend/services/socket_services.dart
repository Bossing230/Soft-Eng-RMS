import 'package:rms/Frontend/patterns/singleton/session_manager.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants/app_constants.dart';

/// Wraps the Socket.IO client connection used to receive live
/// notifications pushed by the backend's Observer pattern.
class SocketService {
  io.Socket? _socket;

  void connect(void Function(Map<String, dynamic>) onNotification) {
    final session = SessionManager();
    _socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );

    _socket!.onConnect((_) {
      _socket!.emit('join', {'role': session.role, 'employeeId': session.employeeId});
    });

    _socket!.on('notification', (data) {
      if (data is Map<String, dynamic>) onNotification(data);
    });

    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}