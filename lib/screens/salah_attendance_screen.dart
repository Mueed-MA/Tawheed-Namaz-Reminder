import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../salah_calendar/salah_calendar_repository.dart';
import '../../salah_calendar/salah_database_helper.dart';

class SalahAttendanceScreen extends StatefulWidget {
  const SalahAttendanceScreen({super.key});

  @override
  State<SalahAttendanceScreen> createState() => _SalahAttendanceScreenState();
}

class _SalahAttendanceScreenState extends State<SalahAttendanceScreen> {
  static const String _trackingStartKey = 'attendance_tracking_start_date';
  static const String _installDateKey = 'app_install_date';
  DateTime _focusedDate = DateTime.now();
  Map<String, List<bool>> _attendanceCache = {};
  bool _isLoading = false;
  SharedPreferences? _prefs;
  String _statsFilter = 'Month';
  Map<String, int> _missedStats = {};
  int _totalPossibleSalahs = 0;
  DateTime? _trackingStartDate;

  final List<String> _salahs = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  List<DateTime> _todayPrayerStarts = [];
  List<DateTime> _todayPrayerEnds = [];

  @override
  void initState() {
    super.initState();
    _loadTodayPrayerTimes();
    _loadMonthData();
  }

  Future<void> _loadTodayPrayerTimes() async {
    try {
      final db = await SalahDatabaseHelper.instance.database;
      final repo = SalahCalendarRepository(db);
      final now = DateTime.now();
      final row = await repo.getByDate(DateTime(now.year, now.month, now.day));

      if (row != null) {
        DateTime parse(String t) {
          if (t.isEmpty) return now;
          final parts = t.split(':');
          final h = int.parse(parts[0]);
          final m = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));
          return DateTime(now.year, now.month, now.day, h, m);
        }

        DateTime toPm(DateTime d) =>
            d.hour < 12 ? d.add(const Duration(hours: 12)) : d;

        var f = parse(row.fajrAzan);
        var d = parse(row.dhuhrAzan);
        if (d.hour < 11) d = toPm(d);
        var a = parse(row.asrAzan);
        if (a.hour < 12) a = toPm(a);
        var m = parse(row.maghribAzan);
        if (m.hour < 12) m = toPm(m);
        var i = parse(row.ishaAzan);
        if (i.hour < 12) {
          if (i.hour > 4) {
            i = toPm(i);
          }
        }

        DateTime fEnd = parse(row.sunrise);
        if (!fEnd.isAfter(f)) {
          fEnd = f.add(const Duration(minutes: 90));
        }
        final dEnd = a.subtract(const Duration(minutes: 5));
        final aEnd = m.subtract(const Duration(minutes: 5));
        final mEnd = i.subtract(const Duration(minutes: 5));
        final iEnd = DateTime(
          now.year,
          now.month,
          now.day + 1,
          f.hour,
          f.minute,
        ).subtract(const Duration(minutes: 5));

        if (mounted) {
          setState(() {
            _todayPrayerStarts = [f, d, a, m, i];
            _todayPrayerEnds = [fEnd, dEnd, aEnd, mEnd, iEnd];
          });
          _updateStats();
        }
      }
    } catch (e) {
      debugPrint('Error loading today stats times: $e');
    }
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  Future<void> _loadMonthData() async {
    setState(() => _isLoading = true);
    _prefs ??= await SharedPreferences.getInstance();
    await _ensureTrackingStartDate();

    final Map<String, List<bool>> newData = {};

    // Calculate days in current focused month
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedDate.year,
      _focusedDate.month,
    );

    for (int i = 1; i <= daysInMonth; i++) {
      final d = DateTime(_focusedDate.year, _focusedDate.month, i);
      newData[_dateKey(d)] = _getDailyAttendance(d);
    }

    if (mounted) {
      setState(() {
        _attendanceCache = newData;
        _isLoading = false;
      });
      _updateStats();
    }
  }

  Future<void> _ensureTrackingStartDate() async {
    if (_prefs == null) return;
    if (_trackingStartDate != null) return;

    final String? installStored = _prefs!.getString(_installDateKey);
    if (installStored != null && installStored.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(installStored);
      if (parsed != null) {
        _trackingStartDate = DateUtils.dateOnly(parsed);
        await _prefs!.setString(
          _trackingStartKey,
          DateFormat('yyyy-MM-dd').format(_trackingStartDate!),
        );
        return;
      }
    }

    final String? stored = _prefs!.getString(_trackingStartKey);
    if (stored != null && stored.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(stored);
      if (parsed != null) {
        _trackingStartDate = DateUtils.dateOnly(parsed);
        return;
      }
    }

    DateTime start = DateUtils.dateOnly(DateTime.now());
    final RegExp datePrefix = RegExp(r'^attendance_(\d{4}-\d{2}-\d{2})');
    for (final key in _prefs!.getKeys()) {
      final match = datePrefix.firstMatch(key);
      if (match == null) continue;
      final String? datePart = match.group(1);
      if (datePart == null) continue;
      final DateTime? parsed = DateTime.tryParse(datePart);
      if (parsed == null) continue;
      final DateTime only = DateUtils.dateOnly(parsed);
      if (only.isBefore(start)) {
        start = only;
      }
    }

    _trackingStartDate = start;
    await _prefs!.setString(
      _trackingStartKey,
      DateFormat('yyyy-MM-dd').format(start),
    );
  }

  bool _isFutureDate(DateTime date) {
    return DateUtils.dateOnly(date).isAfter(DateUtils.dateOnly(DateTime.now()));
  }

  bool _canMarkPrayerForDate(DateTime date, int prayerIndex) {
    final DateTime now = DateTime.now();
    final bool isToday = DateUtils.isSameDay(date, now);
    if (_isFutureDate(date)) return false;
    if (_isBeforeTrackingStart(date)) return false;
    if (!isToday) return true;
    if (_todayPrayerStarts.isEmpty ||
        prayerIndex >= _todayPrayerStarts.length) {
      return true;
    }
    return !now.isBefore(_todayPrayerStarts[prayerIndex]);
  }

  bool _isPrayerWindowCompletedForDate(DateTime date, int prayerIndex) {
    final DateTime now = DateTime.now();
    final bool isToday = DateUtils.isSameDay(date, now);
    if (!isToday) return date.isBefore(now);
    if (_todayPrayerEnds.isEmpty || prayerIndex >= _todayPrayerEnds.length) {
      return false;
    }
    return !now.isBefore(_todayPrayerEnds[prayerIndex]);
  }

  bool _isBeforeTrackingStart(DateTime date) {
    if (_trackingStartDate == null) return false;
    return DateUtils.dateOnly(date).isBefore(_trackingStartDate!);
  }

  bool _shouldShiftIshaToYesterday(DateTime date) {
    final DateTime now = DateTime.now();
    if (!DateUtils.isSameDay(date, now)) return false;
    if (_todayPrayerStarts.isEmpty) return false;
    return now.isBefore(_todayPrayerStarts[0]);
  }

  Future<void> _setSinglePrayerAttendance({
    required DateTime date,
    required int prayerIndex,
    required bool isPresent,
    required SharedPreferences prefs,
  }) async {
    if (prayerIndex < 0 || prayerIndex >= _salahs.length) return;
    _prefs ??= prefs;

    final String key = _dateKey(date);
    final List<bool> current = _getDailyAttendance(date);
    current[prayerIndex] = isPresent;

    final str = current.map((e) => e ? '1' : '0').join(',');
    await prefs.setString('attendance_$key', str);

    final name = _salahs[prayerIndex];
    if (!isPresent) {
      await prefs.remove('attendance_${key}_$name');
      await prefs.remove('attendance_${key}_$name Azan');
      await prefs.remove('attendance_${key}_$name Jamat');
    } else {
      await prefs.setString('attendance_${key}_$name', 'present');
    }

    if (mounted) {
      setState(() {
        _attendanceCache[key] = current;
      });
    }
  }

  Future<void> _persistAttendanceForDate({
    required DateTime date,
    required List<bool> attendance,
    required SharedPreferences prefs,
  }) async {
    final key = _dateKey(date);
    final str = attendance.map((e) => e ? '1' : '0').join(',');
    await prefs.setString('attendance_$key', str);

    // Sync individual keys to match manual edits
    final prayerNames = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    for (int i = 0; i < prayerNames.length; i++) {
      final name = prayerNames[i];
      if (!attendance[i]) {
        // If marked as missed, remove any 'accepted' status from individual keys
        await prefs.remove('attendance_${key}_$name');
        await prefs.remove('attendance_${key}_$name Azan');
        await prefs.remove('attendance_${key}_$name Jamat');
        if (name == 'Dhuhr') {
          await prefs.remove('attendance_${key}_Juma');
          await prefs.remove('attendance_${key}_Juma Azan');
          await prefs.remove('attendance_${key}_Juma Jamat');
        }
      } else {
        // If marked as present, ensure individual key reflects it (for SalahTable)
        await prefs.setString('attendance_${key}_$name', 'present');
      }
    }

    if (mounted) {
      setState(() {
        _attendanceCache[key] = attendance;
      });
    }
  }

  String? _normalizeAttendanceStatus(String? raw) {
    if (raw == null) return null;
    final String v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'accepted' || v == 'present') return 'accepted';
    if (v == 'declined' || v == 'decline' || v == 'rejected') return 'declined';
    if (v == 'missed' || v == 'absent') return 'missed';
    return v;
  }

  String? _resolveAttendanceStatus(List<String?> candidates) {
    final normalized = candidates
        .map(_normalizeAttendanceStatus)
        .whereType<String>()
        .toList();
    if (normalized.isEmpty) return null;
    if (normalized.contains('declined')) return 'declined';
    if (normalized.contains('accepted')) return 'accepted';
    if (normalized.contains('missed')) return 'missed';
    return normalized.first;
  }

  List<String?> _getDailyAttendanceStatuses(DateTime date) {
    if (_prefs == null) return List<String?>.filled(5, null);

    final dateKey = _dateKey(date);
    final prayerNames = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final bool isFriday = date.weekday == DateTime.friday;
    final List<String?> statuses = List<String?>.filled(5, null);

    for (int i = 0; i < prayerNames.length; i++) {
      final name = prayerNames[i];
      final List<String?> candidates = <String?>[
        _prefs!.getString('attendance_${dateKey}_$name'),
        _prefs!.getString('attendance_${dateKey}_$name Azan'),
        _prefs!.getString('attendance_${dateKey}_$name Jamat'),
      ];

      // Keep Dhuhr/Juma status in sync on Friday.
      if (isFriday && name == 'Dhuhr') {
        candidates.addAll(<String?>[
          _prefs!.getString('attendance_${dateKey}_Juma'),
          _prefs!.getString('attendance_${dateKey}_Juma Azan'),
          _prefs!.getString('attendance_${dateKey}_Juma Jamat'),
        ]);
      }

      statuses[i] = _resolveAttendanceStatus(candidates);
    }

    return statuses;
  }

  List<bool> _getDailyAttendance(DateTime date) {
    if (_prefs == null) return List.filled(5, false);

    final dateKey = _dateKey(date);
    final csvKey = 'attendance_$dateKey';

    // 1. Start with CSV data
    final stored = _prefs!.getString(csvKey);
    List<bool> status = List.filled(5, false);

    if (stored != null) {
      final parts = stored.split(',');
      for (int i = 0; i < parts.length && i < 5; i++) {
        status[i] = parts[i] == '1';
      }
    }

    // 2. Merge individual keys (Alarm integration)
    final prayerNames = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    for (int i = 0; i < prayerNames.length; i++) {
      final name = prayerNames[i];
      // Check base name and suffixes
      String? val = _prefs!.getString('attendance_${dateKey}_$name');
      val ??= _prefs!.getString('attendance_${dateKey}_$name Azan');
      val ??= _prefs!.getString('attendance_${dateKey}_$name Jamat');

      if (name == 'Dhuhr') {
        String? jVal = _prefs!.getString('attendance_${dateKey}_Juma');
        jVal ??= _prefs!.getString('attendance_${dateKey}_Juma Azan');
        jVal ??= _prefs!.getString('attendance_${dateKey}_Juma Jamat');
        if (jVal == 'accepted' || jVal == 'present') val = jVal;
      }

      if (val == 'accepted' || val == 'present') {
        status[i] = true;
      }
    }
    return status;
  }

  void _updateStats() {
    if (_prefs == null || _trackingStartDate == null) return;

    DateTime now = DateTime.now();
    DateTime start, end;

    if (_statsFilter == 'Today') {
      start = now;
      end = now;
    } else if (_statsFilter == 'Week') {
      // Current week (Monday start)
      int weekday = now.weekday;
      start = now.subtract(Duration(days: weekday - 1));
      end = start.add(const Duration(days: 6));
    } else if (_statsFilter == 'Month') {
      // Visible month
      start = DateTime(_focusedDate.year, _focusedDate.month, 1);
      int days = DateUtils.getDaysInMonth(
        _focusedDate.year,
        _focusedDate.month,
      );
      end = DateTime(_focusedDate.year, _focusedDate.month, days);
    } else {
      // Visible year
      start = DateTime(_focusedDate.year, 1, 1);
      end = DateTime(_focusedDate.year, 12, 31);
    }

    Map<String, int> missedCounts = {for (var s in _salahs) s: 0};
    int possibleSalahs = 0;

    int daysDiff = end.difference(start).inDays;
    for (int i = 0; i <= daysDiff; i++) {
      DateTime d = start.add(Duration(days: i));
      if (d.isAfter(now)) continue;
      if (_isBeforeTrackingStart(d)) continue;

      List<bool> flags = _getDailyAttendance(d);
      final bool isToday = DateUtils.isSameDay(d, now);

      for (int j = 0; j < _salahs.length; j++) {
        // For today, do not count as possible/missed until the prayer window is over.
        if (isToday && !_isPrayerWindowCompletedForDate(d, j)) {
          continue;
        }

        possibleSalahs++;
        if (j < flags.length && !flags[j]) {
          missedCounts[_salahs[j]] = (missedCounts[_salahs[j]] ?? 0) + 1;
        }
      }
    }

    setState(() {
      _missedStats = missedCounts;
      _totalPossibleSalahs = possibleSalahs;
    });
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedDate = DateTime(_focusedDate.year, _focusedDate.month + offset);
    });
    _loadMonthData();
  }

  Future<void> _showAttendanceDialog(DateTime date) async {
    if (_isBeforeTrackingStart(date)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _trackingStartDate == null
                ? 'Attendance is not available yet.'
                : 'Attendance is available from ${DateFormat('d MMM yyyy').format(_trackingStartDate!)}.',
          ),
        ),
      );
      return;
    }
    if (_isFutureDate(date)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Future dates cannot be marked.')),
      );
      return;
    }

    final key = _dateKey(date);
    // Create a copy so we don't mutate state directly until saved
    List<bool> current = List.from(
      _attendanceCache[key] ?? List.filled(5, false),
    );
    final List<String?> dailyStatuses = _getDailyAttendanceStatuses(date);
    for (int i = 0; i < current.length; i++) {
      if (!_canMarkPrayerForDate(date, i)) {
        current[i] = false;
      }
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(DateFormat('EEE, MMM d').format(date)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_salahs.length, (index) {
                  final bool canMark = _canMarkPrayerForDate(date, index);
                  final bool windowCompleted = _isPrayerWindowCompletedForDate(
                    date,
                    index,
                  );
                  final String? status = _normalizeAttendanceStatus(
                    dailyStatuses[index],
                  );
                  final bool showAccepted =
                      current[index] || status == 'accepted';
                  final bool showDeclined =
                      !showAccepted && status == 'declined';
                  final bool showMissedByWindow =
                      !showAccepted && !showDeclined && windowCompleted;
                  final Color borderColor = showDeclined
                      ? Colors.red
                      : (showMissedByWindow
                            ? Colors.red
                            : (showAccepted
                                  ? Colors.green
                                  : Colors.grey.shade500));
                  final Color fillColor = showDeclined
                      ? Colors.red.shade50
                      : (showMissedByWindow
                            ? Colors.red.shade50
                            : (showAccepted
                                  ? Colors.green.shade50
                                  : Colors.transparent));
                  final Widget? mark = showDeclined
                      ? const Icon(Icons.close, color: Colors.red, size: 20)
                      : (showMissedByWindow
                            ? const Icon(
                                Icons.close,
                                color: Colors.red,
                                size: 20,
                              )
                            : (showAccepted
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                      size: 20,
                                    )
                                  : null));

                  void markPresent() {
                    if (!canMark) return;
                    setStateDialog(() {
                      current[index] = true;
                    });
                  }

                  return ListTile(
                    onTap: markPresent,
                    dense: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    minLeadingWidth: 30,
                    leading: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: markPresent,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: fillColor,
                          border: Border.all(color: borderColor, width: 2.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: mark == null ? null : Center(child: mark),
                      ),
                    ),
                    title: Text(
                      _salahs[index],
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: canMark
                        ? null
                        : const Text(
                            'Available after salah time starts',
                            style: TextStyle(fontSize: 13),
                          ),
                  );
                }),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    await _saveAttendance(date, current);
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveAttendance(DateTime date, List<bool> attendance) async {
    if (_isBeforeTrackingStart(date)) return;
    if (_isFutureDate(date)) return;
    for (int i = 0; i < attendance.length; i++) {
      if (!_canMarkPrayerForDate(date, i)) {
        attendance[i] = false;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    _prefs ??= prefs;

    final bool shiftIsha =
        _shouldShiftIshaToYesterday(date) && attendance.length > 4
        ? attendance[4]
        : false;

    if (shiftIsha) {
      final List<bool> todayAttendance = List<bool>.from(attendance);
      todayAttendance[4] = false;
      await _persistAttendanceForDate(
        date: date,
        attendance: todayAttendance,
        prefs: prefs,
      );

      final DateTime prevDate = DateUtils.dateOnly(
        date.subtract(const Duration(days: 1)),
      );
      await _setSinglePrayerAttendance(
        date: prevDate,
        prayerIndex: 4,
        isPresent: true,
        prefs: prefs,
      );
    } else {
      await _persistAttendanceForDate(
        date: date,
        attendance: attendance,
        prefs: prefs,
      );
    }

    _updateStats();
  }

  Color _getAttendanceColor(int count) {
    if (count == 5) return Colors.green;
    if (count >= 3) return Colors.orange;
    if (count > 0) return Colors.red;
    if (count == 0) return Colors.red;
    return Colors.transparent;
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
      default:
        return Icons.access_time;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Salah Attendance'),
        backgroundColor: Colors.green[700],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                if (details.primaryVelocity! < 0) {
                  // Swipe Left -> Next Month
                  _changeMonth(1);
                } else if (details.primaryVelocity! > 0) {
                  // Swipe Right -> Previous Month
                  _changeMonth(-1);
                }
              },
              child: Column(
                children: [
                  _buildHeader(),
                  _buildDaysOfWeek(),
                  _isLoading
                      ? const SizedBox(
                          height: 350,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _buildCalendarGrid(),
                ],
              ),
            ),
            _buildStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final String gregorianMonth = DateFormat('MMMM yyyy').format(_focusedDate);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gregorianMonth,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDaysOfWeek() {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: days
            .map(
              (d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedDate.year,
      _focusedDate.month,
    );
    final firstDayOfMonth = DateTime(_focusedDate.year, _focusedDate.month, 1);
    final weekdayOffset =
        firstDayOfMonth.weekday %
        7; // Sunday is 7 in DateTime, usually we want 0 for Sun or adjust accordingly.
    // DateTime.weekday returns 1 for Mon, 7 for Sun.
    // If our grid starts on Sunday (0), then offset is (weekday % 7).

    final totalCells = daysInMonth + weekdayOffset;

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 0.85,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        if (index < weekdayOffset) {
          return const SizedBox();
        }
        final day = index - weekdayOffset + 1;
        final date = DateTime(_focusedDate.year, _focusedDate.month, day);
        return _buildDayCell(date);
      },
    );
  }

  Widget _buildDayCell(DateTime date) {
    final key = _dateKey(date);
    final attendance = _attendanceCache[key] ?? List.filled(5, false);
    final count = attendance.where((e) => e).length;
    final isToday = DateUtils.isSameDay(date, DateTime.now());
    final statusColor = _getAttendanceColor(count);
    final isFuture = _isFutureDate(date);
    final isBeforeStart = _isBeforeTrackingStart(date);
    final bool showIndicator = !isFuture && !isBeforeStart;

    return Padding(
      padding: const EdgeInsets.all(0.5),
      child: Material(
        color: showIndicator && count > 0
            ? statusColor.withOpacity(0.2)
            : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: isToday
              ? const BorderSide(color: Colors.green, width: 2)
              : BorderSide(color: Colors.grey.shade300),
        ),
        child: InkWell(
          onTap: (!isFuture && !isBeforeStart)
              ? () => _showAttendanceDialog(date)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${date.day}',
                style: TextStyle(
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: Colors.black,
                  fontSize: 12,
                ),
              ),
              if (showIndicator)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 0.5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count/5',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    final totalMissed = _missedStats.values.fold(
      0,
      (sum, count) => sum + count,
    );
    return GestureDetector(
      behavior:
          HitTestBehavior.opaque, // Ensures gesture is detected on container
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        const filters = ['Today', 'Week', 'Month', 'Year'];
        final currentIndex = filters.indexOf(_statsFilter);

        if (details.primaryVelocity! < 0) {
          // Swipe Left
          final nextIndex = (currentIndex + 1) % filters.length;
          setState(() {
            _statsFilter = filters[nextIndex];
            _updateStats();
          });
        } else if (details.primaryVelocity! > 0) {
          // Swipe Right
          final prevIndex =
              (currentIndex - 1 + filters.length) % filters.length;
          setState(() {
            _statsFilter = filters[prevIndex];
            _updateStats();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, -4),
            ),
          ],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Section
            Column(
              children: [
                const Text(
                  'Salah Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _totalPossibleSalahs > 0
                      ? Text(
                          totalMissed == 0
                              ? 'Perfect!- No pending Namazes'
                              : '$totalMissed missed in this $_statsFilter',
                          key: ValueKey<String>(
                            'summary_text_$_statsFilter$_totalPossibleSalahs',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: totalMissed == 0
                                ? Colors.green
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        )
                      : Text(
                          'No data for this period',
                          key: const ValueKey<String>('no_data'),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Section
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: ['Today', 'Week', 'Month', 'Year'].map((filter) {
                  final isSelected = _statsFilter == filter;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        setState(() => _statsFilter = filter);
                        _updateStats();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.black87
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Stats Cards
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Row(
                key: ValueKey<String>(_statsFilter),
                children: _salahs.map((salah) {
                  final count = _missedStats[salah] ?? 0;
                  final isMissed = count > 0;
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isMissed
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isMissed
                              ? Colors.red.shade100
                              : Colors.green.shade100,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            _getSalahIcon(salah),
                            size: 20,
                            color: isMissed
                                ? Colors.red[700]
                                : Colors.green[700],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            salah.substring(0, 3),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMissed
                                  ? Colors.red[700]
                                  : Colors.green[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isMissed
                                  ? Colors.red[900]
                                  : Colors.green[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
