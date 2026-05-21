import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String get baseUrl => AppConfig.baseUrl;

  String? _userId;
  String? _userName;

  String? get userId   => _userId;
  String? get userName => _userName;
  bool    get isLoggedIn => _userId != null;

  // ─── Initialisation ───────────────────────────────────
  // Called once in main() before runApp().  Loads (or generates) a
  // persistent UUID that identifies this device across sessions.

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    if (_userId == null) {
      _userId = _generateUuid();
      await prefs.setString('user_id', _userId!);
    }
    _userName = prefs.getString('user_name') ?? 'User';
  }

  Future<void> setUserName(String name) async {
    _userName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
  }

  // ─── UUID generator ───────────────────────────────────

  String _generateUuid() {
    final rng   = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6]    = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8]    = (bytes[8] & 0x3f) | 0x80; // variant
    final hex   = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
           '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
           '${hex.substring(20)}';
  }

  // ─── HTTP headers ─────────────────────────────────────

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_userId != null) 'X-User-ID': _userId!,
      };

  // ─── Private HTTP helpers with timeout ────────────────

  Future<http.Response> _get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(AppConfig.requestTimeout);

  Future<http.Response> _post(String path,
          {Object? body, Map<String, String>? headers}) =>
      http.post(
        Uri.parse('$baseUrl$path'),
        headers: headers ?? _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(AppConfig.requestTimeout);

  Future<http.Response> _put(String path, {Object? body}) =>
      http.put(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(AppConfig.requestTimeout);

  // ─── Response handler ─────────────────────────────────

  Future<Map<String, dynamic>> _handleResponse(http.Response response) async {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = body['data'] as Map<String, dynamic>?;
      return data ?? body;
    }
    final error = body['error'] ?? 'Something went wrong';
    throw ApiException(error.toString(), statusCode: response.statusCode);
  }

  // ─── Session ──────────────────────────────────────────

  Future<Map<String, dynamic>> submitCrave(
      String craveItem, double latitude, double longitude) async {
    final response = await _post('/session/crave', body: {
      'crave_item': craveItem,
      'latitude':   latitude,
      'longitude':  longitude,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> selectOption(
      String sessionId, String selectedOption) async {
    final response = await _post('/session/select', body: {
      'session_id':      sessionId,
      'selected_option': selectedOption,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> chooseType(
      String sessionId, String sessionType) async {
    final response = await _post('/session/choose-type', body: {
      'session_id':   sessionId,
      'session_type': sessionType,
    });
    return _handleResponse(response);
  }

  // ─── Challenge ────────────────────────────────────────

  Future<Map<String, dynamic>> selectChallenge(
      String sessionId, String challengeDescription, int timeLimit) async {
    final response = await _post('/challenge/select', body: {
      'session_id':            sessionId,
      'challenge_description': challengeDescription,
      'time_limit':            timeLimit,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> startChallenge(String challengeId) async {
    final response = await _post('/challenge/start',
        body: {'challenge_id': challengeId});
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> completeChallenge(
      String challengeId, int completionPercentage) async {
    final response = await _post('/challenge/complete', body: {
      'challenge_id':          challengeId,
      'completion_percentage': completionPercentage,
    });
    return _handleResponse(response);
  }

  // ─── User ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getProfile() async {
    final response = await _get('/user/profile');
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    int?    age,
    double? height,
    double? weight,
  }) async {
    final body = <String, dynamic>{};
    if (name   != null) body['name']   = name;
    if (age    != null) body['age']    = age;
    if (height != null) body['height'] = height;
    if (weight != null) body['weight'] = weight;

    if (name != null) await setUserName(name);

    final response = await _put('/user/profile', body: body);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getHistory() async {
    final response = await _get('/user/history');
    return _handleResponse(response);
  }

  // ─── Regenerate endpoints ─────────────────────────────

  Future<Map<String, dynamic>> regenerateCraveOptions(String sessionId) async {
    final response = await _post('/session/crave/regenerate',
        body: {'session_id': sessionId});
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> regenerateChallenges(String sessionId) async {
    final response = await _post('/session/challenges/regenerate',
        body: {'session_id': sessionId});
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> regenerateHealthy(String sessionId) async {
    final response = await _post('/session/healthy/regenerate',
        body: {'session_id': sessionId});
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> acceptHealthy(
      String sessionId, String selectedSuggestion) async {
    final response = await _post('/session/healthy/accept', body: {
      'session_id':          sessionId,
      'selected_suggestion': selectedSuggestion,
    });
    return _handleResponse(response);
  }
}
