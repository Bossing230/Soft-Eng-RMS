import 'dart:async';
import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../../repositories/menu_repository.dart';
import '../../widgets/menu_card.dart';
import '../shared/add_menu_item_page.dart';
import '../shared/edit_recipe_page.dart';

enum MenuSort { nameAsc, priceLow, priceHigh, availableFirst }

extension on MenuSort {
  String get label => switch (this) {
        MenuSort.nameAsc => 'Name (A-Z)',
        MenuSort.priceLow => 'Price: low to high',
        MenuSort.priceHigh => 'Price: high to low',
        MenuSort.availableFirst => 'Available first',
      };
}

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
  Timer? _debounce;

  // null means "All" is selected.
  int? _selectedCategoryId;
  bool _availableOnly = false;
  MenuSort _sort = MenuSort.nameAsc;

  List<MenuItem> get _filteredItems {
    var list = _items.where((i) {
      if (_selectedCategoryId != null && i.categoryId != _selectedCategoryId) return false;
      if (_availableOnly && !i.isAvailable) return false;
      return true;
    }).toList();

    switch (_sort) {
      case MenuSort.nameAsc:
        list.sort((a, b) => a.foodName.toLowerCase().compareTo(b.foodName.toLowerCase()));
        break;
      case MenuSort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case MenuSort.priceHigh:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case MenuSort.availableFirst:
        list.sort((a, b) {
          if (a.isAvailable == b.isAvailable) {
            return a.foodName.toLowerCase().compareTo(b.foodName.toLowerCase());
          }
          return a.isAvailable ? -1 : 1;
        });
        break;
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _repo.getAll(search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim());
      final categories = await _repo.getCategories();
      if (!mounted) return;
      setState(() {
        _items = items;
        _categories = categories;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load menu: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
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

  /// Opens the recipe editor for a dish that already exists.
  Future<void> _openRecipe(MenuItem item) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EditRecipePage(item: item)),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Stock setup saved for ${item.foodName}.')));
    }
  }

  /// Opens the same form as "Add Item", pre-filled with this dish.
  Future<void> _editItem(MenuItem item) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddMenuItemPage(categories: _categories, item: item)),
    );
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.foodName} updated.')));
      }
    }
  }

  /// The card already asked "Are you sure?" before calling this.
  Future<void> _deleteItem(MenuItem item) async {
    try {
      await _repo.delete(item.menuId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${item.foodName} deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not delete ${item.foodName}. If it is used in past orders, mark it Sold out instead. ($e)'),
        ));
      }
    }
  }

  Widget _categoryPill({required String label, required bool selected, required VoidCallback onTap}) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? primary : Colors.grey[300]!),
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

  Widget _toolbar(int shown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          Text('$shown item${shown == 1 ? '' : 's'}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          const Spacer(),
          FilterChip(
            label: const Text('Available only'),
            selected: _availableOnly,
            onSelected: (v) => setState(() => _availableOnly = v),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<MenuSort>(
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              for (final s in MenuSort.values) PopupMenuItem(value: s, child: Text(s.label)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sort, size: 18),
                  const SizedBox(width: 4),
                  Text(_sort.label, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final searching = _searchCtrl.text.trim().isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.restaurant_menu, size: 56, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Center(
          child: Text(
            searching ? 'No items match "${_searchCtrl.text.trim()}"' : 'No menu items here yet',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            searching || _availableOnly || _selectedCategoryId != null
                ? 'Try a different search or clear the filters.'
                : 'Tap "Add Item" to create your first dish.',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;

    return Scaffold(
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
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
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                ),
              ),
              onChanged: _onSearchChanged,
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
                    label: 'All (${_items.length})',
                    selected: _selectedCategoryId == null,
                    onTap: () => setState(() => _selectedCategoryId = null),
                  ),
                  const SizedBox(width: 8),
                  for (final c in _categories) ...[
                    _categoryPill(
                      label: '${c['category_name']} (${_items.where((i) => i.categoryId == c['category_id']).length})',
                      selected: _selectedCategoryId == c['category_id'],
                      onTap: () => setState(() => _selectedCategoryId = c['category_id']),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          _toolbar(items.length),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: items.isEmpty
                        ? _emptyState()
                        : GridView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            // Extra bottom padding keeps the last row clear of the floating buttons.
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 160),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              mainAxisExtent: 310,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: items.length,
                            itemBuilder: (_, i) {
                              final item = items[i];
                              return MenuCard(
                                item: item,
                                onToggleAvailability: () async {
                                  await _repo.setAvailability(item.menuId, !item.isAvailable);
                                  _load();
                                },
                                // Recipe: ingredients taken from inventory per order.
                                onRecipe: () => _openRecipe(item),
                                onEdit: () => _editItem(item),
                                onDelete: () => _deleteItem(item),
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