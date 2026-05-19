import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/config.dart';
import '../auth/auth_provider.dart';

class BalanceState {
  final double balance;
  final bool isLoading;
  final String? error;

  BalanceState({
    this.balance = 0.0,
    this.isLoading = false,
    this.error,
  });

  BalanceState copyWith({
    double? balance,
    bool? isLoading,
    String? error,
  }) {
    return BalanceState(
      balance: balance ?? this.balance,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class BalanceNotifier extends StateNotifier<BalanceState> {
  final Dio _dio;
  final String? _token;

  BalanceNotifier(this._token)
      : _dio = Dio(BaseOptions(baseUrl: '${AppConfig.baseUrl}/auth')),
        super(BalanceState()) {
    if (_token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $_token';
      fetchBalance();
    }
  }

  Future<void> fetchBalance() async {
    if (_token == null) return;
    
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _dio.get('/balance');
      final balance = (response.data['balance'] as num).toDouble();
      state = state.copyWith(balance: balance, isLoading: false);
    } on DioException catch (e) {
      print('[BALANCE Error] ${e.message}');
      state = state.copyWith(
        isLoading: false,
        error: e.response?.data['detail'] ?? 'Failed to fetch balance',
      );
    } catch (e) {
      print('[BALANCE Error] $e');
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred',
      );
    }
  }
}

final balanceProvider = StateNotifierProvider<BalanceNotifier, BalanceState>((ref) {
  final authState = ref.watch(authProvider);
  return BalanceNotifier(authState.token);
});
