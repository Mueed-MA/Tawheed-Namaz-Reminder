import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import '../../services/firebase_db.dart';

// Design Tokens
class _AuthColors {
  static const Color primary = Color(0xFF1A5C38);
  static const Color primaryLight = Color(0xFF2E7D4F);
  static const Color gold = Color(0xFFB8963E);
}

class ForgotPasswordScreen2 extends StatefulWidget {
  const ForgotPasswordScreen2({super.key});

  @override
  State<ForgotPasswordScreen2> createState() => _ForgotPasswordScreen2State();
}

class _ForgotPasswordScreen2State extends State<ForgotPasswordScreen2> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _securityAnswerController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isChecking = false;
  String? _statusMessage;

  bool _accountResolved = false;
  bool _hintVerified = false;
  bool _isAdmin = false;
  String? _securityQuestion;

  bool _isAdminIdentifier(String value) =>
      RegExp(r'[A-Za-z]').hasMatch(value.trim());

  Future<void> _resolveAccount() async {
    final identifier = _identifierController.text.trim();
    if (identifier.isEmpty) {
      setState(() => _statusMessage = 'Please enter user id or mobile number');
      return;
    }

    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });

    try {
      final isAdmin = _isAdminIdentifier(identifier);
      if (isAdmin) {
        final hint = await FirebaseDB.instance.getSecurityHintForAdmin(
          identifier,
        );
        if (hint == null || (hint['question'] ?? '').trim().isEmpty) {
          final exists =
              await FirebaseDB.instance.adminExistsByUsername(identifier);
          setState(() => _statusMessage = exists
              ? 'Security question not set for this admin'
              : 'Admin username not found');
          return;
        }
        setState(() {
          _isAdmin = true;
          _securityQuestion = (hint['question'] ?? '').trim();
          _accountResolved = true;
        });
      } else {
        final exists = await FirebaseDB.instance.userExistsByMobile(identifier);
        if (!exists) {
          setState(() => _statusMessage = 'Mobile number not found');
          return;
        }
        final hint = await FirebaseDB.instance.getSecurityHintForUser(
          identifier,
        );
        if (hint == null || (hint['question'] ?? '').trim().isEmpty) {
          setState(() => _statusMessage =
              'Security question not set for this user');
          return;
        }
        setState(() {
          _isAdmin = false;
          _securityQuestion = (hint['question'] ?? '').trim();
          _accountResolved = true;
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _verifyHint() async {
    final answer = _securityAnswerController.text.trim();
    if (answer.isEmpty) {
      setState(() => _statusMessage = 'Please enter your answer');
      return;
    }

    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });

    try {
      final valid = await FirebaseDB.instance.verifySecurityHint(
        role: _isAdmin ? 'masjid_admin' : 'user',
        identifier: _identifierController.text.trim(),
        answer: answer,
      );
      if (!mounted) return;
      setState(() {
        _hintVerified = valid;
        _statusMessage = valid ? 'Answer verified' : 'Incorrect answer';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() => _statusMessage = 'Please fill all fields');
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _statusMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });

    try {
      if (_isAdmin) {
        await FirebaseDB.instance.updateAdminPasswordByUsername(
          _identifierController.text.trim(),
          newPassword,
        );
      } else {
        await FirebaseDB.instance.updatePassword(
          _identifierController.text.trim(),
          newPassword,
        );
      }

      await FirebaseDB.instance.tryUpdateAuthPassword(
        role: _isAdmin ? 'masjid_admin' : 'user',
        identifier: _identifierController.text.trim(),
        oldPassword: '',
        newPassword: newPassword,
      );

      if (!mounted) return;
      setState(() {
        _statusMessage = 'Password reset successfully';
        _securityAnswerController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _hintVerified = false;
        _accountResolved = false;
        _securityQuestion = null;
      });
    } catch (e) {
      setState(() => _statusMessage = 'Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _securityAnswerController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Background Image
          Container(
            decoration: BoxDecoration(
              image: DecorationImage(
                image: const AssetImage('assets/images/1bg.jpeg'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.2),
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.6),
                ],
              ),
            ),
          ),
          // Decorative Elements
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
          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    _buildFormCard(),
                  ],
                ),
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
          child: const Icon(
            Icons.lock_reset_rounded,
            size: 40,
            color: _AuthColors.gold,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Reset Password',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _hintVerified
              ? 'Set your new password'
              : _accountResolved
                  ? 'Answer your security question'
                  : 'Verify your account to continue',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.7),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            if (!_accountResolved) ...[
              _buildTextField(
                controller: _identifierController,
                label: 'User ID / Mobile Number',
                icon: Icons.person_rounded,
                hintText: 'Enter admin username or user mobile',
                onChanged: (_) {
                  if (!_accountResolved && !_hintVerified && _statusMessage == null) {
                    return;
                  }
                  setState(() {
                    _accountResolved = false;
                    _hintVerified = false;
                    _isAdmin = false;
                    _securityQuestion = null;
                    _statusMessage = null;
                  });
                },
              ),
              const SizedBox(height: 30),
              _buildResolveButton(),
            ] else if (_accountResolved && !_hintVerified) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Security Question',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _securityQuestion ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _securityAnswerController,
                label: 'Answer',
                icon: Icons.question_answer_rounded,
                hintText: 'Enter your answer (one word)',
                keyboardType: TextInputType.text,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
              ),
              const SizedBox(height: 30),
              _buildVerifyHintButton(),
            ] else ...[
              _buildTextField(
                controller: _newPasswordController,
                label: 'New Password',
                icon: Icons.lock_rounded,
                hintText: 'Enter new password',
                obscureText: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_reset_rounded,
                hintText: 'Confirm new password',
                obscureText: true,
              ),
              const SizedBox(height: 30),
              _buildResetButton(),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _statusMessage!.toLowerCase().contains('success') ||
                          _statusMessage!.toLowerCase().contains('sent') ||
                          _statusMessage!.toLowerCase().contains('verified')
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _statusMessage!.toLowerCase().contains('success') ||
                            _statusMessage!.toLowerCase().contains('sent') ||
                            _statusMessage!.toLowerCase().contains('verified')
                        ? Colors.green.withOpacity(0.5)
                        : Colors.red.withOpacity(0.5),
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
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
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
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
              onChanged: onChanged,
              inputFormatters: inputFormatters,
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

  Widget _buildResolveButton() {
    return GestureDetector(
      onTap: _isChecking ? null : _resolveAccount,
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
            onTap: _isChecking ? null : _resolveAccount,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isChecking
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
                  : const Text(
                      'Verify Account',
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
    );
  }

  Widget _buildVerifyHintButton() {
    return GestureDetector(
      onTap: _isChecking ? null : _verifyHint,
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
            onTap: _isChecking ? null : _verifyHint,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isChecking
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
                  : const Text(
                      'Verify Answer',
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
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: _isChecking ? null : _resetPassword,
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
            onTap: _isChecking ? null : _resetPassword,
            borderRadius: BorderRadius.circular(14),
            child: Center(
              child: _isChecking
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
                  : const Text(
                      'Reset Password',
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
    );
  }
}
