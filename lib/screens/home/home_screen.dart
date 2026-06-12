import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../masjid/nearby_masjids_screen.dart';
import '../registered_masjids_screen.dart';
import '../qibla/qibla_screen.dart';
import '../admin/super_admin_approval_screen.dart';
import '../admin/masjid_time_settings_screen.dart';
import '../my_preferences_screen.dart';
import '../salah_attendance_screen.dart';
import 'contact_us_screen.dart';
import 'upcoming_jamat_screen.dart';
import 'rakats_screen.dart';
import 'zikr_screen.dart';
import 'dua_screen.dart';
import 'asset_pdf_viewer_screen.dart';

import '../../services/firebase_db.dart';
import '../../models/masjid.dart';
import '../../models/prayer_time_data.dart';
import '../../services/notification_service.dart';
import '../../services/masjid_timing_cache.dart';
import '../../services/default_masjid_repository.dart';
import '../../services/village_timing_snapshot_repository.dart';

import '../../salah_calendar/salah_calendar_model.dart';
import '../../salah_calendar/salah_calendar_repository.dart';
import '../../salah_calendar/salah_database_helper.dart';

import '../../widgets/salah_table.dart';
import '../auth/auth_screen.dart';
import '../../services/masjid_timing_cache.dart';

// ─── Design Tokens ───────────────────────────────────────────────────────────
class _AppColors {
  static const Color primary = Color(0xFF1A5C38);
  static const Color primaryLight = Color(0xFF2E7D4F);
  static const Color primarySurface = Color(0xFFF0F7F3);
  static const Color gold = Color(0xFFB8963E);
  static const Color goldLight = Color(0xFFFDF6E7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F7F5);
  static const Color textPrimary = Color(0xFF1A2B22);
  static const Color textSecondary = Color(0xFF6B7C73);
  static const Color divider = Color(0xFFE8EDE9);
  static const Color danger = Color(0xFFCC4444);
  static const Color dangerSurface = Color(0xFFFFF0F0);
}

class HomeScreen extends StatefulWidget {
  final String userMobile;
  final String role;

  const HomeScreen({super.key, required this.userMobile, required this.role});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const String _exactAlarmPromptedKey = 'exact_alarm_prompted';
  final MasjidTimingCache _masjidTimingCache = MasjidTimingCache.instance;
  final DefaultMasjidRepository _defaultMasjidRepo =
      DefaultMasjidRepository.instance;
  final VillageTimingSnapshotRepository _villageSnapshotRepo =
      VillageTimingSnapshotRepository.instance;
  final Map<String, String> _prefTimes = {};

  List<PrayerTimeData> _allPrayers = [];
  int _currentPrayerIndex = -1;

  Masjid? _jamatData;
  SalahCalendarRepository? _calendarRepo;

  // bool _isLoading = true; // ← REMOVED to prevent white screen. UI will build with placeholders.

  // Alternative Jamat State
  List<Map<String, dynamic>> _sortedNearbyMasjids = [];
  List<Map<String, dynamic>> _allUpcomingMasjids = [];
  bool _isShowingAlternatives = false;
  String _alternativeSalahName = '';
  List<Masjid> _alternativeCandidates = [];
  DateTime? _alternativeCandidatesFetchedAt;
  String _alternativeCandidatesVillage = '';
  bool _isRefreshingAlternativeCandidates = false;
  static const Duration _alternativeCandidatesTtl = Duration(minutes: 30);
  static const Duration _alternativeCandidatesEmptyRetryTtl = Duration(
    minutes: 2,
  );
  static const Duration _alternativeRemoteRetryTtl = Duration(minutes: 30);
  static const Duration _alarmRescheduleCooldown = Duration(seconds: 20);
  static const Duration _masjidFetchCooldown = Duration(seconds: 30);
  DateTime? _lastAlarmRescheduleAt;
  DateTime? _lastMasjidFetchAt;
  bool _isAlarmRescheduleInProgress = false;
  bool _isFetchingJamatTimings = false;
  Timer? _timer;
  StreamSubscription<void>? _remoteDataUpdateSubscription;
  StreamSubscription? _villageSnapshotSubscription;
  StreamSubscription<Masjid?>? _defaultMasjidSubscription;
  String _watchedVillageKey = '';
  String _watchedMasjidId = '';

  // Animation controllers
  late AnimationController _headerController;
  late AnimationController _cardController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _cardFade;

  static const List<String> _salahNames = [
    'Fajr',
    'Dhuhr',
    'Asr',
    'Maghrib',
    'Isha',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Setup animations
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _headerFade = CurvedAnimation(
      parent: _headerController,
      curve: Curves.easeOut,
    );
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _headerController,
            curve: Curves.easeOutCubic,
          ),
        );
    _cardFade = CurvedAnimation(parent: _cardController, curve: Curves.easeOut);

    NotificationService.instance.init();
    _initializeData();
    _maybePromptExactAlarmPermission();

    // Start animations immediately to show the UI shell.
    // Data will populate as it loads.
    _headerController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _cardController.forward();
    });

    NotificationService.instance.actionStream.stream.listen((action) {
      if (mounted) {
        Future.delayed(
          const Duration(milliseconds: 500),
          _tryCalculateAlternatives,
        );
      }
    });
    _remoteDataUpdateSubscription = NotificationService
        .instance
        .dataUpdateStream
        .stream
        .listen((_) async {
          if (!mounted) return;
          await _loadCachedJamatData();
          await _rescheduleAlarms(force: true);
          await _refreshAlternativeCandidatesIfNeeded(force: true);
          _tryCalculateAlternatives(refreshCandidates: true);
        });

    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _tryCalculateAlternatives(),
    );
  }

  Future<void> _maybePromptExactAlarmPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final bool prompted = prefs.getBool(_exactAlarmPromptedKey) ?? false;
    if (prompted) return;

    final bool? canExact = await NotificationService.instance
        .canScheduleExactAlarms();
    if (canExact == null || canExact) {
      await prefs.setBool(_exactAlarmPromptedKey, true);
      return;
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bool? allow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Enable Exact Alarms',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Exact alarm permission is needed for Azan notifications to ring '
            'on time. Please allow it to avoid delays.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Allow'),
            ),
          ],
        ),
      );

      await prefs.setBool(_exactAlarmPromptedKey, true);

      if (allow == true) {
        await NotificationService.instance.requestExactAlarmsPermission();
      }
    });
  }

  Future<void> _initializeData() async {
    try {
      // Data is loaded and state is updated by individual methods.
      // Run non-dependent tasks in parallel first.
      await Future.wait([_initCalendar(), _loadPreferences()]);

      // Sequentially load masjid data: cache first for speed, then network for freshness.
      // This ensures the widget is populated immediately on app start.
      await _loadCachedJamatData();
      await _fetchJamatTimings();
    } catch (e, stack) {
      debugPrint('Data initialization error: $e\n$stack');
      // Even if initialization fails, try to load from cache as a fallback.
      if (_jamatData == null) {
        await _loadCachedJamatData();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _remoteDataUpdateSubscription?.cancel();
    _villageSnapshotSubscription?.cancel();
    _defaultMasjidSubscription?.cancel();
    _headerController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTodayFromCalendar(rescheduleAlarms: false);
    }
  }

  // ─── Gate ────────────────────────────────────────────────────────────────
  void _tryCalculateAlternatives({bool refreshCandidates = false}) {
    if (mounted) {
      final int newIndex = _calculateCurrentPrayerIndex();
      if (newIndex != _currentPrayerIndex) {
        setState(() => _currentPrayerIndex = newIndex);
      }
    }

    final String? village = _jamatData?.village;
    // We need _allPrayers to determine the current Salah window
    if (village != null && village.isNotEmpty && _jamatData != null) {
      _calculateAlternativeJamats(refreshCandidates: refreshCandidates);
    }
  }

  String _toVillageKey(String? village) {
    if (village == null) return '';
    return village.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _startVillageSnapshotWatchForCurrentMasjid() {
    final String villageKey = _toVillageKey(_jamatData?.village);
    if (villageKey.isEmpty) {
      _villageSnapshotSubscription?.cancel();
      _villageSnapshotSubscription = null;
      _watchedVillageKey = '';
      return;
    }
    if (_watchedVillageKey == villageKey &&
        _villageSnapshotSubscription != null) {
      return;
    }

    _villageSnapshotSubscription?.cancel();
    _watchedVillageKey = villageKey;
    // Snapshot watch is the primary real-time channel for timing updates.
    // Keep default-masjid doc watch only as fallback to avoid duplicate live reads.
    _defaultMasjidSubscription?.cancel();
    _defaultMasjidSubscription = null;
    _watchedMasjidId = '';
    _villageSnapshotSubscription = _villageSnapshotRepo
        .watchVillageSnapshot(villageKey)
        .listen((snapshot) async {
          if (!mounted || snapshot == null) return;

          final List<Masjid> snapshotMasjids = snapshot.toMasjids();
          if (snapshotMasjids.isEmpty) return;
          await _masjidTimingCache.upsertMasjids(villageKey, snapshotMasjids);

          final String currentMasjidId = (_jamatData?.id ?? '').trim();
          if (currentMasjidId.isEmpty) return;

          Masjid? updatedDefault;
          for (final masjid in snapshotMasjids) {
            if (masjid.id.trim() == currentMasjidId) {
              updatedDefault = masjid;
              break;
            }
          }

          if (updatedDefault == null || _jamatData == null) return;

          final Masjid merged = _withLocationFallback(
            updatedDefault,
            _jamatData!,
          );
          if (!_hasTimingChanged(_jamatData!, merged)) return;

          if (mounted) {
            setState(() => _jamatData = merged);
          }
          await _rescheduleAlarms(force: true);
          await _refreshAlternativeCandidatesIfNeeded(force: true);
          _tryCalculateAlternatives(refreshCandidates: true);
          await _loadTodayFromCalendar(rescheduleAlarms: false);
        });
  }

  void _startDefaultMasjidWatch() {
    // When village is known, snapshot listener already provides live timing updates.
    // Avoid parallel doc watch to reduce read volume.
    if (_toVillageKey(_jamatData?.village).isNotEmpty) {
      _defaultMasjidSubscription?.cancel();
      _defaultMasjidSubscription = null;
      _watchedMasjidId = '';
      return;
    }

    final String masjidId = (_jamatData?.id ?? '').trim();
    if (masjidId.isEmpty) {
      _defaultMasjidSubscription?.cancel();
      _defaultMasjidSubscription = null;
      _watchedMasjidId = '';
      return;
    }
    if (_watchedMasjidId == masjidId && _defaultMasjidSubscription != null) {
      return;
    }

    _defaultMasjidSubscription?.cancel();
    _watchedMasjidId = masjidId;
    _defaultMasjidSubscription = FirebaseDB.instance
        .watchMasjidById(masjidId)
        .listen((remoteMasjid) async {
          if (!mounted || remoteMasjid == null || _jamatData == null) return;
          final Masjid merged = _withLocationFallback(
            remoteMasjid,
            _jamatData!,
          );
          if (!_hasTimingChanged(_jamatData!, merged)) return;

          setState(() => _jamatData = merged);
          await _rescheduleAlarms(force: true);
          await _refreshAlternativeCandidatesIfNeeded(force: true);
          _tryCalculateAlternatives(refreshCandidates: true);
          await _loadTodayFromCalendar(rescheduleAlarms: false);
        });
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

  Future<void> _refreshAlternativeCandidatesIfNeeded({
    bool force = false,
    bool localOnly = false,
  }) async {
    final String villageKey = _toVillageKey(_jamatData?.village);
    if (villageKey.isEmpty) return;

    if (_isRefreshingAlternativeCandidates) return;

    final bool sameVillage = _alternativeCandidatesVillage == villageKey;
    final bool hasExistingCandidates = _alternativeCandidates.isNotEmpty;
    final Duration retryWindow = hasExistingCandidates
        ? _alternativeCandidatesTtl
        : _alternativeCandidatesEmptyRetryTtl;
    final bool recentAttempt =
        _alternativeCandidatesFetchedAt != null &&
        DateTime.now().difference(_alternativeCandidatesFetchedAt!) <
            retryWindow;

    // Throttle retries for both success and empty-results cases.
    if (!force && sameVillage && recentAttempt) {
      return;
    }

    _isRefreshingAlternativeCandidates = true;
    try {
      final cachedMasjids = await _masjidTimingCache.getVillageMasjids(
        villageKey,
      );
      List<Masjid> nextCandidates = [];

      // Read from local caches only to avoid extra Firestore reads.
      final cachedSnapshot = await _villageSnapshotRepo.getCachedSnapshot(
        villageKey,
      );
      if (cachedSnapshot != null && cachedSnapshot.timings.isNotEmpty) {
        nextCandidates = _mergeAlternativeCandidates(
          snapshotMasjids: cachedSnapshot.toMasjids(),
          cachedMasjids: cachedMasjids,
        );
      } else if (cachedMasjids.isNotEmpty) {
        nextCandidates = cachedMasjids;
      }

      // Seed caches once when local sources are empty so alternate jamat works
      // even before visiting Registered Masjids.
      if (!localOnly && nextCandidates.isEmpty) {
        final snapshot = await _villageSnapshotRepo.getSnapshotForVillage(
          villageKey,
        );
        if (snapshot != null && snapshot.timings.isNotEmpty) {
          final snapshotMasjids = snapshot.toMasjids();
          await _masjidTimingCache.upsertMasjids(villageKey, snapshotMasjids);
          nextCandidates = _mergeAlternativeCandidates(
            snapshotMasjids: snapshotMasjids,
            cachedMasjids: cachedMasjids,
          );
        }
      }

      if (localOnly) {
        if (_jamatData != null) {
          nextCandidates = _mergeCurrentMasjidIntoCandidates(
            nextCandidates,
            _jamatData!,
          );
        }
        _alternativeCandidates = nextCandidates;
        _alternativeCandidatesFetchedAt = DateTime.now();
        _alternativeCandidatesVillage = villageKey;
        return;
      }

      // Final fallback: pull only this village from Firebase (incremental),
      // then persist locally. Gate remote retries by last sync timestamp to
      // avoid repeated empty fetches that increase reads.
      if (nextCandidates.isEmpty) {
        final int? lastSyncMs = await _masjidTimingCache.getLastSyncMs(
          villageKey,
        );
        final bool shouldTryRemoteNow =
            force ||
            lastSyncMs == null ||
            DateTime.now().difference(
                  DateTime.fromMillisecondsSinceEpoch(lastSyncMs),
                ) >=
                _alternativeRemoteRetryTtl;

        if (!shouldTryRemoteNow) {
          _alternativeCandidates = nextCandidates;
          _alternativeCandidatesFetchedAt = DateTime.now();
          _alternativeCandidatesVillage = villageKey;
          return;
        }

        final DateTime? updatedAfter = lastSyncMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastSyncMs);

        List<Masjid> remote = await FirebaseDB.instance
            .getApprovedMasjidsByVillage(
              villageKey: villageKey,
              updatedAfter: updatedAfter,
            );

        // If incremental returns nothing and cache is still empty, do one
        // bounded full village fetch.
        if (remote.isEmpty && lastSyncMs != null) {
          remote = await FirebaseDB.instance.getApprovedMasjidsByVillage(
            villageKey: villageKey,
            updatedAfter: null,
          );
        }

        if (remote.isNotEmpty) {
          await _masjidTimingCache.upsertMasjids(villageKey, remote);
          final refreshedCache = await _masjidTimingCache.getVillageMasjids(
            villageKey,
          );
          nextCandidates = refreshedCache.isNotEmpty ? refreshedCache : remote;
        }
        // Update sync time for both success and empty responses to throttle
        // subsequent remote retries.
        await _masjidTimingCache.setLastSyncMs(
          villageKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      _alternativeCandidates = nextCandidates;
      _alternativeCandidatesFetchedAt = DateTime.now();
      _alternativeCandidatesVillage = villageKey;
    } catch (e) {
      debugPrint('Alternative candidates refresh failed: $e');
    } finally {
      _isRefreshingAlternativeCandidates = false;
    }
  }

  List<Masjid> _mergeCurrentMasjidIntoCandidates(
    List<Masjid> candidates,
    Masjid current,
  ) {
    final String id = current.id.trim();
    final String key = _altCandidateKey(current.name, current.village);
    final List<Masjid> next = [];
    bool replaced = false;

    for (final m in candidates) {
      final bool idMatch = id.isNotEmpty && m.id.trim() == id;
      final bool keyMatch =
          id.isEmpty && _altCandidateKey(m.name, m.village) == key;
      if (idMatch || keyMatch) {
        next.add(current);
        replaced = true;
      } else {
        next.add(m);
      }
    }

    if (!replaced) {
      next.add(current);
    }
    return next;
  }

  List<Masjid> _mergeAlternativeCandidates({
    required List<Masjid> snapshotMasjids,
    required List<Masjid> cachedMasjids,
  }) {
    if (snapshotMasjids.isEmpty) return cachedMasjids;
    if (cachedMasjids.isEmpty) return snapshotMasjids;

    final Map<String, Masjid> cacheById = {
      for (final m in cachedMasjids)
        if (m.id.trim().isNotEmpty) m.id.trim(): m,
    };
    final Map<String, Masjid> cacheByKey = {
      for (final m in cachedMasjids) _altCandidateKey(m.name, m.village): m,
    };

    return snapshotMasjids.map((m) {
      final Masjid? cachedById = cacheById[m.id.trim()];
      final Masjid? cachedByKey =
          cacheByKey[_altCandidateKey(m.name, m.village)];
      final Masjid? source = cachedById ?? cachedByKey;
      if (source == null) return m;
      return _withLocationFallback(m, source);
    }).toList();
  }

  String _altCandidateKey(String name, String? village) {
    final n = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final v = _toVillageKey(village);
    return '$n|$v';
  }

  Masjid _withLocationFallback(Masjid base, Masjid source) {
    return Masjid(
      id: base.id,
      name: base.name,
      isApproved: base.isApproved,
      geoHash: base.geoHash,
      ownerMobile: base.ownerMobile,
      isTimingConfigured: base.isTimingConfigured,
      salahs: base.salahs,
      address: (base.address ?? '').isNotEmpty ? base.address : source.address,
      latitude: base.latitude ?? source.latitude,
      longitude: base.longitude ?? source.longitude,
      state: (base.state ?? '').isNotEmpty ? base.state : source.state,
      district: (base.district ?? '').isNotEmpty
          ? base.district
          : source.district,
      mandal: (base.mandal ?? '').isNotEmpty ? base.mandal : source.mandal,
      village: (base.village ?? '').isNotEmpty ? base.village : source.village,
      colony: (base.colony ?? '').isNotEmpty ? base.colony : source.colony,
      fajr: base.fajr,
      dhuhr: base.dhuhr,
      asr: base.asr,
      maghrib: base.maghrib,
      isha: base.isha,
      juma: base.juma,
      fajr_azan: (base.fajr_azan ?? '').isNotEmpty
          ? base.fajr_azan
          : source.fajr_azan,
      fajr_jamat: (base.fajr_jamat ?? '').isNotEmpty
          ? base.fajr_jamat
          : source.fajr_jamat,
      dhuhr_azan: (base.dhuhr_azan ?? '').isNotEmpty
          ? base.dhuhr_azan
          : source.dhuhr_azan,
      dhuhr_jamat: (base.dhuhr_jamat ?? '').isNotEmpty
          ? base.dhuhr_jamat
          : source.dhuhr_jamat,
      asar_azan: (base.asar_azan ?? '').isNotEmpty
          ? base.asar_azan
          : source.asar_azan,
      asar_jamat: (base.asar_jamat ?? '').isNotEmpty
          ? base.asar_jamat
          : source.asar_jamat,
      maghrib_azan: (base.maghrib_azan ?? '').isNotEmpty
          ? base.maghrib_azan
          : source.maghrib_azan,
      maghrib_jamat: (base.maghrib_jamat ?? '').isNotEmpty
          ? base.maghrib_jamat
          : source.maghrib_jamat,
      isha_azan: (base.isha_azan ?? '').isNotEmpty
          ? base.isha_azan
          : source.isha_azan,
      isha_jamat: (base.isha_jamat ?? '').isNotEmpty
          ? base.isha_jamat
          : source.isha_jamat,
      juma_azan: (base.juma_azan ?? '').isNotEmpty
          ? base.juma_azan
          : source.juma_azan,
      juma_jamat: (base.juma_jamat ?? '').isNotEmpty
          ? base.juma_jamat
          : source.juma_jamat,
    );
  }

  // ─── Alternative Jamat Core ───────────────────────────────────────────────
  Future<void> _calculateAlternativeJamats({
    bool refreshCandidates = false,
  }) async {
    if (_jamatData == null ||
        _jamatData?.village == null ||
        _jamatData!.village!.isEmpty ||
        _allPrayers.isEmpty) {
      _hideAlternatives();
      return;
    }

    final Masjid defaultMasjid = _jamatData!;
    final String village = defaultMasjid.village ?? '';

    if (village.isEmpty) {
      _hideAlternatives();
      return;
    }

    final DateTime now = DateTime.now();

    // Identify the current Salah window
    PrayerTimeData? currentPrayer;

    // Handle post-midnight Isha case (before Fajr)
    if (_allPrayers.isNotEmpty && now.isBefore(_allPrayers[0].startTime)) {
      final DateTime prevIshaEnd = _allPrayers[0].startTime.subtract(
        const Duration(minutes: 5),
      );
      if (now.isBefore(prevIshaEnd)) {
        currentPrayer = _allPrayers.last; // Isha
      }
    }

    if (currentPrayer == null) {
      for (final p in _allPrayers) {
        // Check if now is within the prayer window [startTime, endTime)
        if (!now.isBefore(p.startTime) && now.isBefore(p.endTime)) {
          currentPrayer = p;
          break;
        }
      }
    }

    // Friday-only fallback:
    // After Fajr ends and before Dhuhr starts, show upcoming Juma alternatives.
    if (currentPrayer == null && now.weekday == DateTime.friday) {
      PrayerTimeData? fajrPrayer;
      PrayerTimeData? dhuhrPrayer;
      for (final p in _allPrayers) {
        if (p.name == 'Fajr') fajrPrayer = p;
        if (p.name == 'Dhuhr') dhuhrPrayer = p;
      }

      if (fajrPrayer != null &&
          dhuhrPrayer != null &&
          !now.isBefore(fajrPrayer.endTime) &&
          now.isBefore(dhuhrPrayer.startTime)) {
        currentPrayer = dhuhrPrayer;
      }
    }

    if (currentPrayer == null) {
      // Outside an active salah window, fall back to the next upcoming salah
      // so alternate jamat still appears throughout the day.
      for (final p in _allPrayers) {
        if (now.isBefore(p.startTime)) {
          currentPrayer = p;
          break;
        }
      }
      // If all today's salah windows are done, use tomorrow's Fajr slot.
      currentPrayer ??= _allPrayers.first;
    }

    final String salahName = currentPrayer.name;
    final bool isFriday = now.weekday == DateTime.friday;

    final String currentVillageKey = _toVillageKey(village);
    final bool villageChanged =
        _alternativeCandidatesVillage != currentVillageKey;
    if (refreshCandidates || _alternativeCandidates.isEmpty || villageChanged) {
      await _refreshAlternativeCandidatesIfNeeded(
        // Village switch should refresh candidate source, but keep it
        // non-forced so repository can stay local-first and low-read.
        force: refreshCandidates,
      );
    }

    final List<Masjid> allMasjids = _alternativeCandidates;
    if (allMasjids.isEmpty) {
      _hideAlternatives();
      return;
    }
    final String villageKey = currentVillageKey;
    List<Map<String, dynamic>> buildResultsFor(String targetSalahName) {
      final List<Map<String, dynamic>> localResults = [];
      final double? baseLat = defaultMasjid.latitude;
      final double? baseLng = defaultMasjid.longitude;
      for (final masjid in allMasjids) {
        // Candidate set is already village-scoped from cache, but keep a safe key
        // check for mixed/legacy cache entries.
        if (villageKey.isNotEmpty &&
            _toVillageKey(masjid.village) != villageKey) {
          continue;
        }

        final String rawTime = _getRawJamatTime(
          masjid,
          targetSalahName,
          isFriday: isFriday,
        );
        DateTime? jamatDt = _parseTime(rawTime, targetSalahName);

        // Handle Isha Jamat times that are past midnight (AM)
        if (targetSalahName == 'Isha' && jamatDt != null) {
          if (now.hour < 12) {
            // Post-midnight: We are in the early morning.
            // Filter out PM times (which belong to the next Isha cycle in the evening).
            if (jamatDt.hour >= 12) continue;
          } else {
            // Pre-midnight: We are in the evening.
            // If Jamat is AM (next day) but parsed as today AM (past), add 1 day.
            if (jamatDt.isBefore(now) && jamatDt.hour < 12) {
              jamatDt = jamatDt.add(const Duration(days: 1));
            }
          }
        }

        if (jamatDt != null && jamatDt.isAfter(now)) {
          localResults.add({
            'masjid': masjid,
            'jamatTime': jamatDt,
            'isDefault': masjid.id == defaultMasjid.id,
            'distanceToDefault': _distanceMeters(
              baseLat,
              baseLng,
              masjid.latitude,
              masjid.longitude,
            ),
          });
        }
      }
      localResults.sort((a, b) {
        final DateTime aTime = a['jamatTime'] as DateTime;
        final DateTime bTime = b['jamatTime'] as DateTime;
        final int timeCmp = aTime.compareTo(bTime);
        if (timeCmp != 0) return timeCmp;

        final double? aDist = a['distanceToDefault'] as double?;
        final double? bDist = b['distanceToDefault'] as double?;
        if (aDist != null && bDist != null) {
          final int distCmp = aDist.compareTo(bDist);
          if (distCmp != 0) return distCmp;
        } else if (aDist != null) {
          return -1;
        } else if (bDist != null) {
          return 1;
        }

        final String aName = (a['masjid'] as Masjid).name.toLowerCase().trim();
        final String bName = (b['masjid'] as Masjid).name.toLowerCase().trim();
        return aName.compareTo(bName);
      });
      return localResults;
    }

    List<Map<String, dynamic>> results = buildResultsFor(salahName);
    String displaySalahName = (isFriday && salahName == 'Dhuhr')
        ? 'Juma'
        : salahName;

    final bool isWithinCurrentWindow =
        !now.isBefore(currentPrayer.startTime) &&
        now.isBefore(currentPrayer.endTime);

    // Show upcoming jamat only once the actual prayer window starts.
    // Friday exception: allow Juma alternatives right after Fajr ends.
    if (!isWithinCurrentWindow) {
      if (!(isFriday && salahName == 'Dhuhr')) {
        _hideAlternatives();
        return;
      }
    }

    if (results.isEmpty) {
      _hideAlternatives();
      return;
    }

    if (mounted) {
      setState(() {
        _allUpcomingMasjids = results;
        _sortedNearbyMasjids = results.take(5).toList();
        _isShowingAlternatives = true;
        _alternativeSalahName = displaySalahName;
      });
    }
  }

  void _hideAlternatives() {
    if (mounted) {
      setState(() {
        _sortedNearbyMasjids = [];
        _allUpcomingMasjids = [];
        _isShowingAlternatives = false;
        _alternativeSalahName = '';
      });
    }
  }

  String _getRawJamatTime(
    Masjid masjid,
    String salahName, {
    bool isFriday = false,
  }) {
    String time = '';
    if (isFriday && salahName == 'Dhuhr') {
      return masjid.juma_jamat ?? '';
    }
    switch (salahName) {
      case 'Fajr':
        time = masjid.fajr_jamat ?? '';
        break;
      case 'Dhuhr':
        time = masjid.dhuhr_jamat ?? '';
        break;
      case 'Asr':
        time = masjid.asar_jamat ?? '';
        break;
      case 'Maghrib':
        time = '';
        break;
      case 'Isha':
        time = masjid.isha_jamat ?? '';
        break;
    }
    if (salahName == 'Maghrib' &&
        (time.isEmpty || (!time.contains(':') && !time.contains('.')))) {
      final maghrib = _allPrayers.firstWhere(
        (p) => p.name == 'Maghrib',
        orElse: () => PrayerTimeData(
          name: '',
          startTime: DateTime.now(),
          endTime: DateTime.now(),
        ),
      );
      if (maghrib.name == 'Maghrib') {
        time =
            '${maghrib.startTime.hour}:${maghrib.startTime.minute.toString().padLeft(2, '0')}';
      }
    }
    return time;
  }

  double? _distanceMeters(
    double? lat1,
    double? lng1,
    double? lat2,
    double? lng2,
  ) {
    if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) {
      return null;
    }
    const double radius = 6371000; // meters
    final double dLat = _degToRad(lat2 - lat1);
    final double dLng = _degToRad(lng2 - lng1);
    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radius * c;
  }

  double _degToRad(double deg) => deg * (math.pi / 180.0);

  // Moved _parseTime to be accessible or keep it here.
  // Note: The original _parseTime logic is fine, just ensuring it handles the logic correctly.
  DateTime? _parseTime(String raw, [String? salahName]) {
    if (raw.trim().isEmpty) return null;
    final String s = raw.trim().replaceAll('.', ':').toLowerCase();
    final bool hasPm = s.contains('pm');
    final bool hasAm = s.contains('am');
    final String digits = s.replaceAll(RegExp(r'[^0-9:]'), '');
    if (!digits.contains(':')) return null;
    final List<String> parts = digits.split(':');
    if (parts.length < 2) return null;
    int? h = int.tryParse(parts[0]);
    int? m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h > 23 || m > 59) return null;
    if (hasPm && h < 12) h += 12;
    if (hasAm && h == 12) h = 0;
    if (!hasPm && !hasAm && salahName != null) {
      switch (salahName) {
        case 'Fajr':
          break;
        case 'Dhuhr':
          if (h > 0 && h < 11) h += 12;
          break;
        case 'Asr':
        case 'Maghrib':
        case 'Isha':
          if (h < 12) h += 12;
          break;
      }
    }
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h, m);
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _normalizeOffsetDirection(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    return v == 'more' ? 'more' : 'less';
  }

  DateTime _applyOffset(DateTime time, int minutes, String direction) {
    if (minutes <= 0) return time;
    return direction == 'more'
        ? time.add(Duration(minutes: minutes))
        : time.subtract(Duration(minutes: minutes));
  }

  // ─── Calendar ─────────────────────────────────────────────────────────────
  Future<void> _initCalendar() async {
    try {
      final db = await SalahDatabaseHelper.instance.database;
      _calendarRepo = SalahCalendarRepository(db);
      await _loadTodayFromCalendar(rescheduleAlarms: false);
    } catch (e) {
      debugPrint('SalahCalendar: Init Error → $e');
    }
  }

  Future<void> _loadTodayFromCalendar({bool rescheduleAlarms = true}) async {
    if (_calendarRepo == null) return;
    try {
      final DateTime now = DateTime.now();
      final SalahCalendarModel? row = await _calendarRepo!.getByDate(
        DateTime(now.year, now.month, now.day),
      );
      if (row == null) return;

      String? rawFajrEnd;
      try {
        final rawMap = await SalahDatabaseHelper.instance.getRowForDate(now);
        if (rawMap != null) rawFajrEnd = rawMap['fajr_end']?.toString();
      } catch (e) {
        debugPrint('fajr_end fetch error: $e');
      }

      final List<PrayerTimeData> prayers = _parsePrayers(row, rawFajrEnd);
      if (mounted) {
        setState(() {
          _allPrayers = prayers;
          _currentPrayerIndex = _calculateCurrentPrayerIndex();
        });
      }
      if (rescheduleAlarms) {
        await _rescheduleAlarms();
      }
      _tryCalculateAlternatives();
    } catch (e, stack) {
      debugPrint('SalahCalendar: LOAD ERROR → $e\n$stack');
    }
  }

  List<PrayerTimeData> _parsePrayers(
    SalahCalendarModel row, [
    String? rawFajrEnd,
  ]) {
    final DateTime now = DateTime.now();
    final DateTime date = DateTime(now.year, now.month, now.day);

    final int sunriseOffsetMinutes = _jamatData?.sunriseOffsetMinutes ?? 0;
    final int sunsetOffsetMinutes = _jamatData?.sunsetOffsetMinutes ?? 0;
    final String sunriseOffsetDirection = _normalizeOffsetDirection(
      _jamatData?.sunriseOffsetDirection,
    );
    final String sunsetOffsetDirection = _normalizeOffsetDirection(
      _jamatData?.sunsetOffsetDirection,
    );

    // Use calendar times strictly for Start/End calculations
    final fajrAzan = row.fajrAzan;
    final dhuhrAzan = row.dhuhrAzan;
    final asrAzan = row.asrAzan;
    final maghribAzan = row.maghribAzan;
    final ishaAzan = row.ishaAzan;
    final sunrise = row.sunrise; // Sunrise is only in calendar

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

    final fStart = _applyOffset(
      parse(fajrAzan),
      sunriseOffsetMinutes,
      sunriseOffsetDirection,
    );
    DateTime fEnd = (rawFajrEnd != null && rawFajrEnd.isNotEmpty)
        ? parse(rawFajrEnd)
        : parse(sunrise);
    fEnd = _applyOffset(fEnd, sunriseOffsetMinutes, sunriseOffsetDirection);
    if (!fEnd.isAfter(fStart)) {
      fEnd = fStart.add(const Duration(minutes: 90));
    }
    var dStart = parse(dhuhrAzan);
    if (dStart.hour < 11) dStart = toPm(dStart);
    dStart = _applyOffset(dStart, sunriseOffsetMinutes, sunriseOffsetDirection);
    var aStart = parse(asrAzan);
    if (aStart.hour < 12) aStart = toPm(aStart);
    aStart = _applyOffset(aStart, sunriseOffsetMinutes, sunriseOffsetDirection);
    var mStart = parse(maghribAzan);
    if (mStart.hour < 12) mStart = toPm(mStart);
    mStart = _applyOffset(mStart, sunsetOffsetMinutes, sunsetOffsetDirection);
    var iStart = parse(ishaAzan);
    if (iStart.hour < 12) {
      if (iStart.hour > 4) {
        iStart = toPm(iStart);
      }
    }
    iStart = _applyOffset(iStart, sunsetOffsetMinutes, sunsetOffsetDirection);

    // End Times align to the next salah start time
    final dEnd = aStart;
    final aEnd = mStart;
    final mEnd = iStart;

    // Isha End = Next Day Fajr
    final nextFajr = fStart.add(const Duration(days: 1));
    final iEnd = nextFajr;

    return [
      PrayerTimeData(name: 'Fajr', startTime: fStart, endTime: fEnd),
      PrayerTimeData(name: 'Dhuhr', startTime: dStart, endTime: dEnd),
      PrayerTimeData(name: 'Asr', startTime: aStart, endTime: aEnd),
      PrayerTimeData(name: 'Maghrib', startTime: mStart, endTime: mEnd),
      PrayerTimeData(name: 'Isha', startTime: iStart, endTime: iEnd),
    ];
  }

  // ─── Prefs ────────────────────────────────────────────────────────────────
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return; // ← FIX: guard before setState
    setState(() {
      _prefTimes.clear();
      for (final key in prefs.getKeys()) {
        if (key.startsWith('pref_')) {
          _prefTimes[key] = prefs.getString(key) ?? '';
        }
      }
    });
  }

  // ─── Masjid ───────────────────────────────────────────────────────────────
  Future<void> _loadCachedJamatData() async {
    try {
      final Masjid? cachedMasjid = await _defaultMasjidRepo
          .getLocalDefaultMasjid(userMobile: widget.userMobile);

      if (cachedMasjid != null && mounted) {
        setState(() {
          _jamatData = cachedMasjid;
        });
        _startDefaultMasjidWatch();
        _startVillageSnapshotWatchForCurrentMasjid();

        // Immediately update the widget with cached data.
        // This is the key to fixing the blank widget issue.
        await _loadTodayFromCalendar(rescheduleAlarms: false);
        await _refreshAlternativeCandidatesIfNeeded(
          force: true,
          localOnly: true,
        );
        _tryCalculateAlternatives();
        debugPrint('Home Widget updated with cached Masjid data.');
      }
    } catch (e) {
      debugPrint('Error loading cached masjid data: $e');
      // Don't throw, as fetching from network is the next step.
    }
  }

  Future<void> _fetchJamatTimings({bool force = false}) async {
    if (_isFetchingJamatTimings) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastMasjidFetchAt != null &&
        now.difference(_lastMasjidFetchAt!) < _masjidFetchCooldown) {
      return;
    }
    _isFetchingJamatTimings = true;
    _lastMasjidFetchAt = now;
    try {
      final Masjid? masjid = await _defaultMasjidRepo.getDefaultMasjid(
        userMobile: widget.userMobile,
        forceRefresh: force,
      );
      if (masjid == null) return;

      if (mounted) {
        setState(() => _jamatData = masjid);
        _startDefaultMasjidWatch();
        _startVillageSnapshotWatchForCurrentMasjid();
        await _rescheduleAlarms(force: false);
        await _refreshAlternativeCandidatesIfNeeded(force: false);
        _tryCalculateAlternatives();
        _loadTodayFromCalendar(rescheduleAlarms: false);
      }
    } catch (e) {
      debugPrint('Masjid Load Error: $e');
    } finally {
      _isFetchingJamatTimings = false;
    }
  }

  Future<void> _rescheduleAlarms({bool force = false}) async {
    if (_isAlarmRescheduleInProgress) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastAlarmRescheduleAt != null &&
        now.difference(_lastAlarmRescheduleAt!) < _alarmRescheduleCooldown) {
      return;
    }
    _isAlarmRescheduleInProgress = true;
    _lastAlarmRescheduleAt = now;

    try {
      final prefs = await SharedPreferences.getInstance();
      bool isMasterEnabled = prefs.getBool('master_alarm_enabled') ?? false;
      if (!isMasterEnabled) {
        isMasterEnabled = prefs.getBool('salah_alerts_enabled') ?? false;
      }

      final List<String> prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
      for (int i = 0; i < prayers.length; i++) {
        final name = prayers[i];
        String masjidAzanTime = '', masjidJamatTime = '';
        if (_jamatData != null) {
          switch (name) {
            case 'Fajr':
              masjidAzanTime = _jamatData!.fajr_azan ?? '';
              masjidJamatTime = _jamatData!.fajr_jamat ?? '';
              break;
            case 'Dhuhr':
              masjidAzanTime = _jamatData!.dhuhr_azan ?? '';
              masjidJamatTime = _jamatData!.dhuhr_jamat ?? '';
              break;
            case 'Asr':
              masjidAzanTime = _jamatData!.asar_azan ?? '';
              masjidJamatTime = _jamatData!.asar_jamat ?? '';
              break;
            case 'Maghrib':
              masjidAzanTime = '';
              masjidJamatTime = '';
              break;
            case 'Isha':
              masjidAzanTime = _jamatData!.isha_azan ?? '';
              masjidJamatTime = _jamatData!.isha_jamat ?? '';
              break;
          }
        }

        String myAzanTime = prefs.getString('pref_${name}_Azan') ?? '';
        String myJamatTime = prefs.getString('pref_${name}_Jamat') ?? '';
        if (myAzanTime.isEmpty) myAzanTime = masjidAzanTime;
        if (myJamatTime.isEmpty) myJamatTime = masjidJamatTime;

        bool azanEnabled = prefs.getBool('${name}_Azan') ?? false;
        bool jamatEnabled = prefs.getBool('${name}_Jamat') ?? false;

        if ((azanEnabled && myAzanTime.isEmpty) ||
            (jamatEnabled && myJamatTime.isEmpty)) {
          await NotificationService.instance.cancelAlarm(i + 1);
          continue;
        }

        DateTime endTime = DateTime.now().add(const Duration(hours: 1));
        DateTime? calculatedStartTime;
        if (_allPrayers.isNotEmpty && i < _allPrayers.length) {
          endTime = _allPrayers[i].endTime;
          calculatedStartTime = _allPrayers[i].startTime;
        }

        if (name == 'Maghrib' && calculatedStartTime != null) {
          final String cal =
              '${calculatedStartTime.hour}:${calculatedStartTime.minute.toString().padLeft(2, '0')}';
          masjidAzanTime = cal;
          myAzanTime = cal;
          final DateTime jTime = calculatedStartTime.add(
            const Duration(minutes: 2),
          );
          final String calJamat =
              '${jTime.hour}:${jTime.minute.toString().padLeft(2, '0')}';
          masjidJamatTime = calJamat;
          myJamatTime = calJamat;
        }

        await NotificationService.instance.scheduleSalahAlarm(
          id: i + 1,
          title: name,
          body: 'It is time for $name',
          masjidTime: masjidAzanTime,
          masjidJamatTime: masjidJamatTime,
          myTime: myAzanTime,
          myJamatTime: myJamatTime,
          isMyPrefsMode: true,
          endTime: endTime,
          azanEnabled: isMasterEnabled && azanEnabled,
          jamatEnabled: isMasterEnabled && jamatEnabled,
        );
      }

      String masjidJumaAzan = _jamatData?.juma_azan ?? '';
      String masjidJumaJamat = _jamatData?.juma_jamat ?? '';
      String myJumaAzan = prefs.getString('pref_Juma_Azan') ?? '';
      String myJumaJamat = prefs.getString('pref_Juma_Jamat') ?? '';
      if (myJumaAzan.isEmpty) myJumaAzan = masjidJumaAzan;
      if (myJumaJamat.isEmpty) myJumaJamat = masjidJumaJamat;

      bool jumaAzanEnabled = prefs.getBool('Juma_Azan') ?? false;
      bool jumaJamatEnabled = prefs.getBool('Juma_Jamat') ?? false;
      if ((jumaAzanEnabled && myJumaAzan.isEmpty) ||
          (jumaJamatEnabled && myJumaJamat.isEmpty)) {
        await NotificationService.instance.cancelAlarm(6);
        return;
      }
      DateTime jumaEndTime = DateTime.now().add(const Duration(hours: 1));
      if (_allPrayers.length > 2) jumaEndTime = _allPrayers[1].endTime;

      await NotificationService.instance.scheduleSalahAlarm(
        id: 6,
        title: 'Juma',
        body: 'It is time for Juma',
        masjidTime: masjidJumaAzan,
        masjidJamatTime: masjidJumaJamat,
        myTime: myJumaAzan,
        myJamatTime: myJumaJamat,
        isMyPrefsMode: true,
        endTime: jumaEndTime,
        azanEnabled: isMasterEnabled && jumaAzanEnabled,
        jamatEnabled: isMasterEnabled && jumaJamatEnabled,
      );
    } finally {
      _isAlarmRescheduleInProgress = false;
    }
  }

  int _calculateCurrentPrayerIndex() {
    if (_allPrayers.isEmpty) return -1;

    final DateTime now = DateTime.now();

    // Handle post-midnight Isha case (before Fajr)
    if (now.isBefore(_allPrayers[0].startTime)) {
      return _allPrayers.length - 1; // Isha
    }

    for (int i = 0; i < _allPrayers.length; i++) {
      final p = _allPrayers[i];
      if (!now.isBefore(p.startTime) && now.isBefore(p.endTime)) return i;
    }
    return -1;
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width >= 768;
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double horizontalPadding = isLargeScreen
        ? 24
        : (isSmallScreen ? 12 : 16);
    final double sectionGap = isSmallScreen ? 8 : 12;
    final double tableToGridGap = 12;

    return Scaffold(
      backgroundColor: _AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF8FBF9),
                    Color(0xFFF2F6F3),
                    _AppColors.background,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 110,
            left: -48,
            child: _buildGlowOrb(140, const Color(0x332E7D4F)),
          ),
          Positioned(
            top: 330,
            right: -36,
            child: _buildGlowOrb(120, const Color(0x22B8963E)),
          ),
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _cardFade,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      0,
                      horizontalPadding,
                      (isSmallScreen ? 12 : 16) + bottomInset,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: sectionGap),
                        _buildOverviewCard(),
                        SizedBox(height: sectionGap),
                        _buildSalahTableCard(),
                        SizedBox(height: tableToGridGap),
                        if (_isShowingAlternatives) ...[
                          _buildUpcomingJamatSummaryCard(),
                          SizedBox(height: tableToGridGap),
                        ],
                        _homeGrid(),
                        const SizedBox(height: 12),
                        _buildFooterCard(),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Sliver App Bar ───────────────────────────────────────────────────────
  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: _AppColors.primary,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          onPressed: () {
            _fetchJamatTimings(force: true);
            _loadTodayFromCalendar(rescheduleAlarms: false);
          },
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          onPressed: () => _confirmLogout(context),
          tooltip: 'Logout',
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: _buildAppBarBackground(),
      ),
    );
  }

  Widget _buildAppBarBackground() {
    final String dateStr = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3D24), Color(0xFF1A5C38), Color(0xFF2E7D4F)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            child: SlideTransition(
              position: _headerSlide,
              child: FadeTransition(
                opacity: _headerFade,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'Tawheed Namaz Reminder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _AppColors.gold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _AppColors.gold.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              dateStr,
                              style: const TextStyle(
                                color: Color(0xFFD4A840),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Salah Table Card ─────────────────────────────────────────────────────
  Widget _buildSalahTableCard() {
    return Container(
      decoration: BoxDecoration(
        color: _AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _AppColors.primary.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A5C38), Color(0xFF2E7D4F)],
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.access_time_filled_rounded,
                  color: Color(0xFFFFE3A0),
                  size: 15,
                ),
                SizedBox(width: 8),
                Text(
                  'Prayer Timings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFE3A0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // ← FIX: Show a placeholder when prayer data isn't loaded yet
          _allPrayers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 36,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Prayer times not available.\nPlease refresh or check your connection.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SalahTable(
                        allPrayers: _allPrayers,
                        currentPrayerIndex: _currentPrayerIndex,
                        jamatData: _jamatData,
                        prefTimes: _getMergedTimes(),
                        showPreferences: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Start and end times may vary by location.\nPlease follow according to your locality.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color.fromARGB(255, 226, 35, 35),
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }

  Map<String, String> _getMergedTimes() {
    final Map<String, String> merged = {};
    if (_jamatData == null) return merged;

    void add(String key, String? val) {
      if (val != null && val.isNotEmpty) merged[key] = val;
    }

    add('pref_Fajr_Azan', _jamatData!.fajr_azan);
    add('pref_Fajr_Jamat', _jamatData!.fajr_jamat);
    add('pref_Dhuhr_Azan', _jamatData!.dhuhr_azan);
    add('pref_Dhuhr_Jamat', _jamatData!.dhuhr_jamat);
    add('pref_Asr_Azan', _jamatData!.asar_azan);
    add('pref_Asr_Jamat', _jamatData!.asar_jamat);
    add('pref_Isha_Azan', _jamatData!.isha_azan);
    add('pref_Isha_Jamat', _jamatData!.isha_jamat);
    add('pref_Juma_Azan', _jamatData!.juma_azan);
    add('pref_Juma_Jamat', _jamatData!.juma_jamat);

    _prefTimes.forEach((key, value) {
      if (value.isNotEmpty) {
        merged[key] = value;
      }
    });
    return merged;
  }

  // ─── Upcoming Jamat Summary Card ─────────────────────────────────────────
  Widget _buildUpcomingJamatSummaryCard() {
    final String salahLabel = _alternativeSalahName.isNotEmpty
        ? _alternativeSalahName
        : 'Upcoming';

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openUpcomingJamatList,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _AppColors.primary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: _AppColors.primary.withOpacity(0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.mosque_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Upcoming Jamat - $salahLabel',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to view all upcoming jamats',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openUpcomingJamatList() {
    if (_allUpcomingMasjids.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UpcomingJamatScreen(
          items: _allUpcomingMasjids,
          salahLabel: _alternativeSalahName.isNotEmpty
              ? _alternativeSalahName
              : 'Upcoming',
          village: _jamatData?.village,
        ),
      ),
    );
  }

  Widget _buildAlternativeItem(int index, int count) {
    final item = _sortedNearbyMasjids[index];
    final Masjid masjid = item['masjid'] as Masjid;
    final DateTime jt = item['jamatTime'] as DateTime;
    final bool isDefault = (item['isDefault'] as bool?) ?? false;
    final bool isLast = index == count - 1;

    return Column(
      children: [
        _AlternativeMasjidTile(
          masjid: masjid,
          jamatTime: jt,
          isDefault: isDefault,
          timeLabel: _fmtTime12H(jt),
          onTap: () => _openAlternativeMasjidInMaps(masjid),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: _AppColors.divider,
            indent: 68,
            endIndent: 16,
          ),
      ],
    );
  }

  // ─── Home Grid ────────────────────────────────────────────────────────────
  Widget _homeGrid() {
    final List<Widget> tiles = [
      _HomeGridCard(
        item: _GridItem(
          Icons.tune_rounded,
          'My prefernces/ Notifications',
          _AppColors.primary,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MyPreferencesScreen(userMobile: widget.userMobile),
              ),
            ).then((_) async {
              _loadPreferences();
              await _loadCachedJamatData();
              await _loadTodayFromCalendar(rescheduleAlarms: false);
              _tryCalculateAlternatives();
            });
          },
        ),
        index: 0,
      ),
      _HomeGridCard(
        item: _GridItem(
          Icons.location_on_rounded,
          'Nearby Masjids',
          const Color(0xFFE67E22),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NearbyMasjidsScreen()),
            );
          },
        ),
        index: 1,
      ),
      _HomeGridCard(
        item: _GridItem(
          Icons.mosque_rounded,
          '(Registered/Default)\nMasjids',
          const Color(0xFF6D3B8E),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const RegisteredMasjidsScreen(),
              ),
            ).then((_) async {
              await _loadCachedJamatData();
              await _loadTodayFromCalendar(rescheduleAlarms: false);
              _tryCalculateAlternatives();
            });
          },
        ),
        index: 2,
      ),
      _buildRoleOrTrackerTile(index: 3),
      _HomeGridCard(
        item: _GridItem(Icons.explore_rounded, 'Qibla', _AppColors.primary, () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QiblaCompassScreen()),
          );
        }),
        index: 4,
      ),
      _HomeGridCard(
        item: _GridItem(
          Icons.autorenew_rounded,
          'Zikr Counter',
          const Color(0xFF2F4B9B),
          () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ZikrScreen()));
          },
        ),
        index: 5,
      ),
      _HomeGridCard(
        item: _GridItem(
          Icons.calculate_rounded,
          'Namaz Guide',
          const Color(0xFF1C7C54),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RakatsScreen()),
            );
          },
        ),
        index: 6,
      ),
      _HomeGridCard(
        item: _GridItem(
          Icons.menu_book_rounded,
          'Masnoon Dua',
          const Color(0xFFB65C1D),
          () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DuaScreen()),
            );
          },
        ),
        index: 7,
      ),
      _buildSupportActionsCard(index: 8),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        const int crossAxisCount = 3;
        const double horizontalGap = 6;
        const double verticalGap = 6;
        final double cellWidth =
            (width - (horizontalGap * (crossAxisCount - 1))) / crossAxisCount;
        const double targetHeight = 46;
        final double ratio = (cellWidth / targetHeight).clamp(0.92, 1.6);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: verticalGap,
            crossAxisSpacing: horizontalGap,
            childAspectRatio: ratio,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, index) => tiles[index],
        );
      },
    );
  }

  Widget _buildGlowOrb(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required IconData icon}) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _AppColors.primarySurface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _AppColors.primary.withOpacity(0.15)),
          ),
          child: Icon(icon, size: 17, color: _AppColors.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: _AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );
  }

  _SalahSlot? _getNextPrayerSlot() {
    if (_allPrayers.isEmpty) return null;
    final now = DateTime.now();
    for (final p in _allPrayers) {
      if (p.startTime.isAfter(now)) {
        return _SalahSlot(name: p.name, jamatTime: p.startTime);
      }
    }
    final firstTomorrow = _allPrayers.first.startTime.add(
      const Duration(days: 1),
    );
    return _SalahSlot(name: _allPrayers.first.name, jamatTime: firstTomorrow);
  }

  String _getCurrentPrayerLabel() {
    if (_currentPrayerIndex == -1 || _allPrayers.isEmpty) {
      return 'No active prayer';
    }
    final rawName = _allPrayers[_currentPrayerIndex].name;
    if (rawName == 'Dhuhr' && DateTime.now().weekday == DateTime.friday) {
      return 'Juma in progress';
    }
    return '$rawName in progress';
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return '00h 00m 00s';
    final int hours = d.inHours;
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  Widget _buildOverviewCard() {
    final _SalahSlot? next = _getNextPrayerSlot();
    final String location = (_jamatData?.village?.trim().isNotEmpty ?? false)
        ? _jamatData!.village!
        : 'Location pending';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123D28), Color(0xFF1A5C38), Color(0xFF2D7A4D)],
        ),
        boxShadow: [
          BoxShadow(
            color: _AppColors.primary.withOpacity(0.24),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _jamatData?.name ?? 'My Masjid',
                  style: const TextStyle(
                    color: _AppColors.gold,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_currentPrayerIndex != -1)
                Container(
                  margin: const EdgeInsets.only(left: 8, top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7ED87E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_allPrayers[_currentPrayerIndex].name == 'Dhuhr' && DateTime.now().weekday == DateTime.friday ? 'Juma' : _allPrayers[_currentPrayerIndex].name} Time',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 14,
                color: _AppColors.gold,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _AppColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, chipConstraints) {
              final bool compact = chipConstraints.maxWidth < 360;
              final Widget nowChip = _buildStatusChip(
                icon: Icons.play_circle_fill_rounded,
                title: 'Now',
                value: _getCurrentPrayerLabel(),
                compact: compact,
              );
              final Widget nextChip = _buildStatusChip(
                icon: Icons.notifications_active_rounded,
                title: 'Next',
                compact: compact,
                valueWidget: StreamBuilder<DateTime>(
                  stream: Stream<DateTime>.periodic(
                    const Duration(seconds: 1),
                    (_) => DateTime.now(),
                  ),
                  initialData: DateTime.now(),
                  builder: (context, snapshot) {
                    if (next?.jamatTime == null) {
                      return Text(
                        'Loading...',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    }
                    final now = snapshot.data ?? DateTime.now();
                    final timeLeft = next!.jamatTime!.difference(now);
                    return Text(
                      '${next.name} in ${_formatDuration(timeLeft)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: nowChip),
                  const SizedBox(width: 10),
                  Expanded(child: nextChip),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String title,
    String? value,
    Widget? valueWidget,
    bool compact = false,
  }) {
    assert(value != null || valueWidget != null);
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 10,
        compact ? 7 : 9,
        compact ? 8 : 10,
        compact ? 7 : 9,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: compact ? 15 : 17, color: Colors.white70),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                if (valueWidget != null)
                  valueWidget
                else
                  Text(
                    value!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterCard() {
    return Center(
      child: TextButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            AssetPdfViewerScreen.route(
              title: 'User Guide',
              assetPath: 'assets/pdfs/user_guide.pdf',
            ),
          );
        },
        icon: const Icon(
          Icons.picture_as_pdf_rounded,
          size: 18,
          color: _AppColors.primary,
        ),
        label: const Text(
          'User Guide',
          style: TextStyle(
            color: _AppColors.primary,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildRoleOrTrackerTile({required int index}) {
    if (widget.role == 'super_admin') {
      return _HomeGridCard(
        item: _GridItem(
          Icons.verified_user_rounded,
          'Approve Admins',
          _AppColors.danger,
          () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SuperAdminApprovalScreen(),
              ),
            );
          },
        ),
        index: index,
      );
    }
    if (widget.role == 'masjid_admin') {
      return _HomeGridCard(
        item: _GridItem(
          Icons.edit_calendar_rounded,
          'Update Timings',
          const Color(0xFF1976A8),
          () async {
            final prefs = await SharedPreferences.getInstance();
            final String? masjidId = prefs.getString('masjidId');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MasjidTimeSettingsScreen(
                  ownerMobile: widget.userMobile,
                  masjidId: (masjidId ?? '').trim().isEmpty ? null : masjidId,
                ),
              ),
            ).then((_) async {
              await _loadCachedJamatData();
              await _loadTodayFromCalendar(rescheduleAlarms: false);
              _tryCalculateAlternatives();
            });
          },
        ),
        index: index,
      );
    }

    return _HomeGridCard(
      item: _GridItem(
        Icons.bar_chart_rounded,
        'Salah Tracker',
        const Color(0xFF2E5BA8),
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalahAttendanceScreen()),
          );
        },
      ),
      index: index,
    );
  }

  Widget _buildSupportActionsCard({required int index}) {
    return _HomeGridCard(
      item: _GridItem(
        Icons.support_agent_rounded,
        'Contact Us',
        _AppColors.primary,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContactUsScreen()),
          );
        },
      ),
      index: index,
    );
  }

  String _fmtTime12H(DateTime dt) {
    int h = dt.hour;
    final String m = dt.minute.toString().padLeft(2, '0');
    final String period = h >= 12 ? 'PM' : 'AM';
    if (h > 12) h -= 12;
    if (h == 0) h = 12;
    return '$h:$m $period';
  }

  Future<void> _openAlternativeMasjidInMaps(Masjid masjid) async {
    double? lat = masjid.latitude;
    double? lng = masjid.longitude;

    if (lat == null || lng == null) {
      for (final m in _alternativeCandidates) {
        if (m.id == masjid.id ||
            _altCandidateKey(m.name, m.village) ==
                _altCandidateKey(masjid.name, masjid.village)) {
          lat ??= m.latitude;
          lng ??= m.longitude;
          if (lat != null && lng != null) break;
        }
      }
    }

    if ((lat == null || lng == null) &&
        _jamatData != null &&
        _jamatData!.id == masjid.id) {
      lat = _jamatData!.latitude;
      lng = _jamatData!.longitude;
    }

    // Backward compatibility for older snapshot docs that lack coordinates.
    if ((lat == null || lng == null) && masjid.id.trim().isNotEmpty) {
      final remote = await FirebaseDB.instance.getMasjidById(masjid.id);
      lat ??= remote?.latitude;
      lng ??= remote?.longitude;
    }

    await _launchMaps(lat, lng);
  }

  Future<void> _launchMaps(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location not available for this masjid.'),
        ),
      );
      return;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open maps.')));
    }
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: _AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child: const Text('Logout'),
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

// ─── Alternative Masjid Tile ──────────────────────────────────────────────────
class _AlternativeMasjidTile extends StatelessWidget {
  final Masjid masjid;
  final DateTime jamatTime;
  final bool isDefault;
  final String timeLabel;
  final VoidCallback onTap;

  const _AlternativeMasjidTile({
    required this.masjid,
    required this.jamatTime,
    required this.isDefault,
    required this.timeLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: _AppColors.danger.withOpacity(0.05),
        highlightColor: _AppColors.dangerSurface.withOpacity(0.5),
        child: SizedBox(
          height: 80,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDefault
                        ? _AppColors.primarySurface
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: isDefault
                        ? Border.all(
                            color: _AppColors.primary.withOpacity(0.25),
                            width: 1,
                          )
                        : null,
                  ),
                  child: Icon(
                    Icons.mosque_rounded,
                    size: 19,
                    color: isDefault ? _AppColors.primary : Colors.grey[400],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              masjid.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: _AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _AppColors.primary.withOpacity(0.35),
                                ),
                              ),
                              child: const Text(
                                'Home',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (masjid.colony != null && masjid.colony!.isNotEmpty)
                        Text(
                          masjid.colony!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _AppColors.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _AppColors.primary.withOpacity(0.18),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jamat',
                        style: TextStyle(
                          fontSize: 9,
                          color: _AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          color: _AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Grid Item Data ───────────────────────────────────────────────────────────
class _GridItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _GridItem(this.icon, this.label, this.color, this.onTap);
}

// ─── Home Grid Card ───────────────────────────────────────────────────────────
class _HomeGridCard extends StatefulWidget {
  final _GridItem item;
  final int index;
  const _HomeGridCard({required this.item, required this.index});

  @override
  State<_HomeGridCard> createState() => _HomeGridCardState();
}

class _HomeGridCardState extends State<_HomeGridCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color c = widget.item.color;
    final int delayMs = 40 * widget.index;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final slide = 14 * (1 - value);
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, slide), child: child),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => _pressController.forward(),
        onTapUp: (_) {
          _pressController.reverse();
          widget.item.onTap();
        },
        onTapCancel: () => _pressController.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bool isTight = constraints.maxWidth < 120;
              final double iconBox = isTight ? 24 : 28;
              final double iconSize = isTight ? 16 : 19;
              final double labelSize = isTight ? 9 : 10;
              final bool isMultiLine = widget.item.label.contains('\n');
              final double effectiveLabelSize = isMultiLine
                  ? (isTight ? 8 : 9)
                  : labelSize;

              return Container(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: _AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.withOpacity(0.13)),
                  boxShadow: [
                    BoxShadow(
                      color: c.withOpacity(0.10),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      Positioned(
                        top: -22,
                        right: -18,
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.withOpacity(0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: -24,
                        left: -14,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.withOpacity(0.04),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTight ? 2 : 3,
                          vertical: isTight ? 2 : 3,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: iconBox,
                                height: iconBox,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      c.withOpacity(0.18),
                                      c.withOpacity(0.08),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: c.withOpacity(0.2)),
                                ),
                                child: Icon(
                                  widget.item.icon,
                                  size: iconSize,
                                  color: c,
                                ),
                              ),
                              SizedBox(height: isTight ? 2 : 4),
                              Text(
                                widget.item.label,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                                style: TextStyle(
                                  fontSize: effectiveLabelSize,
                                  fontWeight: FontWeight.w700,
                                  color: _AppColors.textPrimary,
                                  letterSpacing: -0.1,
                                  height: 1.15,
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
            },
          ),
        ),
      ),
    );
  }
}

// ─── Data Class ───────────────────────────────────────────────────────────────
class _SalahSlot {
  final String name;
  final DateTime? jamatTime;
  const _SalahSlot({required this.name, required this.jamatTime});
}
