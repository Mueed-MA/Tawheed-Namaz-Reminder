import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmScreen extends StatefulWidget {
  final String payload; // e.g., "Fajr Azan"

  const AlarmScreen({super.key, required this.payload});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  static const int _autoSnoozeMinutes = 5;
  static const Duration _autoSnoozeDelay = Duration(minutes: 1);

  int _snoozeMinutes = 5;
  int? _alarmId;
  int? _jamatTimeMillis;
  int? _endTimeMillis;
  late String _displayTitle;
  String? _timeLeftLabel;
  String? _timeLeftValue;
  Timer? _timer;
  Timer? _autoSnoozeTimer;
  bool _didRespondToAlarm = false;

  @override
  void initState() {
    super.initState();
    _parsePayload();
    _maybeAutoDismissIfExpired();
    _calculateTimeLeft();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _calculateTimeLeft(),
    );
    _autoSnoozeTimer = Timer(_autoSnoozeDelay, _autoSnoozeIfNoResponse);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _autoSnoozeTimer?.cancel();
    super.dispose();
  }

  void _markAlarmResponded() {
    _didRespondToAlarm = true;
    _autoSnoozeTimer?.cancel();
    NotificationService.instance.cancelAutoSnoozeForAlarmId(_alarmId);
  }

  Future<void> _autoSnoozeIfNoResponse() async {
    if (!mounted || _didRespondToAlarm || _alarmId == null) return;
    _snoozeMinutes = _autoSnoozeMinutes;
    await _snooze(showFeedback: false);
  }

  void _parsePayload() {
    final parts = widget.payload.split('|');
    _alarmId = int.tryParse(parts[0]);
    _displayTitle = parts.length > 1 ? parts[1] : widget.payload;

    if (parts.length > 2 && parts[2].isNotEmpty) {
      int? t = int.tryParse(parts[2]);
      if (t != null) _endTimeMillis = NotificationService.normalizeTime(t);
    }

    if (parts.length > 3 && parts[3].isNotEmpty) {
      int? t = int.tryParse(parts[3]);
      if (t != null) _jamatTimeMillis = NotificationService.normalizeTime(t);
    }
  }

  void _maybeAutoDismissIfExpired() {
    if (_endTimeMillis == null) return;
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs <= _endTimeMillis!) return;
    _markAlarmResponded();
    if (_alarmId != null) {
      unawaited(
        NotificationService.instance.cancelAllAutoSnoozeArtifacts(_alarmId!),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) {
      d = Duration.zero;
    }
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  void _calculateTimeLeft() {
    if (!mounted) return;
    final now = DateTime.now();

    if (_jamatTimeMillis != null) {
      final jamatTime = DateTime.fromMillisecondsSinceEpoch(_jamatTimeMillis!);
      final timeLeft = jamatTime.difference(now);

      if (!timeLeft.isNegative) {
        setState(() {
          _timeLeftLabel = 'Time left for the jamat';
          _timeLeftValue = _formatDuration(timeLeft);
        });
        return;
      }
    }

    if (_endTimeMillis != null) {
      final endTime = DateTime.fromMillisecondsSinceEpoch(_endTimeMillis!);
      final timeLeft = endTime.difference(now);
      if (!timeLeft.isNegative) {
        setState(() {
          _timeLeftLabel = '$_displayTitle time ends in';
          _timeLeftValue = _formatDuration(timeLeft);
        });
      } else {
        setState(() {
          _timeLeftLabel = '$_displayTitle time has ended';
          _timeLeftValue = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_alarm, size: 80, color: Colors.green),
              const SizedBox(height: 24),
              Text(
                'Time for $_displayTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_timeLeftLabel != null) ...[
                const SizedBox(height: 16),
                Column(
                  children: [
                    Text(
                      _timeLeftLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.black54,
                      ),
                    ),
                    if (_timeLeftValue != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _timeLeftValue!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionButton(
                    label: 'Decline',
                    color: Colors.red,
                    icon: Icons.close,
                    onTap: _declineAlarm,
                  ),
                  _actionButton(
                    label: 'Accept',
                    color: Colors.green,
                    icon: Icons.check,
                    onTap: _acceptAlarm,
                  ),
                ],
              ),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Snooze',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () {
                            if (_snoozeMinutes > 5) {
                              setState(() => _snoozeMinutes -= 5);
                            }
                          },
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '$_snoozeMinutes min',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _snoozeMinutes += 5),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _snooze,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45),
                      ),
                      child: const Text('Snooze Alarm'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: color.withOpacity(0.1),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptAlarm() async {
    _markAlarmResponded();
    final prefs = await SharedPreferences.getInstance();
    final today = await NotificationService.instance
        .resolveAttendanceDateKey(_displayTitle);
    final key = 'attendance_${today}_$_displayTitle';
    await prefs.setString(key, 'accepted');

    // Notify listeners that an action was taken
    NotificationService.instance.actionStream.add('accept');
    await _dismissAlarm();
  }

  Future<void> _declineAlarm() async {
    _markAlarmResponded();
    final prefs = await SharedPreferences.getInstance();
    final today = await NotificationService.instance
        .resolveAttendanceDateKey(_displayTitle);
    final key = 'attendance_${today}_$_displayTitle';
    await prefs.setString(key, 'declined');

    // Notify listeners that an action was taken
    NotificationService.instance.actionStream.add('decline');
    await _dismissAlarm();
  }

  Future<void> _dismissAlarm() async {
    if (_alarmId != null) {
      // Use the service's comprehensive cancel method to remove all
      // related alarms for this salah (including repeating ones and snoozes).
      // This ensures the sound stops and no more alarms for this salah today.
      await NotificationService.instance.cancelAlarm(_alarmId!);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _snooze({bool showFeedback = true}) async {
    if (_alarmId == null) return;
    _markAlarmResponded();

    // Save snooze state for Home Screen
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setBool('salah_snoozed_${today}_$_displayTitle', true);

    await NotificationService.instance.snoozeAlarm(
      id: _alarmId!,
      notificationTitle: _displayTitle,
      payloadTitle: _displayTitle,
      minutes: _snoozeMinutes,
      endTimeMillis: _endTimeMillis,
      jamatTimeMillis: _jamatTimeMillis,
    );

    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Snoozed for $_snoozeMinutes minutes'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    NotificationService.instance.actionStream.add('snooze');
    if (mounted) Navigator.pop(context);
  }
}
