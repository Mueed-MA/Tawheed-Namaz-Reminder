import 'package:flutter/material.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF1A5C38);
    const Color bg = Color(0xFFF5F7F5);
    const Color textMain = Color(0xFF1A2B22);
    const Color textMuted = Color(0xFF6B7C73);
    final items = _faqItems();
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Frequently Asked Questions'),
        backgroundColor: primary,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2ECE5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                collapsedIconColor: textMuted,
                iconColor: primary,
                title: Text(
                  item.question,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    item.answer,
                    style: const TextStyle(height: 1.4, color: textMuted),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemCount: items.length,
      ),
    );
  }
}

class _FaqItem {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});
}

List<_FaqItem> _faqItems() {
  return const [
    _FaqItem(
      question: 'My masjid name is not showing during user registration.',
      answer:
          'First, register your masjid in the app. After the registration is approved by the admin, it will appear in the user registration list.',
    ),
    _FaqItem(
      question: 'What details are required to register a masjid?',
      answer:
          'You need: Masjid name, basic user details, and accurate latitude and longitude so the masjid can be located correctly.',
    ),
    _FaqItem(
      question:
          'After registering, the masjid Azan and Jamaat timings are not showing. Why?',
      answer:
          'The masjid admin has not entered the prayer timings yet. Please ask your masjid admin to update the timings.',
    ),
    _FaqItem(
      question:
          'The prayer timings in my masjid have changed, but the app is not updated.',
      answer:
          'Please inform your masjid admin to update the new timings in the app.',
    ),
    _FaqItem(
      question: 'Does this app work offline?',
      answer:
          'Yes. The app works offline, but if the admin updates timings while you are offline, the changes will not appear automatically. You can refresh manually in the Preferences section.',
    ),
    _FaqItem(
      question: 'How can I find the Qibla direction? It is not showing.',
      answer:
          'Enable location in the app, open the Qibla option, and slowly rotate your phone. When the orange indicator turns green, you are facing the correct direction.',
    ),
    _FaqItem(
      question: 'How can I change the default masjid?',
      answer:
          'Open Registered Masjids, search or filter your masjid, then tap the bookmark (star) icon. That masjid will become your default.',
    ),
    _FaqItem(
      question:
          'I missed marking a prayer due to silent mode or other reasons. How can I update it?',
      answer:
          'Go to the Salah Tracker section, select the missed prayer, and mark it manually.',
    ),
    _FaqItem(
      question: 'How can I submit a grievance or suggestion?',
      answer:
          'Open Contact Us, tap the email address, write your grievance or suggestion, and send the email.',
    ),
    _FaqItem(
      question:
          'I entered the wrong latitude and longitude while registering the Masjid. How can I correct it?',
      answer:
          '1. Log in using your Masjid Admin account.\n'
          '2. Go to the edit masjid location.\n'
          '3. You can either:\n'
          '   - Manually enter the correct Latitude and Longitude, or\n'
          '   - Stand inside the Masjid premises and click “Get Location” to automatically capture the correct coordinates.\n'
          '4. Save the updated details.\n'
          'This will update the correct location of the Masjid in the system.',
    ),
    _FaqItem(
      question:
          'My Masjid prayer start and end times are showing incorrectly and the offset is not set. What should I do?',
      answer:
          'If the prayer start or end times are showing incorrectly and the offset is not set, please contact the admin for correction.\n\n'
          'You can:\n'
          '- Send an email, or\n'
          '- Call the admin using the contact details available in the “Contact Us” section of the app.\n\n'
          'The admin team will verify and update the correct settings.',
    ),
    _FaqItem(
      question:
          'I entered the wrong phone number during registration. How can I know my user ID for login and how can I change it?',
      answer:
          'In most cases, the User ID is the registered phone number. '
          'If you accidentally entered the wrong digits during registration and cannot log in with the correct number, '
          'please contact us.\n\n'
          'If you want to continue using the account created with the incorrect number, you may log in using that registered number.\n\n'
          'Otherwise, please send us an email with the details. Our team will delete the incorrect account, '
          'and you can create a new account using the correct phone number.',
    ),
  ];
}
