import 'package:rms/Frontend/models/expense.dart';
import 'package:rms/Frontend/services/api_services.dart';

class ExpenseRepository {
  final ApiService _api = ApiService();

  /// [start] and [end] are 'YYYY-MM-DD'; leave both null for all time.
  Future<ExpenseResult> getAll({String? start, String? end, String? category}) async {
    final data = await _api.get('/expenses', query: {
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      if (category != null) 'category': category,
    });
    return ExpenseResult.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Expense> create({
    required String category,
    required String description,
    required double amount,
    required String expenseDate,
  }) async {
    final data = await _api.post('/expenses', body: {
      'category': category,
      'description': description,
      'amount': amount,
      'expenseDate': expenseDate,
    });
    return Expense.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Expense> update(
    int id, {
    required String category,
    required String description,
    required double amount,
    required String expenseDate,
  }) async {
    final data = await _api.put('/expenses/$id', body: {
      'category': category,
      'description': description,
      'amount': amount,
      'expenseDate': expenseDate,
    });
    return Expense.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> remove(int id) => _api.post('/expenses/$id/delete', body: {});
}