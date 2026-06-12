import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

class EmailHelper {
  static Future<void> sendEmail({
    required String to,
    String? subject,
    String? body,
  }) async {
    final String safeSubject = subject ?? '';
    final String safeBody = body ?? '';
    final Uri emailUri = Uri.parse(
      'mailto:$to?subject=${Uri.encodeComponent(safeSubject)}&body=${Uri.encodeComponent(safeBody)}',
    );
    final bool launchedMailto = await launchUrl(
      emailUri,
      mode: LaunchMode.externalApplication,
    );
    if (launchedMailto) {
      return;
    }

    final Uri gmailWeb = Uri.https(
      'mail.google.com',
      '/mail/',
      {
        'view': 'cm',
        'fs': '1',
        'to': to,
        'su': safeSubject,
        'body': safeBody,
      },
    );
    if (!await launchUrl(gmailWeb, mode: LaunchMode.externalApplication)) {
      throw 'Could not open email app';
    }
  }
}
