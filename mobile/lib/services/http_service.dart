import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Minimal HTTP JSON helper for calling the Flask backend.
class HttpService {
  /// POSTs JSON and returns decoded JSON (Map or List).
  /// Throws if non-200 or invalid JSON.
  static Future<dynamic> postJson(String path, Map<String, dynamic> body,
      {Map<String, String>? headers}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}$path');
    final h = <String, String>{
      'Content-Type': 'application/json',
      ...?headers,
    };

    final resp = await http
        .post(url, headers: h, body: jsonEncode(body))
        .timeout(ApiConfig.timeout);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw HttpException(
          'HTTP ${resp.statusCode}: ${resp.body.isNotEmpty ? resp.body : 'No content'}');
    }

    if (resp.body.isEmpty) return null;

    try {
      return jsonDecode(resp.body);
    } catch (e) {
      throw FormatException('Invalid JSON from server: ${resp.body}');
    }
  }
}

/// Simple exception used above when we want to signal a request failure.
class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override
  String toString() => 'HttpException: $message';
}
