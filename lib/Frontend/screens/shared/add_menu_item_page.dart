import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/recipe_editor.dart';

// Must match Backend/constants/stations.js.
const _stations = ['Grill', 'Pasta', 'Salad', 'Desserts', 'Drinks', 'Counter'];

/// 30 -> "30", 12.5 -> "12.50" (for stock amounts coming from the server).
String _num(dynamic v) {
  final n = v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}

/// A full page (not a dialog) for adding OR editing a menu item. This exists
/// specifically to avoid a known Flutter Web bug where a modal
/// showDialog + the native OS file picker (triggered by image_picker)
/// can desync the framework's mouse-tracking state and crash. Full-page
/// navigation doesn't hit that bug.
///
/// Pass [item] to edit an existing dish. The recipe is not shown in edit mode;
/// it has its own page (EditRecipePage).
class AddMenuItemPage extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final MenuItem? item;

  const AddMenuItemPage({super.key, required this.categories, this.item});

  @override
  State<AddMenuItemPage> createState() => _AddMenuItemPageState();
}

class _AddMenuItemPageState extends State<AddMenuItemPage> {
  final _repo = MenuRepository();
  final _recipeKey = GlobalKey<RecipeEditorState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  late int _categoryId;
  String _station = _stations.first;

  // How the item is sold: 'dish' = cooked from a recipe, 'ready' = sold as it
  // is (like a bottle of Coke) and linked to one inventory item.
  String _kind = 'dish';
  final _perSaleCtrl = TextEditingController(text: '1');
  List<Map<String, dynamic>> _stockOptions = [];
  int? _stockItemId; // null = don't track stock
  bool _stockLoading = false;
  String? _stockError;

  XFile? _pickedImage;
  Uint8List? _previewBytes;
  bool _submitting = false;

  // A dish that already has this name (any category), found while typing.
  Timer? _nameTimer;
  Map<String, dynamic>? _duplicate;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.first['category_id'];
    if (widget.item == null) {
      _stockLoading = true;
      _loadStockOptions();
    }

    final item = widget.item;
    if (item != null) {
      _nameCtrl.text = item.foodName;
      final d = item.description.trim().toLowerCase();
      _descCtrl.text = (d == 'n/a' || d == 'na') ? '' : item.description;
      _priceCtrl.text = item.price.toStringAsFixed(2);
      final hasCategory = widget.categories.any((c) => c['category_id'] == item.categoryId);
      if (hasCategory) _categoryId = item.categoryId;
      if (item.station != null && _stations.contains(item.station)) _station = item.station!;
    }
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _perSaleCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String? get _existingImageUrl {
    final path = widget.item?.image;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
    return '$base$path';
  }

  void _scheduleNameCheck() {
    _nameTimer?.cancel();
    _nameTimer = Timer(const Duration(milliseconds: 400), _checkName);
  }

  Future<void> _checkName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() => _duplicate = null);
      return;
    }
    try {
      final found = await _repo.checkName(name, excludeId: widget.item?.menuId, categoryId: _categoryId);
      // Ignore the answer if the name changed while we were waiting.
      if (!mounted || name != _nameCtrl.text.trim()) return;
      setState(() => _duplicate = found);
    } catch (_) {
      // The warning is a convenience: if the check fails, the server still
      // refuses a real duplicate when saving.
    }
  }

  bool get _duplicateInSameCategory => _duplicate != null && '${_duplicate!['category_id']}' == '$_categoryId';

  Widget _duplicateNotice() {
    final d = _duplicate;
    if (d == null) return const SizedBox.shrink();
    final same = _duplicateInSameCategory;
    final color = same ? Colors.red.shade700 : Colors.orange.shade800;
    final message = same
        ? '"${d['food_name']}" already exists in ${d['category_name']}. Choose a different name.'
        : '"${d['food_name']}" already exists in ${d['category_name']}. You can still add it to this category.';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(same ? Icons.block : Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(fontSize: 12.5, color: color))),
        ],
      ),
    );
  }

  /// Items that aren't cooked: drinks, counter items and anything marked ready-made.
  bool get _notCooked => _kind == 'ready' || _station == 'Drinks' || _station == 'Counter';

  /// Where a ready-made item is handed out: Drinks for bottles and cups,
  /// the Counter for anything else (packaged snacks, bottled goods...).
  String _defaultReadyStation() {
    var name = '';
    for (final c in widget.categories) {
      if (c['category_id'] == _categoryId) name = '${c['category_name']}'.toLowerCase();
    }
    const drinkWords = ['drink', 'beverage', 'soda', 'juice', 'water', 'coffee', 'tea', 'shake'];
    return drinkWords.any(name.contains) ? 'Drinks' : 'Counter';
  }

  Future<void> _loadStockOptions() async {
    try {
      final options = await _repo.getRecipeIngredientOptions();
      if (!mounted) return;
      setState(() {
        _stockOptions = options;
        _stockLoading = false;
        _stockError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stockLoading = false;
        _stockError = '$e';
      });
    }
  }

  /// The unit of the linked inventory item (g, ml, pcs...), if one is chosen.
  String? get _stockUnit {
    for (final o in _stockOptions) {
      if (o['inventory_id'] == _stockItemId) return '${o['unit']}';
    }
    return null;
  }

  Widget _stockSection() {
    final ready = _kind == 'ready';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('How is this sold?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'dish', icon: Icon(Icons.restaurant), label: Text('Cooked dish')),
            ButtonSegment(value: 'ready', icon: Icon(Icons.local_drink_outlined), label: Text('Ready-made item')),
          ],
          selected: {_kind},
          onSelectionChanged: _submitting
              ? null
              : (selection) => setState(() {
                    _kind = selection.first;
                    // Nothing is cooked for a ready-made item: hand it out from Drinks or the Counter unless a station was chosen.
                    if (_kind == 'ready' && _station == _stations.first) _station = _defaultReadyStation();
                  }),
        ),
        const SizedBox(height: 8),
        Text(
          ready
              ? 'Sold as it is, like a bottle of Coke. It is not cooked, so it has no recipe: link it to the item in your inventory instead.'
              : 'Cooked in the kitchen from one or more ingredients. Add them in the recipe below.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        // Kept alive (just hidden) so a half-written recipe isn't lost when switching.
        Visibility(
          visible: !ready,
          maintainState: true,
          child: RecipeEditor(
            key: _recipeKey,
            price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
            enabled: !_submitting,
          ),
        ),
        if (ready) _readyMadeFields(),
      ],
    );
  }

  Widget _readyMadeFields() {
    if (_stockLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_stockError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Couldn't load the inventory: $_stockError", style: TextStyle(fontSize: 12.5, color: Colors.red.shade700)),
          TextButton(
            onPressed: () {
              setState(() => _stockLoading = true);
              _loadStockOptions();
            },
            child: const Text('Try again'),
          ),
        ],
      );
    }

    final unit = _stockUnit;
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
          onChanged: _submitting ? null : (v) => setState(() => _stockItemId = v),
        ),
        const SizedBox(height: 8),
        if (_stockItemId != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _perSaleCtrl,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount taken out per sale',
              prefixIcon: const Icon(Icons.remove_circle_outline),
              suffixText: unit,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Each time this is ordered, that amount is taken out of the inventory item. '
            'If the inventory runs out, it can no longer be ordered.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ] else
          Text(
            _stockOptions.isEmpty
                ? 'There are no inventory items yet. Add it in Inventory first, or leave this as it is to sell it without tracking stock.'
                : "Stock isn't tracked: ordering this won't change your inventory.",
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _pickedImage = file;
        _previewBytes = bytes;
      });
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _priceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Food name and price are required')));
      return;
    }
    if (_duplicateInSameCategory) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${_duplicate!['food_name']}" already exists in ${_duplicate!['category_name']}.'),
      ));
      return;
    }

    // The recipe (may be empty: the dish just isn't stock-tracked). Null means
    // an ingredient row is half filled in, and the editor already said so.
    // Only used when adding; editing a recipe happens on its own page.
    List<Map<String, dynamic>> ingredients = <Map<String, dynamic>>[];
    if (!_isEdit && _kind == 'dish') {
      final editor = _recipeKey.currentState;
      final collected = editor == null ? <Map<String, dynamic>>[] : editor.collect();
      if (collected == null) return;
      ingredients = collected;
    } else if (!_isEdit && _kind == 'ready' && _stockItemId != null) {
      // A ready-made item is stored as a one-ingredient recipe: each sale takes
      // this amount out of the linked inventory item.
      final perSale = double.tryParse(_perSaleCtrl.text.trim());
      if (perSale == null || perSale <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter how much is taken out of inventory per sale (more than zero).')),
        );
        return;
      }
      ingredients = [
        {'inventoryId': _stockItemId, 'quantity': perSale},
      ];
    }

    setState(() => _submitting = true);

    try {
      // A new photo replaces the old one; otherwise keep whatever the item had.
      String? imageUrl = widget.item?.image;
      if (_previewBytes != null && _pickedImage != null) {
        imageUrl = await _repo.uploadImage(bytes: _previewBytes!, filename: _pickedImage!.name);
      }

      if (_isEdit) {
        await _repo.update(
          widget.item!.menuId,
          categoryId: _categoryId,
          foodName: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text) ?? 0,
          image: imageUrl,
          station: _station,
        );
      } else {
        await _repo.create(
          categoryId: _categoryId,
          foodName: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text) ?? 0,
          image: imageUrl,
          station: _station,
          ingredients: ingredients,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to ${_isEdit ? 'save' : 'add'} item: $e')));
      }
    }
  }

  Widget _photoArea() {
    final existing = _existingImageUrl;

    Widget content;
    if (_previewBytes != null) {
      content = Image.memory(_previewBytes!, fit: BoxFit.cover, width: double.infinity, height: 160);
    } else if (existing != null) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            existing,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey, size: 32)),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: const Text('Tap to change photo', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
        ],
      );
    } else {
      content = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo, color: Colors.grey, size: 32),
          SizedBox(height: 8),
          Text('Tap to add a photo', style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    return GestureDetector(
      onTap: _submitting ? null : _pickImage,
      child: Container(
        height: 160,
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Menu Item' : 'New Menu Item')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _photoArea(),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameCtrl,
                  onChanged: (_) => _scheduleNameCheck(),
                  decoration: const InputDecoration(labelText: 'Food name', prefixIcon: Icon(Icons.fastfood_outlined)),
                ),
                _duplicateNotice(),
                const SizedBox(height: 16),
                TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes))),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price', prefixIcon: Icon(Icons.attach_money)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}), // keeps the recipe's margin hint current
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  items: widget.categories.map((c) => DropdownMenuItem<int>(value: c['category_id'], child: Text(c['category_name']))).toList(),
                  onChanged: (v) {
                    setState(() {
                      _categoryId = v!;
                      // Keep the automatic Drinks / Counter choice in step with the category.
                      if (_kind == 'ready' && (_station == 'Drinks' || _station == 'Counter')) {
                        _station = _defaultReadyStation();
                      }
                    });
                    _checkName();
                  },
                  decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _station,
                  items: _stations.map((s) => DropdownMenuItem<String>(value: s, child: Text('$s Station'))).toList(),
                  onChanged: (v) => setState(() => _station = v!),
                  decoration: InputDecoration(
                    // Drinks and other ready-made items aren't cooked, so don't say "cooks".
                    labelText: _notCooked ? 'Handed out by' : 'Kitchen station',
                    helperText: _notCooked
                        ? "Not cooked. Drinks for bottles and cups, Counter for packaged items like chips. That screen shows the order so it can be handed out."
                        : "The station that cooks this dish. Its orders show up on that station's screen.",
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.soup_kitchen_outlined),
                  ),
                ),
                const SizedBox(height: 28),
                if (_isEdit)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.grey[700]),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('To change ingredients, use "Edit recipe" in the card\'s ⋮ menu.', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  )
                else
                  _stockSection(),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _submitting ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(_isEdit ? 'Save' : 'Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}