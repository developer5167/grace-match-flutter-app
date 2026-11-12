import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import '../constants/app_constants.dart';
import '../storage/app_storage.dart';

class DioClient {
  static Dio? _instance;

  static Dio get instance {
    _instance ??= _createDio();
    return _instance!;
  }

  static Dio _createDio() {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.addAll([
      _AuthInterceptor(dio),
      // Reads only. A POST that timed out may still have gone through, and
      // sending it again could send an interest or a payment twice.
      RetryInterceptor(
        dio: dio,
        retries: 2,
        retryDelays: const [Duration(seconds: 1), Duration(seconds: 3)],
        retryEvaluator: _retryGet,
      ),
      _LoggingInterceptor(),
    ]);

    return dio;
  }

  /// Retry a GET that failed on a dropped or refused connection, or on a
  /// gateway/server hiccup (5xx, 408, 429). Not on timeouts: each one already
  /// waited 15-20 s, and three in a row would hold a screen for a minute.
  static bool _retryGet(DioException error, int attempt) {
    if (error.requestOptions.method.toUpperCase() != 'GET') return false;
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return error.error is! FormatException;
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode ?? 0;
        return code == 408 || code == 429 || (code >= 500 && code <= 599);
      default:
        // Timeouts, cancellations, bad certificates.
        return false;
    }
  }

  static Future<String>? _refreshing;

  /// Rotate the token pair. One refresh at a time across HTTP and the socket:
  /// refresh tokens are single-use, so two concurrent refreshes log the member
  /// out.
  static Future<String> refreshTokens() => _refreshing ??= _refresh();

  static Future<String> _refresh() async {
    try {
      final refreshToken = await AppStorage.getRefreshToken();
      if (refreshToken == null) {
        throw StateError('no refresh token');
      }
      // Bounded like every other request. Without timeouts a refresh stuck
      // on a dead connection held every request queued behind it for good.
      final response = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      ).post(
        '${AppConstants.baseUrl}${ApiEndpoints.refreshToken}',
        data: {'refresh_token': refreshToken},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final newAccess = data['access_token'] as String;
      final newRefresh = data['refresh_token'] as String;
      await AppStorage.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      return newAccess;
    } finally {
      _refreshing = null;
    }
  }

  /// The access token, refreshed first if it expires within a minute.
  ///
  /// The socket handshake cannot retry on a 401 the way HTTP does, so it asks
  /// for a token that will still be valid when it reaches the server.
  static Future<String?> freshAccessToken() async {
    final token = await AppStorage.getAccessToken();
    if (token == null) return null;
    final exp = _expiry(token);
    if (exp == null ||
        exp.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return token;
    }
    try {
      return await refreshTokens();
    } catch (_) {
      return token;
    }
  }

  static DateTime? _expiry(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {
      return null;
    }
  }
}

class _AuthInterceptor extends Interceptor {
  final Dio _dio;

  _AuthInterceptor(this._dio);

  static bool _isTimeout(Object e) =>
      e is DioException &&
      (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout);

  bool _isRefreshCall(RequestOptions options) =>
      options.path.contains(ApiEndpoints.refreshToken);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await AppStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    if (_isRefreshCall(err.requestOptions) ||
        err.requestOptions.extra['retried'] == true) {
      await AppStorage.clearAll();
      return handler.next(err);
    }

    final currentToken = await AppStorage.getAccessToken();
    if (currentToken == null) {
      return handler.next(err);
    }

    final String access;
    try {
      access = await DioClient.refreshTokens();
    } catch (e) {
      // A refresh that timed out says nothing about the session: keep it and
      // let the next request try again, rather than signing the member out.
      if (!_isTimeout(e)) await AppStorage.clearAll();
      return handler.next(err);
    }

    try {
      err.requestOptions.headers['Authorization'] = 'Bearer $access';
      err.requestOptions.extra['retried'] = true;
      final retryResponse = await _dio.fetch(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      // The session was renewed; only the repeated request failed (a 401 on
      // it has already signed out above). A server or network error there is
      // not a reason to sign the member out.
      handler.next(err);
    }
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print('→ ${options.method} ${options.path}');
      return true;
    }());
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print('← ${response.statusCode} ${response.requestOptions.path}');
      return true;
    }());
    handler.next(response);
  }
}
