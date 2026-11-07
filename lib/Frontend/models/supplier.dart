class Supplier {
  final int supplierId;
  final String name;
  final String? contactPerson;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;

  /// How many active ingredients name this supplier.
  final int ingredientCount;

  Supplier({
    required this.supplierId,
    required this.name,
    this.contactPerson,
    this.phone,
    this.email,
    this.address,
    this.notes,
    this.ingredientCount = 0,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    String? clean(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return Supplier(
      supplierId: int.parse(json['supplier_id'].toString()),
      name: (json['name'] ?? '').toString(),
      contactPerson: clean(json['contact_person']),
      phone: clean(json['phone']),
      email: clean(json['email']),
      address: clean(json['address']),
      notes: clean(json['notes']),
      ingredientCount: int.tryParse('${json['ingredient_count'] ?? 0}') ?? 0,
    );
  }
}