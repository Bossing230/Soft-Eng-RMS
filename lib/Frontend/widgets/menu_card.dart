import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/menu.dart';
import '../core/constants/app_constants.dart';

class MenuCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback? onTap;
  final VoidCallback? onToggleAvailability;

  const MenuCard({super.key, required this.item, this.onTap, this.onToggleAvailability});

  String get _fullImageUrl {
    final path = item.image;
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
    return '$base$path';
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.image != null && item.image!.isNotEmpty)
              Container(
                height: 120,
                width: double.infinity,
                color: Colors.grey[100],
                child: Image.network(
                  _fullImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[200],
                    child: const Icon(Icons.image_not_supported, color: Colors.grey),
                  ),
                ),
              )
            else
              Container(
                height: 120,
                width: double.infinity,
                color: Colors.grey[100],
                child: const Icon(Icons.restaurant, color: Colors.grey, size: 32),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.foodName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      if (!item.isAvailable)
                        const Chip(label: Text('Unavailable', style: TextStyle(fontSize: 10)), visualDensity: VisualDensity.compact),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('₱${item.price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (onToggleAvailability != null)
                        Switch(value: item.isAvailable, onChanged: (_) => onToggleAvailability!()),
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