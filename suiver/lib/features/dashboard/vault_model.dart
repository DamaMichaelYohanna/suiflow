class Vault {
  final int id;
  final String name;
  final String objectId;
  final String? vaultCapId;
  final double balance;

  Vault({
    required this.id,
    required this.name,
    required this.objectId,
    this.vaultCapId,
    this.balance = 0.0,
  });

  factory Vault.fromJson(Map<String, dynamic> json) {
    return Vault(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      objectId: json['object_id'] ?? '',
      vaultCapId: json['vault_cap_id'],
      balance: (json['balance'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'object_id': objectId,
      'vault_cap_id': vaultCapId,
      'balance': balance,
    };
  }

  /// Whether this vault supports withdrawals (has a VaultCap stored)
  bool get canWithdraw => vaultCapId != null && vaultCapId!.isNotEmpty;
}
