import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/masjid.dart';
import '../../services/firebase_db.dart';
import '../../services/masjid_timing_cache.dart';
import '../../services/default_masjid_repository.dart';
import '../../services/village_timing_snapshot_repository.dart';
import '../../salah_calendar/salah_calendar_model.dart';
import '../../salah_calendar/salah_calendar_repository.dart';
import '../../salah_calendar/salah_database_helper.dart';

class MasjidDetailsScreen extends StatefulWidget {
  final Masjid masjid;

  const MasjidDetailsScreen({super.key, required this.masjid});

  @override
  State<MasjidDetailsScreen> createState() => _MasjidDetailsScreenState();
}

class _MasjidDetailsScreenState extends State<MasjidDetailsScreen> {
  String? _calendarMaghribTime;
  late Masjid _masjid;
  bool _isDefaultMasjid = false;
  final MasjidTimingCache _masjidTimingCache = MasjidTimingCache.instance;
  final DefaultMasjidRepository _defaultMasjidRepo =
      DefaultMasjidRepository.instance;
  final VillageTimingSnapshotRepository _villageSnapshotRepo =
      VillageTimingSnapshotRepository.instance;

  @override
  void initState() {
    super.initState();
    _masjid = widget.masjid;
    _loadCalendarMaghribTime();
    _loadLatestFromCache();
    _loadLatestFromSnapshotCache();
    _loadDefaultMasjidState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masjid Details'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1E3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0D8C7)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.schedule_rounded,
                      color: Colors.green,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Salah Timings',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A5C38),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _timingsList(),
          ],
        ),
      ),
    );
  }

  Future<void> _loadCalendarMaghribTime() async {
    try {
      final db = await SalahDatabaseHelper.instance.database;
      final repo = SalahCalendarRepository(db);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final SalahCalendarModel? row = await repo.getByDate(today);

      if (row != null && row.maghribAzan.isNotEmpty) {
        if (mounted) {
          setState(() {
            _calendarMaghribTime = row.maghribAzan;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading calendar maghrib time: $e');
    }
  }

  Future<void> _loadLatestFromCache() async {
    final String id = _masjid.id.trim();
    if (id.isEmpty) return;
    final cached = await _masjidTimingCache.getMasjidById(id);
    if (!mounted || cached == null) return;
    if (_hasTimingChanged(_masjid, cached)) {
      setState(() => _masjid = cached);
    }
  }

  Future<void> _loadLatestFromSnapshotCache() async {
    final String villageKey = (_masjid.village ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (villageKey.isEmpty) return;
    final cachedSnapshot = await _villageSnapshotRepo.getCachedSnapshot(
      villageKey,
    );
    if (!mounted || cachedSnapshot == null) return;
    final snapshotMasjids = cachedSnapshot.toMasjids();
    if (snapshotMasjids.isEmpty) return;
    final String id = _masjid.id.trim();
    if (id.isEmpty) return;
    final Masjid updated = snapshotMasjids.firstWhere(
      (m) => m.id.trim() == id,
      orElse: () => _masjid,
    );
    if (_hasTimingChanged(_masjid, updated)) {
      setState(() => _masjid = updated);
    }
  }

  Future<void> _launchMaps() async {
    final lat = _masjid.latitude;
    final lng = _masjid.longitude;
    if (lat == null || lng == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error launching maps: $e');
    }
  }

  Future<void> _setAsDefaultMasjid() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set as Home Masjid'),
        content: Text(
          'Do you want to set ${widget.masjid.name} as your Home masjid?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final String? mobile = prefs.getString('userMobile')?.trim();

        // Always update local default so the app changes immediately.
        final String villageKey = (_masjid.village ?? '')
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]'), '');
        await _masjidTimingCache.upsertMasjids(villageKey, [_masjid]);
        await _defaultMasjidRepo.persistDefaultMasjid(
          _masjid,
          setAsDefault: true,
        );

        // Update remote default only when userMobile is available.
        if (mobile != null && mobile.isNotEmpty) {
          await FirebaseDB.instance.setDefaultMasjid(mobile, _masjid.id);
        }

        if (mounted) {
          setState(() => _isDefaultMasjid = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Default masjid updated successfully!'),
            ),
          );
        }
      } catch (e) {
        debugPrint('Error setting default masjid: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Default masjid update failed: $e')),
          );
        }
      }
    }
  }

  Future<void> _loadDefaultMasjidState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? defaultId = prefs.getString('cached_default_masjid_id');
      if (!mounted) return;
      setState(() {
        _isDefaultMasjid =
            defaultId != null &&
            defaultId.isNotEmpty &&
            defaultId.trim() == _masjid.id.trim();
      });
    } catch (_) {
      // Best effort; keep toggle off if unable to read.
    }
  }

  // ---------------- HEADER ----------------

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mosque, size: 32, color: Colors.green),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _masjid.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _masjid.address ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _launchMaps,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions,
                    color: Colors.blue,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isDefaultMasjid ? Icons.star : Icons.star_border_rounded,
                  color: Colors.orange,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Change your Home masjid',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              Switch(
                value: _isDefaultMasjid,
                onChanged: (value) async {
                  if (value) {
                    await _setAsDefaultMasjid();
                    return;
                  }
                  if (_isDefaultMasjid && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Select another masjid to change default.',
                        ),
                      ),
                    );
                    setState(() => _isDefaultMasjid = true);
                  }
                },
                activeColor: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- TIMINGS GRID ----------------

  Widget _timingsList() {
    String? maghribJamatTime;
    if (_calendarMaghribTime != null) {
      final azanTime = _parseTime(_calendarMaghribTime);
      if (azanTime != null) {
        final jamatDateTime = azanTime.add(const Duration(minutes: 2));
        maghribJamatTime =
            '${jamatDateTime.hour}:${jamatDateTime.minute.toString().padLeft(2, '0')}';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8C7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            _timingsHeaderRow(),
            _timingsRow(
              'Fajr',
              azan: _format12Hour(_masjid.fajr_azan),
              jamat: _format12Hour(_masjid.fajr_jamat ?? _masjid.fajr),
            ),
            _timingsRow(
              'Dhuhr',
              azan: _format12Hour(_masjid.dhuhr_azan),
              jamat: _format12Hour(_masjid.dhuhr_jamat ?? _masjid.dhuhr),
            ),
            _timingsRow(
              'Asr',
              azan: _format12Hour(_masjid.asar_azan),
              jamat: _format12Hour(_masjid.asar_jamat ?? _masjid.asr),
            ),
            _timingsRow(
              'Maghrib',
              azan: _format12Hour(_calendarMaghribTime, forcePm: true),
              jamat: _format12Hour(
                maghribJamatTime ?? _calendarMaghribTime,
                forcePm: true,
              ),
            ),
            _timingsRow(
              'Isha',
              azan: _format12Hour(_masjid.isha_azan),
              jamat: _format12Hour(_masjid.isha_jamat ?? _masjid.isha),
            ),
            _timingsRow(
              'Juma',
              azan: _format12Hour(_masjid.juma_azan),
              jamat: _format12Hour(_masjid.juma_jamat ?? _masjid.juma),
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _timingsHeaderRow() {
    return Container(
      color: const Color(0xFF2E7D4F),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: const [
          Expanded(
            child: Text(
              'Namaz',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          Expanded(
            child: Text(
              'Azan',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          Expanded(
            child: Text(
              'Jamat',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timingsRow(
    String label, {
    String? azan,
    String? jamat,
    bool highlight = false,
  }) {
    final TextStyle labelStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: highlight ? Colors.green.shade800 : Colors.black87,
    );
    final TextStyle timeStyle = TextStyle(
      fontWeight: FontWeight.w600,
      color: highlight ? Colors.green.shade800 : Colors.black87,
    );

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFE4DEC9), width: 1),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: Text(
              (azan == null || azan.isEmpty) ? '-' : azan,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: timeStyle,
            ),
          ),
          Expanded(
            child: Text(
              (jamat == null || jamat.isEmpty) ? '-' : jamat,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: timeStyle,
            ),
          ),
        ],
      ),
    );
  }

  bool _hasTimingChanged(Masjid previous, Masjid next) {
    return previous.fajr_azan != next.fajr_azan ||
        previous.fajr_jamat != next.fajr_jamat ||
        previous.dhuhr_azan != next.dhuhr_azan ||
        previous.dhuhr_jamat != next.dhuhr_jamat ||
        previous.asar_azan != next.asar_azan ||
        previous.asar_jamat != next.asar_jamat ||
        previous.maghrib_azan != next.maghrib_azan ||
        previous.maghrib_jamat != next.maghrib_jamat ||
        previous.isha_azan != next.isha_azan ||
        previous.isha_jamat != next.isha_jamat ||
        previous.juma_azan != next.juma_azan ||
        previous.juma_jamat != next.juma_jamat;
  }

  // ---------------- TIME CARD ----------------

  Widget _timeCard(
    String label, {
    String? azan,
    String? jamat,
    String? badge,
    bool highlight = false,
  }) {
    IconData iconData;
    switch (label) {
      case 'Fajr':
        iconData = Icons.wb_twilight;
        break;
      case 'Dhuhr':
        iconData = Icons.wb_sunny;
        break;
      case 'Asr':
        iconData = Icons.wb_sunny_outlined;
        break;
      case 'Maghrib':
        iconData = Icons.nights_stay_outlined;
        break;
      case 'Isha':
        iconData = Icons.nights_stay;
        break;
      case 'Juma':
        iconData = Icons.mosque;
        break;
      default:
        iconData = Icons.access_time;
    }

    Color contentColor = highlight ? Colors.green.shade800 : Colors.black87;
    Color labelColor = highlight ? Colors.green.shade700 : Colors.grey.shade600;
    Color timeColor = highlight ? Colors.green.shade900 : Colors.black87;
    Color iconBg = highlight ? Colors.white : Colors.grey.shade100;

    return Container(
      decoration: BoxDecoration(
        color: highlight ? Colors.green.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? Colors.green.shade300 : Colors.grey.shade200,
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight
                ? Colors.green.withOpacity(0.1)
                : Colors.grey.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  iconData,
                  size: 18,
                  color: highlight ? Colors.green : Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: contentColor,
                ),
              ),
            ],
          ),
          if (badge != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: highlight
                    ? Colors.green.withOpacity(0.2)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: highlight
                      ? Colors.green.shade800
                      : Colors.orange.shade800,
                ),
              ),
            ),
          ] else
            const SizedBox(height: 2),
          const SizedBox(height: 2),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AZAN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        azan != null && azan.isNotEmpty ? azan : '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: timeColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
                VerticalDivider(
                  color: highlight
                      ? Colors.green.shade200
                      : Colors.grey.shade300,
                  thickness: 1,
                  width: 20,
                  indent: 4,
                  endIndent: 4,
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'JAMAT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: labelColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (jamat == null || jamat.isEmpty) ? '-' : jamat,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: timeColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- TIME FORMATTER ----------------

  String _format12Hour(String? time, {bool forcePm = false}) {
    if (time == null || time.isEmpty) return '';
    try {
      final t = time.trim();
      if (t.toLowerCase().contains('am') || t.toLowerCase().contains('pm')) {
        return t;
      }
      final parts = t.split(':');
      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

        if (forcePm && hour < 12) {
          hour += 12;
        }

        final period = hour >= 12 ? 'PM' : 'AM';
        if (hour > 12) hour -= 12;
        if (hour == 0) hour = 12;
        return '$hour:${minute.toString().padLeft(2, '0')} $period';
      }
    } catch (_) {}
    return time;
  }

  // ---------------- TIME PARSER ----------------

  DateTime? _parseTime(String? time) {
    try {
      if (time == null || time.isEmpty) return null;
      final t = time.trim();
      final parts = t.split(':');
      if (parts.length < 2) return null;

      final now = DateTime.now();
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

      if (t.toLowerCase().contains('pm') && hour < 12) {
        hour += 12;
      } else if (t.toLowerCase().contains('am') && hour == 12) {
        hour = 0;
      }

      return DateTime(now.year, now.month, now.day, hour, minute);
    } catch (_) {
      return null;
    }
  }
}
