import 'dart:convert';

import 'package:dio/dio.dart';
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
      _LoggingInterceptor(),
    ]);

    return dio;
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
      final response = await Dio().post(
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
    if (exp == null || exp.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
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

  bool _isRefreshCall(RequestOptions options) =>
      options.path.contains(ApiEndpoints.refreshToken);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
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

    try {
      final access = await DioClient.refreshTokens();
      err.requestOptions.headers['Authorization'] = 'Bearer $access';
      err.requestOptions.extra['retried'] = true;
      final retryResponse = await _dio.fetch(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await AppStorage.clearAll();
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
