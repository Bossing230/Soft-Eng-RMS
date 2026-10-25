import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:rms/Frontend/models/inventory.dart';

import '../../core/constants/app_constants.dart';
import '../../repositories/inventory_repository.dart';

// ---------------------------------------------------------------------------
// Design tokens, taken from the inventory dashboard design.
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
  static const pillIdle = Color(0xFFEFE9E0);
  static const ink = Color(0xFF2B2B2B);
  static const muted = Color(0xFF7A7A7A);
  static const green = Color(0xFF4CAF50);
  static const redText = Color(0xFFE53935);
  static const amberText = Color(0xFFB07A00);
  static const greenText = Color(0xFF2E7D32);
}

/// Standard choices, so "g", "G" and "grams" don't become three different units.
/// Ingredients measured by weight or volume use g / ml (not kg / L) so recipes
/// can use small amounts like 30 g. Countable things use pcs, pack, can, etc.
const _units = ['g', 'ml', 'pcs', 'pack', 'can', 'bottle', 'box', 'sack'];
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

/// Where an item is kept. "Not set" in the form clears it.
const _locations = ['Freezer', 'Chiller', 'Dry store', 'Kitchen line', 'Bar', 'Other'];
const _noLocation = 'Not set';

/// Must match WASTE_REASONS in the backend inventoryController.js.
const _wasteReasons = ['Expired', 'Spoiled', 'Spilled or damaged', 'Returned to supplier', 'Other'];

final _categoryIcons = {
  'meat': Icons.kebab_dining_outlined,
  'seafood': Icons.set_meal_outlined,
  'vegetables': Icons.eco_outlined,
  'fruits': Icons.local_grocery_store_outlined,
  'dairy & eggs': Icons.egg_outlined,
  'grains': Icons.grain_outlined,
  'dry goods': Icons.inventory_2_outlined,
  'condiments & sauces': Icons.liquor_outlined,
  'beverages': Icons.local_drink_outlined,
};
IconData _categoryIcon(String category) => _categoryIcons[category.toLowerCase()] ?? Icons.inventory_2_outlined;

final _qtyFormat = NumberFormat('#,##0.0#');
final _wholeFormat = NumberFormat('#,##0.##');
final _moneyFormat = NumberFormat('#,##0.00');

String _fmtQty(double v) => _qtyFormat.format(v);
String _fmtWhole(double v) => _wholeFormat.format(v);
String _fmtMoney(double v) => '₱${_moneyFormat.format(v)}';
double _round2(double v) => (v * 100).roundToDouble() / 100;
String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _SeverityStyle {
  final Color bg;
  final Color fg;
  final Color dot;
  final String label;
  const _SeverityStyle(this.bg, this.fg, this.dot, this.label);
}

/// The four-state display bucket (ok/low/critical/out). The stock-change
/// alerts and restock logic still use the item's 3-state `status`; this is
/// only for how a row or chip is colored and labeled.
_SeverityStyle _severityStyle(String severity) {
  switch (severity) {
    case 'out':
      return const _SeverityStyle(Color(0xFFFFCDD2), Color(0xFFC62828), Color(0xFFC62828), 'Out of Stock');
    case 'critical':
      return const _SeverityStyle(Color(0xFFFFEBEE), _Ui.redText, _Ui.redText, 'Critical');
    case 'low':
      return const _SeverityStyle(Color(0xFFFFF4D6), _Ui.amberText, Color(0xFFE0A400), 'Low Stock');
    default:
      return const _SeverityStyle(Color(0xFFE8F5E9), _Ui.greenText, _Ui.green, 'In Stock');
  }
}

String _formatTime(String raw) {
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  return parsed == null ? raw : DateFormat('MMM d, h:mm a').format(parsed);
}

/// "Today, 10:24 AM" / "Yesterday, 4:02 PM" / "Jan 4, 2026".
String _formatLastUpdated(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  if (parsed == null) return raw;
  final now = DateTime.now();
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today, ${DateFormat('h:mm a').format(parsed)}';
  if (diff == 1) return 'Yesterday, ${DateFormat('h:mm a').format(parsed)}';
  return DateFormat('MMM d, yyyy').format(parsed);
}

InputDecoration _fieldDecoration({String? hint, String? label, IconData? icon, String? error, String? helper}) {
  return InputDecoration(
    hintText: hint,
    labelText: label,
    errorText: error,
    helperText: helper,
    helperMaxLines: 2,
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _Ui.muted),
    filled: true,
    fillColor: _Ui.fieldFill,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
  );
}

const _itemsPerPage = 8;

// ---------------------------------------------------------------------------
// Item photos
// ---------------------------------------------------------------------------

/// Turns what the server stored into a link the app can load. Photos kept on
/// Cloudinary are already full links; older ones are a path on our own server.
String? _fullImageUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return path;
  final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
  return '$base$path';
}

/// Lets the person choose a photo from their device. Returns null if they
/// cancel.
Future<(XFile, Uint8List)?> _pickPhoto() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1000);
  if (file == null) return null;
  return (file, await file.readAsBytes());
}

/// The item's photo in a rounded square, or its category icon if it has none
/// (or the photo can't be loaded).
class _ItemThumb extends StatelessWidget {
  final InventoryItem item;
  final double size;
  const _ItemThumb({required this.item, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final url = _fullImageUrl(item.image);
    final fallback = Center(child: Icon(_categoryIcon(item.category), size: size * 0.5, color: _Ui.tanDeep));
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _Ui.tanTint, borderRadius: BorderRadius.circular(10)),
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
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
  InventoryOverview? _overview;
  bool _loading = true;
  String? _error;
  String _categoryFilter = 'All'; // 'All' or a real category name
  String _query = '';
  int _page = 0;
  bool _downloadingReport = false;
  bool _showArchived = false; // false = the normal list, true = archived items

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
      final results = await Future.wait([_repo.getAll(archived: _showArchived), _repo.getOverview()]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<InventoryItem>;
        _overview = results[1] as InventoryOverview;
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

  /// Out of stock and critical first, then low, then the rest; A to Z inside each group.
  List<InventoryItem> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = _items.where((i) {
      if (!_showArchived && _categoryFilter != 'All') {
        final category = i.category.isEmpty ? 'Uncategorized' : i.category;
        if (category != _categoryFilter) return false;
      }
      if (q.isEmpty) return true;
      return i.ingredientName.toLowerCase().contains(q) || i.category.toLowerCase().contains(q);
    }).toList();

    const rank = {'out': 0, 'critical': 1, 'low': 2, 'ok': 3};
    list.sort((a, b) {
      final byRank = (rank[a.severity] ?? 9).compareTo(rank[b.severity] ?? 9);
      return byRank != 0 ? byRank : a.ingredientName.toLowerCase().compareTo(b.ingredientName.toLowerCase());
    });
    return list;
  }

  int get _pageCount => (_filtered.length / _itemsPerPage).ceil().clamp(1, 999999);

  List<InventoryItem> get _pageItems {
    final all = _filtered;
    final page = _page.clamp(0, _pageCount - 1);
    final start = page * _itemsPerPage;
    if (start >= all.length) return [];
    return all.sublist(start, (start + _itemsPerPage).clamp(0, all.length));
  }

  void _setCategoryFilter(String category) => setState(() {
        _categoryFilter = category;
        _page = 0;
      });

  // ---- actions ----

  // The add / edit form is a full page (not a dialog) because it has a photo
  // picker: the native file picker can crash a modal dialog on Flutter Web
  // (the same reason the menu's "Add Item" is a page).
  Future<void> _openAddItem() async {
    final created = await Navigator.of(context).push<InventoryItem>(
      MaterialPageRoute(builder: (_) => _ItemFormPage(repo: _repo)),
    );
    if (created == null) return;
    _load(showSpinner: false);
    _snack('Added ${created.ingredientName}');
  }

  Future<void> _editItem(InventoryItem item) async {
    final saved = await Navigator.of(context).push<InventoryItem>(
      MaterialPageRoute(builder: (_) => _ItemFormPage(repo: _repo, existing: item)),
    );
    if (saved == null) return;
    _load(showSpinner: false);
    _snack('Saved ${saved.ingredientName}');
  }

  /// Quick photo change from the row's ⋮ menu.
  Future<void> _changePhoto(InventoryItem item) async {
    try {
      final picked = await _pickPhoto();
      if (picked == null) return;
      final url = await _repo.uploadImage(bytes: picked.$2, filename: picked.$1.name);
      await _repo.setImage(item.inventoryId, url);
      _load(showSpinner: false);
      _snack('Photo updated for ${item.ingredientName}');
    } catch (e) {
      _snack('Could not update the photo: $e');
    }
  }

  /// Switches between the normal list and the archived items.
  void _toggleArchived() {
    setState(() {
      _showArchived = !_showArchived;
      _page = 0;
      _query = '';
      _categoryFilter = 'All';
      _searchController.clear();
    });
    _load();
  }

  Future<void> _archiveItem(InventoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _Ui.dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Archive ${item.ingredientName}?', style: const TextStyle(fontSize: 18)),
        content: const Text(
          'It will disappear from the inventory list, stock alerts, totals and reports. '
          'Its history is kept, and you can restore it any time from the Archived list.',
          style: TextStyle(fontSize: 13.5, color: _Ui.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _Ui.tanDeep, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _repo.setArchived(item.inventoryId, true);
      await _load(showSpinner: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.ingredientName} archived.'),
          action: SnackBarAction(label: 'Undo', onPressed: () => _restoreItem(item, quiet: true)),
        ),
      );
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _restoreItem(InventoryItem item, {bool quiet = false}) async {
    try {
      await _repo.setArchived(item.inventoryId, false);
      await _load(showSpinner: false);
      if (!quiet) _snack('${item.ingredientName} restored.');
    } catch (e) {
      _snack('$e');
    }
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

  /// What the "Current view" option of the report means right now, or null
  /// when no category or search is active (then it would just be "All items").
  String? get _viewLabel {
    final parts = <String>[
      if (_categoryFilter != 'All') _categoryFilter,
      if (_query.trim().isNotEmpty) 'search "${_query.trim()}"',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _downloadReport() async {
    if (_downloadingReport) return;
    if (_showArchived) {
      _snack('The report covers active items. Go back to the inventory to download it.');
      return;
    }

    final choice = await showDialog<_ReportChoice>(
      context: context,
      builder: (_) => _ReportDialog(viewLabel: _viewLabel, viewCount: _filtered.length, totalCount: _items.length),
    );
    if (choice == null) return;

    final useView = choice.scope == 'view';
    setState(() => _downloadingReport = true);
    try {
      final started = await _repo.downloadReport(
        format: choice.format,
        filter: choice.scope == 'low' || choice.scope == 'expiring' ? choice.scope : 'all',
        category: useView && _categoryFilter != 'All' ? _categoryFilter : null,
        search: useView && _query.trim().isNotEmpty ? _query.trim() : null,
      );
      _snack(started ? 'Downloading the ${choice.formatLabel} report…' : "Downloading isn't supported on this device yet.");
    } catch (e) {
      _snack('Could not download the report: $e');
    } finally {
      if (mounted) setState(() => _downloadingReport = false);
    }
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    final overview = _overview;
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1000;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PageHeader(onAdd: _openAddItem, onDownload: _downloadReport, downloading: _downloadingReport),
                    const SizedBox(height: 16),
                    if (overview != null) _StatCardsRow(overview: overview),
                    const SizedBox(height: 16),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: _itemsPanel(overview)),
                          const SizedBox(width: 16),
                          SizedBox(width: 340, child: _sidebar(overview)),
                        ],
                      )
                    else ...[
                      _itemsPanel(overview),
                      const SizedBox(height: 16),
                      _sidebar(overview),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _itemsPanel(InventoryOverview? overview) {
    final filtered = _filtered;
    final pageItems = _pageItems;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _showArchived ? 'Archived items' : 'Inventory Items',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _Ui.ink),
              ),
              const Spacer(),
              if (_showArchived || (overview?.archivedCount ?? 0) > 0)
                TextButton.icon(
                  onPressed: _toggleArchived,
                  icon: Icon(_showArchived ? Icons.arrow_back : Icons.archive_outlined, size: 16),
                  label: Text(_showArchived ? 'Back to inventory' : 'Archived (${overview?.archivedCount ?? 0})'),
                  style: TextButton.styleFrom(foregroundColor: _Ui.tanDeep),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() {
              _query = v;
              _page = 0;
            }),
            decoration: InputDecoration(
              hintText: 'Search ingredients or categories...',
              prefixIcon: const Icon(Icons.search, size: 20, color: _Ui.muted),
              filled: true,
              fillColor: _Ui.searchFill,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _Ui.tan)),
            ),
          ),
          const SizedBox(height: 12),
          if (overview != null && !_showArchived)
            _CategoryPills(
              totalItems: overview.totalItems,
              categories: overview.categories,
              selected: _categoryFilter,
              onSelected: _setCategoryFilter,
            ),
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            _EmptyState(hasItems: _items.isNotEmpty, archived: _showArchived)
          else ...[
            _ItemsTableHeader(),
            for (final item in pageItems)
              _ItemRow(
                item: item,
                onTap: () => _openDetail(item),
                onEdit: () => _editItem(item),
                onChangePhoto: () => _changePhoto(item),
                onAddDelivery: !_showArchived && item.needsRestock ? () => _quickDelivery(item) : null,
                onArchive: () => _archiveItem(item),
                onRestore: _showArchived ? () => _restoreItem(item) : null,
              ),
            const SizedBox(height: 10),
            _Pagination(
              total: filtered.length,
              page: _page,
              pageCount: _pageCount,
              perPage: _itemsPerPage,
              onPage: (p) => setState(() => _page = p),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sidebar(InventoryOverview? overview) {
    if (overview == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StockOverviewCard(overview: overview),
        const SizedBox(height: 16),
        _RecentActivityCard(activity: overview.recentActivity),
        if (overview.actionNeeded != null) ...[
          const SizedBox(height: 16),
          _ActionNeededCard(
            item: overview.actionNeeded!,
            onRestock: () => _quickDelivery(overview.actionNeeded!),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _PageHeader extends StatelessWidget {
  final VoidCallback onAdd;
  final VoidCallback onDownload;
  final bool downloading;
  const _PageHeader({required this.onAdd, required this.onDownload, required this.downloading});

  @override
  Widget build(BuildContext context) {
    final titleBlock = Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: _Ui.tanDeep, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 14),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inventory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _Ui.ink)),
            Text('Track stock, monitor usage and avoid waste', style: TextStyle(fontSize: 12, color: _Ui.muted)),
          ],
        ),
      ],
    );

    final buttons = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: downloading ? null : onDownload,
          icon: downloading
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download Report'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _Ui.tanDeep,
            side: const BorderSide(color: _Ui.tan),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Item'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _Ui.tanDeep,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return Row(children: [Expanded(child: titleBlock), buttons]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [titleBlock, const SizedBox(height: 14), buttons]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Download report: pick a format and what to include
// ---------------------------------------------------------------------------

class _ReportChoice {
  final String format; // 'pdf' | 'excel' | 'csv'
  final String scope; // 'view' | 'all' | 'low' | 'expiring'
  const _ReportChoice(this.format, this.scope);

  String get formatLabel => format == 'excel' ? 'Excel' : format.toUpperCase();
}

class _ReportDialog extends StatefulWidget {
  final String? viewLabel; // null when no category or search is active
  final int viewCount;
  final int totalCount;
  const _ReportDialog({required this.viewLabel, required this.viewCount, required this.totalCount});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String _format = 'pdf';
  late String _scope = widget.viewLabel != null ? 'view' : 'all';

  @override
  Widget build(BuildContext context) {
    const heading = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _Ui.muted);

    return AlertDialog(
      backgroundColor: _Ui.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Download report', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('FORMAT', style: heading),
              const SizedBox(height: 8),
              _OptionTile(
                icon: Icons.picture_as_pdf_outlined,
                title: 'PDF',
                subtitle: 'Easy to print or share',
                selected: _format == 'pdf',
                onTap: () => setState(() => _format = 'pdf'),
              ),
              _OptionTile(
                icon: Icons.table_chart_outlined,
                title: 'Excel (.xlsx)',
                subtitle: 'Formatted, with filters you can sort',
                selected: _format == 'excel',
                onTap: () => setState(() => _format = 'excel'),
              ),
              _OptionTile(
                icon: Icons.description_outlined,
                title: 'CSV',
                subtitle: 'Plain data for other programs',
                selected: _format == 'csv',
                onTap: () => setState(() => _format = 'csv'),
              ),
              const SizedBox(height: 14),
              const Text('WHAT TO INCLUDE', style: heading),
              const SizedBox(height: 8),
              if (widget.viewLabel != null)
                _OptionTile(
                  icon: Icons.filter_list,
                  title: 'Current view',
                  subtitle: '${widget.viewLabel} · ${widget.viewCount} items',
                  selected: _scope == 'view',
                  onTap: () => setState(() => _scope = 'view'),
                ),
              _OptionTile(
                icon: Icons.inventory_2_outlined,
                title: 'All items',
                subtitle: '${widget.totalCount} items in the inventory',
                selected: _scope == 'all',
                onTap: () => setState(() => _scope = 'all'),
              ),
              _OptionTile(
                icon: Icons.warning_amber_rounded,
                title: 'Low stock only',
                subtitle: 'Low, critical and out of stock',
                selected: _scope == 'low',
                onTap: () => setState(() => _scope = 'low'),
              ),
              _OptionTile(
                icon: Icons.schedule,
                title: 'Expiring soon only',
                subtitle: 'Expires within 7 days or already expired',
                selected: _scope == 'expiring',
                onTap: () => setState(() => _scope = 'expiring'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: _Ui.tanDeep, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(context).pop(_ReportChoice(_format, _scope)),
          icon: const Icon(Icons.download_outlined, size: 18),
          label: const Text('Download'),
        ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _Ui.tanTint : _Ui.fieldFill,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? _Ui.tanDeep : _Ui.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: selected ? _Ui.tanDeep : _Ui.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.ink)),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _Ui.muted)),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle, size: 20, color: _Ui.tanDeep),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat cards
// ---------------------------------------------------------------------------

class _StatCardsRow extends StatelessWidget {
  final InventoryOverview overview;
  const _StatCardsRow({required this.overview});

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[
      _StatCard(
        icon: Icons.inventory_2_outlined,
        color: _Ui.tanDeep,
        value: '${overview.totalItems}',
        label: 'Total Items',
        sublabel: '${overview.categories.length} categories',
      ),
      _StatCard(
        icon: Icons.warning_amber_rounded,
        color: _Ui.redText,
        value: '${overview.lowCount + overview.criticalCount}',
        label: 'Low Stock',
        sublabel: 'At or below the reorder level',
      ),
      _StatCard(
        icon: Icons.schedule,
        color: _Ui.amberText,
        value: '${overview.expiringCount}',
        label: 'Expiring Soon',
        sublabel: 'Within 7 days',
      ),
      _StatCard(
        icon: Icons.payments_outlined,
        color: _Ui.greenText,
        value: _fmtMoney(overview.totalValue),
        label: 'Total Value',
        sublabel: overview.pricedCount == overview.totalItems
            ? 'All items priced'
            : 'Based on ${overview.pricedCount} of ${overview.totalItems} priced items',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;
        final columns = constraints.maxWidth >= 900 ? 4 : (constraints.maxWidth >= 560 ? 2 : 1);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: cards.map((c) => SizedBox(width: width, child: c)).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String sublabel;
  const _StatCard({required this.icon, required this.color, required this.value, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _Ui.ink)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: _Ui.muted)),
          const SizedBox(height: 4),
          Text(sublabel, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category pills
// ---------------------------------------------------------------------------

class _CategoryPills extends StatelessWidget {
  final int totalItems;
  final List<InventoryCategoryCount> categories;
  final String selected;
  final ValueChanged<String> onSelected;
  const _CategoryPills({required this.totalItems, required this.categories, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _pill('All', 'All Items', totalItems),
          for (final c in categories) ...[
            const SizedBox(width: 8),
            _pill(c.category, c.category, c.count),
          ],
        ],
      ),
    );
  }

  Widget _pill(String key, String label, int count) {
    final isSelected = key == selected;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: isSelected ? _Ui.tanDeep : _Ui.pillIdle,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onSelected(key),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              '$label ($count)',
              style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: isSelected ? Colors.white : _Ui.ink),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Items table
// ---------------------------------------------------------------------------

class _ItemsTableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _Ui.muted);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: const [
              SizedBox(width: 46 + 10), // photo + gap
              Expanded(flex: 3, child: Text('ITEM', style: style)),
              Expanded(flex: 2, child: Text('CATEGORY', style: style)),
              Expanded(flex: 2, child: Text('CURRENT STOCK', style: style)),
              Expanded(flex: 2, child: Text('STATUS', style: style)),
              Expanded(flex: 2, child: Text('LAST UPDATED', style: style)),
              SizedBox(width: 32),
            ],
          ),
        );
      },
    );
  }
}

class _ItemRow extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onChangePhoto;
  final VoidCallback? onAddDelivery;
  final VoidCallback onArchive;

  /// Set only when the row is in the Archived list: the only action is then "Restore".
  final VoidCallback? onRestore;
  const _ItemRow({
    required this.item,
    required this.onTap,
    required this.onEdit,
    required this.onChangePhoto,
    required this.onAddDelivery,
    required this.onArchive,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final style = _severityStyle(item.severity);
    final thumbnail = _ItemThumb(item: item);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: style.dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(style.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: style.fg)),
        ],
      ),
    );
    final menu = PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18, color: _Ui.muted),
      onSelected: (v) {
        if (v == 'open') onTap();
        if (v == 'edit') onEdit();
        if (v == 'photo') onChangePhoto();
        if (v == 'delivery' && onAddDelivery != null) onAddDelivery!();
        if (v == 'archive') onArchive();
        if (v == 'restore' && onRestore != null) onRestore!();
      },
      itemBuilder: (_) => onRestore != null
          ? const [PopupMenuItem(value: 'restore', child: Text('Restore'))]
          : [
              const PopupMenuItem(value: 'open', child: Text('View details')),
              const PopupMenuItem(value: 'edit', child: Text('Edit item')),
              PopupMenuItem(value: 'photo', child: Text(item.hasImage ? 'Change photo' : 'Add photo')),
              if (onAddDelivery != null) const PopupMenuItem(value: 'delivery', child: Text('Add delivery')),
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
            ],
    );

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onRestore != null ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              if (wide) {
                return Row(
                  children: [
                    thumbnail,
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.ingredientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _Ui.ink)),
                          Text(
                            item.storageLocation == null ? item.unit : '${item.unit} · ${item.storageLocation}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: _Ui.muted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(flex: 2, child: Text(item.category.isEmpty ? 'Uncategorized' : item.category, style: const TextStyle(fontSize: 12, color: _Ui.ink))),
                    Expanded(flex: 2, child: Text('${_fmtQty(item.quantity)} ${item.unit}', style: const TextStyle(fontSize: 12, color: _Ui.ink))),
                    Expanded(flex: 2, child: Align(alignment: Alignment.centerLeft, child: badge)),
                    Expanded(flex: 2, child: Text(_formatLastUpdated(item.lastUpdated), style: const TextStyle(fontSize: 11, color: _Ui.muted))),
                    SizedBox(width: 32, child: menu),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  thumbnail,
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.ingredientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _Ui.ink)),
                        Text('${item.category.isEmpty ? 'Uncategorized' : item.category} · ${_fmtQty(item.quantity)} ${item.unit}', style: const TextStyle(fontSize: 11, color: _Ui.muted)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [badge, Text(_formatLastUpdated(item.lastUpdated), style: const TextStyle(fontSize: 11, color: _Ui.muted))]),
                      ],
                    ),
                  ),
                  menu,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int total;
  final int page;
  final int pageCount;
  final int perPage;
  final ValueChanged<int> onPage;
  const _Pagination({required this.total, required this.page, required this.pageCount, required this.perPage, required this.onPage});

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : page * perPage + 1;
    final end = ((page + 1) * perPage).clamp(0, total);

    final pageButtons = <Widget>[];
    for (var i = 0; i < pageCount; i++) {
      final selected = i == page;
      pageButtons.add(
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Material(
            color: selected ? _Ui.tanDeep : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onPage(i),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : _Ui.ink)),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text('Showing $start-$end of $total items', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: pageButtons),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar: Stock Overview donut
// ---------------------------------------------------------------------------

class _StockOverviewCard extends StatelessWidget {
  final InventoryOverview overview;
  const _StockOverviewCard({required this.overview});

  @override
  Widget build(BuildContext context) {
    final total = overview.totalItems;
    final slices = [
      ('In Stock', overview.okCount, _Ui.green),
      ('Low Stock', overview.lowCount, const Color(0xFFE0A400)),
      ('Critical', overview.criticalCount, _Ui.redText),
      ('Out of Stock', overview.outCount, const Color(0xFF8D8D8D)),
    ].where((s) => s.$2 > 0).toList();

    return _SidebarCard(
      title: 'Stock Overview',
      child: total == 0
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No items yet.', style: TextStyle(color: _Ui.muted))))
          : Column(
              children: [
                SizedBox(
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 54,
                          sections: [
                            for (final s in slices)
                              PieChartSectionData(value: s.$2.toDouble(), color: s.$3, radius: 26, title: '', showTitle: false),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: _Ui.ink)),
                          const Text('Total Items', style: TextStyle(fontSize: 11, color: _Ui.muted)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (final s in slices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(width: 9, height: 9, decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(s.$1, style: const TextStyle(fontSize: 12, color: _Ui.ink))),
                        Text('${s.$2} (${(s.$2 / total * 100).round()}%)', style: const TextStyle(fontSize: 12, color: _Ui.muted)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar: Recent Activity
// ---------------------------------------------------------------------------

class _RecentActivityCard extends StatelessWidget {
  final List<InventoryActivity> activity;
  const _RecentActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    return _SidebarCard(
      title: 'Recent Activity',
      child: activity.isEmpty
          ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No stock changes recorded yet.', style: TextStyle(fontSize: 12, color: _Ui.muted)))
          : Column(
              children: [
                for (var i = 0; i < activity.length; i++) ...[
                  _ActivityRow(entry: activity[i]),
                  if (i < activity.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final InventoryActivity entry;
  const _ActivityRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isIn = entry.quantity >= 0;
    final color = (entry.type == 'usage' || entry.type == 'waste') ? _Ui.redText : (isIn ? _Ui.greenText : _Ui.amberText);
    final verb = entry.type == 'delivery'
        ? 'added to inventory'
        : entry.type == 'waste'
            ? (entry.reason.isEmpty ? 'written off as waste' : 'wasted (${entry.reason.toLowerCase()})')
            : entry.type == 'usage'
            ? (entry.orderId != null ? 'used for order #${entry.orderId}' : 'used from inventory')
            : entry.type == 'return'
                ? (entry.orderId != null ? 'returned from order #${entry.orderId}' : 'returned to inventory')
                : 'stock adjusted';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          margin: const EdgeInsets.only(top: 1),
          decoration: BoxDecoration(color: color.withOpacity(0.14), shape: BoxShape.circle),
          child: Icon(isIn ? Icons.add : Icons.remove, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 12.5, color: _Ui.ink),
                  children: [
                    TextSpan(text: entry.ingredientName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: ' $verb'),
                  ],
                ),
              ),
              Text('${isIn ? '+' : ''}${_fmtQty(entry.quantity)} · ${_formatTime(entry.time)}', style: const TextStyle(fontSize: 11, color: _Ui.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar: Action Needed
// ---------------------------------------------------------------------------

class _ActionNeededCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback onRestock;
  const _ActionNeededCard({required this.item, required this.onRestock});

  @override
  Widget build(BuildContext context) {
    final verb = item.isOut ? 'is out of stock' : 'is running low';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFFFFF4E8), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF3D9B8))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.priority_high_rounded, size: 18, color: _Ui.amberText),
              const SizedBox(width: 8),
              const Text('Action Needed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _Ui.amberText)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${item.ingredientName} $verb (${_fmtQty(item.quantity)} ${item.unit} left). Consider ordering soon to avoid stockouts.',
            style: const TextStyle(fontSize: 12.5, color: _Ui.ink, height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRestock,
              icon: const Icon(Icons.add_shopping_cart, size: 16),
              label: const Text('Restock this item'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _Ui.tanDeep,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SidebarCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _Ui.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _Ui.ink)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool hasItems;
  final bool archived;
  const _EmptyState({required this.hasItems, this.archived = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Text(
          archived
              ? (hasItems ? 'No archived items match your search.' : 'Nothing is archived.')
              : (hasItems ? 'No items match your search or filter.' : 'No inventory items yet. Tap "Add Item" to start.'),
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
// Record waste (quantity + reason)
// ---------------------------------------------------------------------------

class _WasteEntry {
  final double quantity;
  final String reason;
  const _WasteEntry(this.quantity, this.reason);
}

class _WasteDialog extends StatefulWidget {
  final String unit;
  final double inStock;
  const _WasteDialog({required this.unit, required this.inStock});

  @override
  State<_WasteDialog> createState() => _WasteDialogState();
}

class _WasteDialogState extends State<_WasteDialog> {
  final _controller = TextEditingController();
  String _reason = _wasteReasons.first;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a number greater than zero');
      return;
    }
    if (value > widget.inStock) {
      setState(() => _error = 'Only ${_fmtQty(widget.inStock)} ${widget.unit} in stock');
      return;
    }
    Navigator.of(context).pop(_WasteEntry(_round2(value), _reason));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _Ui.dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Record waste', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'In stock: ${_fmtQty(widget.inStock)} ${widget.unit}. This removes the amount from stock and keeps the reason in the history.',
              style: const TextStyle(fontSize: 13, color: _Ui.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _submit(),
              decoration: _fieldDecoration(hint: 'Quantity (${widget.unit})', error: _error),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              decoration: _fieldDecoration(),
              items: _wasteReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => _reason = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _Ui.tanDeep, foregroundColor: Colors.white),
          onPressed: _submit,
          child: const Text('Record waste'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Add / edit item form (a full page, see _openAddItem for why)
// ---------------------------------------------------------------------------

class _ItemFormPage extends StatefulWidget {
  final InventoryRepository repo;
  final InventoryItem? existing;
  const _ItemFormPage({required this.repo, this.existing});

  @override
  State<_ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<_ItemFormPage> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.ingredientName ?? '');
  late final TextEditingController _current = TextEditingController();
  late final TextEditingController _max = TextEditingController(
    text: (widget.existing != null && widget.existing!.maxStock > 0) ? _plain(widget.existing!.maxStock) : '',
  );
  late final TextEditingController _cost = TextEditingController(
    text: (widget.existing != null && widget.existing!.unitCost > 0) ? _plain(widget.existing!.unitCost) : '',
  );
  late final TextEditingController _reorder = TextEditingController(
    text: widget.existing?.reorderLevel != null ? _plain(widget.existing!.reorderLevel!) : '',
  );
  late final TextEditingController _supplier = TextEditingController(text: widget.existing?.supplierName ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.existing?.supplierPhone ?? '');
  late final TextEditingController _notes = TextEditingController(text: widget.existing?.notes ?? '');
  String? _location;
  String? _unit;
  String? _category;
  DateTime? _expiryDate;

  // Photo: a newly chosen one, or the existing one marked for removal.
  XFile? _pickedImage;
  Uint8List? _previewBytes;
  bool _removePhoto = false;

  String? _nameError;
  String? _currentError;
  String? _maxError;
  String? _unitError;
  String? _categoryError;
  String? _costError;
  String? _reorderError;
  String? _phoneError;
  String? _error;
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _unit = widget.existing?.unit;
    _location = widget.existing?.storageLocation;
    final category = widget.existing?.category ?? '';
    _category = category.isEmpty ? null : category;
    final expiry = widget.existing?.expiryDate;
    _expiryDate = (expiry != null && expiry.isNotEmpty) ? DateTime.tryParse(expiry) : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _current.dispose();
    _max.dispose();
    _cost.dispose();
    _reorder.dispose();
    _supplier.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _choosePhoto() async {
    try {
      final picked = await _pickPhoto();
      if (picked == null || !mounted) return;
      setState(() {
        _pickedImage = picked.$1;
        _previewBytes = picked.$2;
        _removePhoto = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't open the photo: $e");
    }
  }

  void _clearPhoto() {
    setState(() {
      _pickedImage = null;
      _previewBytes = null;
      _removePhoto = widget.existing?.hasImage ?? false;
    });
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final max = double.tryParse(_max.text.trim());
    final current = _editing ? null : double.tryParse(_current.text.trim());
    final costText = _cost.text.trim();
    final cost = costText.isEmpty ? 0.0 : double.tryParse(costText);
    final reorderText = _reorder.text.trim();
    final reorder = reorderText.isEmpty ? null : double.tryParse(reorderText);
    final phone = _phone.text.trim();

    String? nameError;
    String? currentError;
    String? maxError;
    String? unitError;
    String? categoryError;
    String? costError;
    String? reorderError;
    String? phoneError;

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
    if (costText.isNotEmpty && (cost == null || cost < 0)) costError = 'Enter a cost of zero or more';
    if (reorderText.isNotEmpty) {
      if (reorder == null || reorder <= 0) {
        reorderError = 'Enter a number above zero';
      } else if (max != null && max > 0 && reorder > max) {
        reorderError = "Can't be more than max stock";
      }
    }
    if (phone.isNotEmpty && !RegExp(r'^[0-9+()\-\s]+$').hasMatch(phone)) {
      phoneError = 'Use digits, spaces and + ( ) -';
    }

    setState(() {
      _nameError = nameError;
      _currentError = currentError;
      _maxError = maxError;
      _unitError = unitError;
      _categoryError = categoryError;
      _costError = costError;
      _reorderError = reorderError;
      _phoneError = phoneError;
      _error = null;
    });
    if ([nameError, currentError, maxError, unitError, categoryError, costError, reorderError, phoneError].any((e) => e != null)) {
      return;
    }

    final expiryStr = _expiryDate == null ? null : DateFormat('yyyy-MM-dd').format(_expiryDate!);

    setState(() => _saving = true);
    try {
      // null = leave the photo alone, '' = remove it, anything else = the new link.
      String? imageArg;
      if (_previewBytes != null && _pickedImage != null) {
        imageArg = await widget.repo.uploadImage(bytes: _previewBytes!, filename: _pickedImage!.name);
      } else if (_removePhoto) {
        imageArg = '';
      }

      final InventoryItem saved;
      if (_editing) {
        saved = await widget.repo.update(
          widget.existing!.inventoryId,
          ingredientName: name,
          unit: _unit!,
          maxStock: max!,
          category: _category ?? '',
          expiryDate: expiryStr ?? '',
          unitCost: cost,
          image: imageArg,
          reorderLevel: reorder,
          supplierName: _supplier.text.trim(),
          supplierPhone: phone,
          storageLocation: _location ?? '',
          notes: _notes.text.trim(),
        );
      } else {
        saved = await widget.repo.create(
          ingredientName: name,
          quantity: current!,
          unit: _unit!,
          maxStock: max,
          category: _category ?? '',
          expiryDate: expiryStr,
          unitCost: cost,
          image: imageArg,
          reorderLevel: reorder,
          supplierName: _supplier.text.trim(),
          supplierPhone: phone,
          storageLocation: _location,
          notes: _notes.text.trim(),
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
      initialValue: value,
      isExpanded: true,
      hint: Text(hint, style: const TextStyle(color: _Ui.muted)),
      decoration: _fieldDecoration(error: error),
      items: all.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
      onChanged: _saving ? null : onChanged,
    );
  }

  Widget _expiryField() {
    return InkWell(
      onTap: _saving ? null : _pickExpiryDate,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _fieldDecoration(icon: Icons.event_outlined).copyWith(
          suffixIcon: _expiryDate == null
              ? null
              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _saving ? null : () => setState(() => _expiryDate = null)),
        ),
        child: Text(
          _expiryDate == null ? 'No expiry date (optional)' : DateFormat('MMM d, yyyy').format(_expiryDate!),
          style: TextStyle(color: _expiryDate == null ? _Ui.muted : _Ui.ink, fontSize: 14),
        ),
      ),
    );
  }

  Widget _photoPicker() {
    const size = 96.0;
    final existingUrl = _removePhoto ? null : _fullImageUrl(widget.existing?.image);
    final hasPhoto = _previewBytes != null || existingUrl != null;

    final Widget inner;
    if (_previewBytes != null) {
      inner = Image.memory(_previewBytes!, fit: BoxFit.cover, width: size, height: size);
    } else if (existingUrl != null) {
      inner = Image.network(
        existingUrl,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_outlined, color: _Ui.muted)),
      );
    } else {
      inner = const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, color: _Ui.muted, size: 26),
          SizedBox(height: 4),
          Text('Add photo', style: TextStyle(fontSize: 11, color: _Ui.muted)),
        ],
      );
    }

    return Row(
      children: [
        GestureDetector(
          onTap: _saving ? null : _choosePhoto,
          child: Container(
            width: size,
            height: size,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _Ui.fieldFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _Ui.border),
            ),
            child: inner,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Item photo (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _Ui.ink)),
              const SizedBox(height: 2),
              const Text('A clear photo helps staff spot the right item quickly.', style: TextStyle(fontSize: 12, color: _Ui.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: _saving ? null : _choosePhoto,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(hasPhoto ? 'Change' : 'Choose photo'),
                    style: TextButton.styleFrom(foregroundColor: _Ui.tanDeep),
                  ),
                  if (hasPhoto)
                    TextButton.icon(
                      onPressed: _saving ? null : _clearPhoto,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'),
                      style: TextButton.styleFrom(foregroundColor: _Ui.redText),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      if (!_editing) _textField(_current, 'Current stock', error: _currentError, number: true),
      _textField(_max, 'Max stock', error: _maxError, number: true),
      _textField(_reorder, 'Reorder level (optional)', icon: Icons.notifications_active_outlined, error: _reorderError, number: true),
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
      _dropdown(
        hint: 'Storage location (optional)',
        value: _location,
        options: const [_noLocation, ..._locations],
        error: null,
        onChanged: (v) => setState(() => _location = v == _noLocation ? null : v),
      ),
      _textField(_cost, 'Cost per unit (optional)', icon: Icons.payments_outlined, error: _costError, number: true),
      _expiryField(),
      _textField(_supplier, 'Supplier (optional)', icon: Icons.local_shipping_outlined),
      _textField(_phone, 'Supplier phone (optional)', icon: Icons.phone_outlined, error: _phoneError),
    ];

    return Scaffold(
      backgroundColor: _Ui.dialogBg,
      appBar: AppBar(
        title: Text(_editing ? 'Edit inventory item' : 'Add inventory item'),
        backgroundColor: _Ui.tanDeep,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _photoPicker(),
                const SizedBox(height: 20),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  enabled: !_saving,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: _fieldDecoration(hint: 'Notes (optional), e.g. keep frozen, use within 2 days of opening'),
                ),
                const SizedBox(height: 6),
                const Text(
                  'An item counts as low stock at its reorder level, or at 30% of max stock if you leave the reorder level blank, '
                  'and as critical at a third of that. '
                  'Measure ingredients by weight or volume in g or ml (not kg or L) so recipes can use small amounts. '
                  'Changing the unit does not convert the numbers, so use Correct count afterwards. '
                  "Everything marked optional can be left blank.",
                  style: TextStyle(fontSize: 12, color: _Ui.muted),
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

  Future<void> _waste() async {
    final entry = await showDialog<_WasteEntry>(
      context: context,
      builder: (_) => _WasteDialog(unit: _item.unit, inStock: _item.quantity),
    );
    if (entry == null) return;
    await _apply(() => widget.repo.adjustStock(_item.inventoryId, entry.quantity, 'waste', reason: entry.reason));
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
    final saved = await Navigator.of(context).push<InventoryItem>(
      MaterialPageRoute(builder: (_) => _ItemFormPage(repo: widget.repo, existing: _item)),
    );
    if (saved == null || !mounted) return;
    setState(() => _item = saved);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.88;
    final style = _severityStyle(_item.severity);
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
                  _ItemThumb(item: _item, size: 56),
                  const SizedBox(width: 14),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(20)),
                    child: Text(style.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: style.fg)),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_fmtQty(_item.quantity)} / ${_fmtWhole(_item.capacity)} ${_item.unit}',
                    style: const TextStyle(fontSize: 15, color: _Ui.ink),
                  ),
                  const Spacer(),
                  Text(
                    '${_item.percent}%',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: style.fg),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _item.fraction,
                  minHeight: 6,
                  color: style.dot,
                  backgroundColor: _Ui.track,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  if (_item.unitCost > 0)
                    _DetailFact(label: 'Stock value', value: _fmtMoney(_item.stockValue)),
                  _DetailFact(
                    label: 'Reorder level',
                    value: '${_fmtQty(_item.minimumStock)} ${_item.unit}${_item.hasCustomReorder ? '' : ' (default)'}',
                  ),
                  if (_item.storageLocation != null) _DetailFact(label: 'Stored in', value: _item.storageLocation!),
                  if (_item.supplierName != null || _item.supplierPhone != null)
                    _DetailFact(
                      label: 'Supplier',
                      value: [if (_item.supplierName != null) _item.supplierName!, if (_item.supplierPhone != null) _item.supplierPhone!].join(' · '),
                    ),
                  if (_item.hasExpiryDate)
                    _DetailFact(
                      label: _item.isExpired ? 'Expired' : (_item.isExpiringSoon ? 'Expires soon' : 'Expires'),
                      value: DateFormat('MMM d, yyyy').format(DateTime.parse(_item.expiryDate!)),
                      valueColor: _item.isExpired || _item.isExpiringSoon ? _Ui.redText : null,
                    ),
                ],
              ),
              if (_item.notes != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _Ui.fieldFill, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 16, color: _Ui.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_item.notes!, style: const TextStyle(fontSize: 12.5, color: _Ui.ink))),
                    ],
                  ),
                ),
              ],
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
                    onPressed: _busy ? null : _waste,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: const Text('Record waste'),
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

class _DetailFact extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailFact({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: _Ui.muted)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? _Ui.ink)),
      ],
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
      case 'waste':
        icon = Icons.delete_sweep_outlined;
        color = _Ui.redText;
        label = entry.reason.isEmpty ? 'Waste' : 'Waste: ${entry.reason}';
        break;
      case 'usage':
        icon = Icons.remove_circle_outline;
        color = _Ui.redText;
        label = entry.orderId != null ? 'Used for order #${entry.orderId}' : 'Usage';
        break;
      case 'return':
        icon = Icons.undo;
        color = _Ui.greenText;
        label = entry.orderId != null ? 'Returned (order #${entry.orderId} cancelled)' : 'Returned';
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