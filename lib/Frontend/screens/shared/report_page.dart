import 'package:flutter/material.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  Future<void> _openReport(BuildContext context, String endpoint, String label) async {
    // In a full build this fetches /reports/<endpoint>?format=pdf|excel via
    // ApiService and pushes the bytes to the `printing` package (PDF) or
    // triggers a file download (Excel). Wire that up once the backend URL
    // is live — the endpoints and formats are already implemented server-side.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fetching $label report...')));
  }

  @override
  Widget build(BuildContext context) {
    final reports = [
      ('Daily Sales Report', 'sales'),
      ('Best-Selling Items', 'best-sellers'),
      ('Inventory Report', 'inventory'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: reports.map((r) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: Text(r.$1),
            trailing: Wrap(spacing: 8, children: [
              TextButton(onPressed: () => _openReport(context, r.$2, r.$1), child: const Text('PDF')),
              TextButton(onPressed: () => _openReport(context, r.$2, r.$1), child: const Text('Excel')),
            ]),
          ),
        );
      }).toList(),
    );
  }
}