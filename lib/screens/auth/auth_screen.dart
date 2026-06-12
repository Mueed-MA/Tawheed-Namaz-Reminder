import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../services/firebase_db.dart';
import '../home/home_screen.dart';
import '../home/faq_screen.dart';
import '../home/contact_us_screen.dart';
import 'register_candidate_screen.dart';
import 'masjid_registration_screen.dart';
import '../admin/masjid_time_settings_screen.dart';
import '../admin/super_admin_approval_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'forgot_password2.dart';
import '../../services/notification_service.dart';

// â”€â”€â”€ Design Tokens â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _AuthColors {
  static const Color primary = Color(0xFF1A5C38);
  static const Color primaryLight = Color(0xFF2E7D4F);
  static const Color gold = Color(0xFFB8963E);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1A2B22);
  static const Color textSecondary = Color(0xFF6B7C73);
  static const Color divider = Color(0xFFE8EDE9);
}

enum AuthScreenMode { entry, login }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthScreenMode.login});

  final AuthScreenMode initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  late AuthScreenMode _mode;
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;
  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _fadeController.forward();
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _fadeController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isLogin => _mode == AuthScreenMode.login;

  bool get _showBackButtonOnLogin =>
      _isLogin && widget.initialMode == AuthScreenMode.entry;

  void _showLogin() => setState(() => _mode = AuthScreenMode.login);

  void _showEntry() => setState(() => _mode = AuthScreenMode.entry);

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: _AuthColors.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // â”€â”€â”€ Login Logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      _showMessage('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = await FirebaseDB.instance.login(identifier, password);

      if (user != null) {
        if (user['role'] == 'masjid_admin' && user['approved'] == false) {
          _showMessage('Your account is pending approval');
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        final String role = user['role'];
        final String adminUsernameLower =
            (user['adminUsernameLower'] as String? ?? '').trim();
        final String resolvedMobile = role == 'masjid_admin'
            ? (adminUsernameLower.isNotEmpty
                  ? adminUsernameLower
                  : (user['mobile'] as String? ?? '').trim())
            : (user['mobile'] as String? ?? '').trim();
        if (resolvedMobile.isEmpty) {
          _showMessage('Login failed: missing admin or mobile mapping');
          return;
        }
        await prefs.setBool('isLoggedIn', true);
        await prefs.setString('userMobile', resolvedMobile);
        await prefs.setString('userRole', role);
        if (adminUsernameLower.isNotEmpty) {
          await prefs.setString('adminUsernameLower', adminUsernameLower);
        } else {
          await prefs.remove('adminUsernameLower');
        }

        await NotificationService.instance.syncRoleBasedFcmSubscriptions(
          role: role,
          mobile: resolvedMobile,
        );

        if (role == 'masjid_admin') {
          if (adminUsernameLower.isNotEmpty) {
            // Best-effort repair for shared-mobile admin mappings.
            await FirebaseDB.instance.repairAdminUsernameMapping(
              adminUsernameLower,
            );
          }
          final String masjidId = (user['masjidId'] as String? ?? '').trim();
          if (masjidId.isNotEmpty) {
            await prefs.setString('masjidId', masjidId);
          } else {
            await prefs.remove('masjidId');
            _showMessage('Login failed: missing masjid mapping');
            return;
          }
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => MasjidTimeSettingsScreen(
                  ownerMobile: resolvedMobile,
                  masjidId: masjidId.isEmpty ? null : masjidId,
                ),
              ),
            );
          }
          return;
        }
        if (role == 'super_admin') {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => const SuperAdminApprovalScreen(),
              ),
            );
          }
          return;
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  HomeScreen(userMobile: resolvedMobile, role: role),
            ),
          );
        }
      } else {
        _showMessage('Invalid credentials');
      }
    } catch (e) {
      _showMessage('Login failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _submit() {
    _login();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // â”€â”€â”€ Background Image â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/1bg.jpeg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // â”€â”€â”€ Gradient Overlay â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0),
                  Colors.black.withOpacity(0),
                  Colors.black.withOpacity(0),
                ],
              ),
            ),
          ),
          // â”€â”€â”€ Decorative Elements â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            top: -50,
            right: -50,
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _AuthColors.gold.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: _AuthColors.primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // â”€â”€â”€ Content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SafeArea(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_showBackButtonOnLogin)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(top: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.25),
                                ),
                              ),
                              child: IconButton(
                                onPressed: _showEntry,
                                icon: const Icon(
                                  Icons.arrow_back_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 40),
                        // â”€â”€â”€ Logo/Title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        _buildHeader(),
                        const SizedBox(height: 50),
                        // â”€â”€â”€ Form Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        _buildFormCard(),
                        if (_isLogin) ...[
                          const SizedBox(height: 24),
                          // â”€â”€â”€ Bottom Links â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          _buildBottomLinks(),
                          const SizedBox(height: 12),
                          _buildSupportLinks(),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_isLogin)
            Positioned(
              left: 24,
              right: 24,
              bottom: 68,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBottomLinks(),
                    const SizedBox(height: 4),
                    _buildSupportLinks(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _AuthColors.gold.withOpacity(0.15),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: _AuthColors.gold.withOpacity(0.4),
              width: 2,
            ),
          ),
          child: Icon(Icons.mosque_rounded, size: 40, color: _AuthColors.gold),
        ),
        const SizedBox(height: 20),
        Text(
          '',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Text(
              _isLogin ? 'Tawheed Namaz Reminder' : 'Start with a new account',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: const Color.fromARGB(255, 185, 156, 97).withOpacity(0.7),
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    if (!_isLogin) {
      return _buildEntryCard();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            _buildTextField(
              controller: _identifierController,
              label: 'Mobile / Admin Username',
              icon: Icons.phone_rounded,
              hintText: 'Enter mobile (user) or username (admin)',
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              icon: Icons.lock_rounded,
              hintText: 'Enter your password',
              obscureText: !_showPassword,
              suffixIcon: true,
              onToggleVisibility: () {
                setState(() => _showPassword = !_showPassword);
              },
            ),
            if (_isLogin)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 4),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ForgotPasswordScreen2(),
                        ),
                      );
                    },
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(
                        color: _AuthColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            // â”€â”€â”€ Submit Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _buildSubmitButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hintText,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    bool suffixIcon = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.95),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              keyboardType: keyboardType,
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 14,
                ),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 10),
                  child: Icon(
                    icon,
                    color: Colors.white.withOpacity(0.7),
                    size: 20,
                  ),
                ),
                suffixIcon: suffixIcon
                    ? GestureDetector(
                        onTap: onToggleVisibility,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: Icon(
                            _showPassword
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            color: Colors.white.withOpacity(0.6),
                            size: 20,
                          ),
                        ),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _submit,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A5C38), Color(0xFF2E7D4F)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _AuthColors.primary.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _submit,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(
                          Colors.white.withOpacity(0.9),
                        ),
                      ),
                    )
                  : Text(
                      'Login',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A5C38), Color(0xFF2E7D4F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _AuthColors.primary.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: const Center(
                    child: Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomLinks() {
    return Column(
      children: [
        if (_isLogin)
          Column(
            children: [
              _buildHighlightedActionLink(
                'New user? Create Account',
                'Register here first to start using the app.',
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RegisterScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              _buildTextLink('Register your Masjid', () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MasjidRegistrationScreen(),
                  ),
                );
              }),
            ],
          )
        else
          Column(
            children: [
              _buildHighlightedActionLink(
                'Already registered? Login',
                'Sign in here if you already created your account.',
                _showLogin,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSupportLinks() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        _buildTextLink('FAQs', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FaqScreen()),
          );
        }),
        Text(
          '|',
          style: TextStyle(
            color: Colors.white.withOpacity(0.65),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        _buildTextLink('Contact Us', () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContactUsScreen()),
          );
        }),
      ],
    );
  }

  Widget _buildTextLink(
    String text,
    VoidCallback onTap, {
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.white.withOpacity(0.9),
            fontWeight: fontWeight,
            letterSpacing: 0.2,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedActionLink(
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: _AuthColors.gold.withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _AuthColors.gold.withOpacity(0.7),
            width: 1.4,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.88),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
