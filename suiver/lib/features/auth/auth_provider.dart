import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/config.dart';

class AuthState {
  final String? phoneNumber;
  final String? socialId;
  final String? token;
  final bool isAuthenticated;
  final bool isLoading;
  final String? error;

  AuthState({
    this.phoneNumber,
    this.socialId,
    this.token,
    this.isAuthenticated = false,
    this.isLoading = false,
    this.error,
  });

  AuthState copyWith({
    String? phoneNumber,
    String? socialId,
    String? token,
    bool? isAuthenticated,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      socialId: socialId ?? this.socialId,
      token: token ?? this.token,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Dio _dio;

  AuthNotifier()
      : _dio = Dio(BaseOptions(baseUrl: '${AppConfig.baseUrl}/auth')),
        super(AuthState()) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[AUTH PROVIDER Request] ${options.method} ${options.uri}');
        if (options.data != null) {
          print('[AUTH PROVIDER Request Body] ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print(
            '[AUTH PROVIDER Response] ${response.statusCode} from ${response.requestOptions.uri}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print(
            '[AUTH PROVIDER Error] ${e.response?.statusCode} from ${e.requestOptions.uri}: ${e.message}');
        if (e.response?.data != null) {
          print('[AUTH PROVIDER Error Body] ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));
  }

  Future<void> register({
    String? phoneNumber,
    required String username,
    required String password,
    String? fullName,
    String? socialId,
    String authMethod = 'PHONE',
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/register', data: {
        'phone_number': phoneNumber,
        'username': username,
        'password': password,
        'full_name': fullName,
        'social_id': socialId,
        'auth_method': authMethod,
      });

      state = state.copyWith(
        phoneNumber: response.data['user']['phone_number'],
        socialId: response.data['user']['social_id'],
        token: response.data['token']['access_token'],
        isAuthenticated: true,
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
          isLoading: false,
          error: e.response?.data['detail'] ?? 'Registration failed');
    }
  }

  Future<void> login(String phoneNumber, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post(
        '/login',
        data: {
          'username': phoneNumber, // Standard OAuth2 field
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      state = state.copyWith(
        phoneNumber: response.data['user']['phone_number'],
        token: response.data['token']['access_token'],
        isAuthenticated: true,
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
          isLoading: false,
          error: e.response?.data['detail'] ?? 'Login failed');
    }
  }

  Future<void> zkLogin(String jwt) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.post('/zklogin', data: {
        'jwt': jwt,
      });

      state = state.copyWith(
        socialId: response.data['user']['social_id'],
        token: response.data['token']['access_token'],
        isAuthenticated: true,
        isLoading: false,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // Special case: social ID verified but user not registered in our DB
        state = state.copyWith(
          isLoading: false,
          socialId: jwt, // In a real app, this would be the verified sub
          error: 'SOCIAL_NOT_REGISTERED',
        );
      } else {
        state = state.copyWith(
            isLoading: false,
            error: e.response?.data['detail'] ?? 'Social login failed');
      }
    }
  }

  void logout() {
    state = AuthState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
