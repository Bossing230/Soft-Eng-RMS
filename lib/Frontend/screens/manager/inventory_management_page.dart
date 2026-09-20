import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/inventory.dart';

import '../../repositories/inventory_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the inventory design.
// ---------------------------------------------------------------------------
class _Ui {
  static const border = Color(0xFFEBE3D8);
  static const tan = Color(0xFFD4A574);
  static const tanDeep = Color(0xFFB98A5E);
  static const tanTint = Color(0xFFF0DFCF);
  static const searchFill = Color(0xFFF1EBE4);
  static const fieldFill = Color(0xFFFBF5F0);
  static const dialogBg = Color(0xFFF6E7DB);
  static const track = Color(0xFFE9E3DC);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const green = Color(0xFF4CAF50);
  static const amber = Color(0xFFFFC107);
  static const red = Color(0xFFF44336);
  static const redText = Color(0xFFE53935);
  static const amberText = Color(0xFFB07A00);
  static const greenText = Color(0xFF2E7D32);
}

/// Standard choices, so "kg", "Kg" and "kgs" don't become three different units.
const _units = ['kg', 'g', 'L', 'ml', 'pcs', 'pack', 'can', 'bottle', 'sack', 'box'];
const _categories = [
  'Meat',
  'Seafood',
  'Vegetables',
  'Fruits',
  'Dairy & eggs',
  'Grains',
  'Dry goods',
  'Condiments & sauces',
  'Beverages',
  'Other',
];

final _qtyFormat = NumberFormat('#,##0.0#');
final _wholeFormat = NumberFormat('#,##0.##');

String _fmtQty(double v) => _qtyFormat.format(v);
String _fmtWhole(double v) => _wholeFormat.format(v);
double _round2(double v) => (v * 100).roundToDouble() / 100;
String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Red when low or out, amber up to 60%, green above.
Color _barColor(InventoryItem i) => i.needsRestock ? _Ui.red : (i.fraction <= 0.6 ? _Ui.amber : _Ui.green);
Color _percentColor(InventoryItem i) =>
    i.needsRestock ? _Ui.redText : (i.fraction <= 0.6 ? _Ui.amberText : _Ui.greenText);

String _formatTime(String raw) {
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  return parsed == null ? raw : DateFormat('MMM d, h:mm a').format(parsed);
}

InputDecoration _fieldDecoration({String? hint, IconData? icon, String? error}) {
  return InputDecoration(
    hintText: hint,
    errorText: error,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _Ui.muted),
    filled: true,
    fillColor: _Ui.fieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class InventoryManagementPage extends StatefulWidget {
  const InventoryManagementPage({super.key});

  @override
  State<InventoryManagementPage> createState() => _InventoryManagementPageState();
}

class _InventoryManagementPageState extends State<InventoryManagementPage> {
  final _repo = InventoryRepository();
  final _searchController = TextEditingController();

  List<InventoryItem> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all'; // 'all' | 'low' | 'out'
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.getAll();
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_items.isEmpty) _error = e.toString();
      });
      if (_items.isNotEmpty) _snack('Could not refresh: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Out of stock first, then low, then the rest; A to Z inside each group.
  List<InventoryItem> get _visible {
    final q = _query.trim().toLowerCase();
    final list = _items.where((i) {
      if (_filter == 'low' && !i.isLow) return false;
      if (_filter == 'out' && !i.isOut) return false;
      if (q.isEmpty) return true;
      return i.ingredientName.toLowerCase().contains(q) || i.category.toLowerCase().contains(q);
    }).toList();

    int rank(InventoryItem i) => i.isOut ? 0 : (i.isLow ? 1 : 2);
    list.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.ingredientName.toLowerCase().compareTo(b.ingredientName.toLowerCase());
    });
    return list;
  }

  // ---- actions ----

  Future<void> _openAddItem() async {
    final created = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => _ItemFormDialog(repo: _repo),
    );
    if (created == null) return;
    _load(showSpinner: false);
    _snack('Added ${created.ingredientName}');
  }

  Future<void> _openDetail(InventoryItem item) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ItemDetailDialog(item: item, repo: _repo, onChanged: () => _load(showSpinner: false)),
    );
  }

  Future<void> _quickDelivery(InventoryItem item) async {
    final qty = await _promptQuantity(
      context,
      title: 'Add delivery: ${item.ingredientName}',
      unit: item.unit,
      helper: 'Now ${_fmtQty(item.quantity)} of ${_fmtWhole(item.capacity)} ${item.unit}',
      confirmLabel: 'Add delivery',
    );
    if (qty == null) return;
    try {
      await _repo.adjustStock(item.inventoryId, qty, 'delivery');
      _load(showSpinner: false);
      _snack('Added ${_fmtQty(qty)} ${item.unit} to ${item.ingredientName}');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _restockAllLow() async {
    final low = _items.where((i) => i.needsRestock).toList();
    // Each low item gets enough to reach its max stock.
    final plan = <int, double>{};
    for (final i in low) {
      final add = _round2(i.capacity - i.quantity);
      if (add > 0) plan[i.inventoryId] = add;
    }
    if (plan.isEmpty) {
      _snack(low.isEmpty ? 'Nothing needs restocking.' : 'Set a max stock on the low items first.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _Ui.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Restock all low items'),
        content: SizedBox(
          width: 420,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'This records a delivery for each item below, bringing it up to its max stock. '
                    'Only confirm once the stock has actually arrived.',
                    style: TextStyle(fontSize: 13, color: _Ui.muted),
                  ),
                  const SizedBox(height: 12),
                  for (final i in low)
                    if (plan.containsKey(i.inventoryId))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(child: Text(i.ingredientName, style: const TextStyle(fontSize: 14, color: _Ui.ink))),
                            Text(
                              '+${_fmtQty(plan[i.inventoryId]!)} ${i.unit}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.greenText),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _Ui.tanDeep, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Record ${plan.length} ${plan.length == 1 ? 'delivery' : 'deliveries'}'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repo.restock(plan);
      await _load(showSpinner: false);
      _snack('Restocked ${plan.length} ${plan.length == 1 ? 'item' : 'items'}');
    } catch (e) {
      _snack('$e');
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final visible = _visible;
    final lowCount = _items.where((i) => i.isLow).length;
    final outCount = _items.where((i) => i.isOut).length;
    final needCount = lowCount + outCount;

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 20 : 16, wide ? 24 : 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Controls(
                      controller: _searchController,
                      onSearch: (v) => setState(() => _query = v),
                      onRestock: _restockAllLow,
                      onAdd: _openAddItem,
                    ),
                    const SizedBox(height: 12),
                    _FilterPills(
                      selected: _filter,
                      counts: {'all': _items.length, 'low': lowCount, 'out': outCount},
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                    if (needCount > 0) ...[
                      const SizedBox(height: 12),
                      _LowBanner(count: needCount),
                    ],
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      _EmptyState(hasItems: _items.isNotEmpty)
                    else
                      for (final item in visible)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _InventoryCard(
                            item: item,
                            onTap: () => _openDetail(item),
                            onAddDelivery: () => _quickDelivery(item),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top controls, filters, banner
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final VoidCallback onRestock;
  final VoidCallback onAdd;
  const _Controls({required this.controller, required this.onSearch, required this.onRestock, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      controller: controller,
      onChanged: onSearch,
      decoration: InputDecoration(
        hintText: 'Search inventory...',
        prefixIcon: const Icon(Icons.search, size: 20, color: _Ui.muted),
        filled: true,
        fillColor: _Ui.searchFill,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.tan)),
      ),
    );

    final restock = OutlinedButton.icon(
      onPressed: onRestock,
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Restock all low'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _Ui.tanDeep,
        side: const BorderSide(color: _Ui.tan),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );

    final add = ElevatedButton.icon(
      onPressed: onAdd,
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Add item'),
      style: ElevatedButton.styleFrom(
        backgroundColor: _Ui.tanDeep,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 12),
              restock,
              const SizedBox(width: 12),
              add,
            ],
          );
        }
        return Column(
          children: [
            search,
            const SizedBox(height: 10),
            Row(children: [Expanded(child: restock), const SizedBox(width: 10), Expanded(child: add)]),
          ],
        );
      },
    );
  }
}

class _FilterPills extends StatelessWidget {
  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onChanged;
  const _FilterPills({required this.selected, required this.counts, required this.onChanged});

  static const _labels = {'all': 'All', 'low': 'Low stock', 'out': 'Out of stock'};

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _labels.entries.map((e) {
        final isSelected = e.key == selected;
        return Material(
          color: isSelected ? _Ui.tanDeep : _Ui.searchFill,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onChanged(e.key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${e.value} (${counts[e.key] ?? 0})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : _Ui.muted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _LowBanner extends StatelessWidget {
  final int count;
  const _LowBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: _Ui.redText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1 ? '1 item below 30% stock level' : '$count items below 30% stock level',
              style: const TextStyle(fontSize: 13, color: _Ui.redText),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasItems;
  const _EmptyState({required this.hasItems});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          hasItems ? 'No items match your search or filter.' : 'No inventory items yet. Tap "Add item" to start.',
          style: const TextStyle(color: _Ui.muted),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: _Ui.muted),
            const SizedBox(height: 12),
            const Text("Couldn't load the inventory", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _Ui.muted)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item card
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (status) {
      case 'out':
        bg = const Color(0xFFFFCDD2);
        fg = const Color(0xFFC62828);
        label = 'Out of stock';
        break;
      case 'low':
        bg = const Color(0xFFFFEBEE);
        fg = _Ui.redText;
        label = 'Low stock';
        break;
      default:
        bg = const Color(0xFFE8F5E9);
        fg = _Ui.greenText;
        label = 'In stock';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onAddDelivery;
  const _InventoryCard({required this.item, required this.onTap, required this.onAddDelivery});

  @override
  Widget build(BuildContext context) {
    final needs = item.needsRestock;
    final barColor = _barColor(item);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final badge = _StatusBadge(status: item.status);
              final amount = Text(
                '${_fmtQty(item.quantity)} / ${_fmtWhole(item.capacity)} ${item.unit}',
                style: const TextStyle(fontSize: 13, color: _Ui.muted),
              );
              final Widget? plus = needs
                  ? IconButton(
                      tooltip: 'Add delivery',
                      onPressed: onAddDelivery,
                      icon: const Icon(Icons.add_circle_outline, color: _Ui.green),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: needs ? const Color(0xFFFFEBEE) : _Ui.tanTint,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.inventory_2_outlined, size: 22, color: needs ? _Ui.redText : _Ui.tanDeep),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.ingredientName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _Ui.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.category.isEmpty ? 'Uncategorized' : item.category,
                              style: const TextStyle(fontSize: 13, color: _Ui.muted),
                            ),
                          ],
                        ),
                      ),
                      if (!narrow) ...[
                        badge,
                        const SizedBox(width: 12),
                        amount,
                        if (plus != null) ...[const SizedBox(width: 8), plus],
                      ],
                    ],
                  ),
                  if (narrow) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [badge, amount, if (plus != null) plus],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text('${item.percent}% remaining', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
                      const Spacer(),
                      Text(
                        '${item.percent}%',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _percentColor(item)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: item.fraction,
                      minHeight: 6,
                      color: barColor,
                      backgroundColor: _Ui.track,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quantity prompt (used for deliveries, usage and count corrections)
// ---------------------------------------------------------------------------

Future<double?> _promptQuantity(
  BuildContext context, {
  required String title,
  required String unit,
  String? helper,
  String confirmLabel = 'Save',
  bool allowZero = false,
  double? max,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _QuantityDialog(
      title: title,
      unit: unit,
      helper: helper,
      confirmLabel: confirmLabel,
      allowZero: allowZero,
      max: max,
    ),
  );
}

class _QuantityDialog extends StatefulWidget {
  final String title;
  final String unit;
  final String? helper;
  final String confirmLabel;
  final bool allowZero;
  final double? max;
  const _QuantityDialog({
    required this.title,
    required this.unit,
    required this.helper,
    required this.confirmLabel,
    required this.allowZero,
    required this.max,
  });

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < 0 || (!widget.allowZero && value == 0)) {
      setState(() => _error = widget.allowZero ? 'Enter a number, zero or more' : 'Enter a number greater than zero');
      return;
    }
    if (widget.max != null && value > widget.max!) {
      setState(() => _error = 'Only ${_fmtQty(widget.max!)} ${widget.unit} in stock');
      return;
    }
    Navigator.of(context).pop(_round2(value));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _Ui.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title, style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.helper != null) ...[
              Text(widget.helper!, style: const TextStyle(fontSize: 13, color: _Ui.muted)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _submit(),
              decoration: _fieldDecoration(hint: 'Quantity (${widget.unit})', error: _error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _Ui.tanDeep, foregroundColor: Colors.white),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit item form
// ---------------------------------------------------------------------------

class _ItemFormDialog extends StatefulWidget {
  final InventoryRepository repo;
  final InventoryItem? existing;
  const _ItemFormDialog({required this.repo, this.existing});

  @override
  State<_ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<_ItemFormDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.ingredientName ?? '');
  late final TextEditingController _current = TextEditingController();
  late final TextEditingController _max = TextEditingController(
    text: (widget.existing != null && widget.existing!.maxStock > 0) ? _plain(widget.existing!.maxStock) : '',
  );
  String? _unit;
  String? _category;

  String? _nameError;
  String? _currentError;
  String? _maxError;
  String? _unitError;
  String? _categoryError;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _unit = widget.existing?.unit;
    final category = widget.existing?.category ?? '';
    _category = category.isEmpty ? null : category;
  }

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final max = double.tryParse(_max.text.trim());
    final current = _editing ? null : double.tryParse(_current.text.trim());

    String? nameError;
    String? currentError;
    String? maxError;
    String? unitError;
    String? categoryError;

    if (name.isEmpty) nameError = 'Enter the item name';
    if (max == null || max <= 0) maxError = 'Enter a max stock above zero';
    if (!_editing && (current == null || current < 0)) currentError = 'Enter the current stock';
    if (max != null && max > 0) {
      if (!_editing && current != null && current > max) currentError = "Can't be more than max stock";
      if (_editing && max < widget.existing!.quantity) {
        maxError = "Can't be less than the current stock (${_fmtQty(widget.existing!.quantity)})";
      }
    }
    if (_unit == null) unitError = 'Choose a unit';
    if (!_editing && _category == null) categoryError = 'Choose a category';

    setState(() {
      _nameError = nameError;
      _currentError = currentError;
      _maxError = maxError;
      _unitError = unitError;
      _categoryError = categoryError;
      _error = null;
    });
    if ([nameError, currentError, maxError, unitError, categoryError].any((e) => e != null)) return;

    setState(() => _saving = true);
    try {
      final InventoryItem saved;
      if (_editing) {
        saved = await widget.repo.update(
          widget.existing!.inventoryId,
          ingredientName: name,
          unit: _unit!,
          maxStock: max!,
          category: _category ?? '',
        );
      } else {
        saved = await widget.repo.create(
          ingredientName: name,
          quantity: current!,
          unit: _unit!,
          maxStock: max,
          category: _category ?? '',
        );
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  Widget _textField(TextEditingController controller, String hint, {IconData? icon, String? error, bool number = false}) {
    return TextField(
      controller: controller,
      enabled: !_saving,
      keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: _fieldDecoration(hint: hint, icon: icon, error: error),
    );
  }

  Widget _dropdown({
    required String hint,
    required String? value,
    required List<String> options,
    required String? error,
    required ValueChanged<String?> onChanged,
  }) {
    // Keep a value that is no longer in the standard list (an older item) selectable.
    final all = [...options, if (value != null && !options.contains(value)) value];
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      hint: Text(hint, style: const TextStyle(color: _Ui.muted)),
      decoration: _fieldDecoration(error: error),
      items: all.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: _saving ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      if (!_editing) _textField(_current, 'Current stock', error: _currentError, number: true),
      _textField(_max, 'Max stock', error: _maxError, number: true),
      _dropdown(
        hint: 'Unit',
        value: _unit,
        options: _units,
        error: _unitError,
        onChanged: (v) => setState(() {
          _unit = v;
          _unitError = null;
        }),
      ),
      _dropdown(
        hint: 'Category',
        value: _category,
        options: _categories,
        error: _categoryError,
        onChanged: (v) => setState(() {
          _category = v;
          _categoryError = null;
        }),
      ),
    ];

    return Dialog(
      backgroundColor: _Ui.dialogBg,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? 'Edit inventory item' : 'Add inventory item',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: _Ui.ink),
              ),
              const SizedBox(height: 16),
              _textField(_name, 'Item name', icon: Icons.inventory_2_outlined, error: _nameError),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 480) {
                    return Column(
                      children: [
                        for (var i = 0; i < fields.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          fields[i],
                        ],
                      ],
                    );
                  }
                  final width = (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: fields.map((f) => SizedBox(width: width, child: f)).toList(),
                  );
                },
              ),
              const SizedBox(height: 10),
              Text(
                'Items count as low stock at 30% of max stock or less.',
                style: const TextStyle(fontSize: 12, color: _Ui.muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 13, color: _Ui.redText)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _Ui.tanDeep,
                        side: const BorderSide(color: _Ui.tan),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _Ui.tanDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_editing ? 'Save changes' : 'Add item'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Item detail: actions and stock history
// ---------------------------------------------------------------------------

class _ItemDetailDialog extends StatefulWidget {
  final InventoryItem item;
  final InventoryRepository repo;
  final VoidCallback onChanged;
  const _ItemDetailDialog({required this.item, required this.repo, required this.onChanged});

  @override
  State<_ItemDetailDialog> createState() => _ItemDetailDialogState();
}

class _ItemDetailDialogState extends State<_ItemDetailDialog> {
  late InventoryItem _item = widget.item;
  List<InventoryTransaction> _history = [];
  bool _historyLoading = true;
  String? _historyError;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final data = await widget.repo.history(_item.inventoryId);
      if (!mounted) return;
      setState(() {
        _history = data;
        _historyLoading = false;
        _historyError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
        _historyError = e.toString();
      });
    }
  }

  Future<void> _apply(Future<InventoryItem> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _item = updated);
      widget.onChanged();
      await _loadHistory();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delivery() async {
    final qty = await _promptQuantity(
      context,
      title: 'Add delivery',
      unit: _item.unit,
      helper: 'Now ${_fmtQty(_item.quantity)} of ${_fmtWhole(_item.capacity)} ${_item.unit}',
      confirmLabel: 'Add delivery',
    );
    if (qty == null) return;
    await _apply(() => widget.repo.adjustStock(_item.inventoryId, qty, 'delivery'));
  }

  Future<void> _usage() async {
    final qty = await _promptQuantity(
      context,
      title: 'Record usage',
      unit: _item.unit,
      helper: 'In stock: ${_fmtQty(_item.quantity)} ${_item.unit}',
      confirmLabel: 'Record usage',
      max: _item.quantity,
    );
    if (qty == null) return;
    await _apply(() => widget.repo.adjustStock(_item.inventoryId, qty, 'usage'));
  }

  Future<void> _correctCount() async {
    final actual = await _promptQuantity(
      context,
      title: 'Correct stock count',
      unit: _item.unit,
      helper: 'Enter what you actually counted. The difference is saved as an adjustment.',
      confirmLabel: 'Save count',
      allowZero: true,
    );
    if (actual == null) return;
    final delta = _round2(actual - _item.quantity);
    if (delta == 0) {
      setState(() => _error = 'That matches the current stock, so nothing changed.');
      return;
    }
    await _apply(() => widget.repo.adjustStock(_item.inventoryId, delta, 'adjustment'));
  }

  Future<void> _edit() async {
    final saved = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => _ItemFormDialog(repo: widget.repo, existing: _item),
    );
    if (saved == null || !mounted) return;
    setState(() => _item = saved);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final actionStyle = OutlinedButton.styleFrom(
      foregroundColor: _Ui.tanDeep,
      side: const BorderSide(color: _Ui.tan),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _item.ingredientName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: _Ui.ink),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _item.category.isEmpty ? 'Uncategorized' : _item.category,
                          style: const TextStyle(fontSize: 13, color: _Ui.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _Ui.muted),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatusBadge(status: _item.status),
                  const SizedBox(width: 12),
                  Text(
                    '${_fmtQty(_item.quantity)} / ${_fmtWhole(_item.capacity)} ${_item.unit}',
                    style: const TextStyle(fontSize: 15, color: _Ui.ink),
                  ),
                  const Spacer(),
                  Text(
                    '${_item.percent}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _percentColor(_item)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _item.fraction,
                  minHeight: 6,
                  color: _barColor(_item),
                  backgroundColor: _Ui.track,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _delivery,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Add delivery'),
                    style: actionStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _usage,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('Record usage'),
                    style: actionStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _correctCount,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Correct count'),
                    style: actionStyle,
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit item'),
                    style: actionStyle,
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(fontSize: 13, color: _Ui.redText)),
              ],
              const SizedBox(height: 20),
              const Divider(height: 1, color: _Ui.border),
              const SizedBox(height: 16),
              const Text('History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: _Ui.ink)),
              const SizedBox(height: 10),
              if (_historyLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (_historyError != null)
                Text("Couldn't load the history: $_historyError", style: const TextStyle(fontSize: 13, color: _Ui.muted))
              else if (_history.isEmpty)
                const Text('No stock changes recorded yet.', style: TextStyle(fontSize: 13, color: _Ui.muted))
              else
                for (final t in _history) _HistoryRow(entry: t, unit: _item.unit),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final InventoryTransaction entry;
  final String unit;
  const _HistoryRow({required this.entry, required this.unit});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    final String label;
    switch (entry.type) {
      case 'delivery':
        icon = Icons.add_circle_outline;
        color = _Ui.greenText;
        label = 'Delivery';
        break;
      case 'usage':
        icon = Icons.remove_circle_outline;
        color = _Ui.redText;
        label = 'Usage';
        break;
      default:
        icon = Icons.tune;
        color = _Ui.tanDeep;
        label = 'Adjustment';
    }
    final sign = entry.quantity >= 0 ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, color: _Ui.ink)),
                Text(
                  [
                    if (entry.employeeName.isNotEmpty) entry.employeeName,
                    _formatTime(entry.time),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: _Ui.muted),
                ),
              ],
            ),
          ),
          Text(
            '$sign${_fmtQty(entry.quantity.abs())} $unit',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}