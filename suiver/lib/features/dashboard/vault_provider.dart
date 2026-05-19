import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'vault_model.dart';
import '../auth/auth_provider.dart';
import '../../core/network/config.dart';

class VaultNotifier extends StateNotifier<AsyncValue<List<Vault>>> {
  final Ref ref;
  final Dio _dio;

  VaultNotifier(this.ref)
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
    fetchVaults();
  }

  Future<void> fetchVaults() async {
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null) {
      state = const AsyncValue.error('User is not authenticated', StackTrace.empty);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final response = await _dio.get(
        '/vaults/',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final List<dynamic> data = response.data;
      final vaults = data.map((e) => Vault.fromJson(e)).toList();
      state = AsyncValue.data(vaults);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> createVault(String name) async {
    final auth = ref.read(authProvider);
    final token = auth.token;
    if (token == null) return;

    try {
      await _dio.post(
        '/vaults/', 
        data: {'name': name},
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      // Refresh the list after creation
      await fetchVaults();
    } catch (e) {
      print('Error creating vault: $e');
    }
  }
}

final vaultProvider = StateNotifierProvider<VaultNotifier, AsyncValue<List<Vault>>>((ref) {
  return VaultNotifier(ref);
});
