import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../repositories/employee_repository.dart';
import '../../models/employee.dart';
import '../../core/constants/app_constants.dart';

class EmployeeManagementPage extends StatefulWidget {
  const EmployeeManagementPage({super.key});

  @override
  State<EmployeeManagementPage> createState() => _EmployeeManagementPageState();
}

class _EmployeeManagementPageState extends State<EmployeeManagementPage> {
  final _repo = EmployeeRepository();
  List<Employee> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.getAll();
    setState(() {
      _employees = data;
      _loading = false;
    });
  }

  String _fullImageUrl(String path) {
  if (path.startsWith('http')) return path;
  final base = AppConstants.apiBaseUrl.replaceAll('/api', '');
  return '$base$path';
}

  Color _roleColor(String role) {
    switch (role) {
      case 'administrator':
        return Colors.red;
      case 'manager':
        return Colors.indigo;
      case 'cashier':
        return Colors.teal;
      case 'kitchen':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  // Shows a read-only detail card for one employee: large photo, email,
  // role, status — and a "Reset Password" action instead of ever
  // displaying the actual password, which is hashed and unrecoverable.
  void _showDetail(Employee e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // lets the sheet grow and scroll instead of clipping
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: e.profileImage != null ? NetworkImage(_fullImageUrl(e.profileImage!)) : null,
                child: e.profileImage == null
                    ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 32))
                    : null,
              ),
              const SizedBox(height: 16),
              Text(e.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Chip(
                label: Text(e.role, style: const TextStyle(color: Colors.white, fontSize: 12)),
                backgroundColor: _roleColor(e.role),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(height: 24),
 
              _DetailRow(icon: Icons.alternate_email, label: 'Username', value: e.username),
              const SizedBox(height: 14),
              _DetailRow(icon: Icons.mail_outline, label: 'Email', value: e.email),
              const SizedBox(height: 14),
              _DetailRow(
                icon: e.status == 'active' ? Icons.check_circle_outline : Icons.pause_circle_outline,
                label: 'Status',
                value: e.status == 'active' ? 'Active' : 'Deactivated',
              ),
 
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Passwords are encrypted and can\'t be viewed by anyone, including administrators. '
                'Use the button below to set a new one if this employee needs it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showResetPasswordDialog(e);
                  },
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reset Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showResetPasswordDialog(Employee e) async {
    final newPasswordCtrl = TextEditingController();
    bool submitting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Reset password for ${e.name}'),
          content: TextField(
            controller: newPasswordCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New temporary password'),
          ),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (newPasswordCtrl.text.trim().length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Password must be at least 6 characters')));
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        await _repo.resetPassword(e.employeeId, newPasswordCtrl.text.trim());
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset successfully')));
                        }
                      } catch (err) {
                        setDialogState(() => submitting = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed: $err')));
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    String role = AppConstants.roleCashier;

    XFile? pickedPhoto;
    Uint8List? previewBytes;
    bool submitting = false;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Employee Account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: submitting
                      ? null
                      : () async {
                          final picker = ImagePicker();
                          final file = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600);
                          if (file != null) {
                            final bytes = await file.readAsBytes();
                            setDialogState(() {
                              pickedPhoto = file;
                              previewBytes = bytes;
                            });
                          }
                        },
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: previewBytes != null ? MemoryImage(previewBytes!) : null,
                        child: previewBytes == null ? const Icon(Icons.person, size: 40, color: Colors.grey) : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.badge_outlined))),
                const SizedBox(height: 16),
                TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email))),
                const SizedBox(height: 16),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Temporary password', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Role', prefixIcon: Icon(Icons.assignment_ind_outlined)),
                  items: const [
                    DropdownMenuItem(value: AppConstants.roleManager, child: Text('Manager')),
                    DropdownMenuItem(value: AppConstants.roleCashier, child: Text('Cashier')),
                    DropdownMenuItem(value: AppConstants.roleKitchen, child: Text('Kitchen Staff')),
                  ],
                  onChanged: submitting ? null : (v) => setDialogState(() => role = v!),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().isEmpty || usernameCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Name, username, and password are required')));
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        String? photoUrl;
                        if (previewBytes != null && pickedPhoto != null) {
                          photoUrl = await _repo.uploadPhoto(bytes: previewBytes!, filename: pickedPhoto!.name);
                        }
                        await _repo.create(
                          name: nameCtrl.text.trim(),
                          username: usernameCtrl.text.trim(),
                          email: emailCtrl.text.trim(),
                          password: passwordCtrl.text,
                          role: role,
                          profileImage: photoUrl,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to create: $e')));
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Employee'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _employees.length,
                itemBuilder: (_, i) {
                  final e = _employees[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        onTap: () => _showDetail(e),
                        leading: CircleAvatar(
                          backgroundImage: e.profileImage != null ? NetworkImage(_fullImageUrl(e.profileImage!)) : null,
                          child: e.profileImage == null ? Text(e.name.isNotEmpty ? e.name[0].toUpperCase() : '?') : null,
                        ),
                        title: Text(e.name),
                        subtitle: Text('${e.username} • ${e.role}'),
                        trailing: Switch(
                          value: e.status == 'active',
                          onChanged: (val) async {
                            await _repo.setStatus(e.employeeId, val);
                            _load();
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
 
  const _DetailRow({required this.icon, required this.label, required this.value});
 
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
 