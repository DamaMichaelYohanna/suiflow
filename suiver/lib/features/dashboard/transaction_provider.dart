import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../auth/auth_provider.dart';
import '../../core/network/config.dart';

class TransactionItem {
  final int id;
  final String direction; // "sent" | "received"
  final String counterpartName;
  final String? counterpartPhone;
  final double amount;
  final String status;
  final DateTime timestamp;
  final String? suiDigest;

  const TransactionItem({
    required this.id,
    required this.direction,
    required this.counterpartName,
    this.counterpartPhone,
    required this.amount,
    required this.status,
    required this.timestamp,
    this.suiDigest,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      id: json['id'] as int,
      direction: json['direction'] as String,
      counterpartName: json['counterpart_name'] as String,
      counterpartPhone: json['counterpart_phone'] as String?,
      amount: (json['amount'] as num).toDouble(),
      status: json['status'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      suiDigest: json['sui_digest'] as String?,
    );
  }

  bool get isSent => direction == 'sent';
}

class TransactionNotifier extends StateNotifier<AsyncValue<List<TransactionItem>>> {
  final Ref ref;
  final Dio _dio;

  TransactionNotifier(this.ref)
      : _dio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl)),
        super(const AsyncValue.loading()) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        print('[TX HISTORY Request] ${options.method} ${options.uri}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        print('[TX HISTORY Response] ${response.statusCode}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        print('[TX HISTORY Error] ${e.response?.statusCode}: ${e.message}');
        if (e.response?.data != null) print('[TX HISTORY Error Body] ${e.response?.data}');
        return handler.next(e);
      },
    ));
    fetchHistory();
  }

  Future<void> fetchHistory() async {
    final token = ref.read(authProvider).token;
    if (token == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    try {
      final response = await _dio.get(
        '/payments/history',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final List<dynamic> data = response.data;
      final items = data.map((e) => TransactionItem.fromJson(e as Map<String, dynamic>)).toList();
      state = AsyncValue.data(items);
    } catch (e, stack) {
      print('[TX HISTORY] Failed to fetch history: $e');
      state = AsyncValue.error(e, stack);
    }
  }
}

final transactionProvider =
    StateNotifierProvider<TransactionNotifier, AsyncValue<List<TransactionItem>>>((ref) {
  return TransactionNotifier(ref);
});
