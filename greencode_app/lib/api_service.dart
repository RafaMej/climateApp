import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://10.10.251.134:8080'; // ← puerto 8080

  static const Duration _timeout = Duration(seconds: 15);

  // ── Riesgo inmediato (hoy y mañana) ──────────────────────────────────────
  static Future<Map<String, dynamic>> getFrostCheck({
    double lat = 19.0414,
    double lon = -98.2063,
  }) async {
    final uri = Uri.parse('$baseUrl/analysis/frost-check');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'lat': lat, 'lon': lon}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('frost-check error ${response.statusCode}');
  }

  // ── Pronóstico mensual SEAS5 (1-6 meses) ─────────────────────────────────
  static Future<Map<String, dynamic>> getMonthlyRisk({
    double lat = 19.0414,
    double lon = -98.2063,
    int monthsAhead = 3,
  }) async {
    final uri = Uri.parse('$baseUrl/analysis/monthly-risk');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'lat': lat, 'lon': lon, 'months_ahead': monthsAhead}),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('monthly-risk error ${response.statusCode}');
  }
}