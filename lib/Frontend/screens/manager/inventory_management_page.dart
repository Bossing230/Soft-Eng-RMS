import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/inventory.dart';
import '../../repositories/inventory_repository.dart';

class InventoryManagementPage extends StatefulWidget {
  const InventoryManagementPage({super.key});

  @override
  State<InventoryManagementPage> createState() => _InventoryManagementPageState();
}

class _InventoryManagementPageState extends State<InventoryManagementPage> {
  final _repo = InventoryRepository();
  List<InventoryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.getAll();
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'low':
        return Colors.orange;
      case 'out':
        return Colors.red;
      default:
        return Colors.green;
    }
  }

  Future<void> _showAdjustDialog(InventoryItem item) async {
    final qtyCtrl = TextEditingController();
    String type = 'delivery';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Adjust: ${item.ingredientName}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: qtyCtrl, decoration: InputDecoration(labelText: 'Quantity (${item.unit})'), keyboardType: TextInputType.number),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'delivery', child: Text('Stock Delivery (+)')),
                DropdownMenuItem(value: 'usage', child: Text('Stock Usage (-)')),
              ],
              onChanged: (v) => setDialogState(() => type = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final qty = double.tryParse(qtyCtrl.text) ?? 0;
      if (qty > 0) {
        await _repo.adjustStock(item.inventoryId, qty, type);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: _statusColor(item.status).withOpacity(0.15), child: Icon(Icons.inventory, color: _statusColor(item.status))),
              title: Text(item.ingredientName),
              subtitle: Text('${item.quantity} ${item.unit} (min: ${item.minimumStock})'),
              trailing: TextButton(onPressed: () => _showAdjustDialog(item), child: const Text('Adjust')),
            ),
          );
        },
      ),
    );
  }
}