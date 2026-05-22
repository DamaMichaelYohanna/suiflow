import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/glass_container.dart';
import '../payments/send_payment_screen.dart';
import 'vault_provider.dart';
import 'vault_settings_screen.dart';
import 'rule_provider.dart';
import 'transaction_provider.dart';
import 'balance_provider.dart';
import '../auth/auth_screen.dart';
import '../auth/auth_provider.dart';
import '../../core/network/api_client.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vaultsAsync = ref.watch(vaultProvider);
    final balanceState = ref.watch(balanceProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.all_inclusive, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Suiver', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Offline Data',
            onPressed: () async {
              try {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Syncing offline transactions with Sui Network...')),
                );
                await ref.read(apiClientProvider).syncOfflineQueue();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Offline sync completed successfully!'), backgroundColor: Colors.green),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: $e'), backgroundColor: Colors.redAccent),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const AuthScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // Background accents
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.secondary.withOpacity(0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 200,
            right: -100,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                boxShadow: [
                  BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), blurRadius: 100),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: RefreshIndicator(
              backgroundColor: const Color(0xFF1E1E1E),
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                await Future.wait([
                  ref.read(balanceProvider.notifier).fetchBalance(),
                  ref.read(vaultProvider.notifier).fetchVaults(),
                  ref.read(transactionProvider.notifier).fetchHistory(),
                ]);
              },
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // Premium Balance Card
                  _buildBalanceCard(context, ref, balanceState),
                  const SizedBox(height: 32),
                  
                  // Vaults Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Vaults',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () => _showCreateVaultDialog(context, ref),
                        child: Row(
                          children: [
                            const Icon(Icons.add, size: 18),
                            const SizedBox(width: 4),
                            Text('Add', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  vaultsAsync.when(
                    data: (vaults) => vaults.isEmpty 
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text('No vaults yet. Create one to start saving!', style: TextStyle(color: Colors.white54)),
                        ))
                      : SizedBox(
                          height: 160,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: vaults.length,
                            separatorBuilder: (context, index) => const SizedBox(width: 16),
                            itemBuilder: (context, index) {
                              final vault = vaults[index];
                              final colors = [
                                const Color(0xFF00B0FF), // Cyber Blue
                                const Color(0xFFD500F9), // Neon Purple
                                const Color(0xFF00E676), // Spring Green
                                const Color(0xFFFF3D00), // Deep Orange
                              ];
                              final icons = [
                                Icons.shield_outlined,
                                Icons.trending_up,
                                Icons.account_balance_wallet_outlined,
                                Icons.savings_outlined,
                              ];
                              
                              final color = colors[index % colors.length];
                              final iconData = icons[index % icons.length];
                              return GestureDetector(
                                onTap: () async {
                                  final result = await Navigator.push<bool>(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (context, animation, secondaryAnimation) =>
                                          VaultSettingsScreen(
                                            vault: vault,
                                            accentColor: color,
                                            icon: iconData,
                                          ),
                                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                        return SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(1, 0),
                                            end: Offset.zero,
                                          ).animate(CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          )),
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                  if (result == true) {
                                    ref.read(vaultProvider.notifier).fetchVaults();
                                    ref.read(ruleProvider.notifier).fetchRules();
                                  }
                                },
                                child: SizedBox(
                                  width: 160,
                                  child: _buildVaultCard(
                                    context,
                                    vault.name,
                                    '\$${vault.balance.toStringAsFixed(2)}',
                                    color,
                                    iconData,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
                  ),
                  const SizedBox(height: 32),

                  // Recent Transactions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Recent Transactions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        onPressed: () {},
                        child: const Text('View All', style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ref.watch(transactionProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(
                      child: Text('Could not load transactions', style: const TextStyle(color: Colors.white54)),
                    ),
                    data: (txns) => txns.isEmpty
                      ? GlassContainer(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 40, color: Colors.white24),
                                const SizedBox(height: 12),
                                const Text('No transactions yet', style: TextStyle(color: Colors.white38)),
                              ],
                            ),
                          ),
                        )
                      : GlassContainer(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: txns.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final tx = txns[index];
                              final isSent = tx.isSent;
                              final primary = Theme.of(context).colorScheme.primary;
                              final secondary = Theme.of(context).colorScheme.secondary;
                              final color = isSent ? primary : secondary;
                              final icon = isSent ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
                              final sign = isSent ? '-' : '+';
                              final date = '${tx.timestamp.day} ${_monthName(tx.timestamp.month)} ${tx.timestamp.year}';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: color.withOpacity(0.3)),
                                  ),
                                  child: Icon(icon, color: color, size: 20),
                                ),
                                title: Text(
                                  tx.counterpartName,
                                  style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                                subtitle: Text(
                                  '$date  ·  ${tx.status}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                trailing: Text(
                                  '$sign\$${tx.amount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isSent ? Colors.white : secondary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                  ),
                  const SizedBox(height: 24),

                ],
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, WidgetRef ref, BalanceState balanceState) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E1E1E),
            const Color(0xFF0F0F0F),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Balance',
                style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi, size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Text('Online', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          if (balanceState.isLoading)
            const SizedBox(
              height: 42,
              child: Align(
                alignment: Alignment.centerLeft,
                child: CircularProgressIndicator(),
              ),
            )
          else if (balanceState.error != null)
            const Text(
              'Error loading balance',
              style: TextStyle(color: Colors.redAccent, fontSize: 16),
            )
          else
            Text(
              '${balanceState.balance.toStringAsFixed(2)} SUI',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            balanceState.isLoading ? 'Loading...' : '~ \$${(balanceState.balance * 1.05).toStringAsFixed(2)} USD', // Mock SUI conversion
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(context, Icons.send_rounded, 'Send', () {
                Navigator.push(context, PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => const SendPaymentScreen(),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    return SlideTransition(
                      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                      ),
                      child: child,
                    );
                  },
                ));
              }),
              _buildActionButton(context, Icons.qr_code_scanner_rounded, 'Receive', () {}),
              _buildActionButton(context, Icons.swap_horiz_rounded, 'Swap', () {}),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.05),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildVaultCard(BuildContext context, String title, String amount, Color accentColor, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.15),
            Colors.transparent,
          ],
        ),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        color: const Color(0xFF121212),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(amount, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
  void _showCreateVaultDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
            title: const Text('Create New Vault', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  enabled: !isLoading,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g. Rainy Day, New Car',
                    hintStyle: const TextStyle(color: Colors.white24),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ]
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;
                        
                        setState(() {
                          isLoading = true;
                          errorText = null;
                        });
                        
                        final err = await ref.read(vaultProvider.notifier).createVault(text);
                        
                        if (context.mounted) {
                          if (err != null) {
                            setState(() {
                              isLoading = false;
                              errorText = err;
                            });
                          } else {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Vault created successfully!'), backgroundColor: Colors.green),
                            );
                          }
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }
}
