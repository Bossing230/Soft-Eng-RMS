import 'package:intl/intl.dart';
import 'package:rms/Frontend/services/api_services.dart';
import 'package:rms/Frontend/services/file_download.dart';

class ReportExportRepository {
  final ApiService _api = ApiService();

  /// [report] is 'sales' or 'inventory'. [format] is 'pdf', 'excel' or 'csv'.
  /// [start] / [end] apply to the sales report.
  /// Returns false if downloading isn't supported on this platform yet.
  Future<bool> download({
    required String report,
    required String format,
    DateTime? start,
    DateTime? end,
  }) async {
    final day = DateFormat('yyyy-MM-dd');
    final bytes = await _api.getBytes('/reports/$report', query: {
      'format': format,
      if (start != null) 'start': day.format(start),
      if (end != null) 'end': day.format(end),
    });

    final extension = format == 'excel' ? 'xlsx' : format;
    const mimeTypes = {
      'pdf': 'application/pdf',
      'excel': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv': 'text/csv',
    };
    return downloadBytes(
      bytes,
      filename: '$report-report-${day.format(DateTime.now())}.$extension',
      mimeType: mimeTypes[format] ?? 'application/octet-stream',
    );
  }
}