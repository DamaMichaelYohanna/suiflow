import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'offline_queue.dart';
import 'config.dart';
import '../../features/auth/auth_provider.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(String? token) : _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    headers: token != null ? {'Authorization': 'Bearer $token'} : {},
  )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[API CLIENT Request] ${options.method} ${options.uri}');
        if (options.data != null) {
          print('[API CLIENT Request Body] ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('[API CLIENT Response] ${response.statusCode} from ${response.requestOptions.uri}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print('[API CLIENT Error] ${e.response?.statusCode} from ${e.requestOptions.uri}: ${e.message}');
        if (e.response?.data != null) {
          print('[API CLIENT Error Body] ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));
  }


  /// Simulates syncing offline transactions with the backend
  Future<void> syncOfflineQueue() async {
    final pending = OfflineQueue.getPendingTransactions();
    if (pending.isEmpty) return;

    try {
      final response = await _dio.post('/sync/offline', data: {
        'transactions': pending,
      });

      if (response.statusCode == 202) {
        // Clear queue on success
        await OfflineQueue.clearAll();
        print('Sync Successful');
      }
    } catch (e) {
      print('Sync failed, will retry later: \$e');
      // In a real app, we might handle individual failures, 
      // update retry counts, or display an error state.
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authProvider);
  return ApiClient(auth.token);
});
