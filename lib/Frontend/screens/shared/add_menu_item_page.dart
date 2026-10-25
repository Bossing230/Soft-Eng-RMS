import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_constants.dart';
import '../../models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/recipe_editor.dart';

// Must match Backend/constants/stations.js.
const _stations = ['Grill', 'Pasta', 'Salad', 'Desserts', 'Drinks'];

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

  XFile? _pickedImage;
  Uint8List? _previewBytes;
  bool _submitting = false;

  bool get _isEdit => widget.item != null;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.first['category_id'];

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

    // The recipe (may be empty: the dish just isn't stock-tracked). Null means
    // an ingredient row is half filled in, and the editor already said so.
    // Only used when adding; editing a recipe happens on its own page.
    List<Map<String, dynamic>> ingredients = <Map<String, dynamic>>[];
    if (!_isEdit) {
      final editor = _recipeKey.currentState;
      final collected = editor == null ? <Map<String, dynamic>>[] : editor.collect();
      if (collected == null) return;
      ingredients = collected;
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
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Food name', prefixIcon: Icon(Icons.fastfood_outlined))),
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
                  onChanged: (v) => setState(() => _categoryId = v!),
                  decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category_outlined)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _station,
                  items: _stations.map((s) => DropdownMenuItem<String>(value: s, child: Text('$s Station'))).toList(),
                  onChanged: (v) => setState(() => _station = v!),
                  decoration: const InputDecoration(
                    labelText: 'Kitchen station',
                    helperText: 'Which station in the kitchen cooks this dish',
                    prefixIcon: Icon(Icons.soup_kitchen_outlined),
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
                  RecipeEditor(
                    key: _recipeKey,
                    price: double.tryParse(_priceCtrl.text.trim()) ?? 0,
                    enabled: !_submitting,
                  ),
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