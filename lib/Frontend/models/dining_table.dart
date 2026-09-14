class DiningTable {
  final int tableId;
  final String tableNumber;
  final int capacity;
  final String status;

  DiningTable({
    required this.tableId,
    required this.tableNumber,
    required this.capacity,
    required this.status,
  });

  factory DiningTable.fromJson(Map<String, dynamic> json) {
    return DiningTable(
      tableId: int.parse(json['table_id'].toString()),
      tableNumber: json['table_number'] ?? '',
      capacity: int.parse(json['capacity'].toString()),
      status: json['status'] ?? 'available',
    );
  }
}