class Vault {
  final String name;
  final String objectId;
  final double balance; // Simulated balance for now

  Vault({
    required this.name,
    required this.objectId,
    this.balance = 0.0,
  });

  factory Vault.fromJson(Map<String, dynamic> json) {
    return Vault(
      name: json['name'] ?? '',
      objectId: json['object_id'] ?? '',
      balance: (json['balance'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'object_id': objectId,
      'balance': balance,
    };
  }
}
