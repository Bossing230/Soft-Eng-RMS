class Expense {
  final int expenseId;
  final String date; // 'YYYY-MM-DD'
  final String category;
  final String description;
  final double amount;
  final int? supplierId;
  final String? supplierName;
  final String recordedBy;

  Expense({
    required this.expenseId,
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
    this.supplierId,
    this.supplierName,
    this.recordedBy = '',
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      expenseId: int.parse(json['expense_id'].toString()),
      date: (json['expense_date'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      amount: double.tryParse('${json['amount']}') ?? 0,
      supplierId: json['supplier_id'] == null ? null : int.tryParse('${json['supplier_id']}'),
      supplierName: json['supplier_name']?.toString(),
      recordedBy: (json['recorded_by'] ?? '').toString(),
    );
  }
}

class ExpenseCategoryTotal {
  final String category;
  final double total;
  ExpenseCategoryTotal(this.category, this.total);
}

/// The list plus the totals for the same period.
class ExpenseResult {
  final List<Expense> items;
  final double total;
  final int count;
  final List<ExpenseCategoryTotal> byCategory;

  ExpenseResult({required this.items, required this.total, required this.count, required this.byCategory});

  factory ExpenseResult.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] ?? {});
    return ExpenseResult(
      items: ((json['items'] as List?) ?? [])
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      total: double.tryParse('${summary['total'] ?? 0}') ?? 0,
      count: int.tryParse('${summary['count'] ?? 0}') ?? 0,
      byCategory: ((summary['byCategory'] as List?) ?? [])
          .map((e) => ExpenseCategoryTotal(
                (e['category'] ?? '').toString(),
                double.tryParse('${e['total']}') ?? 0,
              ))
          .toList(),
    );
  }
}