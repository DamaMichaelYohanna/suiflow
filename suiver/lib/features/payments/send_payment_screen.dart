import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/offline_queue.dart';
import '../auth/auth_provider.dart';
import '../../core/ui/glass_container.dart';

class SendPaymentScreen extends ConsumerStatefulWidget {
  const SendPaymentScreen({super.key});

  @override
  ConsumerState<SendPaymentScreen> createState() => _SendPaymentScreenState();
}

class _SendPaymentScreenState extends ConsumerState<SendPaymentScreen>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  double _savingsPercentage = 0.0;
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  bool _isVerifying = false;
  String? _lookupError;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation =
        CurvedAnimation(parent: _animController, curve: Curves.elasticOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _lookupUser(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _isVerifying = true;
      _lookupError = null;
    });

    try {
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8000/api/auth'));
      final response = await dio.get('/lookup', queryParameters: {'query': query});
      
      if (mounted) {
        setState(() {
          _nameController.text = response.data['full_name'] ?? response.data['username'];
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _lookupError = 'User not found';
        });
      }
    }
  }

  void _sendPayment() async {
    final auth = ref.read(authProvider);
    
    if (auth.phoneNumber == _phoneController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot send money to yourself'))
      );
      return;
    }

    final payload = {
      'receiver_phone': _phoneController.text,
      'amount': double.tryParse(_amountController.text) ?? 0.0,
      'programmable_split': _savingsPercentage > 0
          ? {'savings': _savingsPercentage.toInt()}
          : null,
      'status': 'QUEUED',
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Store locally first (Offline-First)
    await OfflineQueue.addTransaction(payload);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: GlassContainer(
              padding: const EdgeInsets.all(32),
              borderRadius: 32,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 24),
                  const Text('Payment Queued',
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text('Your transaction will sync shortly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60)),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Go back to dashboard
                    },
                    child: const Text('Back to Home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Send Money',
            style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background accents
          Positioned(
            top: 100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                boxShadow: [
                  BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.1),
                      blurRadius: 100),
                ],
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),

                  // Main Transaction Card
                  GlassContainer(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Recipient Details',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: (val) {
                            if (val.length >= 10) _lookupUser(val);
                          },
                          style: const TextStyle(
                              fontSize: 18, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Phone or Username',
                            prefixIcon:
                                const Icon(Icons.person_search_rounded),
                            hintStyle:
                                TextStyle(color: Colors.white.withOpacity(0.3)),
                            suffixIcon: _isVerifying 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : _lookupError != null 
                                  ? const Icon(Icons.error_outline, color: Colors.redAccent)
                                  : _nameController.text.isNotEmpty 
                                    ? const Icon(Icons.check_circle_outline, color: Colors.greenAccent)
                                    : null,
                          ),
                        ),
                        if (_lookupError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 12),
                            child: Text(_lookupError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _nameController,
                          readOnly: true, // Only show name from lookup
                          style: const TextStyle(
                              fontSize: 18, color: Colors.white70),
                          decoration: InputDecoration(
                            hintText: 'Recipient Name (Auto-lookup)',
                            prefixIcon:
                                const Icon(Icons.badge_outlined),
                            hintStyle:
                                TextStyle(color: Colors.white.withOpacity(0.3)),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text('Amount to Send',
                            style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                          decoration: InputDecoration(
                            hintText: '0.00',
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(top: 8, right: 8),
                              child: Text('\$',
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white30)),
                            ),
                            suffixText: 'USDC',
                            suffixStyle: const TextStyle(
                                fontSize: 18, color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Programmable Split (PTB) Section
                  Text(
                    'Automation Flow',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white.withOpacity(0.05),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.auto_fix_high_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Text('Programmable Split (PTB)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Enable auto-savings for the recipient. A portion of this payment will be automatically diverted to their locked Savings Vault.',
                          style: TextStyle(color: Colors.white54, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Savings Contribution',
                                style: TextStyle(color: Colors.white70)),
                            Text('${_savingsPercentage.toInt()}%',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18)),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor:
                                Theme.of(context).colorScheme.primary,
                            inactiveTrackColor: Colors.white10,
                            thumbColor: Colors.white,
                            overlayColor: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.2),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: _savingsPercentage,
                            min: 0,
                            max: 100,
                            divisions: 10,
                            onChanged: (val) {
                              setState(() => _savingsPercentage = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),
                  ElevatedButton(
                    onPressed: _sendPayment,
                    child: const Text('Send (Offline-First)'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
