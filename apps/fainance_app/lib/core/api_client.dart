import 'package:dio/dio.dart';

import 'models.dart';

// ── Konfiguration ──────────────────────────────────────────────────────────────
// Auf Android-Emulator ist der Host `10.0.2.2`, weil `localhost` im Emulator
// der Emulator selbst ist, nicht dein Mac. Auf iOS Simulator ist es `localhost`.
//
// Für echte Geräte im selben WLAN: IP deines Macs, z.B. `192.168.1.100`.
// `ifconfig | grep "inet "` auf dem Mac gibt dir die IP.
const String _baseUrl = 'http://10.0.2.2:8000'; // Android Emulator
// const String _baseUrl = 'http://localhost:8000'; // iOS Simulator / Web


class ApiClient {
  late final Dio _dio;

  ApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        // receiveTimeout großzügig — Ollama braucht Zeit
        receiveTimeout: const Duration(seconds: 180),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // Interceptor: loggt jeden Request und Response in der Konsole.
    // In Produktion würdest du das deaktivieren oder durch einen
    // richtigen Logger ersetzen.
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: false,   // false: keine Finanzdaten in Logs
        responseBody: false,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ),
    );
  }

  // ── Health Check ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _dio.get('/');
    return response.data as Map<String, dynamic>;
  }

  // ── CSV Upload ────────────────────────────────────────────────────────────────
  // Für Datei-Uploads verwenden wir FormData statt JSON.
  // Das ist das Multipart/Form-Data Format — wie ein HTML-Formular.
  Future<UploadResponse> uploadCsv(
    String filePath,
    String fileName, {
    String bankName = 'auto',
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        filePath,
        filename: fileName,
      ),
      'bank_name': bankName,
    });

    final response = await _dio.post(
      '/upload-csv',
      data: formData,
      options: Options(
        // Für Datei-Uploads: Content-Type wird von Dio automatisch gesetzt
        contentType: 'multipart/form-data',
      ),
      onSendProgress: onProgress,
    );

    return UploadResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Analyse abrufen ───────────────────────────────────────────────────────────
  Future<AnalysisResult> getAnalysis(String uploadId) async {
    final response = await _dio.get('/analysis/$uploadId');
    return AnalysisResult.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Transaktionen abrufen (paginiert) ────────────────────────────────────────
  Future<List<Transaction>> getTransactions(
    String uploadId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _dio.get(
      '/transactions/$uploadId',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return (response.data as List)
        .map((t) => Transaction.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  // ── Insights generieren ───────────────────────────────────────────────────────
  Future<InsightResponse> getInsights(
    AnalysisResult analysis, {
    String? userContext,
  }) async {
    final response = await _dio.post(
      '/insights',
      data: {
        'analysis': {
          'total_income': analysis.totalIncome,
          'total_expenses': analysis.totalExpenses,
          'net': analysis.net,
          'categories': analysis.categories
              .map((c) => {
                    'category': c.category,
                    'total': c.total,
                    'count': c.count,
                    'percentage': c.percentage,
                  })
              .toList(),
          'period_start': analysis.periodStart.toIso8601String().split('T')[0],
          'period_end': analysis.periodEnd.toIso8601String().split('T')[0],
        },
        if (userContext != null) 'user_context': userContext,
      },
    );
    return InsightResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Kategorie manuell korrigieren ─────────────────────────────────────────────
  Future<void> updateCategory(int transactionId, String category) async {
    await _dio.patch(
      '/transactions/$transactionId/category',
      queryParameters: {'category': category},
    );
  }
}

// ── Fehlerbehandlung ──────────────────────────────────────────────────────────
// Hilfsfunktion die einen DioException in eine lesbare Fehlermeldung umwandelt.
// Wird in den Screens verwendet um dem Nutzer sinnvolle Fehler zu zeigen.
String parseApiError(Object error) {
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Zeitüberschreitung. Läuft das Backend? (uvicorn main:app)';
    }
    if (error.type == DioExceptionType.connectionError) {
      return 'Keine Verbindung zum Backend. Bitte starte den Server.';
    }
    final data = error.response?.data;
    if (data is Map && data.containsKey('detail')) {
      return data['detail'].toString();
    }
    return 'Serverfehler: ${error.response?.statusCode ?? 'unbekannt'}';
  }
  return error.toString();
}

// debugPrint ist Flutter's print-Funktion die lange Strings nicht abschneidet
void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}