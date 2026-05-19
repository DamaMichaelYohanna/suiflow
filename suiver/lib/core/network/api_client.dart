import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'offline_queue.dart';
import '../../features/auth/auth_provider.dart';

class ApiClient {
  final Dio _dio;

  ApiClient(String? token) : _dio = Dio(BaseOptions(
    baseUrl: 'http://localhost:8000/api',
    headers: token != null ? {'Authorization': 'Bearer $token'} : {},
  ));

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
