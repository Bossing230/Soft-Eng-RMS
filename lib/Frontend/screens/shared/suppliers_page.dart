import 'package:flutter/material.dart';
import 'package:rms/Frontend/models/supplier.dart';
import 'package:rms/Frontend/repositories/supplier_repository.dart';

const _border = Color(0xFFEBE3D8);
const _tan = Color(0xFFD4A574);
const _tanDeep = Color(0xFFB98A5E);
const _tanTint = Color(0xFFF0DFCF);
const _fieldFill = Color(0xFFFBF5F0);
const _dialogBg = Color(0xFFF6E7DB);
const _searchFill = Color(0xFFF1EBE4);
const _ink = Color(0xFF2B2B2B);
const _muted = Color(0xFF7A7A7A);
const _red = Color(0xFFE53935);

InputDecoration _decoration(String hint, {IconData? icon, String? error}) => InputDecoration(
      hintText: hint,
      errorText: error,
      prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _muted),
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );

/// Suppliers for Admin and Manager: list, add, edit and delete.
class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _repo = SupplierRepository();
  List<Supplier> _suppliers = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) setState(() => _loading = true);
    try {
      final data = await _repo.getAll();
      if (!mounted) return;
      setState(() {
        _suppliers = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Supplier> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _suppliers;
    return _suppliers
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.contactPerson ?? '').toLowerCase().contains(q) ||
            (s.phone ?? '').contains(q))
        .toList();
  }

  Future<void> _openForm([Supplier? existing]) async {
    final values = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _SupplierDialog(existing: existing),
    );
    if (values == null) return;
    try {
      if (existing == null) {
        await _repo.create(
          name: values['name']!,
          contactPerson: values['contactPerson']!,
          phone: values['phone']!,
          email: values['email']!,
          address: values['address']!,
          notes: values['notes']!,
        );
      } else {
        await _repo.update(
          existing.supplierId,
          name: values['name']!,
          contactPerson: values['contactPerson']!,
          phone: values['phone']!,
          email: values['email']!,
          address: values['address']!,
          notes: values['notes']!,
        );
      }
      await _load(showSpinner: false);
      _snack(existing == null ? 'Supplier added' : 'Supplier saved');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _delete(Supplier s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete ${s.name}?', style: const TextStyle(fontSize: 18)),
        content: const Text(
          'Past expenses keep their amounts but will no longer show this supplier. '
          'Ingredients that name this supplier keep their text as it is.',
          style: TextStyle(fontSize: 13.5, color: _muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.remove(s.supplierId);
      await _load(showSpinner: false);
      _snack('${s.name} deleted');
    } catch (e) {
      _snack('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40, color: _muted),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final list = _filtered;
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(color: _tanDeep, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.local_shipping_outlined, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Suppliers', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _ink)),
                          Text('Who we buy ingredients from', style: TextStyle(fontSize: 12, color: _muted)),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openForm(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Supplier'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tanDeep,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search suppliers...',
                    prefixIcon: const Icon(Icons.search, size: 20, color: _muted),
                    filled: true,
                    fillColor: _searchFill,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _tan)),
                  ),
                ),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        _suppliers.isEmpty ? 'No suppliers yet. Tap "Add Supplier" to start.' : 'No suppliers match your search.',
                        style: const TextStyle(color: _muted),
                      ),
                    ),
                  )
                else
                  for (final s in list) _SupplierCard(supplier: s, onEdit: () => _openForm(s), onDelete: () => _delete(s)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _SupplierCard({required this.supplier, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final details = [
      if (supplier.contactPerson != null) supplier.contactPerson!,
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: _tanTint, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.storefront_outlined, color: _tanDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(supplier.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _ink)),
                if (details.isNotEmpty) Text(details, style: const TextStyle(fontSize: 12.5, color: _muted)),
                if (supplier.address != null) Text(supplier.address!, style: const TextStyle(fontSize: 12, color: _muted)),
                if (supplier.notes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(supplier.notes!, style: const TextStyle(fontSize: 12, color: _ink)),
                  ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: _tanTint, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${supplier.ingredientCount} ${supplier.ingredientCount == 1 ? 'ingredient' : 'ingredients'}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _tanDeep),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18, color: _muted),
            onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  final Supplier? existing;
  const _SupplierDialog({this.existing});

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _contact = TextEditingController(text: widget.existing?.contactPerson ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _email = TextEditingController(text: widget.existing?.email ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  String? _nameError;
  String? _phoneError;
  String? _emailError;

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _email, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Enter the supplier name' : null;
      _phoneError = phone.isNotEmpty && !RegExp(r'^[0-9+()\-\s]+$').hasMatch(phone) ? 'Use digits, spaces and + ( ) -' : null;
      _emailError = email.isNotEmpty && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ? 'Enter a valid email' : null;
    });
    if (_nameError != null || _phoneError != null || _emailError != null) return;
    Navigator.of(context).pop({
      'name': name,
      'contactPerson': _contact.text.trim(),
      'phone': phone,
      'email': email,
      'address': _address.text.trim(),
      'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const SizedBox(height: 12);
    return AlertDialog(
      backgroundColor: _dialogBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.existing == null ? 'Add supplier' : 'Edit supplier', style: const TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _name, autofocus: true, decoration: _decoration('Supplier name', icon: Icons.storefront_outlined, error: _nameError)),
              gap(),
              TextField(controller: _contact, decoration: _decoration('Contact person (optional)', icon: Icons.person_outline)),
              gap(),
              TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _decoration('Phone (optional)', icon: Icons.phone_outlined, error: _phoneError)),
              gap(),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _decoration('Email (optional)', icon: Icons.email_outlined, error: _emailError)),
              gap(),
              TextField(controller: _address, decoration: _decoration('Address (optional)', icon: Icons.place_outlined)),
              gap(),
              TextField(controller: _notes, maxLines: 2, decoration: _decoration('Notes (optional), e.g. delivers Mon and Thu')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _tanDeep, foregroundColor: Colors.white),
          onPressed: _submit,
          child: Text(widget.existing == null ? 'Add supplier' : 'Save'),
        ),
      ],
    );
  }
}