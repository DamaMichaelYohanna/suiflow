import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'vault_model.dart';
import '../auth/auth_provider.dart';

class VaultNotifier extends StateNotifier<AsyncValue<List<Vault>>> {
  final Ref ref;
  final _dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000/api'));

  VaultNotifier(this.ref) : super(const AsyncValue.loading()) {
    fetchVaults();
  }

  Future<void> fetchVaults() async {
    final auth = ref.read(authProvider);
    if (auth.phoneNumber == null) return;

    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/vaults/', queryParameters: {
        'owner_phone': auth.phoneNumber,
      });
      final List<dynamic> data = response.data;
      final vaults = data.map((e) => Vault.fromJson(e)).toList();
      state = AsyncValue.data(vaults);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> createVault(String name) async {
    final auth = ref.read(authProvider);
    if (auth.phoneNumber == null) return;

    try {
      await _dio.post('/vaults/', 
        data: {'name': name},
        queryParameters: {'owner_phone': auth.phoneNumber},
      );
      // Refresh the list after creation
      await fetchVaults();
    } catch (e) {
      // In a real app, handle error
      print('Error creating vault: $e');
    }
  }
}

final vaultProvider = StateNotifierProvider<VaultNotifier, AsyncValue<List<Vault>>>((ref) {
  return VaultNotifier(ref);
});
