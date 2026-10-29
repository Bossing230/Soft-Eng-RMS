import 'dart:math';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';

// Edit these to match your restaurant.
const _restaurantName = 'Restaurant Management System';
const _tagline = 'Good food. Good times.';
const _addressLine1 = 'Upper Maloro,';
const _addressLine2 = 'Tangub City, Misamis Occidental, Philippines';

// Paste your Google Form link here. Leave it empty to hide the QR code.
const _feedbackUrl = 'https://docs.google.com/forms/d/e/1FAIpQLSdOUkjV0gaSTJEf1QilAEmCcA1xkhjvdOwih-HWClssxQ8rpQ/viewform?usp=dialog';

const _ink = Color(0xFF111111);
const _muted = Color(0xFF6B6B6B);
const _paper = Color(0xFFFAFAF8);
const _mono = TextStyle(fontFamily: 'Courier New', fontFamilyFallback: ['monospace', 'NotoSans'], color: _ink);

final _money = NumberFormat('#,##0.00');
String _peso(num v) => '₱${_money.format(v)}';

class ReceiptData {
  final int orderId;
  final DateTime date;
  final String orderType; // dine_in | takeout | delivery
  final String? tableNumber;
  final String cashier;
  final String paymentMethod; // cash | card | ewallet
  final bool paid;
  final List<OrderItem> items;
  final double subtotal;
  final double discount;
  final double taxAndService;
  final double total;
  final double? cashReceived;
  final double? change;

  const ReceiptData({
    required this.orderId,
    required this.date,
    required this.orderType,
    required this.tableNumber,
    required this.cashier,
    required this.paymentMethod,
    required this.paid,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.taxAndService,
    required this.total,
    this.cashReceived,
    this.change,
  });
}

Future<void> showReceiptDialog(BuildContext context, ReceiptData data) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: ClipPath(clipper: _ZigZagClipper(), child: _Paper(data: data)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB98A5E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ZigZagClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const h = 6.0, w = 12.0;
    final path = Path()..moveTo(0, h);
    for (double x = 0; x < size.width; x += w) {
      path.lineTo(x + w / 2, 0);
      path.lineTo(min(x + w, size.width), h);
    }
    path.lineTo(size.width, size.height - h);
    for (double x = size.width; x > 0; x -= w) {
      path.lineTo(x - w / 2, size.height);
      path.lineTo(max(x - w, 0), size.height - h);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _Paper extends StatelessWidget {
  final ReceiptData data;
  const _Paper({required this.data});

  static const _methods = {'cash': 'Cash', 'card': 'Card', 'ewallet': 'E-wallet', 'online': 'Online', 'unpaid': 'Unpaid'};
  static const _types = {'dine_in': 'Dine-in', 'takeout': 'Takeout', 'delivery': 'Delivery'};

  Widget _row(String label, String value, {bool bold = false, double size = 13}) {
    final style = _mono.copyWith(fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: style)),
        ],
      ),
    );
  }

  Widget _solid() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Divider(height: 1, thickness: 1, color: _ink),
      );

  Widget _dashed() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text('- ' * 60, maxLines: 1, overflow: TextOverflow.clip, style: _mono.copyWith(fontSize: 12, color: _muted)),
      );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final isDineIn = d.orderType == 'dine_in';
    final table = (d.tableNumber ?? '').trim();
    final method = _methods[d.paymentMethod] ?? d.paymentMethod;

    return Container(
      color: _paper,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_restaurantName,
              textAlign: TextAlign.center,
              style: _mono.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(_tagline, textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 12, color: _muted)),
          const SizedBox(height: 10),
          Text(_addressLine1, textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 12)),
          Text(_addressLine2, textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 12)),
          _solid(),
          _row('Order No:', '#${d.orderId.toString().padLeft(4, '0')}'),
          _row('Date & Time:', DateFormat('MMM d, y  h:mm a').format(d.date)),
          _row('Order Type:', _types[d.orderType] ?? d.orderType),
          if (isDineIn && table.isNotEmpty) _row('Table:', table),
          _row('Payment:', d.paid ? method : '$method (pending)'),
          _row('Cashier:', d.cashier),
          _solid(),
          Row(
            children: [
              Expanded(child: Text('Item', style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
              SizedBox(width: 40, child: Text('Qty', textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
              SizedBox(width: 90, child: Text('Price', textAlign: TextAlign.right, style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1, color: _ink),
          const SizedBox(height: 8),
          for (final i in d.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(i.foodName, style: _mono.copyWith(fontSize: 13))),
                  SizedBox(width: 40, child: Text('${i.quantity}', textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 13))),
                  SizedBox(width: 90, child: Text(_peso(i.subtotal), textAlign: TextAlign.right, style: _mono.copyWith(fontSize: 13))),
                ],
              ),
            ),
          _solid(),
          _row('Subtotal', _peso(d.subtotal)),
          if (d.discount > 0) _row('Discount', '-${_peso(d.discount)}'),
          _row('Tax & service', _peso(d.taxAndService)),
          _solid(),
          _row('Total', _peso(d.total), bold: true, size: 18),
          if (d.paymentMethod == 'cash' && d.paid && d.cashReceived != null) ...[
            const SizedBox(height: 6),
            _row('Cash received', _peso(d.cashReceived!)),
            _row('Change', _peso(d.change ?? 0)),
          ],
          if (!d.paid) ...[
            const SizedBox(height: 8),
            Text('PAYMENT PENDING', textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          _solid(),
          const SizedBox(height: 4),
          Text('Thank you for dining with us!',
              textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
           Text('We hope you enjoyed your meal.', textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 12)),
          if (_feedbackUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: QrImageView(
                data: _feedbackUrl,
                version: QrVersions.auto,
                size: 110,
                padding: EdgeInsets.zero,
                backgroundColor: _paper,
              ),
            ),
            const SizedBox(height: 8),
            Text('Scan to rate your visit',
                textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 12)),
          ],
          _dashed(),
          Text('Please come again', textAlign: TextAlign.center, style: _mono.copyWith(fontSize: 11, color: _muted)),
        ],
      ),
    );
  }
}