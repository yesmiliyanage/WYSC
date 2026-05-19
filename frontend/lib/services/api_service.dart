import 'dart:convert';
import 'package:http/http.dart' as http;
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
  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  String? _userName;
  String? _userEmail;

  bool get isLoggedIn => _accessToken != null;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userEmail => _userEmail;
  String? get accessToken => _accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  // ─── Private HTTP helpers with timeout ────────────────

  Future<http.Response> _get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(AppConfig.requestTimeout);

  Future<http.Response> _post(String path, {Object? body, Map<String, String>? headers}) =>
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

  // ─── Auth ─────────────────────────────────────────────

  Future<Map<String, dynamic>> signup(
      String email, String password, String name) async {
    final response = await _post(
      '/auth/signup',
      headers: {'Content-Type': 'application/json'},
      body: {'email': email, 'password': password, 'name': name},
    );

    final data = await _handleResponse(response);

    final session = data['session'] as Map<String, dynamic>?;
    if (session != null) {
      _accessToken = session['access_token'] as String?;
      _refreshToken = session['refresh_token'] as String?;
    }

    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      _userId = user['id'] as String?;
      _userName = user['full_name'] as String? ?? name;
      _userEmail = user['email'] as String?;
    }

    return data;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _post(
      '/auth/login',
      headers: {'Content-Type': 'application/json'},
      body: {'email': email, 'password': password},
    );

    final data = await _handleResponse(response);

    final session = data['session'] as Map<String, dynamic>?;
    if (session != null) {
      _accessToken = session['access_token'] as String?;
      _refreshToken = session['refresh_token'] as String?;
    }

    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      _userId = user['id'] as String?;
      _userName = user['full_name'] as String? ?? '';
      _userEmail = user['email'] as String?;
    }

    return data;
  }

  Future<void> logout() async {
    try {
      await _post('/auth/logout');
    } finally {
      _accessToken = null;
      _refreshToken = null;
      _userId = null;
      _userName = null;
      _userEmail = null;
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    final response = await _get('/auth/me');
    return _handleResponse(response);
  }

  // ─── Session ──────────────────────────────────────────

  Future<Map<String, dynamic>> submitCrave(
      String craveItem, double latitude, double longitude) async {
    final response = await _post('/session/crave', body: {
      'crave_item': craveItem,
      'latitude': latitude,
      'longitude': longitude,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> selectOption(
      String sessionId, String selectedOption) async {
    final response = await _post('/session/select', body: {
      'session_id': sessionId,
      'selected_option': selectedOption,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> chooseType(
      String sessionId, String sessionType) async {
    final response = await _post('/session/choose-type', body: {
      'session_id': sessionId,
      'session_type': sessionType,
    });
    return _handleResponse(response);
  }

  // ─── Challenge ────────────────────────────────────────

  Future<Map<String, dynamic>> selectChallenge(
      String sessionId, String challengeDescription, int timeLimit) async {
    final response = await _post('/challenge/select', body: {
      'session_id': sessionId,
      'challenge_description': challengeDescription,
      'time_limit': timeLimit,
    });
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> startChallenge(String challengeId) async {
    final response =
        await _post('/challenge/start', body: {'challenge_id': challengeId});
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> completeChallenge(
      String challengeId, int completionPercentage) async {
    final response = await _post('/challenge/complete', body: {
      'challenge_id': challengeId,
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
    int? age,
    double? height,
    double? weight,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (age != null) body['age'] = age;
    if (height != null) body['height'] = height;
    if (weight != null) body['weight'] = weight;

    final response = await _put('/user/profile', body: body);
    return _handleResponse(response);
  }

  Future<Map<String, dynamic>> getHistory() async {
    final response = await _get('/user/history');
    return _handleResponse(response);
  }

  // ─── Regenerate Endpoints ─────────────────────────────

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
      'session_id': sessionId,
      'selected_suggestion': selectedSuggestion,
    });
    return _handleResponse(response);
  }
}
