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
}

class _AuthInterceptor extends Interceptor {
  final Dio _dio;
  Future<String>? _refreshing;

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
      final access = await (_refreshing ??= _refreshTokens());
      err.requestOptions.headers['Authorization'] = 'Bearer $access';
      err.requestOptions.extra['retried'] = true;
      final retryResponse = await _dio.fetch(err.requestOptions);
      handler.resolve(retryResponse);
    } catch (_) {
      await AppStorage.clearAll();
      handler.next(err);
    }
  }

  Future<String> _refreshTokens() async {
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
