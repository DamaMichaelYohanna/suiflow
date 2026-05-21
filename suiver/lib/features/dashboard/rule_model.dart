class Rule {
  final int id;
  final String ruleType;
  final int? targetVaultId;
  final double percentage;
  final bool isActive;

  Rule({
    required this.id,
    required this.ruleType,
    this.targetVaultId,
    required this.percentage,
    required this.isActive,
  });

  factory Rule.fromJson(Map<String, dynamic> json) {
    return Rule(
      id: json['id'] ?? 0,
      ruleType: json['rule_type'] ?? '',
      targetVaultId: json['target_vault_id'],
      percentage: (json['percentage'] ?? 0).toDouble(),
      isActive: json['is_active'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'rule_type': ruleType,
        'target_vault_id': targetVaultId,
        'percentage': percentage,
        'is_active': isActive,
      };

  /// Convert to the request format for creating/updating a rule (exclude id, isActive)
  Map<String, dynamic> toCreateRequest() => {
        'rule_type': ruleType,
        'target_vault_id': targetVaultId,
        'percentage': percentage,
      };
}
