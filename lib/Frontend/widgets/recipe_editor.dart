import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../repositories/menu_repository.dart';

/// One line of the recipe being built: which inventory item, and how much of
/// it ONE serving of the dish uses (in that item's own unit).
class _IngredientRow {
  int? inventoryId;
  final TextEditingController qty;
  _IngredientRow({this.inventoryId, String qtyText = ''}) : qty = TextEditingController(text: qtyText);
  void dispose() => qty.dispose();
}

String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// The "Recipe" section: a list of ingredient rows, a live cost per serving and
/// a margin hint. It loads the inventory items itself.
///
/// Give it a `GlobalKey<RecipeEditorState>` and call `collect()` when saving.
/// [initialIngredients] are rows as the recipe API returns them
/// (`inventory_id`, `quantity`). [price] is the dish's selling price, used
/// only for the margin hint.
class RecipeEditor extends StatefulWidget {
  final double price;
  final List<Map<String, dynamic>> initialIngredients;
  final bool enabled;

  const RecipeEditor({
    super.key,
    this.price = 0,
    this.initialIngredients = const [],
    this.enabled = true,
  });

  @override
  State<RecipeEditor> createState() => RecipeEditorState();
}

class RecipeEditorState extends State<RecipeEditor> {
  final _repo = MenuRepository();

  List<Map<String, dynamic>> _options = [];
  bool _optionsLoading = true;
  String? _optionsError;
  final List<_IngredientRow> _rows = [];

  /// True once the inventory items have loaded. Saving an EXISTING recipe
  /// before this is true could wipe it, so callers should check it.
  bool get loaded => !_optionsLoading && _optionsError == null;

  @override
  void initState() {
    super.initState();
    for (final ing in widget.initialIngredients) {
      final id = ing['inventory_id'] ?? ing['inventoryId'];
      final q = ing['quantity'];
      _rows.add(_IngredientRow(
        inventoryId: id is num ? id.toInt() : int.tryParse('$id'),
        qtyText: q == null ? '' : _plain(_num(q)),
      ));
    }
    _loadOptions();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _optionsLoading = true;
      _optionsError = null;
    });
    try {
      final options = await _repo.getRecipeIngredientOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _optionsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _optionsError = '$e';
        _optionsLoading = false;
      });
    }
  }

  // ---- helpers ----

  double _num(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

  Map<String, dynamic>? _option(int? id) {
    if (id == null) return null;
    for (final o in _options) {
      if (o['inventory_id'] == id) return o;
    }
    return null;
  }

  double _rowQty(_IngredientRow r) => double.tryParse(r.qty.text.trim()) ?? 0;

  bool get _hasRecipe => _rows.any((r) => r.inventoryId != null);

  double get _costPerServing {
    var total = 0.0;
    for (final r in _rows) {
      final o = _option(r.inventoryId);
      final q = _rowQty(r);
      if (o != null && q > 0) total += q * _num(o['unit_cost']);
    }
    return total;
  }

  bool get _hasMissingCost {
    for (final r in _rows) {
      final o = _option(r.inventoryId);
      if (o != null && _rowQty(r) > 0 && _num(o['unit_cost']) <= 0) return true;
    }
    return false;
  }

  void _addRow() => setState(() => _rows.add(_IngredientRow()));

  void _removeRow(_IngredientRow row) {
    setState(() => _rows.remove(row));
    row.dispose();
  }

  /// The recipe to send: [{ 'inventoryId': 3, 'quantity': 30.0 }, ...]. An empty
  /// list means "no recipe". Returns null (after showing a message) if a row is
  /// only half filled in.
  List<Map<String, dynamic>>? collect() {
    final result = <Map<String, dynamic>>[];
    for (final r in _rows) {
      final text = r.qty.text.trim();
      if (r.inventoryId == null && text.isEmpty) continue; // untouched row
      final q = double.tryParse(text);
      if (r.inventoryId == null || q == null || q < 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Finish or remove each ingredient row: pick an item and enter an amount of at least 0.01')),
        );
        return null;
      }
      result.add({'inventoryId': r.inventoryId, 'quantity': q});
    }
    return result;
  }

  // ---- UI ----

  Widget _ingredientRow(_IngredientRow row) {
    final taken = _rows.where((r) => r != row && r.inventoryId != null).map((r) => r.inventoryId).toSet();
    final choices = _options.where((o) => !taken.contains(o['inventory_id'])).toList();
    final selected = _option(row.inventoryId);

    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: row.inventoryId,
              isExpanded: true,
              items: choices
                  .map((o) => DropdownMenuItem<int>(
                        value: o['inventory_id'] as int,
                        child: Text('${o['ingredient_name']}', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: widget.enabled ? (v) => setState(() => row.inventoryId = v) : null,
              decoration: const InputDecoration(labelText: 'Ingredient', isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: TextField(
              controller: row.qty,
              enabled: widget.enabled,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Per serving',
                isDense: true,
                suffixText: selected == null ? null : '${selected['unit']}',
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 20),
            onPressed: widget.enabled ? () => _removeRow(row) : null,
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    const muted = TextStyle(fontSize: 12, color: Colors.grey);
    if (!_hasRecipe) {
      return const Text("No recipe: stock won't be tracked for this dish.", style: muted);
    }

    final price = widget.price;
    final cost = _costPerServing;
    final profit = price - cost;
    final belowCost = price > 0 && profit < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ingredient cost per serving: ₱${cost.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (price > 0) ...[
            const SizedBox(height: 4),
            Text(
              belowCost
                  ? 'The selling price (₱${price.toStringAsFixed(2)}) is below the ingredient cost.'
                  : 'Profit per serving: ₱${profit.toStringAsFixed(2)} (${(profit / price * 100).toStringAsFixed(0)}% margin)',
              style: TextStyle(fontSize: 12, color: belowCost ? Colors.red.shade700 : Colors.green.shade700),
            ),
          ],
          if (_hasMissingCost) ...[
            const SizedBox(height: 4),
            const Text('Some ingredients have no cost set in Inventory, so this cost is incomplete.', style: muted),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_optionsLoading) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
    } else if (_optionsError != null) {
      body = Row(
        children: [
          Expanded(child: Text("Couldn't load inventory items: $_optionsError", style: const TextStyle(color: Colors.grey))),
          TextButton(onPressed: _loadOptions, child: const Text('Retry')),
        ],
      );
    } else if (_options.isEmpty) {
      body = const Text(
        "Add ingredients in Inventory first, then come back to build this dish's recipe.",
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in _rows) _ingredientRow(row),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: !widget.enabled || _rows.length >= _options.length ? null : _addRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add ingredient'),
            ),
          ),
          const SizedBox(height: 12),
          _summary(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recipe', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
          'What ONE serving uses. These amounts come out of Inventory every time the dish is ordered.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}