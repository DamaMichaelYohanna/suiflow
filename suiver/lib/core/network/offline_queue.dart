import 'package:hive_flutter/hive_flutter.dart';

class OfflineQueue {
  static const String _boxName = 'offline_transactions';
  
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxName);
  }

  static Box get _box => Hive.box(_boxName);

  static Future<void> addTransaction(Map<String, dynamic> transactionData) async {
    // Generate a simple unique ID
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    transactionData['queue_id'] = id;
    await _box.put(id, transactionData);
  }

  static List<Map<String, dynamic>> getPendingTransactions() {
    final list = <Map<String, dynamic>>[];
    for (var key in _box.keys) {
      final item = _box.get(key);
      if (item != null) {
        list.add(Map<String, dynamic>.from(item as Map));
      }
    }
    return list;
  }

  static Future<void> removeTransaction(String id) async {
    await _box.delete(id);
  }
  
  static Future<void> clearAll() async {
    await _box.clear();
  }
}
