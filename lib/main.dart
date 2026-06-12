import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screens/alarm_screen.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/qibla/qibla_screen.dart';
import 'screens/auth/masjid_registration_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/admin/masjid_time_settings_screen.dart';
import 'screens/admin/super_admin_approval_screen.dart';
import 'screens/onboarding_screen.dart'; // Added
import 'services/hive_bootstrap.dart';
import 'services/notification_service.dart';

// NOTE: Background FCM handler lives in NotificationService. Keep the symbol
// name here resolved from the imported file so headless updates can reschedule
// alarms even when the app is killed.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();
  await HiveBootstrap.init();

  // Firebase Messaging handlers
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    debugPrint(
      "FCM FG: msgId=${message.messageId} action=${message.data['action']} "
      "masjidId=${message.data['masjidId']} at=${DateTime.now().toIso8601String()}",
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await FirebaseFirestore.instance.collection('fcm_logs').add({
        'source': 'foreground',
        'messageId': message.messageId,
        'action': message.data['action'],
        'masjidId': message.data['masjidId'],
        'mobile': prefs.getString('userMobile'),
        'loggedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('FCM FG log failed: $e');
    }
    if (message.data['action'] == 'SYNC_SALAH_TIMES') {
      final String? masjidId = message.data['masjidId'];
      await NotificationService.instance.rescheduleAllAlarmsFromRemote(
        targetMasjidId: masjidId,
      );
      return;
    }
    await NotificationService.instance.handleRoleBasedRemoteMessage(message);
  });

  final prefs = await SharedPreferences.getInstance();

  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final String? userMobile = prefs.getString('userMobile');
  final String? userRole = prefs.getString('userRole');
  final String? masjidId = prefs.getString('masjidId');

  // Check onboarding
  final bool onboardingSeen = prefs.getBool('onboardingSeen') ?? false;

  runApp(
    MyApp(
      isLoggedIn: isLoggedIn,
      userMobile: userMobile,
      userRole: userRole,
      masjidId: masjidId,
      onboardingSeen: onboardingSeen,
    ),
  );

  // Post-startup tasks: do not block first frame or offline startup.
  unawaited(_initNotificationsAfterStartup());
  unawaited(
    _syncRoleBasedSubscriptions(
      isLoggedIn: isLoggedIn,
      userMobile: userMobile,
      userRole: userRole,
    ),
  );
}

Future<void> _initNotificationsAfterStartup() async {
  try {
    await NotificationService.instance.init().timeout(
      const Duration(seconds: 6),
    );
    await NotificationService.instance.emitActiveJamatAlarmPayloadIfAny();
  } catch (e, stack) {
    debugPrint('Notification init skipped: $e');
    debugPrintStack(stackTrace: stack);
  }
}

Future<void> _syncRoleBasedSubscriptions({
  required bool isLoggedIn,
  required String? userMobile,
  required String? userRole,
}) async {
  if (!isLoggedIn || userMobile == null || userRole == null) return;

  try {
    await NotificationService.instance
        .syncRoleBasedFcmSubscriptions(role: userRole, mobile: userMobile)
        .timeout(const Duration(seconds: 6));
  } catch (e, stack) {
    debugPrint('FCM subscription sync skipped: $e');
    debugPrintStack(stackTrace: stack);
  }
}

class MyApp extends StatefulWidget {
  final bool isLoggedIn;
  final String? userMobile;
  final String? userRole;
  final String? masjidId;
  final bool onboardingSeen;

  const MyApp({
    super.key,
    required this.isLoggedIn,
    this.userMobile,
    this.userRole,
    this.masjidId,
    required this.onboardingSeen,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<String?>? _payloadSubscription;
  Timer? _activeAlarmPollTimer;
  bool _isAlarmScreenOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _payloadSubscription = NotificationService.instance.payloadStream.stream
        .listen(_handleAlarmPayload);
    _startActiveAlarmPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeAlarmPollTimer?.cancel();
    _payloadSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startActiveAlarmPolling();
      NotificationService.instance.emitActiveJamatAlarmPayloadIfAny();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _activeAlarmPollTimer?.cancel();
      _activeAlarmPollTimer = null;
    }
  }

  void _startActiveAlarmPolling() {
    _activeAlarmPollTimer?.cancel();
    NotificationService.instance.emitActiveJamatAlarmPayloadIfAny();
    _activeAlarmPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      NotificationService.instance.emitActiveJamatAlarmPayloadIfAny();
    });
  }

  void _handleAlarmPayload(String? payload) {
    if (payload == null || payload.isEmpty || _isAlarmScreenOpen) return;
    if (NotificationService.instance.isAlarmPayloadExpired(payload)) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleAlarmPayload(payload);
      });
      return;
    }

    _isAlarmScreenOpen = true;
    navigator
        .push(MaterialPageRoute(builder: (_) => AlarmScreen(payload: payload)))
        .whenComplete(() {
          _isAlarmScreenOpen = false;
        });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      home: _getInitialScreen(),
      routes: {
        '/qibla': (context) => const QiblaCompassScreen(),
        '/masjid_register': (context) => const MasjidRegistrationScreen(),
      },
    );
  }

  Widget _getInitialScreen() {
    if (!widget.onboardingSeen) {
      return const OnboardingScreen();
    }

    if (widget.isLoggedIn &&
        widget.userMobile != null &&
        widget.userRole != null) {
      if (widget.userRole == 'masjid_admin') {
        return MasjidTimeSettingsScreen(
          ownerMobile: widget.userMobile!,
          masjidId: (widget.masjidId ?? '').trim().isEmpty
              ? null
              : widget.masjidId,
        );
      } else if (widget.userRole == 'super_admin') {
        return const SuperAdminApprovalScreen();
      } else {
        return HomeScreen(
          userMobile: widget.userMobile!,
          role: widget.userRole!,
        );
      }
    } else {
      return const AuthScreen(initialMode: AuthScreenMode.login);
    }
  }
}
