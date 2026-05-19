import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ui/glass_container.dart';
import '../dashboard/dashboard_screen.dart';
import 'auth_provider.dart';

enum AuthMode { login, signup }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  AuthMode _mode = AuthMode.login;
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic)),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() async {
    final notifier = ref.read(authProvider.notifier);
    
    if (_mode == AuthMode.login) {
      if (_phoneController.text.isEmpty || _passwordController.text.isEmpty) return;
      await notifier.login(_phoneController.text, _passwordController.text);
    } else {
      if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) return;
      await notifier.register(
        phoneNumber: _phoneController.text.isNotEmpty ? _phoneController.text : null,
        username: _usernameController.text,
        password: _passwordController.text,
        fullName: _nameController.text,
        socialId: ref.read(authProvider).socialId,
        authMethod: ref.read(authProvider).socialId != null ? 'GOOGLE' : 'PHONE',
      );
    }
    
    _handleAuthResult();
  }

  void _zkLogin() async {
    // Simulate getting a JWT from Google
    final mockJwt = "google_user_${DateTime.now().millisecondsSinceEpoch}";
    await ref.read(authProvider.notifier).zkLogin(mockJwt);
    _handleAuthResult();
  }

  void _handleAuthResult() {
    final state = ref.read(authProvider);
    if (state.isAuthenticated) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen()),
      );
    } else if (state.error == 'SOCIAL_NOT_REGISTERED') {
      setState(() {
        _mode = AuthMode.signup;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Social ID verified. Please complete your profile.')),
      );
      ref.read(authProvider.notifier).clearError();
    } else if (state.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.error!), backgroundColor: Colors.redAccent),
      );
      ref.read(authProvider.notifier).clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Background accents
          _buildBackground(),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      const SizedBox(height: 60),
                      _buildLogo(),
                      const SizedBox(height: 32),
                      _buildTitle(),
                      const SizedBox(height: 48),
                      
                      // Auth Card
                      GlassContainer(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _buildModeToggle(),
                            const SizedBox(height: 32),
                            if (_mode == AuthMode.signup) ...[
                              _buildTextField(_nameController, 'Full Name', Icons.person_outline),
                              const SizedBox(height: 20),
                              _buildTextField(_usernameController, 'Username', Icons.alternate_email),
                              const SizedBox(height: 20),
                            ],
                            _buildTextField(_phoneController, 'Phone Number', Icons.phone_android, keyboardType: TextInputType.phone),
                            const SizedBox(height: 20),
                            _buildTextField(_passwordController, 'Password', Icons.lock_outline, obscureText: true),
                            const SizedBox(height: 32),
                            _buildSubmitButton(authState.isLoading),
                            const SizedBox(height: 24),
                            _buildDivider(),
                            const SizedBox(height: 24),
                            _buildSocialButton(authState.isLoading),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
              boxShadow: [
                BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(0.2), blurRadius: 100),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: -50,
          left: -100,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
              boxShadow: [
                BoxShadow(color: Theme.of(context).colorScheme.secondary.withOpacity(0.2), blurRadius: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Hero(
      tag: 'app_logo',
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3), width: 2),
        ),
        child: Icon(
          Icons.all_inclusive,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          'Suiver',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Programmable money, evolved.',
          style: TextStyle(color: Colors.white60, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Row(
      children: [
        _buildModeButton(AuthMode.login, 'Login'),
        const SizedBox(width: 16),
        _buildModeButton(AuthMode.signup, 'Sign Up'),
      ],
    );
  }

  Widget _buildModeButton(AuthMode mode, String label) {
    final isSelected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType? keyboardType, bool obscureText = false}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        labelStyle: const TextStyle(color: Colors.white60),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.02),
      ),
    );
  }

  Widget _buildSubmitButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : _submit,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.black,
        ),
        child: isLoading 
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
            : Text(_mode == AuthMode.login ? 'Login to Wallet' : 'Create Account', 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('OR', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        Expanded(child: Divider(color: Colors.white.withOpacity(0.1))),
      ],
    );
  }

  Widget _buildSocialButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: isLoading ? null : _zkLogin,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.g_mobiledata, color: Colors.white, size: 32),
            const SizedBox(width: 8),
            Text(_mode == AuthMode.login ? 'Continue with Google' : 'Sign up with Google', 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
