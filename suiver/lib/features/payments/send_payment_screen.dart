import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/network/offline_queue.dart';
import '../../core/network/config.dart';
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
      final dio = Dio(BaseOptions(baseUrl: '${AppConfig.baseUrl}/auth'));
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          print('[LOOKUP Request] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print(
              '[LOOKUP Response] ${response.statusCode} from ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          print(
              '[LOOKUP Error] ${e.response?.statusCode} from ${e.requestOptions.uri}: ${e.message}');
          return handler.next(e);
        },
      ));

      final response =
          await dio.get('/lookup', queryParameters: {'query': query});

      if (mounted) {
        setState(() {
          _nameController.text =
              response.data['full_name'] ?? response.data['username'];
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

  void _showResultDialog({
    required bool isSuccess,
    required String title,
    required String description,
    String? digest,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: const Color(0xFF16161E),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon badge
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSuccess
                        ? const Color(0xFF00E676).withOpacity(0.15)
                        : const Color(0xFF00B0FF).withOpacity(0.15),
                    border: Border.all(
                      color: isSuccess
                          ? const Color(0xFF00E676)
                          : const Color(0xFF00B0FF),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isSuccess ? Icons.check_rounded : Icons.schedule_rounded,
                    size: 40,
                    color: isSuccess
                        ? const Color(0xFF00E676)
                        : const Color(0xFF00B0FF),
                  ),
                ),
                const SizedBox(height: 20),
                // Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                // Description
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                    height: 1.5,
                  ),
                ),
                // Digest chip (optional)
                if (digest != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      'Digest: ${digest.length > 16 ? digest.substring(0, 16) : digest}…',
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // Action button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                    child: const Text('Back to Dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  void _sendPayment() async {
    final auth = ref.read(authProvider);

    // Basic validation
    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a recipient phone or username')));
      return;
    }
    if (_amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter an amount')));
      return;
    }
    if (auth.phoneNumber == _phoneController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot send money to yourself')));
      return;
    }

    final amount = double.tryParse(_amountController.text) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amount must be greater than zero')));
      return;
    }

    final split =
        _savingsPercentage > 0 ? {'savings': _savingsPercentage.toInt()} : null;

    final payload = {
      'receiver_phone': _phoneController.text,
      'amount': amount,
      'programmable_split': split,
      'status': 'QUEUED',
      'timestamp': DateTime.now().toIso8601String(),
    };

    setState(() => _isVerifying = true);

    try {
      final dio = Dio(BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: auth.token != null
            ? {'Authorization': 'Bearer ${auth.token}'}
            : {},
      ));

      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          print('[SEND PAYMENT Request] ${options.method} ${options.uri}');
          if (options.data != null) print('[SEND PAYMENT Body] ${options.data}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print('[SEND PAYMENT Response] ${response.statusCode} from ${response.requestOptions.uri}');
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          print('[SEND PAYMENT Error] ${e.response?.statusCode}: ${e.message}');
          if (e.response?.data != null) print('[SEND PAYMENT Error Body] ${e.response?.data}');
          return handler.next(e);
        },
      ));

      final response = await dio.post('/payments/send', data: {
        'receiver_phone': _phoneController.text,
        'amount': amount,
        'programmable_split': split,
      });

      if (mounted) {
        setState(() => _isVerifying = false);
        final digest = response.data['sui_digest'] as String?;
        _showResultDialog(
          isSuccess: true,
          title: 'Payment Sent!',
          description:
              'Your payment of \$$amount USDC to ${_nameController.text.isNotEmpty ? _nameController.text : _phoneController.text} has been submitted to the Sui network.',
          digest: digest,
        );
      }
    } on DioException catch (e) {
      if (mounted) setState(() => _isVerifying = false);

      // Connectivity error → queue offline
      final isConnectivityError = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError;

      if (isConnectivityError) {
        print('[SEND PAYMENT] Connectivity error, queuing offline: $e');
        await OfflineQueue.addTransaction(payload);
        if (mounted) {
          _showResultDialog(
            isSuccess: false,
            title: 'Payment Queued',
            description:
                'No internet connection detected. Your payment has been saved and will sync automatically when you\'re back online.',
          );
        }
      } else {
        // Server returned an error (4xx / 5xx) — show the message, don\'t queue
        print('[SEND PAYMENT] Server error (${e.response?.statusCode}): ${e.response?.data}');
        final detail = e.response?.data is Map
            ? (e.response?.data['detail'] ?? 'Payment failed')
            : 'Payment failed (${e.response?.statusCode})';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(detail.toString()),
              backgroundColor: const Color(0xFFFF3D00),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
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
                          style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Phone or Username',
                            prefixIcon: const Icon(Icons.person_search_rounded),
                            hintStyle:
                                TextStyle(color: Colors.white.withOpacity(0.3)),
                            suffixIcon: _isVerifying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : _lookupError != null
                                    ? const Icon(Icons.error_outline,
                                        color: Colors.redAccent)
                                    : _nameController.text.isNotEmpty
                                        ? const Icon(Icons.check_circle_outline,
                                            color: Colors.greenAccent)
                                        : null,
                          ),
                        ),
                        if (_lookupError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 12),
                            child: Text(_lookupError!,
                                style: const TextStyle(
                                    color: Colors.redAccent, fontSize: 12)),
                          ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _nameController,
                          readOnly: true, // Only show name from lookup
                          style: TextStyle(
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Recipient Name (Auto-lookup)',
                            prefixIcon: const Icon(Icons.badge_outlined),
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
                          style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onSurface),
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
                                    color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Enable auto-savings for the recipient. A portion of this payment will be automatically diverted to their locked Savings Vault.',
                          style: TextStyle(
                              color: Color.fromARGB(137, 0, 0, 0), height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Savings Contribution',
                                style: TextStyle(
                                    color: Color.fromARGB(179, 0, 0, 0))),
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
