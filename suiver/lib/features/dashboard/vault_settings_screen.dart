import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/glass_container.dart';
import 'vault_model.dart';
import 'vault_provider.dart';
import 'rule_provider.dart';
import 'rule_model.dart';

class VaultSettingsScreen extends ConsumerStatefulWidget {
  final Vault vault;
  final Color accentColor;
  final IconData icon;

  const VaultSettingsScreen({
    super.key,
    required this.vault,
    required this.accentColor,
    required this.icon,
  });

  @override
  ConsumerState<VaultSettingsScreen> createState() => _VaultSettingsScreenState();
}

class _VaultSettingsScreenState extends ConsumerState<VaultSettingsScreen> {
  final _withdrawController = TextEditingController();
  double _allocationPercentage = 0;
  bool _ruleIsActive = false;
  int? _existingRuleId;
  bool _isWithdrawing = false;
  bool _isSavingRule = false;
  bool _isDeleting = false;
  bool _isDeletingRule = false;
  bool _isTogglingRule = false;
  bool _hasLoadedRule = false;

  @override
  void initState() {
    super.initState();
    // Ensure rules are fetched
    Future.microtask(() => ref.read(ruleProvider.notifier).fetchRules());
  }

  @override
  void dispose() {
    _withdrawController.dispose();
    super.dispose();
  }

  void _loadExistingRule() {
    if (_hasLoadedRule) return;
    final rule = ref.read(ruleProvider.notifier).ruleForVault(widget.vault.id);
    if (rule != null) {
      _allocationPercentage = rule.percentage;
      _ruleIsActive = rule.isActive;
      _existingRuleId = rule.id;
    }
    _hasLoadedRule = true;
  }

  void _doWithdraw() async {
    final amountStr = _withdrawController.text.trim();
    if (amountStr.isEmpty) {
      _showSnack('Please enter an amount', isError: true);
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      _showSnack('Amount must be greater than zero', isError: true);
      return;
    }
    if (amount > widget.vault.balance) {
      _showSnack(
        'Insufficient balance. Available: ${widget.vault.balance.toStringAsFixed(4)} SUI',
        isError: true,
      );
      return;
    }

    setState(() => _isWithdrawing = true);
    final err = await ref.read(vaultProvider.notifier).withdrawFromVault(widget.vault.id, amount);
    if (mounted) {
      setState(() => _isWithdrawing = false);
      if (err != null) {
        _showSnack(err, isError: true);
      } else {
        _withdrawController.clear();
        _showSnack('Withdrawn ${amount.toStringAsFixed(4)} SUI successfully!');
        // Pop back since vault data has changed
        Navigator.pop(context, true);
      }
    }
  }

  void _saveRule() async {
    if (_allocationPercentage <= 0) {
      _showSnack('Set a percentage above 0%', isError: true);
      return;
    }

    setState(() => _isSavingRule = true);
    String? err;
    if (_existingRuleId != null) {
      err = await ref.read(ruleProvider.notifier).updateRule(
        ruleId: _existingRuleId!,
        ruleType: 'salary_split',
        targetVaultId: widget.vault.id,
        percentage: _allocationPercentage,
      );
    } else {
      err = await ref.read(ruleProvider.notifier).createRule(
        ruleType: 'salary_split',
        targetVaultId: widget.vault.id,
        percentage: _allocationPercentage,
      );
    }

    if (mounted) {
      setState(() {
        _isSavingRule = false;
        _hasLoadedRule = false; // Force reload on next build
      });
      if (err != null) {
        _showSnack(err, isError: true);
      } else {
        _showSnack(_existingRuleId != null ? 'Rule updated!' : 'Rule created!');
      }
    }
  }

  void _toggleRule() async {
    if (_existingRuleId == null) return;
    setState(() => _isTogglingRule = true);
    final err = await ref.read(ruleProvider.notifier).toggleRule(_existingRuleId!);
    if (mounted) {
      setState(() {
        _isTogglingRule = false;
        _hasLoadedRule = false;
      });
      if (err != null) _showSnack(err, isError: true);
    }
  }

  void _deleteRule() async {
    if (_existingRuleId == null) return;
    setState(() => _isDeletingRule = true);
    final err = await ref.read(ruleProvider.notifier).deleteRule(_existingRuleId!);
    if (mounted) {
      setState(() {
        _isDeletingRule = false;
        _existingRuleId = null;
        _allocationPercentage = 0;
        _ruleIsActive = false;
        _hasLoadedRule = false;
      });
      if (err != null) {
        _showSnack(err, isError: true);
      } else {
        _showSnack('Rule deleted');
      }
    }
  }

  void _confirmDeleteVault() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
        ),
        title: const Text('Delete Vault', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "${widget.vault.name}"?\n\nThis will also remove any allocation rules targeting this vault. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _doDeleteVault();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _doDeleteVault() async {
    setState(() => _isDeleting = true);
    final err = await ref.read(vaultProvider.notifier).deleteVault(widget.vault.id);
    // Also refresh rules since cascade may have deleted some
    await ref.read(ruleProvider.notifier).fetchRules();
    if (mounted) {
      setState(() => _isDeleting = false);
      if (err != null) {
        _showSnack(err, isError: true);
      } else {
        _showSnack('Vault deleted');
        Navigator.pop(context, true);
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.redAccent : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Watch rules so we react to updates
    final rulesAsync = ref.watch(ruleProvider);
    rulesAsync.whenData((_) => _loadExistingRule());

    final accent = widget.accentColor;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.vault.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background accent glow
          Positioned(
            top: -60,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.08),
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(0.15), blurRadius: 120),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            left: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.05),
                boxShadow: [
                  BoxShadow(color: accent.withOpacity(0.1), blurRadius: 80),
                ],
              ),
            ),
          ),

          SafeArea(
            child: _isDeleting
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: accent),
                        const SizedBox(height: 16),
                        const Text('Deleting vault...', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ─── VAULT INFO HEADER ───
                        _buildVaultHeader(accent),
                        const SizedBox(height: 28),

                        // ─── WITHDRAW SECTION ───
                        _buildSectionTitle('Withdraw Funds', Icons.account_balance_wallet_outlined, accent),
                        const SizedBox(height: 12),
                        _buildWithdrawSection(accent),
                        const SizedBox(height: 28),

                        // ─── ALLOCATION RULE SECTION ───
                        _buildSectionTitle('Allocation Rule', Icons.auto_fix_high_rounded, accent),
                        const SizedBox(height: 12),
                        _buildAllocationSection(accent),
                        const SizedBox(height: 36),

                        // ─── DANGER ZONE ───
                        _buildDangerZone(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildVaultHeader(Color accent) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withOpacity(0.18),
            const Color(0xFF0F0F0F),
          ],
        ),
        border: Border.all(color: accent.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: accent.withOpacity(0.1), blurRadius: 30, spreadRadius: -5),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withOpacity(0.3)),
            ),
            child: Icon(widget.icon, color: accent, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.vault.name,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.vault.balance.toStringAsFixed(4)} SUI',
                  style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (widget.vault.canWithdraw)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text('Withdrawable', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color accent) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildWithdrawSection(Color accent) {
    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available: ${widget.vault.balance.toStringAsFixed(4)} SUI',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _withdrawController,
            enabled: !_isWithdrawing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: const TextStyle(color: Colors.white24),
              suffixText: 'SUI',
              suffixStyle: const TextStyle(color: Colors.white38, fontSize: 16),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent.withOpacity(0.3))),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: accent)),
            ),
          ),
          const SizedBox(height: 8),
          // Quick amount buttons
          Row(
            children: [25, 50, 75, 100].map((pct) {
              final quickAmount = widget.vault.balance * pct / 100;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: _isWithdrawing
                        ? null
                        : () {
                            _withdrawController.text = quickAmount.toStringAsFixed(4);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('$pct%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isWithdrawing || !widget.vault.canWithdraw) ? null : _doWithdraw,
              icon: _isWithdrawing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded),
              label: Text(_isWithdrawing ? 'Withdrawing...' : 'Withdraw'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (!widget.vault.canWithdraw)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'This vault does not have a VaultCap and cannot process withdrawals.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAllocationSection(Color accent) {
    final hasRule = _existingRuleId != null;

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasRule
                ? 'Currently allocating ${_allocationPercentage.toStringAsFixed(0)}% of incoming funds'
                : 'No allocation rule set for this vault',
            style: TextStyle(
              color: hasRule ? accent : Colors.white54,
              fontSize: 14,
              fontWeight: hasRule ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'When you receive a payment, this percentage will be automatically diverted to this vault.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 20),

          // Percentage display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Allocation', style: TextStyle(color: Colors.white60)),
              Text(
                '${_allocationPercentage.toStringAsFixed(0)}%',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 22),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: Colors.white10,
              thumbColor: Colors.white,
              overlayColor: accent.withOpacity(0.2),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _allocationPercentage,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: _isSavingRule
                  ? null
                  : (val) {
                      setState(() => _allocationPercentage = val);
                    },
            ),
          ),
          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSavingRule ? null : _saveRule,
              icon: _isSavingRule
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(hasRule ? Icons.save_rounded : Icons.add_rounded),
              label: Text(_isSavingRule
                  ? 'Saving...'
                  : hasRule
                      ? 'Update Rule'
                      : 'Create Rule'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent.withOpacity(0.9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          // Toggle & Delete buttons (only if rule exists)
          if (hasRule) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                // Toggle
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTogglingRule ? null : _toggleRule,
                    icon: _isTogglingRule
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            _ruleIsActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                            size: 20,
                          ),
                    label: Text(_ruleIsActive ? 'Pause' : 'Activate'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _ruleIsActive ? Colors.orangeAccent : Colors.greenAccent,
                      side: BorderSide(
                        color: (_ruleIsActive ? Colors.orangeAccent : Colors.greenAccent).withOpacity(0.4),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Delete rule
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isDeletingRule ? null : _deleteRule,
                    icon: _isDeletingRule
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                        : const Icon(Icons.delete_outline, size: 20),
                    label: const Text('Remove Rule'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: (_ruleIsActive ? Colors.greenAccent : Colors.orangeAccent).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _ruleIsActive ? '● Rule is active' : '● Rule is paused',
                  style: TextStyle(
                    color: _ruleIsActive ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
        color: Colors.redAccent.withOpacity(0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
              SizedBox(width: 8),
              Text('Danger Zone', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Deleting this vault will remove it from your account and delete any allocation rules targeting it. The on-chain object will remain.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _confirmDeleteVault,
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Delete Vault'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
