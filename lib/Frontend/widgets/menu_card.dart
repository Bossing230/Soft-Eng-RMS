import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../core/constants/app_constants.dart';

class MenuCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggleAvailability;

  /// Optional actions. A menu entry only appears when its callback is given.
  final VoidCallback? onRecipe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete; // asks for confirmation before calling this

  const MenuCard({
    super.key,
    required this.item,
    this.onTap,
    this.onToggleAvailability,
    this.onRecipe,
    this.onEdit,
    this.onDelete,
  });

  static const _grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  String get _fullImageUrl {
    final path = item.image;
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
    return '$base$path';
  }

  bool get _hasImage => item.image != null && item.image!.isNotEmpty;

  /// Hide empty or placeholder descriptions such as "N/A".
  bool get _showDescription {
    final d = item.description.trim().toLowerCase();
    return d.isNotEmpty && d != 'n/a' && d != 'na' && d != '-';
  }

  /// Bottle/can shots are usually tall product photos on white, so they are
  /// shown whole (contain) instead of being cropped.
  bool get _isDrink => (item.station ?? '').toLowerCase() == 'drinks';

  Widget _placeholder({IconData icon = Icons.restaurant}) => Container(
        color: Colors.grey[200],
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.grey[500], size: 36),
      );

  Widget _buildImage() {
    if (!_hasImage) return _placeholder();

    Widget image = Image.network(
      _fullImageUrl,
      fit: _isDrink ? BoxFit.contain : BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        final total = progress.expectedTotalBytes;
        return Container(
          color: Colors.grey[100],
          alignment: Alignment.center,
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: total == null ? null : progress.cumulativeBytesLoaded / total,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(icon: Icons.image_not_supported_outlined),
    );

    if (!item.isAvailable) {
      image = ColorFiltered(
        colorFilter: _grayscale,
        child: Opacity(opacity: 0.55, child: image),
      );
    }

    return Container(color: _isDrink ? Colors.white : Colors.grey[100], child: image);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('"${item.foodName}" will be removed from the menu. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) onDelete?.call();
  }

  Widget _badge(String text, {Color? bg, Color fg = Colors.white}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _optionsButton(BuildContext context) {
    final hasActions = onRecipe != null || onEdit != null || onDelete != null;
    if (!hasActions) return const SizedBox.shrink();

    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 1,
      child: PopupMenuButton<String>(
        tooltip: 'Options',
        padding: EdgeInsets.zero,
        onSelected: (v) {
          switch (v) {
            case 'recipe':
              onRecipe?.call();
              break;
            case 'edit':
              onEdit?.call();
              break;
            case 'delete':
              _confirmDelete(context);
              break;
          }
        },
        itemBuilder: (_) => [
          if (onEdit != null)
            const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit item'), dense: true)),
          if (onRecipe != null)
            const PopupMenuItem(value: 'recipe', child: ListTile(leading: Icon(Icons.menu_book_outlined), title: Text('Edit recipe'), dense: true)),
          if (onDelete != null)
            const PopupMenuItem(
              value: 'delete',
              child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)), dense: true),
            ),
        ],
        child: const SizedBox(width: 34, height: 34, child: Icon(Icons.more_vert, size: 18)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = (item.categoryName ?? '').trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image takes all the height left over, so the card has no empty gap.
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildImage(),
                  if (category.isNotEmpty)
                    Positioned(top: 8, left: 8, child: _badge(category, bg: Colors.black54)),
                  Positioned(top: 8, right: 8, child: _optionsButton(context)),
                  if (!item.isAvailable)
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        child: _badge('SOLD OUT', bg: Colors.red.shade700),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.foodName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (_showDescription) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '₱${item.price.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: scheme.primary),
                        ),
                      ),
                      if (onToggleAvailability != null) ...[
                        Text(
                          item.isAvailable ? 'Available' : 'Sold out',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: item.isAvailable ? scheme.secondary : Colors.red.shade700,
                          ),
                        ),
                        Switch(
                          value: item.isAvailable,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (_) => onToggleAvailability!(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}