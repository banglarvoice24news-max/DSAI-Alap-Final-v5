import 'dart:async';

import 'package:dio/dio.dart';
import '../constants.dart';
import '../storage/secure_store.dart';

class ApiClient {
  ApiClient({Dio? dio, SecureStore? store})
      : _store = store ?? SecureStore(),
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: AppConstants.apiBaseUrl,
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
                headers: {'Content-Type': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (options.extra['skipAuth'] == true) {
            handler.next(options);
            return;
          }
          final token = await _store.read(SecureStore.accessToken);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final path = error.requestOptions.path;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;
          if (error.response?.statusCode == 401 &&
              !alreadyRetried &&
              !path.contains('/api/auth/refresh') &&
              !path.contains('/api/auth/otp')) {
            try {
              final token = await _refreshAccessToken();
              if (token == null) {
                handler.next(error);
                return;
              }
              final req = error.requestOptions;
              req.headers['Authorization'] = 'Bearer $token';
              req.extra['retried'] = true;
              final clone = await _dio.fetch(req);
              handler.resolve(clone);
              return;
            } catch (_) {}
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SecureStore _store;

  Dio get raw => _dio;

  Future<Map<String, dynamic>> post(String path, {Object? data, Map<String, String>? headers}) async {
    final res = await _dio.post(path, data: data, options: headers == null ? null : Options(headers: headers));
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.get(path, queryParameters: query, options: headers == null ? null : Options(headers: headers));
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final res = await _dio.patch(path, data: data);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<String?> _refreshAccessToken() async {
    final inflight = _refreshCompleter;
    if (inflight != null) return inflight.future;
    final completer = Completer<String?>();
    _refreshCompleter = completer;
    try {
      final stored = await _store.read(SecureStore.refreshToken);
      final refreshed = await _dio.post(
        '/api/auth/refresh',
        data: stored != null ? {'refreshToken': stored} : const {},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = refreshed.data['data'] as Map;
      final token = data['accessToken'] as String;
      await _store.write(SecureStore.accessToken, token);
      final nextRefresh = data['refreshToken'] as String?;
      if (nextRefresh != null) {
        await _store.write(SecureStore.refreshToken, nextRefresh);
      }
      completer.complete(token);
      return token;
    } catch (err) {
      if (!completer.isCompleted) completer.complete(null);
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  Completer<String?>? _refreshCompleter;
}
