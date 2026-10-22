import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/recipe_editor.dart';

// Must match Backend/constants/stations.js.
const _stations = ['Grill', 'Pasta', 'Salad', 'Desserts', 'Drinks'];

/// A full page (not a dialog) for adding a menu item. This exists
/// specifically to avoid a known Flutter Web bug where a modal
/// showDialog + the native OS file picker (triggered by image_picker)
/// can desync the framework's mouse-tracking state and crash. Full-page
/// navigation doesn't hit that bug.
class AddMenuItemPage extends StatefulWidget {
  final List<Map<String, dynamic>> categories;

  const AddMenuItemPage({super.key, required this.categories});

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

  @override
  void initState() {
    super.initState();
    _categoryId = widget.categories.first['category_id'];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
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
    final editor = _recipeKey.currentState;
    final ingredients = editor == null ? <Map<String, dynamic>>[] : editor.collect();
    if (ingredients == null) return;

    setState(() => _submitting = true);

    try {
      String? imageUrl;
      if (_previewBytes != null && _pickedImage != null) {
        imageUrl = await _repo.uploadImage(bytes: _previewBytes!, filename: _pickedImage!.name);
      }
      await _repo.create(
        categoryId: _categoryId,
        foodName: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        price: double.tryParse(_priceCtrl.text) ?? 0,
        image: imageUrl,
        station: _station,
        ingredients: ingredients,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add item: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Menu Item')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GestureDetector(
                  onTap: _submitting ? null : _pickImage,
                  child: Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _previewBytes != null
                        ? Image.memory(_previewBytes!, fit: BoxFit.cover, width: double.infinity, height: 160)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, color: Colors.grey, size: 32),
                              SizedBox(height: 8),
                              Text('Tap to add a photo', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Food name', prefixIcon: Icon(Icons.fastfood_outlined))),
                const SizedBox(height: 16),
                TextField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.notes))),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price', prefixIcon: Icon(Icons.attach_money)),
                  keyboardType: TextInputType.number,
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
                          : const Text('Add'),
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