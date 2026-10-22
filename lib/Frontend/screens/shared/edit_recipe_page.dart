import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/recipe_editor.dart';

/// Edit the recipe of a dish that already exists. Pops with `true` when saved.
class EditRecipePage extends StatefulWidget {
  final MenuItem item;

  const EditRecipePage({super.key, required this.item});

  @override
  State<EditRecipePage> createState() => _EditRecipePageState();
}

class _EditRecipePageState extends State<EditRecipePage> {
  final _repo = MenuRepository();
  final _editorKey = GlobalKey<RecipeEditorState>();

  Map<String, dynamic>? _recipe;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final recipe = await _repo.getRecipe(widget.item.menuId);
      if (!mounted) return;
      setState(() {
        _recipe = recipe;
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

  Future<void> _save() async {
    final editor = _editorKey.currentState;
    // Saving before the inventory list has loaded could wipe the existing recipe.
    if (editor == null || !editor.loaded) {
      _snack('Still loading inventory items. Try again in a moment.');
      return;
    }
    final ingredients = editor.collect();
    if (ingredients == null) return;

    setState(() => _saving = true);
    try {
      await _repo.saveRecipe(widget.item.menuId, ingredients);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _snack('Failed to save the recipe: $e');
    }
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
              Text("Couldn't load the recipe: $_error", textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
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
                  servings == 0 ? 'Current stock cannot make a single serving.' : 'Current stock can make $servings serving${servings == 1 ? '' : 's'}.',
                  style: TextStyle(fontSize: 12, color: servings == 0 ? Colors.red.shade700 : Colors.green.shade700),
                ),
              ],
              const SizedBox(height: 24),
              RecipeEditor(
                key: _editorKey,
                price: widget.item.price,
                initialIngredients: initial,
                enabled: !_saving,
              ),
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
                        : const Text('Save recipe'),
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
      appBar: AppBar(title: const Text('Recipe')),
      body: _body(),
    );
  }
}