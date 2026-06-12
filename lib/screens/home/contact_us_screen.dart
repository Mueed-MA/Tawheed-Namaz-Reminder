import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/email_helper.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link on this device')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF1A5C38);
    const Color bg = Color(0xFFF5F7F5);
    const Color textMain = Color(0xFF1A2B22);
    const Color textMuted = Color(0xFF6B7C73);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Contact Us'),
        backgroundColor: primary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE2ECE5)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x141A5C38),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/ApPlogo1.png',
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 40,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'App developed by',
                      style: TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBF9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3ECE6)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Concept & Project Architecture',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Dr. Mohd Thousif Ahemad',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: textMain,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '(Sami)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: textMain,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBF9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3ECE6)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Lead Developer',
                            style: TextStyle(
                              fontSize: 12,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Mohammed Abdul Mueed',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: textMain,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              'assets/images/myphoto.jpg',
                              width: 140,
                              height: 155,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 140,
                                height: 155,
                                color: const Color(0xFFE8EDE9),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 34,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'B.Sc Computer Science',
                            style: TextStyle(
                              fontSize: 16,
                              color: textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Nagarjuna Government College (A),',
                            style: TextStyle(
                              fontSize: 15,
                              color: textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Nalgonda',
                            style: TextStyle(
                              fontSize: 15,
                              color: textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 24),
                    Text(
                      'For any queries',
                      style: TextStyle(
                        fontSize: 13,
                        color: textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => EmailHelper.sendEmail(
                        to: 'xyztechnologialimited@gmail.com',
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.email_outlined,
                            size: 18,
                            color: Colors.black54,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'xyztechnologialimited@gmail.com',
                            style: TextStyle(
                              fontSize: 14,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _launch(context, 'tel:+918885534438'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.call_outlined,
                            size: 18,
                            color: Colors.black54,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '+91 8885534438',
                            style: TextStyle(
                              fontSize: 14,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => _launch(context, 'tel:+919398988195'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.call_outlined,
                            size: 18,
                            color: Colors.black54,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '+91 9398988195',
                            style: TextStyle(
                              fontSize: 14,
                              color: textMuted,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      'Version: 1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
