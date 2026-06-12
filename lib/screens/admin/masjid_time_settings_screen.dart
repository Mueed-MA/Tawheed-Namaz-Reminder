import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/firebase_db.dart';
import '../../services/masjid_timing_cache.dart';
import '../../services/default_masjid_repository.dart';
import '../../services/location_service.dart';
import '../auth/auth_screen.dart';

class MasjidTimeSettingsScreen extends StatefulWidget {
  final String ownerMobile;
  final String? masjidId;

  const MasjidTimeSettingsScreen({
    Key? key,
    required this.ownerMobile,
    this.masjidId,
  })
    : super(key: key);

  @override
  State<MasjidTimeSettingsScreen> createState() =>
      _MasjidTimeSettingsScreenState();
}

class _MasjidTimeSettingsScreenState extends State<MasjidTimeSettingsScreen> {
  final MasjidTimingCache _masjidTimingCache = MasjidTimingCache.instance;
  final DefaultMasjidRepository _defaultMasjidRepo =
      DefaultMasjidRepository.instance;
  final Map<String, TimeOfDay?> _azanTimes = {};
  final Map<String, TimeOfDay?> _jamatTimes = {};
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  final List<String> _salahs = [
    'fajr',
    'dhuhr',
    'asar',
    'isha',
    'juma',
  ]; // Maghrib removed

  bool _saving = false;
  bool _locationLoading = false;
  String? _masjidName; // NEW

  @override
  void initState() {
    super.initState();

    for (var s in _salahs) {
      _azanTimes[s] = null;
      _jamatTimes[s] = null;
    }

    _loadMasjidData(); // LOAD DATA
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  String _coordToString(dynamic value) {
    if (value == null) return '';
    if (value is double) return value.toStringAsFixed(6);
    if (value is int) return value.toDouble().toStringAsFixed(6);
    if (value is String) return value.trim();
    return '';
  }

  Future<void> _getLocationForMasjid() async {
    if (_locationLoading) return;
    setState(() => _locationLoading = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location captured successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  Future<void> _updateLocationOnly() async {
    if (_locationLoading) return;
    final String latText = _latitudeController.text.trim();
    final String lngText = _longitudeController.text.trim();
    final double? latitude = double.tryParse(latText);
    final double? longitude = double.tryParse(lngText);
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid latitude and longitude')),
      );
      return;
    }

    setState(() => _locationLoading = true);
    try {
      final String id = (widget.masjidId ?? '').trim();
      if (id.isNotEmpty) {
        await FirebaseDB.instance.updateMasjidLocationById(
          masjidId: id,
          latitude: latitude,
          longitude: longitude,
        );
      } else {
        await FirebaseDB.instance.updateMasjidLocation(
          ownerMobile: widget.ownerMobile,
          latitude: latitude,
          longitude: longitude,
        );
      }
      await _updateLocalMasjidCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location updated successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location update failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }


  // ================= LOAD MASJID DATA =================
  Future<void> _loadMasjidData() async {
    final String id = (widget.masjidId ?? '').trim();
    final masjid =
        id.isNotEmpty
            ? await FirebaseDB.instance.getMasjidDetailsById(id)
            : await FirebaseDB.instance.getMasjidDetails(
                widget.ownerMobile,
              );

    if (masjid != null && mounted) {
      setState(() {
        _masjidName = masjid['name'];
        _latitudeController.text = _coordToString(masjid['latitude']);
        _longitudeController.text = _coordToString(masjid['longitude']);

        // Populate existing times
        for (var s in _salahs) {
          _azanTimes[s] =
              _parseTime(masjid['${s}_azan']) ??
              _parseTime(masjid['${s[0].toUpperCase()}${s.substring(1)}_azan']);
          _jamatTimes[s] =
              _parseTime(masjid['${s}_jamat']) ??
              _parseTime(
                masjid['${s[0].toUpperCase()}${s.substring(1)}_jamat'],
              );
        }
      });
    }
  }

  // Helper to parse "5:30" (12-hour format)
  TimeOfDay? _parseTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length != 2) return null;

      int hour = int.parse(parts[0]);
      // Remove any non-digit characters (like legacy AM/PM) just in case
      int minute = int.parse(parts[1].replaceAll(RegExp(r'[^0-9]'), ''));

      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickTime(String salah, bool isAzan) async {
    final initial = isAzan ? _azanTimes[salah] : _jamatTimes[salah];

    final picked = await showTimePicker(
      context: context,
      initialTime: initial ?? TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (picked == null || !mounted) return;

    setState(() {
      if (isAzan) {
        _azanTimes[salah] = picked;
      } else {
        _jamatTimes[salah] = picked;
      }
    });
  }

  String _formatForDb(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  String _formatDisplay(TimeOfDay time) {
    int h = time.hour;
    if (h == 0)
      h = 12;
    else if (h > 12)
      h -= 12;
    final hour = h.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return "$hour:$minute";
  }

  String? _validate() {
    for (var s in _salahs) {
      if (_azanTimes[s] == null || _jamatTimes[s] == null) {
        return "Please set both Azan and Jamat times for ${s.toUpperCase()}";
      }

      final a = _azanTimes[s]!;
      final j = _jamatTimes[s]!;

      final aMin = a.hour * 60 + a.minute;
      final jMin = j.hour * 60 + j.minute;

      if (s != 'isha' && jMin < aMin) {
        return "Jamat time cannot be before Azan time for ${s.toUpperCase()}";
      }
    }
    return null;
  }
  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    final String latText = _latitudeController.text.trim();
    final String lngText = _longitudeController.text.trim();
    double? latitude;
    double? longitude;
    if (latText.isNotEmpty || lngText.isNotEmpty) {
      latitude = double.tryParse(latText);
      longitude = double.tryParse(lngText);
      if (latitude == null || longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter valid latitude and longitude'),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    final Map<String, dynamic> timings = {};

    for (var s in _salahs) {
      timings['${s}_azan'] = _formatForDb(_azanTimes[s]!);
      timings['${s}_jamat'] = _formatForDb(_jamatTimes[s]!);
    }

    try {
      final String id = (widget.masjidId ?? '').trim();
      if (id.isNotEmpty) {
        debugPrint('Admin submit: updating timings for masjidId=$id');
        await FirebaseDB.instance.updateMasjidTimingsById(id, timings);
        if (latitude != null && longitude != null) {
          await FirebaseDB.instance.updateMasjidLocationById(
            masjidId: id,
            latitude: latitude,
            longitude: longitude,
          );
        }
      } else {
        debugPrint(
          'Admin submit: updating timings for owner=${widget.ownerMobile}',
        );
        await FirebaseDB.instance.updateMasjidTimings(
          widget.ownerMobile,
          timings,
        );
        if (latitude != null && longitude != null) {
          await FirebaseDB.instance.updateMasjidLocation(
            ownerMobile: widget.ownerMobile,
            latitude: latitude,
            longitude: longitude,
          );
        }
      }
      debugPrint('Admin submit: Firestore update completed');
      await _updateLocalMasjidCache();
      debugPrint('Admin submit: local cache update completed');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: ${e.code}')),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submit failed: $e')),
      );
      return;
    }

    // final db = await FirebaseDB.instance.database;
    // await db.update(
    //   'masjids',
    //   {'isTimingConfigured': 1},
    //   where: 'ownerMobile = ?',
    //   whereArgs: [widget.ownerMobile],
    // );

    if (!mounted) return;

    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Salah timings saved successfully')),
    );
  }

  Future<void> _updateLocalMasjidCache() async {
    try {
      final String id = (widget.masjidId ?? '').trim();
      if (id.isNotEmpty) {
        final masjid = await FirebaseDB.instance.getMasjidById(id);
        if (masjid != null) {
          final String villageKey = (masjid.village ?? '')
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          await _masjidTimingCache.upsertMasjids(villageKey, [masjid]);
        }
      } else {
        final updatedMasjids = await FirebaseDB.instance.getMasjidsByOwner(
          widget.ownerMobile,
        );
        for (final masjid in updatedMasjids) {
          final String villageKey = (masjid.village ?? '')
              .trim()
              .toLowerCase()
              .replaceAll(RegExp(r'[^a-z0-9]'), '');
          await _masjidTimingCache.upsertMasjids(villageKey, [masjid]);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cached_default_masjid_updated_ms');
      await _defaultMasjidRepo.markRefreshRequired();
    } catch (_) {}
  }

  Widget _timeButton(String label, TimeOfDay? time, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      child: Text(time == null ? label : _formatDisplay(time)),
    );
  }

  Widget _headerRow() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: const [
            Expanded(
              child: Text(
                'Namaz',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Text(
                'Azan',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Text(
                'Jamat',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String salah) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                salah.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _timeButton(
                  'Azan',
                  _azanTimes[salah],
                  () => _pickTime(salah, true),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _timeButton(
                  'Jamat',
                  _jamatTimes[salah],
                  () => _pickTime(salah, false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set Salah Times'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmLogout(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            children: [
              // ================= MASJID NAME =================
              if (_masjidName != null)
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text(
                          'Masjid Name',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _masjidName!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),
              Card(
                child: ExpansionTile(
                  title: const Text('Edit Masjid Location'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _latitudeController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Latitude',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _longitudeController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Longitude',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _locationLoading
                                    ? null
                                    : _getLocationForMasjid,
                                icon: const Icon(Icons.my_location),
                                label: Text(
                                  _locationLoading
                                      ? 'Getting Location...'
                                      : 'Get Location',
                                ),
                              ),
                              const Spacer(),
                              ElevatedButton(
                                onPressed: _locationLoading
                                    ? null
                                    : _updateLocationOnly,
                                child: _locationLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Update Location'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              _headerRow(),
              ..._salahs.map(_row),

              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('SUBMIT'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userMobile');
    await prefs.remove('userRole');
    await prefs.remove('adminUsernameLower');
    await prefs.remove('masjidId');
    await prefs.remove('cached_default_masjid_id');
    await prefs.remove('cached_default_masjid_updated_ms');
    await prefs.remove('__default_masjid_refresh_required__');
    await MasjidTimingCache.instance.clearAll();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

}

