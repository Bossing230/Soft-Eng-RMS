import 'package:flutter/material.dart';
import 'package:rms/Frontend/services/api_services.dart';
import '../../models/order.dart';

/// Payment/checkout screen shown right after an order is created.
/// Backs onto the Strategy-pattern payment endpoint (`POST /payments`),
/// which accepts method = cash | card | ewallet.
class CheckoutPage extends StatefulWidget {
  final RmsOrder order;
  const CheckoutPage({super.key, required this.order});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _api = ApiService();
  final _cashReceivedCtrl = TextEditingController();
  String _method = 'cash';
  bool _processing = false;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _pay() async {
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{'orderId': widget.order.orderId, 'method': _method};
      if (_method == 'cash') {
        body['cashReceived'] = double.tryParse(_cashReceivedCtrl.text) ?? 0;
      }
      if (_method == 'card') {
        body['cardToken'] = 'demo-card-token'; // Replace with real terminal SDK integration.
      }
      final data = await _api.post('/payments', body: body);
      setState(() => _result = Map<String, dynamic>.from(data));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    if (_result != null) {
      final payment = _result!['payment'];
      final checkoutUrl = _result!['checkoutUrl'];
      return Scaffold(
        appBar: AppBar(title: const Text('Payment Result')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  payment['payment_status'] == 'paid' ? Icons.check_circle : Icons.hourglass_top,
                  size: 72,
                  color: payment['payment_status'] == 'paid' ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 16),
                Text(
                  payment['payment_status'] == 'paid' ? 'Payment Successful' : 'Awaiting Payment Confirmation',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (payment['change'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Change due: ₱${payment['change']}'),
                ],
                if (checkoutUrl != null) ...[
                  const SizedBox(height: 8),
                  Text('Customer should complete payment at:\n$checkoutUrl', textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Checkout — Order #${order.orderId}')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total Due', style: TextStyle(fontSize: 16)),
              Text('₱${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 24),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments)),
                ButtonSegment(value: 'card', label: Text('Card'), icon: Icon(Icons.credit_card)),
                ButtonSegment(value: 'ewallet', label: Text('E-Wallet'), icon: Icon(Icons.qr_code)),
              ],
              selected: {_method},
              onSelectionChanged: (s) => setState(() => _method = s.first),
            ),
            const SizedBox(height: 20),
            if (_method == 'cash')
              TextField(
                controller: _cashReceivedCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cash received'),
              ),
            if (_method == 'ewallet')
              const Text('Customer will be redirected to a GCash/Maya checkout link via PayMongo.', style: TextStyle(color: Colors.grey)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _processing ? null : _pay,
              child: _processing ? const CircularProgressIndicator(color: Colors.white) : const Text('Confirm Payment'),
            ),
          ],
        ),
      ),
    );
  }
}