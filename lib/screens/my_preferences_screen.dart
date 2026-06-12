import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/prayer_time_data.dart';
import '../../models/masjid.dart';
import '../../services/default_masjid_repository.dart';
import '../../services/notification_service.dart';
import '../../salah_calendar/salah_calendar_repository.dart';
import '../../salah_calendar/salah_database_helper.dart';

class MyPreferencesScreen extends StatefulWidget {
  final String userMobile;

  const MyPreferencesScreen({super.key, required this.userMobile});

  @override
  State<MyPreferencesScreen> createState() => _MyPreferencesScreenState();
}

class _MyPreferencesScreenState extends State<MyPreferencesScreen>
    with WidgetsBindingObserver {
  final DefaultMasjidRepository _defaultMasjidRepo =
      DefaultMasjidRepository.instance;
  static const String _prefOverridesMasjidIdKey = 'pref_overrides_masjid_id';
  static const List<String> _timingPreferenceKeys = [
    'pref_Fajr_Azan',
    'pref_Fajr_Jamat',
    'pref_Dhuhr_Azan',
    'pref_Dhuhr_Jamat',
    'pref_Asr_Azan',
    'pref_Asr_Jamat',
    'pref_Maghrib_Azan',
    'pref_Maghrib_Jamat',
    'pref_Isha_Azan',
    'pref_Isha_Jamat',
    'pref_Juma_Azan',
    'pref_Juma_Jamat',
  ];

  Masjid? _defaultMasjid;
  Masjid? _rawMasjid; // Store raw masjid data to access original times
  bool _loading = true;
  bool _isMasterEnabled = false;
  bool? _canScheduleExact;
  bool _checkingExact = false;

  // UI-only toggles
  final Map<String, bool> _toggles = {};
  // Calendar Data
  List<PrayerTimeData> _allPrayers = [];
  StreamSubscription? _updateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.init();
    _loadCalendarData();
    _loadDefaultMasjid();
    _loadPreferences();
    _loadMasterToggle();
    _loadExactAlarmStatus();

    // Listen for remote updates (e.g. when admin changes time)
    _updateSubscription = NotificationService.instance.dataUpdateStream.stream
        .listen((_) {
          if (mounted) {
            _loadDefaultMasjid();
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCalendarData();
      _loadDefaultMasjid();
      _loadExactAlarmStatus();
    }
  }

  Future<void> _loadExactAlarmStatus() async {
    final bool? can = await NotificationService.instance
        .canScheduleExactAlarms();
    if (!mounted) return;
    setState(() => _canScheduleExact = can);
  }

  Future<void> _requestExactAlarmPermission() async {
    if (_checkingExact) return;
    setState(() => _checkingExact = true);
    await NotificationService.instance.requestExactAlarmsPermission();
    await Future.delayed(const Duration(milliseconds: 300));
    final bool? can = await NotificationService.instance
        .canScheduleExactAlarms();
    if (!mounted) return;
    setState(() {
      _canScheduleExact = can;
      _checkingExact = false;
    });
    if (can == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exact alarms enabled')));
      // Reschedule so existing alarms switch to exact timing.
      await NotificationService.instance.rescheduleAllAlarmsFromRemote();
    }
  }

  Future<void> _loadMasterToggle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isMasterEnabled = prefs.getBool('master_alarm_enabled') ?? false;
    });
  }

  Future<void> _loadCalendarData() async {
    try {
      final dbHelper = await SalahDatabaseHelper.instance.database;
      final repo = SalahCalendarRepository(dbHelper);
      final now = DateTime.now();
      final row = await repo.getByDate(DateTime(now.year, now.month, now.day));
      if (row == null) return;

      // This parsing logic is duplicated from home_screen.dart.
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

      String? rawFajrEnd;
      final rawMap = await SalahDatabaseHelper.instance.getRowForDate(now);
      if (rawMap != null) {
        rawFajrEnd = rawMap['fajr_end']?.toString();
      }

      final fStart = parse(row.fajrAzan);
      final fEnd = (rawFajrEnd != null && rawFajrEnd.isNotEmpty)
          ? parse(rawFajrEnd)
          : parse(row.sunrise);
      var dStart = parse(row.dhuhrAzan);
      if (dStart.hour < 11) dStart = toPm(dStart);
      var aStart = parse(row.asrAzan);
      if (aStart.hour < 12) aStart = toPm(aStart);
      var mStart = parse(row.maghribAzan);
      if (mStart.hour < 12) mStart = toPm(mStart);
      var iStart = parse(row.ishaAzan);
      if (iStart.hour < 12) iStart = toPm(iStart);

      final prayers = [
        PrayerTimeData(name: 'Fajr', startTime: fStart, endTime: fEnd),
        PrayerTimeData(name: 'Dhuhr', startTime: dStart, endTime: aStart),
        PrayerTimeData(name: 'Asr', startTime: aStart, endTime: mStart),
        PrayerTimeData(name: 'Maghrib', startTime: mStart, endTime: iStart),
        PrayerTimeData(
          name: 'Isha',
          startTime: iStart,
          endTime: fStart.add(const Duration(days: 1)),
        ),
      ];

      if (mounted) {
        setState(() => _allPrayers = prayers);
      }
    } catch (e) {
      debugPrint('Error loading calendar data in prefs: $e');
    }
  }

  Future<void> _loadDefaultMasjid() async {
    final prefs = await SharedPreferences.getInstance();
    final masjid = await _defaultMasjidRepo.getDefaultMasjid(
      userMobile: widget.userMobile,
      forceRefresh: false,
    );
    _rawMasjid = masjid; // Keep a copy of the raw data

    await _syncTimingOverridesToMasjid(prefs, masjid?.id);

    // Fetch Calendar Data for Maghrib fallback (apply sunset offset)
    String calendarMaghrib = '';
    String calendarMaghribJamat = '';
    final int sunsetOffsetMinutes = masjid?.sunsetOffsetMinutes ?? 0;
    final String sunsetOffsetDirection =
        (masjid?.sunsetOffsetDirection ?? 'less').toLowerCase() == 'more'
        ? 'more'
        : 'less';
    try {
      final dbHelper = await SalahDatabaseHelper.instance.database;
      final repo = SalahCalendarRepository(dbHelper);
      final now = DateTime.now();
      final row = await repo.getByDate(DateTime(now.year, now.month, now.day));
      if (row != null && row.maghribAzan.isNotEmpty) {
        final raw = row.maghribAzan.trim();
        if (raw.contains(':')) {
          final parts = raw.split(':');
          int h = int.parse(parts[0]);
          int m = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

          if (h < 12) h += 12; // Ensure Maghrib is treated as PM (24h format)
          DateTime dt = DateTime(now.year, now.month, now.day, h, m);
          if (sunsetOffsetMinutes > 0) {
            dt = sunsetOffsetDirection == 'more'
                ? dt.add(Duration(minutes: sunsetOffsetMinutes))
                : dt.subtract(Duration(minutes: sunsetOffsetMinutes));
          }
          calendarMaghrib =
              '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

          final jDt = dt.add(const Duration(minutes: 2));
          calendarMaghribJamat =
              '${jDt.hour}:${jDt.minute.toString().padLeft(2, '0')}';
        }
      }
    } catch (e) {
      debugPrint('Error loading calendar for prefs: $e');
    }

    // Load local overrides if any
    if (masjid != null) {
      final overrides = Masjid(
        id: masjid.id,
        name: masjid.name,
        isApproved: masjid.isApproved,
        ownerMobile: masjid.ownerMobile,
        isTimingConfigured: masjid.isTimingConfigured,
        address: masjid.address,
        latitude: masjid.latitude,
        longitude: masjid.longitude,
        district: masjid.district,
        village: masjid.village,
        state: masjid.state,
        fajr: masjid.fajr,
        dhuhr: masjid.dhuhr,
        asr: masjid.asr,
        maghrib: masjid.maghrib,
        isha: masjid.isha,
        juma: masjid.juma,
        fajr_azan: prefs.getString('pref_Fajr_Azan') ?? masjid.fajr_azan,
        fajr_jamat: prefs.getString('pref_Fajr_Jamat') ?? masjid.fajr_jamat,
        dhuhr_azan: prefs.getString('pref_Dhuhr_Azan') ?? masjid.dhuhr_azan,
        dhuhr_jamat: prefs.getString('pref_Dhuhr_Jamat') ?? masjid.dhuhr_jamat,
        asar_azan: prefs.getString('pref_Asr_Azan') ?? masjid.asar_azan,
        asar_jamat: prefs.getString('pref_Asr_Jamat') ?? masjid.asar_jamat,
        maghrib_azan: calendarMaghrib.isNotEmpty ? calendarMaghrib : '',
        maghrib_jamat: calendarMaghribJamat.isNotEmpty
            ? calendarMaghribJamat
            : '',
        isha_azan: prefs.getString('pref_Isha_Azan') ?? masjid.isha_azan,
        isha_jamat: prefs.getString('pref_Isha_Jamat') ?? masjid.isha_jamat,
        juma_azan: prefs.getString('pref_Juma_Azan') ?? masjid.juma_azan,
        juma_jamat: prefs.getString('pref_Juma_Jamat') ?? masjid.juma_jamat,
      );
      setState(() {
        _defaultMasjid = overrides;
        _loading = false;
      });
    } else {
      setState(() {
        _defaultMasjid = masjid;
        _loading = false;
      });
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _toggles.clear();
      final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Juma'];
      for (var p in prayers) {
        _toggles['${p}_Azan'] = prefs.getBool('${p}_Azan') ?? false;
        _toggles['${p}_Jamat'] = prefs.getBool('${p}_Jamat') ?? false;
      }
    });
  }

  Future<void> _pickTime(String salah, String type, String? currentTime) async {
    TimeOfDay initial = TimeOfDay.now();
    try {
      if (currentTime != null && currentTime.contains(':')) {
        final parts = currentTime.split(':');
        // Simple parse, assuming HH:mm format
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1].split(' ')[0]); // Remove any AM/PM text
        initial = TimeOfDay(hour: h, minute: m);
      }
    } catch (_) {}

    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      // Always save in 24-hour format for reliable scheduling
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      await _updateMasjidTime(salah, type, '$h:$m');
    }
  }

  Future<void> _updateMasjidTime(
    String salah,
    String type,
    String newTime,
  ) async {
    if (_defaultMasjid == null) return;

    final updated = Masjid(
      id: _defaultMasjid!.id,
      name: _defaultMasjid!.name,
      isApproved: _defaultMasjid!.isApproved,
      ownerMobile: _defaultMasjid!.ownerMobile,
      isTimingConfigured: _defaultMasjid!.isTimingConfigured,
      address: _defaultMasjid!.address,
      latitude: _defaultMasjid!.latitude,
      longitude: _defaultMasjid!.longitude,
      state: _defaultMasjid!.state,
      district: _defaultMasjid!.district,
      village: _defaultMasjid!.village,
      fajr: _defaultMasjid!.fajr,
      dhuhr: _defaultMasjid!.dhuhr,
      asr: _defaultMasjid!.asr,
      maghrib: _defaultMasjid!.maghrib,
      isha: _defaultMasjid!.isha,
      juma: _defaultMasjid!.juma,
      fajr_azan: (salah == 'Fajr' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.fajr_azan,
      fajr_jamat: (salah == 'Fajr' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.fajr_jamat,
      dhuhr_azan: (salah == 'Dhuhr' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.dhuhr_azan,
      dhuhr_jamat: (salah == 'Dhuhr' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.dhuhr_jamat,
      asar_azan: (salah == 'Asr' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.asar_azan,
      asar_jamat: (salah == 'Asr' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.asar_jamat,
      maghrib_azan: (salah == 'Maghrib' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.maghrib_azan,
      maghrib_jamat: (salah == 'Maghrib' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.maghrib_jamat,
      isha_azan: (salah == 'Isha' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.isha_azan,
      isha_jamat: (salah == 'Isha' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.isha_jamat,
      juma_azan: (salah == 'Juma' && type == 'Azan')
          ? newTime
          : _defaultMasjid!.juma_azan,
      juma_jamat: (salah == 'Juma' && type == 'Jamat')
          ? newTime
          : _defaultMasjid!.juma_jamat,
    );

    setState(() => _defaultMasjid = updated);

    // Save to SharedPreferences for HomeScreen access
    final prefs = await SharedPreferences.getInstance();
    await _syncTimingOverridesToMasjid(prefs, _defaultMasjid?.id);
    await prefs.setString('pref_${salah}_$type', newTime);

    // Reschedule this Salah's alarm if Master is ON
    if (_isMasterEnabled) {
      debugPrint('Time updated for $salah $type. Rescheduling...');
      await _rescheduleAlarmForSalah(salah);
    }
  }

  Future<void> _resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearTimingOverrides(prefs);
    if (_defaultMasjid?.id != null && _defaultMasjid!.id.isNotEmpty) {
      await prefs.setString(_prefOverridesMasjidIdKey, _defaultMasjid!.id);
    }
    if (!mounted) return;
    setState(() => _loading = true);
    await _loadDefaultMasjid();
  }

  Future<void> _clearTimingOverrides(SharedPreferences prefs) async {
    for (final key in _timingPreferenceKeys) {
      await prefs.remove(key);
    }
  }

  Future<void> _syncTimingOverridesToMasjid(
    SharedPreferences prefs,
    String? masjidId,
  ) async {
    if (masjidId == null || masjidId.isEmpty) return;

    final String? boundMasjidId = prefs.getString(_prefOverridesMasjidIdKey);
    if (boundMasjidId != null &&
        boundMasjidId.isNotEmpty &&
        boundMasjidId != masjidId) {
      await _clearTimingOverrides(prefs);
    }

    await prefs.setString(_prefOverridesMasjidIdKey, masjidId);
  }

  Widget _salahRow(String name, String? azan, String? jamat) {
    final bool isMaghrib = name == 'Maghrib';
    final bool isEditing = _isMasterEnabled;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      decoration: BoxDecoration(
        color: _isMasterEnabled ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: isEditing && !isMaghrib
            ? Border.all(color: Colors.green.withOpacity(0.5), width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Opacity(
          opacity: _isMasterEnabled ? 1.0 : 0.5,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isEditing && !isMaghrib
                              ? Colors.green.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getSalahIcon(name),
                          color: isEditing && !isMaghrib
                              ? Colors.green[700]
                              : Colors.grey[700],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    _timeItem(name, 'Azan', azan, isMaghrib),
                    Container(
                      width: 1,
                      height: 34,
                      color: Colors.grey.withOpacity(0.3),
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    _timeItem(name, 'Jamat', jamat, isMaghrib),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeItem(String salah, String type, String? time, bool isMaghrib) {
    final bool canEdit = _isMasterEnabled && !isMaghrib;
    final bool showLock = _isMasterEnabled && isMaghrib;

    final toggleKey = '${salah}_$type';
    final bool isToggled = _toggles[toggleKey] ?? false;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  type.toUpperCase(),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Transform.scale(
                  scale: 0.55,
                  child: Switch(
                    value: isToggled,
                    onChanged: _isMasterEnabled
                        ? (val) async {
                            setState(() => _toggles[toggleKey] = val);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool(toggleKey, val);

                            // Reschedule the entire Salah alarm
                            await _rescheduleAlarmForSalah(salah);
                          }
                        : null,
                    activeColor: Colors.green,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: canEdit
                  ? () async => await _pickTime(salah, type, time)
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTo12Hour(time),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _isMasterEnabled
                            ? Colors.black87
                            : Colors.grey.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (showLock)
                      const Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: Colors.grey,
                      )
                    else
                      AnimatedOpacity(
                        opacity: canEdit ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: Colors.green,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // NEW METHOD: Reschedule alarm for a specific Salah
  Future<void> _rescheduleAlarmForSalah(String salah) async {
    final baseSalahId = _getSalahId(salah);

    // If master toggle is off, just cancel the alarm and do nothing else.
    if (!_isMasterEnabled) {
      await NotificationService.instance.cancelAlarm(baseSalahId);
      return;
    }

    // My Times (Overrides)
    final myAzanTime = _getCurrentTime(salah, 'Azan');
    final myJamatTime = _getCurrentTime(salah, 'Jamat');

    // Masjid Times (Original)
    final masjidAzanTime = _getMasjidTime(salah, 'Azan');
    final masjidJamatTime = _getMasjidTime(salah, 'Jamat');

    final azanToggle = _toggles['${salah}_Azan'] ?? false;
    final jamatToggle = _toggles['${salah}_Jamat'] ?? false;

    debugPrint('🔄 Rescheduling $salah');

    await NotificationService.instance.scheduleSalahAlarm(
      id: baseSalahId,
      title: salah,
      body: 'It is time for $salah',
      masjidTime: masjidAzanTime,
      masjidJamatTime: masjidJamatTime,
      myTime: myAzanTime,
      myJamatTime: myJamatTime,
      isMyPrefsMode: true,
      endTime: _getEndTimeForSalah(salah, myAzanTime),
      azanEnabled: azanToggle,
      jamatEnabled: jamatToggle,
    );
  }

  String _formatTo12Hour(String? time24) {
    if (time24 == null || time24.isEmpty || !time24.contains(':')) {
      return '--:--';
    }
    try {
      final parts = time24.split(':');
      int h = int.parse(parts[0]);
      final m = parts[1];
      final period = h >= 12 ? 'PM' : 'AM';
      h = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h:$m $period';
    } catch (e) {
      return time24; // fallback to show the raw data
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Preferences'),
        actions: [
          Switch(value: _isMasterEnabled, onChanged: _onMasterToggleChanged),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _defaultMasjid == null
          ? const Center(child: Text('No default masjid selected'))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _defaultMasjid!.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (_isMasterEnabled)
                          ElevatedButton.icon(
                            onPressed: _resetToDefault,
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text('Reset Defaults'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              foregroundColor: Colors.red,
                              elevation: 0,
                            ),
                          ),
                      ],
                    ),
                    if (_canScheduleExact == false)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _exactAlarmCard(),
                      ),
                    const SizedBox(height: 8),
                    _salahRow(
                      'Fajr',
                      _defaultMasjid!.fajr_azan,
                      _defaultMasjid!.fajr_jamat,
                    ),
                    _salahRow(
                      'Dhuhr',
                      _defaultMasjid!.dhuhr_azan,
                      _defaultMasjid!.dhuhr_jamat,
                    ),
                    _salahRow(
                      'Asr',
                      _defaultMasjid!.asar_azan,
                      _defaultMasjid!.asar_jamat,
                    ),
                    _salahRow(
                      'Maghrib',
                      _defaultMasjid!.maghrib_azan,
                      _defaultMasjid!.maghrib_jamat,
                    ),
                    _salahRow(
                      'Isha',
                      _defaultMasjid!.isha_azan,
                      _defaultMasjid!.isha_jamat,
                    ),
                    _salahRow(
                      'Juma',
                      _defaultMasjid!.juma_azan,
                      _defaultMasjid!.juma_jamat,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _exactAlarmCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.alarm, color: Colors.orange, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Exact Alarms are Off',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Notifications may be delayed.',
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ElevatedButton(
                    onPressed: _checkingExact
                        ? null
                        : _requestExactAlarmPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: _checkingExact
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Enable'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSalahIcon(String name) {
    switch (name) {
      case 'Fajr':
        return Icons.wb_twilight;
      case 'Dhuhr':
        return Icons.wb_sunny;
      case 'Asr':
        return Icons.wb_cloudy;
      case 'Maghrib':
        return Icons.nights_stay_outlined;
      case 'Isha':
        return Icons.nights_stay;
      case 'Juma':
        return Icons.mosque;
      default:
        return Icons.access_time_filled;
    }
  }

  int _getSalahId(String name) {
    switch (name) {
      case 'Fajr':
        return 1;
      case 'Dhuhr':
        return 2;
      case 'Asr':
        return 3;
      case 'Maghrib':
        return 4;
      case 'Isha':
        return 5;
      case 'Juma':
        return 6;
      default:
        return 0;
    }
  }

  String _getMasjidTime(String salah, String type) {
    if (_rawMasjid == null) return '';
    switch (salah) {
      case 'Fajr':
        return type == 'Azan'
            ? _rawMasjid!.fajr_azan ?? ''
            : _rawMasjid!.fajr_jamat ?? '';
      case 'Dhuhr':
        return type == 'Azan'
            ? _rawMasjid!.dhuhr_azan ?? ''
            : _rawMasjid!.dhuhr_jamat ?? '';
      case 'Asr':
        return type == 'Azan'
            ? _rawMasjid!.asar_azan ?? ''
            : _rawMasjid!.asar_jamat ?? '';
      case 'Maghrib':
        return type == 'Azan'
            ? _rawMasjid!.maghrib_azan ?? ''
            : _rawMasjid!.maghrib_jamat ?? '';
      case 'Isha':
        return type == 'Azan'
            ? _rawMasjid!.isha_azan ?? ''
            : _rawMasjid!.isha_jamat ?? '';
      case 'Juma':
        return type == 'Azan'
            ? _rawMasjid!.juma_azan ?? ''
            : _rawMasjid!.juma_jamat ?? '';
      default:
        return '';
    }
  }

  Future<void> _onMasterToggleChanged(bool val) async {
    setState(() => _isMasterEnabled = val);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('master_alarm_enabled', val);

    if (val) {
      await _rescheduleAllAlarms();
    } else {
      await _cancelAllAlarms();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            val ? 'Notifications turned on' : 'Notifications turned off',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _rescheduleAllAlarms() async {
    final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Juma'];

    for (var salah in prayers) {
      await _rescheduleAlarmForSalah(salah);
    }
  }

  Future<void> _cancelAllAlarms() async {
    final prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Juma'];

    for (var salah in prayers) {
      await NotificationService.instance.cancelAlarm(_getSalahId(salah));
    }
    await NotificationService.instance.cancelAlarm(7); // Seher
    await NotificationService.instance.cancelAlarm(8); // Iftar
  }

  String _getCurrentTime(String salah, String type) {
    if (_defaultMasjid == null) return '';
    // Use the same logic as _getMasjidTime but on _defaultMasjid which has overrides
    switch (salah) {
      case 'Fajr':
        return type == 'Azan'
            ? _defaultMasjid!.fajr_azan ?? ''
            : _defaultMasjid!.fajr_jamat ?? '';
      case 'Dhuhr':
        return type == 'Azan'
            ? _defaultMasjid!.dhuhr_azan ?? ''
            : _defaultMasjid!.dhuhr_jamat ?? '';
      case 'Asr':
        return type == 'Azan'
            ? _defaultMasjid!.asar_azan ?? ''
            : _defaultMasjid!.asar_jamat ?? '';
      case 'Maghrib':
        return type == 'Azan'
            ? _defaultMasjid!.maghrib_azan ?? ''
            : _defaultMasjid!.maghrib_jamat ?? '';
      case 'Isha':
        return type == 'Azan'
            ? _defaultMasjid!.isha_azan ?? ''
            : _defaultMasjid!.isha_jamat ?? '';
      case 'Juma':
        return type == 'Azan'
            ? _defaultMasjid!.juma_azan ?? ''
            : _defaultMasjid!.juma_jamat ?? '';
      default:
        return '';
    }
  }

  DateTime _getEndTimeForSalah(String salah, String startTimeStr) {
    if (_allPrayers.isNotEmpty) {
      final prayer = _allPrayers.firstWhere(
        (p) => p.name == salah || (salah == 'Juma' && p.name == 'Dhuhr'),
        orElse: () => PrayerTimeData(
          name: '',
          startTime: DateTime.now(),
          endTime: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      if (prayer.name.isNotEmpty) {
        return prayer.endTime;
      }
    }

    // Fallback logic if calendar data isn't loaded yet
    final now = DateTime.now();
    DateTime start;
    try {
      final parts = startTimeStr.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1].split(' ')[0]);
      start = DateTime(now.year, now.month, now.day, h, m);
    } catch (_) {
      return now.add(const Duration(hours: 1));
    }
    return start.add(const Duration(minutes: 90));
  }
}
