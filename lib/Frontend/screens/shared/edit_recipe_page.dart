import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/recipe_editor.dart';

/// 30 -> "30", 12.5 -> "12.50" (for stock amounts coming from the server).
String _num(dynamic v) {
  final n = v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}

/// Sets how a dish that already exists takes stock out of Inventory. Pops with
/// `true` when saved.
///
/// Two ways to sell something:
///  - Cooked dish: a recipe of one or more ingredients (the RecipeEditor).
///  - Ready-made item (like a bottle of Coke): linked to ONE inventory item,
///    with the amount each sale takes out. It is saved as a one-ingredient
///    recipe, so orders and stock alerts work the same way.
class EditRecipePage extends StatefulWidget {
  final MenuItem item;

  const EditRecipePage({super.key, required this.item});

  @override
  State<EditRecipePage> createState() => _EditRecipePageState();
}

class _EditRecipePageState extends State<EditRecipePage> {
  final _repo = MenuRepository();
  final _editorKey = GlobalKey<RecipeEditorState>();
  final _perSaleCtrl = TextEditingController(text: '1');

  Map<String, dynamic>? _recipe;
  List<Map<String, dynamic>> _stockOptions = [];
  String _kind = 'dish'; // 'dish' | 'ready'
  int? _stockItemId; // the linked inventory item for a ready-made item
  bool _hadRecipe = false; // did the dish already take stock out before this edit?
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _perSaleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.getRecipe(widget.item.menuId),
        _repo.getRecipeIngredientOptions(),
      ]);
      final recipe = results[0] as Map<String, dynamic>;
      final options = results[1] as List<Map<String, dynamic>>;
      final ingredients = ((recipe['ingredients'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

      // The kind isn't stored, so guess it: a drink with no recipe, or a
      // single ingredient, is most likely a ready-made item. Either way it can
      // be switched below.
      final isDrink = (widget.item.station ?? '').toLowerCase() == 'drinks';
      final ready = isDrink && ingredients.length <= 1;

      int? linked;
      if (ingredients.length == 1) {
        final id = ingredients.first['inventory_id'];
        final idInt = id is num ? id.toInt() : int.tryParse('$id');
        if (options.any((o) => o['inventory_id'] == idInt)) linked = idInt;
        final q = ingredients.first['quantity'];
        if (q != null) _perSaleCtrl.text = _num(q);
      }

      if (!mounted) return;
      setState(() {
        _recipe = recipe;
        _stockOptions = options;
        _hadRecipe = ingredients.isNotEmpty;
        _kind = ready ? 'ready' : 'dish';
        _stockItemId = ready ? linked : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// The unit and cost of the linked inventory item, if one is chosen.
  Map<String, dynamic>? get _linkedOption {
    for (final o in _stockOptions) {
      if (o['inventory_id'] == _stockItemId) return o;
    }
    return null;
  }

  Future<bool> _confirmRemoval() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop tracking stock?'),
        content: Text(
          '${widget.item.foodName} will no longer take anything out of Inventory when it is ordered.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop tracking')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    List<Map<String, dynamic>>? ingredients;

    if (_kind == 'dish') {
      final editor = _editorKey.currentState;
      // Saving before the inventory list has loaded could wipe the existing recipe.
      if (editor == null || !editor.loaded) {
        _snack('Still loading inventory items. Try again in a moment.');
        return;
      }
      ingredients = editor.collect();
      if (ingredients == null) return;
    } else if (_stockItemId == null) {
      ingredients = [];
    } else {
      final perSale = double.tryParse(_perSaleCtrl.text.trim());
      if (perSale == null || perSale < 0.01) {
        _snack('Enter how much is taken out of inventory per sale (at least 0.01).');
        return;
      }
      ingredients = [
        {'inventoryId': _stockItemId, 'quantity': perSale},
      ];
    }

    if (ingredients.isEmpty && _hadRecipe && !await _confirmRemoval()) return;

    setState(() => _saving = true);
    try {
      await _repo.saveRecipe(widget.item.menuId, ingredients);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack('Failed to save: $e');
    }
  }

  // ---- UI ----

  Widget _readyMadeFields() {
    final option = _linkedOption;
    final perSale = double.tryParse(_perSaleCtrl.text.trim()) ?? 0;
    final unitCost = option == null ? 0.0 : (double.tryParse('${option['unit_cost']}') ?? 0);
    final saleCost = perSale * unitCost;
    final profit = widget.item.price - saleCost;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int?>(
          initialValue: _stockItemId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Inventory item', prefixIcon: Icon(Icons.inventory_2_outlined)),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text("Don't track stock")),
            for (final o in _stockOptions)
              DropdownMenuItem<int?>(
                value: o['inventory_id'] as int,
                child: Text('${o['ingredient_name']} (${_num(o['quantity'])} ${o['unit']} in stock)', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _saving ? null : (v) => setState(() => _stockItemId = v),
        ),
        const SizedBox(height: 12),
        if (_stockItemId != null) ...[
          TextField(
            controller: _perSaleCtrl,
            enabled: !_saving,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount taken out per sale',
              prefixIcon: const Icon(Icons.remove_circle_outline),
              suffixText: option == null ? null : '${option['unit']}',
            ),
          ),
          const SizedBox(height: 8),
          if (perSale > 0 && unitCost > 0)
            Text(
              profit < 0
                  ? 'Cost per sale ₱${saleCost.toStringAsFixed(2)}: the selling price is below it.'
                  : 'Cost per sale ₱${saleCost.toStringAsFixed(2)}, profit ₱${profit.toStringAsFixed(2)} per sale.',
              style: TextStyle(fontSize: 12, color: profit < 0 ? Colors.red.shade700 : Colors.green.shade700),
            ),
          if (perSale > 0 && unitCost <= 0)
            const Text('That inventory item has no cost set, so the cost per sale is unknown.', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          const Text(
            'Each time this is ordered, that amount is taken out of the inventory item. '
            'If the inventory runs out, it can no longer be ordered.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ] else
          Text(
            _stockOptions.isEmpty
                ? 'There are no inventory items yet. Add it in Inventory first.'
                : "Stock isn't tracked: ordering this won't change your inventory.",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Couldn't load this: $_error", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final recipe = _recipe!;
    final servings = recipe['servings_available'];
    final initial = ((recipe['ingredients'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final ready = _kind == 'ready';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.item.foodName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text('Selling price ₱${widget.item.price.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey)),
              if (servings != null) ...[
                const SizedBox(height: 6),
                Text(
                  servings == 0 ? 'Current stock cannot make a single serving.' : 'Current stock can cover $servings sale${servings == 1 ? '' : 's'}.',
                  style: TextStyle(fontSize: 12, color: servings == 0 ? Colors.red.shade700 : Colors.green.shade700),
                ),
              ],
              const SizedBox(height: 24),
              const Text('How is this sold?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'dish', icon: Icon(Icons.restaurant), label: Text('Cooked dish')),
                  ButtonSegment(value: 'ready', icon: Icon(Icons.local_drink_outlined), label: Text('Ready-made item')),
                ],
                selected: {_kind},
                onSelectionChanged: _saving ? null : (selection) => setState(() => _kind = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                ready
                    ? 'Sold as it is, like a bottle of Coke. It is not cooked, so it has no recipe: link it to the item in your inventory instead.'
                    : 'Cooked in the kitchen from one or more ingredients. Add them in the recipe below.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              // Kept alive (just hidden) so a half-edited recipe isn't lost when switching.
              Visibility(
                visible: !ready,
                maintainState: true,
                child: RecipeEditor(
                  key: _editorKey,
                  price: widget.item.price,
                  initialIngredients: initial,
                  enabled: !_saving,
                ),
              ),
              if (ready) _readyMadeFields(),
              const SizedBox(height: 12),
              const Text(
                'Changes apply to new orders only. Orders already placed keep what they used.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recipe & stock')),
      body: _body(),
    );
  }
}