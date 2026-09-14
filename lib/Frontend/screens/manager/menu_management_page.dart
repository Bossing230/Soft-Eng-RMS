import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/menu_card.dart';
import '../shared/add_menu_item_page.dart';

class MenuManagementPage extends StatefulWidget {
  const MenuManagementPage({super.key});

  @override
  State<MenuManagementPage> createState() => _MenuManagementPageState();
}

class _MenuManagementPageState extends State<MenuManagementPage> {
  final _repo = MenuRepository();
  List<MenuItem> _items = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  // null means "All" is selected.
  int? _selectedCategoryId;

  List<MenuItem> get _filteredItems {
    if (_selectedCategoryId == null) return _items;
    return _items.where((i) => i.categoryId == _selectedCategoryId).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _repo.getAll(search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text);
    final categories = await _repo.getCategories();
    setState(() {
      _items = items;
      _categories = categories;
      _loading = false;
    });
  }

  Future<void> _showAddCategoryDialog() async {
    final nameCtrl = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Category'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Category name', hintText: 'e.g. Main Dishes, Beverages'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );

    if (added == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await _repo.createCategory(nameCtrl.text.trim());
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Category "${nameCtrl.text.trim()}" added.')),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add category: $e')));
      }
    }
  }

  Future<void> _showCreateDialog() async {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a menu category first.')));
      return;
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddMenuItemPage(categories: _categories)),
    );
    if (created == true) _load();
  }

  Widget _categoryPill({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.grey[300]!),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'addCategory',
            onPressed: _showAddCategoryDialog,
            icon: const Icon(Icons.category, color: Colors.white),
            label: const Text('Add Category', style: TextStyle(color: Colors.white)),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'addItem',
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Item'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search menu items...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchCtrl.clear(); _load(); }),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          if (_categories.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _categoryPill(
                    label: 'All',
                    selected: _selectedCategoryId == null,
                    onTap: () => setState(() => _selectedCategoryId = null),
                  ),
                  const SizedBox(width: 8),
                  for (final c in _categories) ...[
                    _categoryPill(
                      label: c['category_name'],
                      selected: _selectedCategoryId == c['category_id'],
                      onTap: () => setState(() => _selectedCategoryId = c['category_id']),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 280, mainAxisExtent: 270, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemCount: _filteredItems.length,
                      itemBuilder: (_, i) {
                        final item = _filteredItems[i];
                        return MenuCard(
                          item: item,
                          onToggleAvailability: () async {
                            await _repo.setAvailability(item.menuId, !item.isAvailable);
                            _load();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}