import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'rule_model.dart';
import '../auth/auth_provider.dart';
import '../../core/network/config.dart';

class RuleNotifier extends StateNotifier<AsyncValue<List<Rule>>> {
  final Ref ref;
  final Dio _dio;
  final String? _token;

  RuleNotifier(this.ref, this._token)
      : _dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl)),
        super(const AsyncValue.loading()) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[RULE PROVIDER Request] ${options.method} ${options.uri}');
        if (options.data != null) {
          print('[RULE PROVIDER Request Body] ${options.data}');
        }
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('[RULE PROVIDER Response] ${response.statusCode} from ${response.requestOptions.uri}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print('[RULE PROVIDER Error] ${e.response?.statusCode} from ${e.requestOptions.uri}: ${e.message}');
        if (e.response?.data != null) {
          print('[RULE PROVIDER Error Body] ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));
    if (_token != null) {
      fetchRules();
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Options _authHeaders() {
    return Options(headers: {'Authorization': 'Bearer $_token'});
  }

  Future<void> fetchRules() async {
    if (_token == null) {
      state = const AsyncValue.error('User is not authenticated', StackTrace.empty);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final response = await _dio.get('/rules/', options: _authHeaders());
      final List<dynamic> data = response.data;
      final rules = data.map((e) => Rule.fromJson(e)).toList();
      state = AsyncValue.data(rules);
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  Future<String?> createRule({
    required String ruleType,
    required int targetVaultId,
    required double percentage,
  }) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.post(
        '/rules/',
        data: {
          'rule_type': ruleType,
          'target_vault_id': targetVaultId,
          'percentage': percentage,
        },
        options: _authHeaders(),
      );
      await fetchRules();
      return null;
    } catch (e) {
      return _extractError(e);
    }
  }

  Future<String?> updateRule({
    required int ruleId,
    required String ruleType,
    required int targetVaultId,
    required double percentage,
  }) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.put(
        '/rules/$ruleId',
        data: {
          'rule_type': ruleType,
          'target_vault_id': targetVaultId,
          'percentage': percentage,
        },
        options: _authHeaders(),
      );
      await fetchRules();
      return null;
    } catch (e) {
      return _extractError(e);
    }
  }

  Future<String?> deleteRule(int ruleId) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.delete('/rules/$ruleId', options: _authHeaders());
      await fetchRules();
      return null;
    } catch (e) {
      return _extractError(e);
    }
  }

  Future<String?> toggleRule(int ruleId) async {
    if (_token == null) return 'User is not authenticated';

    try {
      await _dio.patch('/rules/$ruleId/toggle', options: _authHeaders());
      await fetchRules();
      return null;
    } catch (e) {
      return _extractError(e);
    }
  }

  /// Find the rule targeting a specific vault (if any)
  Rule? ruleForVault(int vaultId) {
    return state.whenOrNull(
      data: (rules) {
        try {
          return rules.firstWhere((r) => r.targetVaultId == vaultId);
        } catch (_) {
          return null;
        }
      },
    );
  }

  String _extractError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('detail')) {
        return data['detail'].toString();
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }
}

final ruleProvider = StateNotifierProvider<RuleNotifier, AsyncValue<List<Rule>>>((ref) {
  // Watch authProvider so the notifier is recreated when a different user logs in.
  final token = ref.watch(authProvider).token;
  return RuleNotifier(ref, token);
});
