import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/masjid.dart';
import 'default_masjid_repository.dart';
import 'hive_bootstrap.dart';

import '../models/prayer_time_data.dart';
import '../salah_calendar/salah_calendar_model.dart';
import '../salah_calendar/salah_calendar_repository.dart';
import '../salah_calendar/salah_database_helper.dart';

// Offset to ensure snooze alarms don't conflict with daily scheduled alarms
const int _snoozeIdOffset = 10000;
const int _autoSnoozeScheduleIdOffset = 20000;
const String _jamatAlarmChannelId = 'salah_alarm_channel_v7';
const int _autoSnoozeMinutes = 5;
const Duration _autoSnoozeNoResponseDelay = Duration(minutes: 1);
const int _autoSnoozeFallbackMaxCount = 3;
const String _nativeReplacementPayloadKeyPrefix = '__native_jamat_payload__';
const MethodChannel _nativeJamatNotificationChannel = MethodChannel(
  'com.tawheed.namazreminder/jamat_notification',
);

class _AlarmPayloadData {
  final int alarmId;
  final String title;
  final int endTimeMillis;
  final int jamatTimeMillis;

  const _AlarmPayloadData({
    required this.alarmId,
    required this.title,
    required this.endTimeMillis,
    required this.jamatTimeMillis,
  });
}

class _CountdownPresentation {
  final String body;
  final DateTime? targetTime;

  const _CountdownPresentation({required this.body, this.targetTime});
}

String _dateKey(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  return d.toIso8601String().split('T')[0];
}

String _stripAttendanceTitle(String title) {
  var t = title.replaceAll('(Snoozed)', '').trim();
  if (t.endsWith(' Azan')) {
    t = t.substring(0, t.length - 5).trim();
  } else if (t.endsWith(' Jamat')) {
    t = t.substring(0, t.length - 6).trim();
  }
  return t;
}

String _formatAlarmDuration(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  if (hours > 0) {
    return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}

_CountdownPresentation _buildJamatCountdownPresentation({
  required String title,
  required DateTime fromTime,
  DateTime? jamatTime,
  DateTime? endTime,
  String fallback = 'Jamat for Salah is about to begin',
}) {
  if (jamatTime != null) {
    final Duration jamatRemaining = jamatTime.difference(fromTime);
    if (jamatRemaining.inSeconds > 0) {
      return _CountdownPresentation(
        body: 'Time left for the jamat',
        targetTime: jamatTime,
      );
    }
  }

  if (endTime != null) {
    final Duration endRemaining = endTime.difference(fromTime);
    if (!endRemaining.isNegative) {
      return _CountdownPresentation(
        body: '$title time ends in',
        targetTime: endTime,
      );
    }
    return _CountdownPresentation(body: '$title time has ended');
  }

  return _CountdownPresentation(body: fallback);
}

String _buildJamatCountdownBody({
  required String title,
  required DateTime fromTime,
  DateTime? jamatTime,
  DateTime? endTime,
  String fallback = 'Jamat for Salah is about to begin',
}) {
  final _CountdownPresentation presentation = _buildJamatCountdownPresentation(
    title: title,
    fromTime: fromTime,
    jamatTime: jamatTime,
    endTime: endTime,
    fallback: fallback,
  );

  if (presentation.targetTime == null) {
    return presentation.body;
  }

  final Duration remaining = presentation.targetTime!.difference(fromTime);
  if (remaining.inSeconds <= 0) {
    return presentation.body;
  }

  return '${presentation.body}\n${_formatAlarmDuration(remaining)}';
}

/// Background handler for FCM data messages.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Needed for village snapshot cache access during background refreshes.
  await HiveBootstrap.init();
  debugPrint(
    "FCM BG: msgId=${message.messageId} action=${message.data['action']} "
    "masjidId=${message.data['masjidId']} at=${DateTime.now().toIso8601String()}",
  );
  try {
    final prefs = await SharedPreferences.getInstance();
    await FirebaseFirestore.instance.collection('fcm_logs').add({
      'source': 'background',
      'messageId': message.messageId,
      'action': message.data['action'],
      'masjidId': message.data['masjidId'],
      'mobile': prefs.getString('userMobile'),
      'loggedAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('FCM BG log failed: $e');
  }

  if (message.data['action'] == 'SYNC_SALAH_TIMES') {
    final String? masjidId = message.data['masjidId'];
    await NotificationService.instance.rescheduleAllAlarmsFromRemote(
      targetMasjidId: masjidId,
    );
    return;
  }

  await NotificationService.instance.handleRoleBasedRemoteMessage(message);
}

// Top-level function to handle background button clicks (Accept/Decline/Snooze)
@pragma('vm:entry-point')
void notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  // Ensure binding is initialized for background isolate
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize plugin in background isolate to ensure it works correctly
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  await _processNotificationAction(
    flutterLocalNotificationsPlugin,
    notificationResponse,
  );
}

// Shared logic for processing notification actions
Future<void> _processNotificationAction(
  FlutterLocalNotificationsPlugin plugin,
  NotificationResponse notificationResponse,
) async {
  final actionId = notificationResponse.actionId;
  final int? id = notificationResponse.id;
  final String? payload = notificationResponse.payload;

  if (id == null || payload == null) return;
  NotificationService.instance.cancelAutoSnoozeForPayload(
    payload,
    notificationId: id,
  );

  // Parse payload: id|title|endTimeMillis|jamatTimeMillis
  final parts = payload.split('|');
  final title = parts.length > 1 ? parts[1] : '';
  int endTimeMillis = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
  int jamatTimeMillis = parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0;
  final int originalId = int.tryParse(parts[0]) ?? id;

  endTimeMillis = NotificationService.normalizeTime(endTimeMillis);
  jamatTimeMillis = NotificationService.normalizeTime(jamatTimeMillis);

  // Fetch fresh end time from DB to ensure we have the correct Salah end time
  final int? freshEndTime = await NotificationService.instance.getFreshEndTime(
    title,
  );
  if (freshEndTime != null) {
    endTimeMillis = freshEndTime;
  }

  // Handle Accept/Decline persistence
  if (title.isNotEmpty && (actionId == 'accept' || actionId == 'decline')) {
    final prefs = await SharedPreferences.getInstance();
    final today = await NotificationService.instance.resolveAttendanceDateKey(
      title,
    );
    final status = actionId == 'accept' ? 'accepted' : 'declined';
    await prefs.setString('attendance_${today}_$title', status);
  }

  // Explicitly cancel the notification for all actions to stop the alarm sound
  if (actionId == 'accept' || actionId == 'decline' || actionId == 'snooze') {
    try {
      await plugin.cancel(id);
      await NotificationService.instance.cancelAllAutoSnoozeArtifacts(
        originalId,
      );
    } catch (e, stack) {
      debugPrint('Notification action cancel failed for id $id: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  if (notificationResponse.notificationResponseType ==
          NotificationResponseType.selectedNotification &&
      actionId == null) {
    try {
      await plugin.cancel(id);
      await NotificationService.instance.cancelAllAutoSnoozeArtifacts(
        originalId,
      );
    } catch (e, stack) {
      debugPrint('Notification tap cancel failed for id $id: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  if (actionId == 'snooze') {
    // Initialize timezones
    tz_data.initializeTimeZones();

    // Schedule snooze (10 minutes)
    final DateTime now = DateTime.now();
    DateTime scheduledDate = now.add(const Duration(minutes: 10));

    // Check if snooze time exceeds Salah end time
    if (endTimeMillis > 0 &&
        scheduledDate.millisecondsSinceEpoch > endTimeMillis) {
      final endTime = DateTime.fromMillisecondsSinceEpoch(endTimeMillis);
      if (endTime.isAfter(now)) {
        scheduledDate = endTime;
      } else {
        return;
      }
    }

    // Save snooze state
    final prefs = await SharedPreferences.getInstance();
    final today = await NotificationService.instance.resolveAttendanceDateKey(
      title,
    );
    await prefs.setBool('salah_snoozed_${today}_$title', true);

    String notificationBody = 'Alarm snoozed for 10 minutes';
    final String notificationTitle = title;

    final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(
      scheduledDate.toUtc(),
      tz.UTC,
    );

    // Re-schedule the alarm
    await plugin.zonedSchedule(
      originalId + _snoozeIdOffset, // Use dedicated snooze ID
      notificationTitle,
      notificationBody,
      tzScheduledDate,
      NotificationService.instance._buildJamatNotificationDetails(
        channelId: _jamatAlarmChannelId,
        playSound: true,
        fullScreenIntent: true,
        isSwipePersistent: true,
        body: notificationBody,
      ),
      androidScheduleMode: NotificationService.instance._scheduleMode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload:
          '$id|$title|$endTimeMillis|$jamatTimeMillis', // Preserve original title, end time, and jamat time
    );
  }
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  static const String _superAdminTopic = 'super_admin_alerts';
  static const String _masjidAdminRequestsTopic = 'masjid_admin_requests';
  static const String _mobileFilterKey = 'fcm_filter_mobile';
  static const String _remoteSyncCooldownKey = '__last_remote_sync_ms__';
  // Keep this very short to avoid dropping legitimate rapid updates.
  static const int _remoteSyncCooldownMs = 5 * 1000;
  final DefaultMasjidRepository _defaultMasjidRepo =
      DefaultMasjidRepository.instance;

  NotificationService._internal() {
    payloadStream = StreamController<String?>.broadcast(
      onListen: () {
        if (launchPayload != null) {
          payloadStream.add(launchPayload);
          launchPayload = null;
        }
      },
    );
    actionStream = StreamController<String>.broadcast();
    dataUpdateStream = StreamController<void>.broadcast();
  }

  /// Fetches prayer times for the user's default masjid and reschedules all
  /// alarms that the user has enabled.
  /// This is intended to be called from a silent push notification handler.
  Future<void> rescheduleAllAlarmsFromRemote({String? targetMasjidId}) async {
    if (!_isInitialized) await init();
    debugPrint(
      "Remote sync triggered at ${DateTime.now().toIso8601String()} "
      "(targetMasjidId=${(targetMasjidId ?? '').trim()}).",
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Force reload to get the latest data in background

      final String? cachedDefaultMasjidId =
          prefs.getString('cached_default_masjid_id') ??
          prefs.getString('masjidId');
      final String cleanedTargetMasjidId = (targetMasjidId ?? '').trim();
      if (cleanedTargetMasjidId.isNotEmpty) {
        if (cachedDefaultMasjidId == null ||
            cachedDefaultMasjidId.trim().isEmpty) {
          debugPrint(
            'Remote sync ignored: no default masjid cached '
            '(target=$cleanedTargetMasjidId).',
          );
          return;
        }
        if (cachedDefaultMasjidId.trim() != cleanedTargetMasjidId) {
          debugPrint(
            'Remote sync ignored for non-default masjid '
            '(target=$cleanedTargetMasjidId, cached=$cachedDefaultMasjidId).',
          );
          return;
        }
      }

      // Avoid duplicate rapid sync executions from repeated/duplicate data
      // messages. This reduces redundant reads and re-scheduling churn.
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final int? lastSyncMs = prefs.getInt(_remoteSyncCooldownKey);
      if (lastSyncMs != null && (nowMs - lastSyncMs) < _remoteSyncCooldownMs) {
        debugPrint('Remote sync skipped due to cooldown.');
        return;
      }
      await prefs.setInt(_remoteSyncCooldownKey, nowMs);

      // Ensure we use the same key as AuthScreen ('userMobile')
      final String? userMobile = prefs.getString('userMobile');

      if (userMobile == null) {
        debugPrint("No user logged in. Aborting reschedule.");
        return;
      }

      // Push-triggered refresh: update local cache first, then schedule alarms
      // from the refreshed local source.
      final Masjid? masjid = await _defaultMasjidRepo.getDefaultMasjid(
        userMobile: userMobile,
        pushTriggered: true,
        forceRefresh: true,
      );

      if (masjid == null) {
        debugPrint("No default masjid found for user. Aborting reschedule.");
        return;
      }

      // Extra safety: clear all existing Salah/Juma schedules up front
      // to avoid leftovers if timings changed while app was inactive.
      debugPrint("Canceling all existing Salah schedules before reschedule...");
      await _cancelAllSalahSchedules();
      debugPrint("Cancel complete. Rebuilding schedules now...");

      // Check both keys to ensure we get the correct master toggle state
      bool isMasterEnabled = prefs.getBool('master_alarm_enabled') ?? false;
      if (!isMasterEnabled) {
        isMasterEnabled = prefs.getBool('salah_alerts_enabled') ?? false;
      }

      // --- NEW: Load calendar data for accurate end times & Maghrib ---
      final List<PrayerTimeData> calendarPrayers =
          await loadCalendarPrayersForToday();
      debugPrint(
        "Background sync: Loaded ${calendarPrayers.length} prayers from local calendar.",
      );

      // Track the next azan time we schedule (for debugging/logging).
      DateTime? nextAzanAt;
      String? nextAzanName;

      // List of prayers to process
      final List<String> prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
      for (int i = 0; i < prayers.length; i++) {
        final name = prayers[i];

        // 1. Get Masjid Time
        String masjidAzanTime = '';
        String masjidJamatTime = '';

        switch (name) {
          case 'Fajr':
            masjidAzanTime = masjid.fajr_azan ?? '';
            masjidJamatTime = masjid.fajr_jamat ?? '';
            break;
          case 'Dhuhr':
            masjidAzanTime = masjid.dhuhr_azan ?? '';
            masjidJamatTime = masjid.dhuhr_jamat ?? '';
            break;
          case 'Asr':
            masjidAzanTime = masjid.asar_azan ?? '';
            masjidJamatTime = masjid.asar_jamat ?? '';
            break;
          case 'Maghrib':
            masjidAzanTime = masjid.maghrib_azan ?? '';
            masjidJamatTime = masjid.maghrib_jamat ?? '';
            break;
          case 'Isha':
            masjidAzanTime = masjid.isha_azan ?? '';
            masjidJamatTime = masjid.isha_jamat ?? '';
            break;
          case 'Juma':
            masjidAzanTime = masjid.juma_azan ?? '';
            masjidJamatTime = masjid.juma_jamat ?? '';
            break;
        }

        // 2. Get User Preferences
        String myAzanTime = prefs.getString('pref_${name}_Azan') ?? '';
        String myJamatTime = prefs.getString('pref_${name}_Jamat') ?? '';

        // Fallback to masjid time if custom time is not set
        if (myAzanTime.isEmpty) myAzanTime = masjidAzanTime;
        if (myJamatTime.isEmpty) myJamatTime = masjidJamatTime;

        // 3. Check Toggles
        final bool azanEnabled = prefs.getBool('${name}_Azan') ?? false;
        final bool jamatEnabled = prefs.getBool('${name}_Jamat') ?? false;

        if ((azanEnabled || jamatEnabled) && isMasterEnabled) {
          debugPrint(
            "Rescheduling $name (Azan: $azanEnabled, Jamat: $jamatEnabled)...",
          );

          // 4. Determine ID
          // IDs in HomeScreen: Fajr=1, Dhuhr=2, Asr=3, Maghrib=4, Isha=5, Juma=6
          int id = (name == 'Juma') ? 6 : (i + 1);

          DateTime endTime = DateTime.now().add(const Duration(hours: 1));
          DateTime? calculatedStartTime;

          if (calendarPrayers.isNotEmpty && i < calendarPrayers.length) {
            // Ensure prayer names match index
            if (calendarPrayers[i].name == name) {
              endTime = calendarPrayers[i].endTime;
              calculatedStartTime = calendarPrayers[i].startTime;
            }
          }

          // --- NEW: Force Maghrib to use calendar time ---
          if (name == 'Maghrib' && calculatedStartTime != null) {
            final String cal =
                '${calculatedStartTime.hour}:${calculatedStartTime.minute.toString().padLeft(2, '0')}';
            myAzanTime = cal;
            masjidAzanTime = cal;

            // Set Jamat to Azan + 2 mins (consistent with UI)
            final DateTime jTime = calculatedStartTime.add(
              const Duration(minutes: 2),
            );
            final String calJamat =
                '${jTime.hour}:${jTime.minute.toString().padLeft(2, '0')}';
            myJamatTime = calJamat;
            masjidJamatTime = calJamat;
          }

          await scheduleSalahAlarm(
            id: id,
            title: name,
            body: 'It is time for $name',
            masjidTime: masjidAzanTime,
            masjidJamatTime: masjidJamatTime,
            myTime: myAzanTime,
            myJamatTime: myJamatTime,
            isMyPrefsMode: true,
            endTime: endTime,
            azanEnabled: azanEnabled,
            jamatEnabled: jamatEnabled,
          );

          // Track next azan candidate for logging.
          if (azanEnabled) {
            final DateTime? candidate = _nextOccurrenceFromTimeString(
              myAzanTime,
            );
            if (candidate != null) {
              if (nextAzanAt == null || candidate.isBefore(nextAzanAt!)) {
                nextAzanAt = candidate;
                nextAzanName = name;
              }
            }
          }
        } else {
          // If disabled, ensure we cancel it
          int id = (name == 'Juma') ? 6 : (i + 1);
          await cancelAlarm(id, cancelSnooze: true);
        }
      }

      // --- NEW: Reschedule Juma with correct end time ---
      String masjidJumaAzan = masjid.juma_azan ?? '';
      String masjidJumaJamat = masjid.juma_jamat ?? '';
      String myJumaAzan = prefs.getString('pref_Juma_Azan') ?? '';
      String myJumaJamat = prefs.getString('pref_Juma_Jamat') ?? '';

      if (myJumaAzan.isEmpty) myJumaAzan = masjidJumaAzan;
      if (myJumaJamat.isEmpty) myJumaJamat = masjidJumaJamat;

      bool jumaAzanEnabled = prefs.getBool('Juma_Azan') ?? false;
      bool jumaJamatEnabled = prefs.getBool('Juma_Jamat') ?? false;

      // Use Dhuhr end time (Asr start) as Juma end time
      DateTime jumaEndTime = DateTime.now().add(const Duration(hours: 1));
      if (calendarPrayers.length > 2) {
        jumaEndTime = calendarPrayers[1].endTime; // Dhuhr end time
      }

      if ((jumaAzanEnabled || jumaJamatEnabled) && isMasterEnabled) {
        await scheduleSalahAlarm(
          id: 6,
          title: 'Juma',
          body: 'It is time for Juma',
          masjidTime: masjidJumaAzan,
          masjidJamatTime: masjidJumaJamat,
          myTime: myJumaAzan,
          myJamatTime: myJumaJamat,
          isMyPrefsMode: true,
          endTime: jumaEndTime,
          azanEnabled: jumaAzanEnabled,
          jamatEnabled: jumaJamatEnabled,
        );

        if (jumaAzanEnabled) {
          final DateTime? candidate = _nextOccurrenceFromTimeString(myJumaAzan);
          if (candidate != null) {
            if (nextAzanAt == null || candidate.isBefore(nextAzanAt!)) {
              nextAzanAt = candidate;
              nextAzanName = 'Juma';
            }
          }
        }
      } else {
        await cancelAlarm(6, cancelSnooze: true);
      }

      debugPrint(
        "Remote sync and rescheduling complete at "
        "${DateTime.now().toIso8601String()}.",
      );
      try {
        final localLog = <String, dynamic>{
          'rescheduledAt': DateTime.now().toIso8601String(),
          'nextAzanName': nextAzanName ?? '',
          'nextAzanAt': nextAzanAt?.toIso8601String() ?? '',
          'masjidId': masjid.id,
          'mobile': userMobile,
        };
        await prefs.setString(
          '__last_bg_reschedule_log__',
          jsonEncode(localLog),
        );
      } catch (e) {
        debugPrint('Local BG reschedule log failed: $e');
      }
      try {
        await FirebaseFirestore.instance.collection('fcm_logs').add({
          'source': 'background_reschedule',
          'messageId': null,
          'action': 'SYNC_SALAH_TIMES',
          'masjidId': masjid.id,
          'mobile': userMobile,
          'loggedAt': FieldValue.serverTimestamp(),
          'rescheduledAt': DateTime.now().toIso8601String(),
          'nextAzanName': nextAzanName ?? '',
          'nextAzanAt': nextAzanAt?.toIso8601String() ?? '',
        });
      } catch (e) {
        debugPrint('FCM BG reschedule log failed: $e');
      }
      dataUpdateStream.add(null);
    } catch (e) {
      debugPrint('❌ Error during remote alarm reschedule: $e');
    }
  }

  DateTime? _nextOccurrenceFromTimeString(String time) {
    if (time.trim().isEmpty) return null;
    try {
      final now = DateTime.now();
      final parts = time.trim().split(':');
      final h = int.parse(parts[0].trim());
      final m = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
      var candidate = DateTime(now.year, now.month, now.day, h, m);
      if (candidate.isBefore(now)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      return candidate;
    } catch (_) {
      return null;
    }
  }

  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  AndroidScheduleMode _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;

  String? launchPayload;

  // Stream to handle notification clicks
  late final StreamController<String?> payloadStream;
  // Stream to handle notification action clicks (Accept/Decline/Snooze)
  late final StreamController<String> actionStream;
  // Stream to notify UI of data updates (e.g. after remote sync)
  late final StreamController<void> dataUpdateStream;
  final Map<int, int> _autoOpenedAlarmIds = <int, int>{};
  final Map<int, Timer> _pendingAutoSnoozeTimers = <int, Timer>{};
  StreamSubscription<String>? _tokenRefreshSubscription;

  String _nativeReplacementPayloadKey(int id) =>
      '$_nativeReplacementPayloadKeyPrefix$id';

  Future<void> _cacheNativeReplacementPayload(int id, String payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nativeReplacementPayloadKey(id), payload);
    } catch (e) {
      debugPrint('Native payload cache set failed for $id: $e');
    }
  }

  Future<String?> _getCachedNativeReplacementPayload(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_nativeReplacementPayloadKey(id));
    } catch (e) {
      debugPrint('Native payload cache read failed for $id: $e');
      return null;
    }
  }

  Future<void> _removeCachedNativeReplacementPayload(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nativeReplacementPayloadKey(id));
    } catch (e) {
      debugPrint('Native payload cache remove failed for $id: $e');
    }
  }

  Future<void> _scheduleNativeInlineJamatReplacement({
    required int id,
    required String title,
    required String body,
    required String payload,
    required DateTime triggerTime,
    required DateTime endTime,
    required DateTime jamatTime,
    required String repeatMode,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _cacheNativeReplacementPayload(id, payload);
      await _nativeJamatNotificationChannel.invokeMethod<void>(
        'scheduleReplacement',
        <String, Object>{
          'id': id,
          'title': title,
          'body': body,
          'payload': payload,
          'triggerAtMillis': triggerTime.millisecondsSinceEpoch,
          'endTimeMillis': endTime.millisecondsSinceEpoch,
          'jamatTimeMillis': jamatTime.millisecondsSinceEpoch,
          'repeatMode': repeatMode,
        },
      );
    } catch (e) {
      debugPrint('Native inline jamat schedule failed for $id: $e');
    }
  }

  Future<void> _cancelNativeInlineJamatReplacement(int id) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _removeCachedNativeReplacementPayload(id);
      await _nativeJamatNotificationChannel.invokeMethod<void>(
        'cancelReplacement',
        <String, Object>{'id': id},
      );
    } catch (e) {
      debugPrint('Native inline jamat cancel failed for $id: $e');
    }
  }

  NotificationDetails _buildJamatNotificationDetails({
    required String channelId,
    required bool playSound,
    required bool fullScreenIntent,
    required bool isSwipePersistent,
    String? body,
  }) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        playSound ? 'Salah Alarms' : 'Salah Reminders',
        channelDescription: playSound
            ? 'Notifications for Salah times'
            : 'Persistent countdown reminders for Salah times',
        importance: Importance.max,
        priority: Priority.max,
        playSound: playSound,
        fullScreenIntent: fullScreenIntent,
        ongoing: !isSwipePersistent,
        autoCancel: true,
        timeoutAfter: playSound ? 60000 : null,
        ticker: 'Salah Alarm',
        vibrationPattern: playSound
            ? Int64List.fromList([0, 1000, 500, 1000])
            : null,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: playSound ? Int32List.fromList(<int>[4]) : null,
        styleInformation: body == null
            ? null
            : BigTextStyleInformation(
                body,
                htmlFormatBigText: false,
              ),
      ),
      iOS: DarwinNotificationDetails(presentSound: playSound),
    );
  }

  Future<void> syncRoleBasedFcmSubscriptions({
    required String? role,
    required String? mobile,
  }) async {
    try {
      final FirebaseMessaging messaging = FirebaseMessaging.instance;
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final bool isSuperAdmin = role == 'super_admin';
      if (isSuperAdmin) {
        await messaging.subscribeToTopic(_superAdminTopic);
      }

      if (role == 'masjid_admin' && mobile != null && mobile.isNotEmpty) {
        await messaging.subscribeToTopic(_masjidAdminRequestsTopic);
        await prefs.setString(_mobileFilterKey, mobile);
      }

      if (mobile != null && mobile.isNotEmpty) {
        final String? token = await messaging.getToken();
        if (token != null && token.trim().isNotEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(mobile).set({
            'fcmToken': token.trim(),
            'tokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = messaging.onTokenRefresh.listen((
          newToken,
        ) async {
          if (newToken.trim().isEmpty) return;
          await FirebaseFirestore.instance.collection('users').doc(mobile).set({
            'fcmToken': newToken.trim(),
            'tokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        });
      }
    } catch (e) {
      debugPrint('FCM topic sync failed: $e');
    }
  }

  /// Returns true/false if Android exact alarms are allowed.
  /// Returns null on non-Android platforms or if the API isn't available.
  Future<bool?> canScheduleExactAlarms() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation == null) return null;
    try {
      return (await androidImplementation.canScheduleExactNotifications()) ??
          false;
    } catch (_) {
      return null;
    }
  }

  /// Prompts the system flow for exact alarm permission on Android 12+.
  Future<void> requestExactAlarmsPermission() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation == null) return;
    try {
      await androidImplementation.requestExactAlarmsPermission();
    } catch (_) {}
    await _refreshScheduleMode();
  }

  Future<void> _refreshScheduleMode() async {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation == null) {
      _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
      return;
    }
    try {
      final bool? canExact = await androidImplementation
          .canScheduleExactNotifications();
      if (canExact == null) {
        // Older Android or API not available: treat as exact-capable.
        _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
        return;
      }
      _scheduleMode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      _scheduleMode = AndroidScheduleMode.exactAllowWhileIdle;
    }
  }

  Future<void> handleRoleBasedRemoteMessage(RemoteMessage message) async {
    final String type = message.data['type'] ?? '';
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String? role = prefs.getString('userRole');
    final String? localMobile = prefs.getString('userMobile');
    final bool isSuperAdmin = role == 'super_admin';

    if (type == 'MASJID_REGISTRATION_REQUEST') {
      if (!isSuperAdmin) return;
      final String title =
          message.data['title'] ??
          message.notification?.title ??
          'New Masjid Registration';
      final String body =
          message.data['body'] ??
          message.notification?.body ??
          'A new masjid registration request was submitted.';
      await showSimplePushNotification(title: title, body: body);
      return;
    }

    if (type == 'MASJID_REQUEST_CREATED') {
      if (!isSuperAdmin) return;
      final String title =
          message.data['title'] ??
          message.notification?.title ??
          'New Masjid Request';
      final String body =
          message.data['body'] ??
          message.notification?.body ??
          'A new masjid registration request was submitted.';
      await showSimplePushNotification(title: title, body: body);
      return;
    }

    if (type == 'MASJID_APPROVAL_DECISION') {
      final String? filteredMobile = prefs.getString(_mobileFilterKey);
      final String? activeMobile = filteredMobile ?? localMobile;
      final String targetMobile = (message.data['adminMobileNumber'] ?? '')
          .trim();
      if (targetMobile.isEmpty ||
          activeMobile == null ||
          activeMobile != targetMobile) {
        return;
      }

      final String title = message.data['title'] ?? 'Masjid request update';
      final String body =
          message.data['body'] ?? 'Your masjid request status has changed.';
      await showSimplePushNotification(title: title, body: body);
      return;
    }

    if (type == 'MASJID_REQUEST_APPROVED') {
      final String? filteredMobile = prefs.getString(_mobileFilterKey);
      final String? activeMobile = filteredMobile ?? localMobile;
      final String targetAdminId = (message.data['adminId'] ?? '').trim();
      if (targetAdminId.isEmpty ||
          activeMobile == null ||
          activeMobile != targetAdminId) {
        return;
      }
      final String title =
          message.data['title'] ??
          message.notification?.title ??
          'Masjid Approved';
      final String body =
          message.data['body'] ??
          message.notification?.body ??
          'Your masjid request has been approved.';
      await showSimplePushNotification(title: title, body: body);
      return;
    }
  }

  Future<void> showSimplePushNotification({
    required String title,
    required String body,
  }) async {
    if (!_isInitialized) await init();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'admin_updates_channel_v1',
          'Admin Updates',
          channelDescription: 'Masjid approval and workflow updates',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  Future<void> _cancelNotificationSafely(int id) async {
    try {
      await flutterLocalNotificationsPlugin.cancel(id);
    } catch (e, stack) {
      debugPrint('Notification cancel failed for id $id: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<String?> _resolveActiveNotificationPayload(
    ActiveNotification notification,
  ) async {
    final String? payload = notification.payload;
    if (payload != null && payload.isNotEmpty) return payload;
    return _getCachedNativeReplacementPayload(notification.id ?? -1);
  }

  _AlarmPayloadData? _parseAlarmPayload(
    String? payload, {
    int? fallbackId,
    String? fallbackTitle,
  }) {
    final String safePayload = payload ?? '';
    final parts = safePayload.split('|');
    final int? alarmId = int.tryParse(parts.first) ?? fallbackId;
    if (alarmId == null) return null;

    final String title = parts.length > 1 && parts[1].isNotEmpty
        ? parts[1]
        : (fallbackTitle ?? '');
    int endTimeMillis = 0;
    int jamatTimeMillis = 0;

    if (parts.length > 2 && parts[2].isNotEmpty) {
      endTimeMillis = normalizeTime(int.tryParse(parts[2]) ?? 0);
    }
    if (parts.length > 3 && parts[3].isNotEmpty) {
      jamatTimeMillis = normalizeTime(int.tryParse(parts[3]) ?? 0);
    }

    return _AlarmPayloadData(
      alarmId: alarmId,
      title: title,
      endTimeMillis: endTimeMillis,
      jamatTimeMillis: jamatTimeMillis,
    );
  }

  bool _isAlarmExpired(_AlarmPayloadData data) {
    if (data.endTimeMillis <= 0) return false;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    return nowMs > data.endTimeMillis;
  }

  bool isAlarmPayloadExpired(String? payload) {
    final _AlarmPayloadData? parsed = _parseAlarmPayload(payload);
    if (parsed == null) return false;
    return _isAlarmExpired(parsed);
  }

  void _pruneAutoSnoozeTimers(Set<int> activeAlarmIds) {
    final staleIds = _pendingAutoSnoozeTimers.keys
        .where((id) => !activeAlarmIds.contains(id))
        .toList();
    for (final int id in staleIds) {
      _pendingAutoSnoozeTimers.remove(id)?.cancel();
    }
  }

  void cancelAutoSnoozeForPayload(String? payload, {int? notificationId}) {
    int? alarmId;
    if (payload != null && payload.isNotEmpty) {
      alarmId = int.tryParse(payload.split('|').first);
    }
    alarmId ??= notificationId;
    if (alarmId == null) return;
    _pendingAutoSnoozeTimers.remove(alarmId)?.cancel();
  }

  void cancelAutoSnoozeForAlarmId(int? alarmId) {
    if (alarmId == null) return;
    _pendingAutoSnoozeTimers.remove(alarmId)?.cancel();
  }

  Future<void> cancelAllAutoSnoozeArtifacts(int alarmId) async {
    cancelAutoSnoozeForAlarmId(alarmId);
    await _cancelNotificationSafely(alarmId + _snoozeIdOffset);
    await _cancelNativeInlineJamatReplacement(alarmId + _snoozeIdOffset);
    await _cancelAutoSnoozeFallbacks(alarmId);
  }

  Future<void> _cancelAutoSnoozeFallbacks(int id) async {
    for (int i = 0; i < _autoSnoozeFallbackMaxCount; i++) {
      await _cancelNotificationSafely(id + _autoSnoozeScheduleIdOffset + i);
      await _cancelNativeInlineJamatReplacement(
        id + _autoSnoozeScheduleIdOffset + i,
      );
    }
  }

  Future<void> _scheduleAutoSnoozeFallbacks({
    required int id,
    required String title,
    required String payload,
    required DateTime alarmTimeLocal,
    DateTime? endTimeLocal,
    DateTime? jamatTimeLocal,
  }) async {
    final Duration interval =
        _autoSnoozeNoResponseDelay +
        const Duration(minutes: _autoSnoozeMinutes);

    await _cancelAutoSnoozeFallbacks(id);

    for (int i = 0; i < _autoSnoozeFallbackMaxCount; i++) {
      final DateTime nextLocal = alarmTimeLocal.add(interval * (i + 1));
      if (endTimeLocal != null &&
          nextLocal.millisecondsSinceEpoch >=
              endTimeLocal.millisecondsSinceEpoch) {
        break;
      }

      final tz.TZDateTime tzNext = tz.TZDateTime.from(
        nextLocal.toUtc(),
        tz.UTC,
      );
      final String fallbackBody = 'Snooze time over for $title';

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id + _autoSnoozeScheduleIdOffset + i,
        title,
        fallbackBody,
        tzNext,
        _buildJamatNotificationDetails(
          channelId: _jamatAlarmChannelId,
          playSound: true,
          fullScreenIntent: true,
          isSwipePersistent: true,
          body: fallbackBody,
        ),
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      if (endTimeLocal != null && jamatTimeLocal != null) {
      await _scheduleNativeInlineJamatReplacement(
        id: id + _autoSnoozeScheduleIdOffset + i,
        title: title,
        body: fallbackBody,
        payload: payload,
        triggerTime: nextLocal,
        endTime: endTimeLocal,
          jamatTime: jamatTimeLocal,
          repeatMode: 'none',
        );
      }
    }
  }

  Future<void> _markAutoSnoozed(String title) async {
    if (title.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = await resolveAttendanceDateKey(title);
      await prefs.setBool('salah_snoozed_${today}_$title', true);
    } catch (e) {
      debugPrint('Failed to persist auto-snooze state for $title: $e');
    }
  }

  Future<void> _clearActiveAlarmNotifications(
    _AlarmPayloadData data,
    Map<int, String?> resolvedPayloads,
  ) async {
    final activeNotifications = await flutterLocalNotificationsPlugin
        .getActiveNotifications();
    for (final ActiveNotification notification in activeNotifications) {
      final int? notificationId = notification.id;
      if (notificationId == null) continue;
      if (notification.channelId != _jamatAlarmChannelId) continue;

      final String? resolvedPayload =
          resolvedPayloads[notificationId] ??
          await _resolveActiveNotificationPayload(notification);
      final _AlarmPayloadData? activeData = _parseAlarmPayload(
        resolvedPayload,
        fallbackId: notificationId,
        fallbackTitle: notification.title,
      );
      if (activeData?.alarmId != data.alarmId) continue;

      await _cancelNotificationSafely(notificationId);
      await _cancelNativeInlineJamatReplacement(notificationId);
    }
  }

  void _ensureAutoSnoozeTimer(_AlarmPayloadData data) {
    if (_pendingAutoSnoozeTimers.containsKey(data.alarmId)) return;

    _pendingAutoSnoozeTimers[data
        .alarmId] = Timer(_autoSnoozeNoResponseDelay, () async {
      _pendingAutoSnoozeTimers.remove(data.alarmId);
      try {
        final activeNotifications = await flutterLocalNotificationsPlugin
            .getActiveNotifications();
        final Map<int, String?> resolvedPayloads = <int, String?>{};
        for (final ActiveNotification notification in activeNotifications) {
          final int? notificationId = notification.id;
          if (notificationId == null) continue;
          resolvedPayloads[notificationId] =
              await _resolveActiveNotificationPayload(notification);
        }
        final bool isStillActive = activeNotifications.any((n) {
          if (n.channelId != _jamatAlarmChannelId) return false;
          final int? notificationId = n.id;
          if (notificationId == null) return false;
          final String? resolvedPayload = resolvedPayloads[notificationId];
          if (resolvedPayload == null || resolvedPayload.isEmpty) {
            return notificationId == data.alarmId;
          }
          final int? activeId = int.tryParse(resolvedPayload.split('|').first);
          return activeId == data.alarmId;
        });

        if (!isStillActive) return;

        await _clearActiveAlarmNotifications(data, resolvedPayloads);
        await _markAutoSnoozed(data.title);
        actionStream.add('snooze');
      } catch (e) {
        debugPrint('Auto-snooze failed for alarm ${data.alarmId}: $e');
      }
    });
  }

  Future<void> init() async {
    if (_isInitialized) return;

    tz_data.initializeTimeZones();

    // Android settings: Ensure you have a drawable named 'ic_launcher' or similar in res/drawable
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: true,
          requestBadgePermission: true,
          requestAlertPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        // When the app is in the foreground, this callback is called.
        // We'll just delegate to the background handler to unify logic.
        debugPrint('Foreground notification action: ${details.actionId}');
        cancelAutoSnoozeForPayload(details.payload, notificationId: details.id);
        _processNotificationAction(flutterLocalNotificationsPlugin, details);
        if (details.payload != null && details.payload!.isNotEmpty) {
          payloadStream.add(details.payload);
        }
        if (details.actionId != null) {
          actionStream.add(details.actionId!);
        }
      },
    );

    // Check if the app was launched by a notification (e.g. full screen intent)
    final NotificationAppLaunchDetails? notificationAppLaunchDetails =
        await flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails();
    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      final response = notificationAppLaunchDetails!.notificationResponse;
      launchPayload = response?.payload;
      if (launchPayload != null) {
        if (payloadStream.hasListener) {
          payloadStream.add(launchPayload);
          launchPayload = null;
        }
      }
      if (response?.actionId != null) {
        Future.delayed(
          Duration.zero,
          () => actionStream.add(response!.actionId!),
        );
      }
    }

    // Request permissions for Android 13+ and Exact Alarms
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
      await _refreshScheduleMode();
    }

    _isInitialized = true;

    // Cleanup legacy notifications to prevent old payloads from triggering the alarm screen
    for (int i = 0; i < 50; i++) {
      await _cancelNotificationSafely(i + 100);
      await _cancelNotificationSafely(i + 200);
    }
  }

  /// Emits payloads for active Jamat alarms so UI can open AlarmScreen
  /// without waiting for notification tap callbacks.
  Future<void> emitActiveJamatAlarmPayloadIfAny() async {
    if (!_isInitialized) return;
    try {
      final List<ActiveNotification> activeNotifications =
          await flutterLocalNotificationsPlugin.getActiveNotifications();
      if (activeNotifications.isEmpty) {
        _pruneAutoSnoozeTimers(<int>{});
        return;
      }

      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final Set<int> activeAlarmIds = <int>{};
      for (final ActiveNotification notification in activeNotifications) {
        final String? payload = await _resolveActiveNotificationPayload(
          notification,
        );
        if (notification.channelId != _jamatAlarmChannelId) {
          continue;
        }

        final _AlarmPayloadData? parsed = _parseAlarmPayload(
          payload,
          fallbackId: notification.id,
          fallbackTitle: notification.title,
        );
        if (parsed == null) continue;
        if (_isAlarmExpired(parsed)) {
          cancelAutoSnoozeForAlarmId(parsed.alarmId);
          await _cancelAutoSnoozeFallbacks(parsed.alarmId);
          continue;
        }

        final int idFromPayload = parsed.alarmId;
        activeAlarmIds.add(idFromPayload);
        _ensureAutoSnoozeTimer(parsed);
        final int? lastOpenedMs = _autoOpenedAlarmIds[idFromPayload];
        if (lastOpenedMs != null && (nowMs - lastOpenedMs) < 5 * 60 * 1000) {
          continue;
        }

        _autoOpenedAlarmIds[idFromPayload] = nowMs;
        if (payload != null && payload.isNotEmpty) {
          payloadStream.add(payload);
        }
      }
      _pruneAutoSnoozeTimers(activeAlarmIds);
    } catch (e) {
      debugPrint('Active Jamat alarm detection failed: $e');
    }
  }

  Future<void> scheduleSalahAlarm({
    required int id,
    required String title,
    required String body,
    required String masjidTime, // Azan Time
    required String masjidJamatTime, // Jamat Time
    required String myTime, // Azan Time
    required String myJamatTime, // Jamat Time
    required bool isMyPrefsMode,
    required DateTime endTime,
    bool azanEnabled = true,
    bool jamatEnabled = false,
    String? sound,
  }) async {
    if (!_isInitialized) await init();
    await _refreshScheduleMode();

    // Always cancel existing alarms for this ID first to ensure toggles and
    // time changes are correctly applied. Do NOT cancel active snoozes here.
    await cancelAlarm(id, cancelSnooze: false);

    // Determine which time to use based on the mode
    final String azanTimeString = isMyPrefsMode ? myTime : masjidTime;
    final String jamatTimeString = isMyPrefsMode
        ? myJamatTime
        : masjidJamatTime;

    if (azanTimeString.isEmpty || !azanTimeString.contains(':')) {
      debugPrint(
        '⚠️ Invalid time string for $title: "$azanTimeString" (Mode: ${isMyPrefsMode ? "Prefs" : "Masjid"})',
      );
      return;
    }

    try {
      final DateTime now = DateTime.now();

      DateTime _parsePrayerTimeForToday(String timeString) {
        final parts = timeString.trim().split(':');
        int parsedHour = int.parse(parts[0]);
        final int parsedMinute = int.parse(
          parts[1].replaceAll(RegExp(r'[^0-9]'), ''),
        );

        if (timeString.toLowerCase().contains('pm') && parsedHour < 12) {
          parsedHour += 12;
        } else if (timeString.toLowerCase().contains('am') &&
            parsedHour == 12) {
          parsedHour = 0;
        }

        // Match the existing heuristics so 12-hour strings without AM/PM
        // still land on the expected part of the day.
        if (!timeString.toLowerCase().contains('pm') &&
            !timeString.toLowerCase().contains('am')) {
          if (title == 'Isha') {
            if (parsedHour == 12) {
              parsedHour = 0;
            } else if (parsedHour > 4 && parsedHour < 12) {
              parsedHour += 12;
            }
          } else if (parsedHour < 12 &&
              (title == 'Asr' || title == 'Maghrib')) {
            parsedHour += 12;
          } else if ((title == 'Dhuhr' || title == 'Juma') && parsedHour < 11) {
            parsedHour += 12;
          }
        }

        return DateTime(now.year, now.month, now.day, parsedHour, parsedMinute);
      }

      // Base Azan time for today (from user's myTime preference)
      DateTime azanBase = _parsePrayerTimeForToday(azanTimeString);
      DateTime endTimeAnchor = DateTime(
        now.year,
        now.month,
        now.day,
        endTime.hour,
        endTime.minute,
      );
      // If end time is before the azan base, it belongs to the next day.
      if (endTimeAnchor.isBefore(azanBase)) {
        endTimeAnchor = endTimeAnchor.add(const Duration(days: 1));
      }

      // Guard against mis-parsed Dhuhr/Juma times that land after the prayer end.
      if ((title == 'Dhuhr' || title == 'Juma') &&
          azanBase.isAfter(endTimeAnchor) &&
          azanBase.difference(endTimeAnchor).inHours >= 2) {
        azanBase = azanBase.subtract(const Duration(hours: 12));
      }
      debugPrint(
        'Schedule compute for $title: azan="$azanTimeString" '
        'jamat="$jamatTimeString" azanBase=$azanBase now=$now',
      );

      // Jamat alarm continues to ring 5 minutes after Azan, but the countdown
      // shown on the alarm screen should use the configured real Jamat time.
      final DateTime jamatAlarmBase = azanBase.add(const Duration(minutes: 5));
      DateTime finalRealJamat = jamatAlarmBase;
      if (jamatTimeString.isNotEmpty && jamatTimeString.contains(':')) {
        final DateTime configuredJamatBase = _parsePrayerTimeForToday(
          jamatTimeString,
        );
        finalRealJamat = configuredJamatBase.isBefore(azanBase)
            ? configuredJamatBase.add(const Duration(days: 1))
            : configuredJamatBase;
      }

      // Safety: If the jamat alarm would fire after the prayer's end time,
      // disable jamat for this schedule (azan can still ring).
      if (jamatEnabled) {
        DateTime jamatCheck = finalRealJamat;
        if (jamatCheck.isBefore(azanBase)) {
          jamatCheck = jamatCheck.add(const Duration(days: 1));
        }
        if (!jamatCheck.isBefore(endTimeAnchor)) {
          debugPrint(
            'Skipping jamat for $title: jamat=$jamatCheck end=$endTimeAnchor',
          );
          jamatEnabled = false;
        }
      }

      // Determine scheduling strategy based on Title (Juma vs Dhuhr vs Others)
      if (title == 'Juma') {
        // Schedule ONLY for Friday
        await _scheduleWeekly(
          id: id,
          title: title,
          body: body,
          azanBase: azanBase,
          jamatAlarmBase: jamatAlarmBase,
          realJamatBase: finalRealJamat,
          endTime: endTime,
          azanEnabled: azanEnabled,
          jamatEnabled: jamatEnabled,
          targetWeekday: DateTime.friday,
          sound: sound,
        );
      } else if (title == 'Dhuhr') {
        // Schedule for every day EXCEPT Friday (Sat, Sun, Mon, Tue, Wed, Thu)
        final List<int> dhuhrDays = [
          DateTime.saturday,
          DateTime.sunday,
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
        ];

        for (int day in dhuhrDays) {
          // Use a unique ID for each day to avoid collision
          // Base ID for Dhuhr is usually 2.
          // We map IDs: Jamat = 2000 + day, Azan = 2300 + day
          await _scheduleWeekly(
            id: 2000 + day, // Special ID range for Dhuhr
            title: title,
            body: body,
            azanBase: azanBase,
            jamatAlarmBase: jamatAlarmBase,
            realJamatBase: finalRealJamat,
            endTime: endTime,
            azanEnabled: azanEnabled,
            jamatEnabled: jamatEnabled,
            targetWeekday: day,
            useCustomId: true,
            sound: sound,
          );
        }
      } else {
        // Standard Daily Scheduling (Fajr, Asr, Maghrib, Isha)
        await _scheduleDaily(
          id: id,
          title: title,
          body: body,
          azanBase: azanBase,
          jamatAlarmBase: jamatAlarmBase,
          realJamatBase: finalRealJamat,
          endTime: endTime,
          azanEnabled: azanEnabled,
          jamatEnabled: jamatEnabled,
          sound: sound,
        );
      }
    } catch (e) {
      debugPrint('❌ Error scheduling alarm: $e');
    }
  }

  // Helper for Standard Daily Scheduling
  Future<void> _scheduleDaily({
    required int id,
    required String title,
    required String body,
    required DateTime azanBase,
    required DateTime jamatAlarmBase,
    required DateTime realJamatBase,
    required DateTime endTime,
    required bool azanEnabled,
    required bool jamatEnabled,
    String? sound,
  }) async {
    final DateTime now = DateTime.now();

    // For Azan: Schedule for next occurrence
    DateTime scheduledAzan = azanBase;
    if (scheduledAzan.isBefore(now)) {
      scheduledAzan = scheduledAzan.add(const Duration(days: 1));
    }

    // For Jamat: Check if we should schedule for today or tomorrow
    DateTime scheduledJamatAlarm = jamatAlarmBase;
    DateTime scheduledRealJamat = realJamatBase;

    if (jamatEnabled) {
      if (jamatAlarmBase.isAfter(now) || jamatAlarmBase.isAtSameMomentAs(now)) {
        scheduledJamatAlarm = jamatAlarmBase;
        scheduledRealJamat = realJamatBase;
      } else {
        scheduledJamatAlarm = jamatAlarmBase.add(const Duration(days: 1));
        scheduledRealJamat = realJamatBase.add(const Duration(days: 1));
      }
    } else {
      if (scheduledJamatAlarm.isBefore(now)) {
        scheduledJamatAlarm = scheduledJamatAlarm.add(const Duration(days: 1));
        scheduledRealJamat = scheduledRealJamat.add(const Duration(days: 1));
      }
    }

    final tz.TZDateTime tzAzanDate = tz.TZDateTime.from(
      scheduledAzan.toUtc(),
      tz.UTC,
    );
    final tz.TZDateTime tzJamatDate = tz.TZDateTime.from(
      scheduledJamatAlarm.toUtc(),
      tz.UTC,
    );

    debugPrint(
      'Scheduling daily $title: azan=$scheduledAzan jamat=$scheduledJamatAlarm '
      'realJamat=$scheduledRealJamat',
    );
    await _scheduleNotifications(
      id: id,
      title: title,
      body: body,
      tzAzanDate: tzAzanDate,
      tzJamatDate: tzJamatDate,
      scheduledRealJamat: scheduledRealJamat,
      endTime: endTime,
      azanEnabled: azanEnabled,
      jamatEnabled: jamatEnabled,
      matchComponent: DateTimeComponents.time, // Daily
      sound: sound,
    );
  }

  // Helper for Weekly Scheduling (Specific Day)
  Future<void> _scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required DateTime azanBase,
    required DateTime jamatAlarmBase,
    required DateTime realJamatBase,
    required DateTime endTime,
    required bool azanEnabled,
    required bool jamatEnabled,
    required int targetWeekday,
    bool useCustomId = false,
    String? sound,
  }) async {
    final DateTime now = DateTime.now();

    // Helper to find next occurrence of specific weekday with correct time
    DateTime nextInstance(DateTime base) {
      DateTime date = base;
      // If base time has passed today and today is the target day, move to next week
      if (date.isBefore(now) && date.weekday == targetWeekday) {
        date = date.add(const Duration(days: 7));
      }
      // Move forward until weekday matches
      while (date.weekday != targetWeekday) {
        date = date.add(const Duration(days: 1));
      }
      // If we found the day but it's in the past (shouldn't happen with above logic but safe check)
      if (date.isBefore(now)) {
        date = date.add(const Duration(days: 7));
      }
      return date;
    }

    DateTime scheduledAzan = nextInstance(azanBase);
    DateTime scheduledJamatAlarm = nextInstance(jamatAlarmBase);
    DateTime scheduledRealJamat = nextInstance(realJamatBase);

    final tz.TZDateTime tzAzanDate = tz.TZDateTime.from(
      scheduledAzan.toUtc(),
      tz.UTC,
    );
    final tz.TZDateTime tzJamatDate = tz.TZDateTime.from(
      scheduledJamatAlarm.toUtc(),
      tz.UTC,
    );

    // For custom IDs (Dhuhr split), we don't use the standard +300 offset logic blindly
    // The caller passes a unique ID for Jamat. We derive Azan ID.
    // If useCustomId is true, id is already unique (e.g. 2001). Azan ID = id + 300 (e.g. 2301).
    debugPrint(
      'Scheduling weekly $title: azan=$scheduledAzan jamat=$scheduledJamatAlarm '
      'realJamat=$scheduledRealJamat weekday=$targetWeekday',
    );
    await _scheduleNotifications(
      id: id,
      title: title,
      body: body,
      tzAzanDate: tzAzanDate,
      tzJamatDate: tzJamatDate,
      scheduledRealJamat: scheduledRealJamat,
      endTime: endTime,
      azanEnabled: azanEnabled,
      jamatEnabled: jamatEnabled,
      matchComponent: DateTimeComponents.dayOfWeekAndTime, // Weekly
      sound: sound,
    );
  }

  Future<void> _scheduleNotifications({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime tzAzanDate,
    required tz.TZDateTime tzJamatDate,
    required DateTime scheduledRealJamat,
    required DateTime endTime,
    required bool azanEnabled,
    required bool jamatEnabled,
    required DateTimeComponents matchComponent,
    String? sound,
  }) async {
    final String repeatMode =
        matchComponent == DateTimeComponents.time ? 'daily' : 'weekly';

    // Calculate EndTime for the Payload
    DateTime targetEndTime = DateTime(
      tzJamatDate.year,
      tzJamatDate.month,
      tzJamatDate.day,
      endTime.hour,
      endTime.minute,
    );
    if (targetEndTime.isBefore(tzJamatDate)) {
      targetEndTime = targetEndTime.add(const Duration(days: 1));
    }

    final String payload =
        '$id|$title|${targetEndTime.millisecondsSinceEpoch}|${scheduledRealJamat.millisecondsSinceEpoch}';

    // 1. Schedule Azan Notification
    if (azanEnabled) {
      final String soundName = sound ?? 'azan';
      // Use a unique channel ID for custom sounds so Android creates a new channel with that sound config
      final String channelId = sound != null
          ? '${sound}_channel'
          : 'azan_notification_channel_v4';

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id + 300,
        title,
        body,
        tzAzanDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            'Salah Notifications',
            channelDescription: 'Simple notifications for Azan times',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(soundName),
            fullScreenIntent: false,
            ongoing: false,
            autoCancel: true,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.notification,
          ),
          iOS: DarwinNotificationDetails(
            presentSound: true,
            sound: '$soundName.mp3',
          ),
        ),
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponent,
        payload: null,
      );
    }

    // 2. Schedule Jamat Alarm
    if (jamatEnabled) {
      final String notificationBody = 'Jamat for $title is about to begin';
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        notificationBody,
        tzJamatDate,
        _buildJamatNotificationDetails(
          channelId: _jamatAlarmChannelId,
          playSound: true,
          fullScreenIntent: true,
          isSwipePersistent: true,
          body: notificationBody,
        ),
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponent,
        payload: payload,
      );
      await _scheduleNativeInlineJamatReplacement(
        id: id,
        title: title,
        body: notificationBody,
        payload: payload,
        triggerTime: tzJamatDate.toLocal(),
        endTime: targetEndTime,
        jamatTime: scheduledRealJamat,
        repeatMode: repeatMode,
      );

      await _scheduleAutoSnoozeFallbacks(
        id: id,
        title: title,
        payload: payload,
        alarmTimeLocal: tzJamatDate.toLocal(),
        endTimeLocal: targetEndTime,
        jamatTimeLocal: scheduledRealJamat,
      );
    }
  }

  Future<void> cancelAlarm(int id, {bool cancelSnooze = true}) async {
    cancelAutoSnoozeForAlarmId(id);
    await _cancelNotificationSafely(id);
    await _cancelNativeInlineJamatReplacement(id);
    await _cancelAutoSnoozeFallbacks(id);
    await _cancelNotificationSafely(id + 100);
    await _cancelNotificationSafely(id + 200);
    await _cancelNotificationSafely(id + 300);

    if (cancelSnooze) {
      await _cancelNotificationSafely(id + _snoozeIdOffset);
      await _cancelNativeInlineJamatReplacement(id + _snoozeIdOffset);
    }

    // If ID is 2 (Dhuhr), also cancel the weekly split IDs
    if (id == 2) {
      for (int day = 1; day <= 7; day++) {
        // Jamat IDs: 2000 + day
        cancelAutoSnoozeForAlarmId(2000 + day);
        await _cancelNotificationSafely(2000 + day);
        await _cancelNativeInlineJamatReplacement(2000 + day);
        await _cancelAutoSnoozeFallbacks(2000 + day);
        // Azan IDs: 2300 + day
        await _cancelNotificationSafely(2300 + day);
        if (cancelSnooze) {
          await _cancelNotificationSafely(2000 + day + _snoozeIdOffset);
          await _cancelNativeInlineJamatReplacement(
            2000 + day + _snoozeIdOffset,
          );
        }
      }
    }

    debugPrint('Canceled alarm $id and associated notifications');
  }

  Future<void> _cancelAllSalahSchedules() async {
    for (int id = 1; id <= 6; id++) {
      await cancelAlarm(id, cancelSnooze: true);
    }
  }

  /// Helper to normalize a timestamp to the current day if it appears to be stale.
  /// This fixes issues where repeating alarms carry old timestamps in their payload.
  static int normalizeTime(int millis) {
    if (millis == 0) return 0;
    final now = DateTime.now();
    DateTime date = DateTime.fromMillisecondsSinceEpoch(millis);

    // A timestamp is considered stale if it's from more than ~23 hours ago.
    // This catches daily repeating alarms whose payloads are now a day old.
    if (now.difference(date).inHours >= 23) {
      // It's stale. Let's calculate the next valid occurrence.
      // We create a time for today using the hour/minute from the payload.
      DateTime newDate = DateTime(
        now.year,
        now.month,
        now.day,
        date.hour,
        date.minute,
      );

      // If that time has already passed today, the next occurrence is tomorrow.
      if (newDate.isBefore(now)) {
        newDate = newDate.add(const Duration(days: 1));
      }
      return newDate.millisecondsSinceEpoch;
    }

    // If the timestamp is recent (past <23h) or in the future, it's considered valid.
    // This correctly handles Isha end times (future) and recently passed Jamat times.
    return millis;
  }

  Future<void> snoozeAlarm({
    required int id,
    required String notificationTitle,
    required String payloadTitle,
    required int minutes,
    int? endTimeMillis,
    int? jamatTimeMillis,
  }) async {
    if (!_isInitialized) await init();
    try {
      cancelAutoSnoozeForAlarmId(id);
      await _cancelAutoSnoozeFallbacks(id);
      // Cancel the original alarm. This stops the sound.
      await _cancelNotificationSafely(id);
      // Also cancel any previous snooze for this ID to avoid duplicates
      await _cancelNotificationSafely(id + _snoozeIdOffset);

      // Normalize times to ensure we aren't comparing against old dates
      endTimeMillis = normalizeTime(endTimeMillis ?? 0);
      jamatTimeMillis = normalizeTime(jamatTimeMillis ?? 0);

      // Fetch fresh end time from DB to ensure we have the correct Salah end time
      final int? freshEndTime = await getFreshEndTime(payloadTitle);
      if (freshEndTime != null) {
        endTimeMillis = freshEndTime;
      }

      final DateTime now = DateTime.now();
      DateTime scheduledDate = now.add(Duration(minutes: minutes));

      // Do not snooze if the snooze time is after the prayer's end time
      if (endTimeMillis > 0 &&
          scheduledDate.millisecondsSinceEpoch > endTimeMillis) {
        final endTime = DateTime.fromMillisecondsSinceEpoch(endTimeMillis);
        if (endTime.isAfter(now)) {
          scheduledDate = endTime;
        } else {
          return;
        }
      }

      final tz.TZDateTime tzScheduledDate = tz.TZDateTime.from(
        scheduledDate.toUtc(),
        tz.UTC,
      );

      final payload =
          '$id|$payloadTitle|${endTimeMillis > 0 ? endTimeMillis : ''}|${jamatTimeMillis > 0 ? jamatTimeMillis : ''}';

      String notificationBody = 'Snooze time over for $payloadTitle';
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id + _snoozeIdOffset, // Use dedicated snooze ID
        notificationTitle,
        notificationBody,
        tzScheduledDate,
        _buildJamatNotificationDetails(
          channelId: _jamatAlarmChannelId,
          playSound: true,
          fullScreenIntent: true,
          isSwipePersistent: true,
          body: notificationBody,
        ),
        androidScheduleMode: _scheduleMode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
      final DateTime? endTimeLocal = endTimeMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(endTimeMillis)
          : null;
      if (endTimeLocal != null && jamatTimeMillis > 0) {
        await _scheduleNativeInlineJamatReplacement(
          id: id + _snoozeIdOffset,
          title: notificationTitle,
          body: notificationBody,
          payload: payload,
          triggerTime: scheduledDate,
          endTime: endTimeLocal,
          jamatTime: DateTime.fromMillisecondsSinceEpoch(jamatTimeMillis),
          repeatMode: 'none',
        );
      }
      await _scheduleAutoSnoozeFallbacks(
        id: id,
        title: payloadTitle,
        payload: payload,
        alarmTimeLocal: scheduledDate,
        endTimeLocal: endTimeLocal,
        jamatTimeLocal: jamatTimeMillis > 0
            ? DateTime.fromMillisecondsSinceEpoch(jamatTimeMillis)
            : null,
      );

      debugPrint('Snoozed alarm $id for $minutes minutes');
    } catch (e) {
      debugPrint('Error snoozing alarm: $e');
    }
  }

  Future<int?> getFreshEndTime(String title) async {
    try {
      final prayers = await loadCalendarPrayersForToday();
      if (prayers.isEmpty) return null;

      final searchTitle = (title == 'Juma') ? 'Dhuhr' : title;
      final match = prayers.firstWhere(
        (p) => p.name == searchTitle,
        orElse: () => PrayerTimeData(
          name: '',
          startTime: DateTime.now(),
          endTime: DateTime.now(),
        ),
      );

      if (match.name.isNotEmpty) {
        return match.endTime.millisecondsSinceEpoch;
      }
    } catch (e) {
      debugPrint('Error getting fresh end time: $e');
    }
    return null;
  }

  Future<String> resolveAttendanceDateKey(String title) async {
    final DateTime now = DateTime.now();
    final String baseTitle = _stripAttendanceTitle(title);
    if (baseTitle != 'Isha') {
      return _dateKey(now);
    }

    final DateTime? fajrStart = await _getTodayFajrStart();
    if (fajrStart != null && now.isBefore(fajrStart)) {
      return _dateKey(now.subtract(const Duration(days: 1)));
    }
    return _dateKey(now);
  }

  Future<DateTime?> _getTodayFajrStart() async {
    try {
      final prayers = await loadCalendarPrayersForToday();
      if (prayers.isEmpty) return null;
      final match = prayers.firstWhere(
        (p) => p.name == 'Fajr',
        orElse: () => PrayerTimeData(
          name: '',
          startTime: DateTime.now(),
          endTime: DateTime.now(),
        ),
      );
      if (match.name.isEmpty) return null;
      return match.startTime;
    } catch (e) {
      debugPrint('Error getting fajr start time: $e');
      return null;
    }
  }

  Future<List<PrayerTimeData>> loadCalendarPrayersForToday() async {
    try {
      final db = await SalahDatabaseHelper.instance.database;
      final repo = SalahCalendarRepository(db);
      final now = DateTime.now();
      final row = await repo.getByDate(DateTime(now.year, now.month, now.day));
      if (row == null) {
        debugPrint("Background sync: No calendar row found for today.");
        return [];
      }

      String? rawFajrEnd;
      try {
        final rawMap = await SalahDatabaseHelper.instance.getRowForDate(now);
        if (rawMap != null) {
          rawFajrEnd = rawMap['fajr_end']?.toString();
        }
      } catch (e) {
        debugPrint('Background sync: Raw fajr_end fetch error: $e');
      }

      return _parsePrayersLocally(row, rawFajrEnd);
    } catch (e) {
      debugPrint('Background sync: Calendar load error: $e');
      return [];
    }
  }

  List<PrayerTimeData> _parsePrayersLocally(
    SalahCalendarModel row, [
    String? rawFajrEnd,
  ]) {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year, now.month, now.day);

    DateTime parse(String time) {
      if (time.isEmpty) return date;
      try {
        final parts = time.trim().split(':');
        final h = int.parse(parts[0].trim());
        final m = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
        return date.add(Duration(hours: h, minutes: m));
      } catch (_) {
        return date;
      }
    }

    DateTime toPm(DateTime t) =>
        t.hour < 12 ? t.add(const Duration(hours: 12)) : t;

    final fStart = parse(row.fajrAzan);

    DateTime fEnd = (rawFajrEnd != null && rawFajrEnd.isNotEmpty)
        ? parse(rawFajrEnd)
        : parse(row.sunrise);
    if (!fEnd.isAfter(fStart)) {
      fEnd = fStart.add(const Duration(minutes: 90));
    }

    var dStart = parse(row.dhuhrAzan);
    if (dStart.hour < 11) dStart = toPm(dStart);

    var aStart = parse(row.asrAzan);
    if (aStart.hour < 12) aStart = toPm(aStart);

    var mStart = parse(row.maghribAzan);
    if (mStart.hour < 12) mStart = toPm(mStart);

    var iStart = parse(row.ishaAzan);
    if (iStart.hour < 12) {
      if (iStart.hour > 4) {
        iStart = toPm(iStart);
      }
    }

    return [
      PrayerTimeData(name: 'Fajr', startTime: fStart, endTime: fEnd),
      PrayerTimeData(
        name: 'Dhuhr',
        startTime: dStart,
        endTime: aStart.subtract(const Duration(minutes: 5)),
      ),
      PrayerTimeData(
        name: 'Asr',
        startTime: aStart,
        endTime: mStart.subtract(const Duration(minutes: 5)),
      ),
      PrayerTimeData(
        name: 'Maghrib',
        startTime: mStart,
        endTime: iStart.subtract(const Duration(minutes: 5)),
      ),
      PrayerTimeData(
        name: 'Isha',
        startTime: iStart,
        endTime: fStart.add(const Duration(days: 1)),
      ),
    ];
  }
}
