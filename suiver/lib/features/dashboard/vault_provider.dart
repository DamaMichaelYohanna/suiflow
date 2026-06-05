import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'vault_model.dart';
import '../auth/auth_provider.dart';
import '../../core/network/config.dart';

class VaultNotifier extends StateNotifier<AsyncValue<List<Vault>>> {
  final Ref ref;
  final Dio _dio;
  final String? _token;

  VaultNotifier(this.ref, this._token)
      : _dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl)),
        super(const AsyncValue.loading()) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[VAULT PROVIDER Request] ${options.method} ${options.uri}');
        if (options.data != null) {
          print('[VAULT PROVIDER Request Body] ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('[VAULT PROVIDER Response] ${response.statusCode} from ${response.requestOptions.uri}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print('[VAULT PROVIDER Error] ${e.response?.statusCode} from ${e.requestOptions.uri}: ${e.message}');
        if (e.response?.data != null) {
          print('[VAULT PROVIDER Error Body] ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));
    if (_token != null) {
      fetchVaults();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> fetchVaults() async {
    if (_token == null) {
      state = const AsyncValue.error('User is not authenticated', StackTrace.empty);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final response = await _dio.get(
        '/vaults/',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
      final List<dynamic> data = response.data;
      final vaults = data.map((e) => Vault.fromJson(e)).toList();
      state = AsyncValue.data(vaults);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<String?> createVault(String name, {double? allocationPercentage}) async {
    if (_token == null) return 'User is not authenticated';

    try {
      final response = await _dio.post(
        '/vaults/', 
        data: {'name': name},
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
      
      final newVault = Vault.fromJson(response.data);
      
      if (allocationPercentage != null && allocationPercentage > 0) {
        await _dio.post(
          '/rules/',
          data: {
            'rule_type': 'salary_split',
            'target_vault_id': newVault.id,
            'percentage': allocationPercentage,
          },
          options: Options(
            headers: {'Authorization': 'Bearer $_token'},
          ),
        );
      }
      
      // Refresh the list after creation
      await fetchVaults();
      return null;
    } catch (e) {
      print('Error creating vault: $e');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          return data['detail'].toString();
        }
        return e.message;
      }
      return e.toString();
    }
  }

  Future<String?> withdrawFromVault(int vaultId, double amount) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.post(
        '/vaults/$vaultId/withdraw',
        data: {'amount': amount},
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
      // Refresh vault list after withdrawal
      await fetchVaults();
      return null;
    } catch (e) {
      print('Error withdrawing from vault: $e');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          return data['detail'].toString();
        }
        return e.message;
      }
      return e.toString();
    }
  }

  Future<String?> deleteVault(int vaultId) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.delete(
        '/vaults/$vaultId',
        options: Options(
          headers: {'Authorization': 'Bearer $_token'},
        ),
      );
      // Refresh the list after deletion
      await fetchVaults();
      return null;
    } catch (e) {
      print('Error deleting vault: $e');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          return data['detail'].toString();
        }
        return e.message;
      }
      return e.toString();
    }
  }
}

final vaultProvider = StateNotifierProvider<VaultNotifier, AsyncValue<List<Vault>>>((ref) {
  // Watch authProvider so that when a different user logs in the notifier is
  // disposed and recreated with the new token — preventing vault data from
  // leaking across accounts.
  final token = ref.watch(authProvider).token;
  return VaultNotifier(ref, token);
});
