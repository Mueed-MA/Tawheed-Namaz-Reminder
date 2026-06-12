import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/masjid.dart';
import 'firebase_db.dart';
import 'masjid_timing_cache.dart';
import 'village_timing_snapshot_repository.dart';

class DefaultMasjidRepository {
  DefaultMasjidRepository._();
  static final DefaultMasjidRepository instance = DefaultMasjidRepository._();

  static const Duration _remoteCheckInterval = Duration(minutes: 15);
  static const String _refreshRequiredKey = '__default_masjid_refresh_required__';
  static const String _checkMetaPrefix = '__default_check__';
  static const String _snapshotVersionMetaPrefix = '__default_snapshot_version__';
  static const String _villageOffsetsCachePrefix = '__village_offsets__';

  final FirebaseDB _db = FirebaseDB.instance;
  final MasjidTimingCache _cache = MasjidTimingCache.instance;
  final VillageTimingSnapshotRepository _snapshotRepo =
      VillageTimingSnapshotRepository.instance;

  String _toVillageKey(String? village) {
    if (village == null) return '';
    return village.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _checkMetaKey(String masjidId) => '$_checkMetaPrefix$masjidId';
  String _snapshotVersionMetaKey(String villageKey) =>
      '$_snapshotVersionMetaPrefix$villageKey';
  String _villageOffsetsCacheKey(String villageKey) =>
      '$_villageOffsetsCachePrefix$villageKey';

  int _offsetInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _offsetDir(dynamic value) {
    final v = (value ?? '').toString().trim().toLowerCase();
    return v == 'more' ? 'more' : 'less';
  }

  Future<Masjid> _withVillageOffsets(Masjid base) async {
    final String villageKey = _toVillageKey(base.village);
    if (villageKey.isEmpty) return base;
    try {
      final cached = await _getCachedVillageOffsets(villageKey);
      if (cached != null) {
        return _applyVillageOffsets(base, cached);
      }
      final offsets = await _db.getVillageOffsets(villageKey);
      if (offsets == null) return base;
      await _cacheVillageOffsets(villageKey, offsets);
      return _applyVillageOffsets(base, offsets);
    } catch (_) {
      return base;
    }
  }

  Future<Map<String, dynamic>?> _getCachedVillageOffsets(
    String villageKey,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_villageOffsetsCacheKey(villageKey));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheVillageOffsets(
    String villageKey,
    Map<String, dynamic> offsets,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalized = <String, dynamic>{
        'sunriseOffsetMinutes': _offsetInt(offsets['sunriseOffsetMinutes']),
        'sunriseOffsetDirection': _offsetDir(offsets['sunriseOffsetDirection']),
        'sunsetOffsetMinutes': _offsetInt(offsets['sunsetOffsetMinutes']),
        'sunsetOffsetDirection': _offsetDir(offsets['sunsetOffsetDirection']),
      };
      await prefs.setString(
        _villageOffsetsCacheKey(villageKey),
        jsonEncode(normalized),
      );
    } catch (_) {
      // Best-effort cache; ignore failures.
    }
  }

  Masjid _applyVillageOffsets(Masjid base, Map<String, dynamic> offsets) {
    final int sunriseMinutes = _offsetInt(offsets['sunriseOffsetMinutes']);
    final int sunsetMinutes = _offsetInt(offsets['sunsetOffsetMinutes']);
    final String sunriseDir = _offsetDir(offsets['sunriseOffsetDirection']);
    final String sunsetDir = _offsetDir(offsets['sunsetOffsetDirection']);

    return Masjid(
      id: base.id,
      name: base.name,
      isApproved: base.isApproved,
      geoHash: base.geoHash,
      ownerMobile: base.ownerMobile,
      isTimingConfigured: base.isTimingConfigured,
      salahs: base.salahs,
      address: base.address,
      latitude: base.latitude,
      longitude: base.longitude,
      state: base.state,
      district: base.district,
      mandal: base.mandal,
      village: base.village,
      colony: base.colony,
      fajr: base.fajr,
      dhuhr: base.dhuhr,
      asr: base.asr,
      maghrib: base.maghrib,
      isha: base.isha,
      juma: base.juma,
      fajr_azan: base.fajr_azan,
      fajr_jamat: base.fajr_jamat,
      dhuhr_azan: base.dhuhr_azan,
      dhuhr_jamat: base.dhuhr_jamat,
      asar_azan: base.asar_azan,
      asar_jamat: base.asar_jamat,
      maghrib_azan: base.maghrib_azan,
      maghrib_jamat: base.maghrib_jamat,
      isha_azan: base.isha_azan,
      isha_jamat: base.isha_jamat,
      juma_azan: base.juma_azan,
      juma_jamat: base.juma_jamat,
      sunriseOffsetMinutes: sunriseMinutes,
      sunriseOffsetDirection: sunriseDir,
      sunsetOffsetMinutes: sunsetMinutes,
      sunsetOffsetDirection: sunsetDir,
    );
  }

  Future<void> markRefreshRequired() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_refreshRequiredKey, true);
  }

  Future<Masjid?> getLocalDefaultMasjid({
    required String userMobile,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final String? defaultMasjidId = prefs.getString('cached_default_masjid_id');
    if (defaultMasjidId != null && defaultMasjidId.isNotEmpty) {
      final local = await _cache.getMasjidById(defaultMasjidId);
      if (local != null) {
        final resolved = await _withVillageOffsets(local);
        await _cache.upsertMasjids(_toVillageKey(resolved.village), [resolved]);
        return resolved;
      }
    }
    final fallback = await _cache.getAnyConfiguredMasjid();
    if (fallback == null) return null;
    final resolved = await _withVillageOffsets(fallback);
    await _cache.upsertMasjids(_toVillageKey(resolved.village), [resolved]);
    return resolved;
  }

  Future<Masjid?> getDefaultMasjid({
    required String userMobile,
    bool forceRefresh = false,
    bool pushTriggered = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    String? defaultMasjidId = prefs.getString('cached_default_masjid_id');
    final bool refreshRequired = prefs.getBool(_refreshRequiredKey) ?? false;

    if (defaultMasjidId == null || defaultMasjidId.isEmpty) {
      defaultMasjidId = await _db.getDefaultMasjidId(userMobile);
      if (defaultMasjidId != null && defaultMasjidId.isNotEmpty) {
        await prefs.setString('cached_default_masjid_id', defaultMasjidId);
      }
    }

    Masjid? local;
    if (defaultMasjidId != null && defaultMasjidId.isNotEmpty) {
      local = await _cache.getMasjidById(defaultMasjidId);
    }
    local ??= await _cache.getAnyConfiguredMasjid();

    bool shouldRefreshRemote = forceRefresh || pushTriggered || refreshRequired;
    if (!shouldRefreshRemote &&
        defaultMasjidId != null &&
        defaultMasjidId.isNotEmpty) {
      final int? lastCheckMs = await _cache.getLastSyncMs(
        _checkMetaKey(defaultMasjidId),
      );
      if (lastCheckMs == null) {
        shouldRefreshRemote = true;
      } else {
        final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckMs);
        shouldRefreshRemote =
            DateTime.now().difference(lastCheck) >= _remoteCheckInterval;
      }
    }

    if (!shouldRefreshRemote && local != null) {
      final resolved = await _withVillageOffsets(local);
      await _persistLocal(
        prefs: prefs,
        masjid: resolved,
        updatedAtMs: null,
        keepExistingUpdatedAt: true,
      );
      return resolved;
    }

    // Snapshot-first refresh to avoid direct masjid doc read where possible.
    Masjid? fromSnapshot;
    final String villageKey = _toVillageKey(local?.village);
    if (villageKey.isNotEmpty) {
      final snapshot = await _snapshotRepo.getSnapshotForVillage(
        villageKey,
        forceRefresh: pushTriggered || forceRefresh,
      );
      if (snapshot != null) {
        await _cache.setLastSyncMs(
          _snapshotVersionMetaKey(villageKey),
          snapshot.version,
        );
        final candidates = snapshot.toMasjids();
        final String targetId = (defaultMasjidId ?? local?.id ?? '').trim();
        if (targetId.isNotEmpty) {
          for (final m in candidates) {
            if (m.id.trim() == targetId) {
              fromSnapshot = _mergeWithLocal(base: m, local: local);
              break;
            }
          }
        }
      }
    }

    Masjid? remote;
    int? remoteUpdatedAtMs;
    if (defaultMasjidId != null && defaultMasjidId.isNotEmpty) {
      await _cache.setLastSyncMs(
        _checkMetaKey(defaultMasjidId),
        DateTime.now().millisecondsSinceEpoch,
      );

      final int? cachedUpdatedMs = prefs.getInt('cached_default_masjid_updated_ms');
      if (forceRefresh || pushTriggered || refreshRequired || cachedUpdatedMs == null) {
        final fetched = await _db.getMasjidWithMetaById(defaultMasjidId);
        if (fetched != null) {
          remote = fetched['masjid'] as Masjid?;
          remoteUpdatedAtMs = fetched['updatedAtMs'] as int?;
        }
      } else {
        final changed = await _db.getMasjidWithMetaByIdIfUpdatedAfter(
          masjidId: defaultMasjidId,
          updatedAfter: DateTime.fromMillisecondsSinceEpoch(cachedUpdatedMs),
        );
        if (changed != null) {
          remote = changed['masjid'] as Masjid?;
          remoteUpdatedAtMs = changed['updatedAtMs'] as int?;
        }
      }
    }

    Masjid? resolved = remote ?? fromSnapshot ?? local;

    if (resolved != null) {
      resolved = await _withVillageOffsets(resolved);
    }

    if (resolved != null) {
      await _persistLocal(
        prefs: prefs,
        masjid: resolved,
        updatedAtMs: remoteUpdatedAtMs,
        keepExistingUpdatedAt: remoteUpdatedAtMs == null,
      );
      await prefs.setBool(_refreshRequiredKey, false);
      return resolved;
    }

    // Bounded fallback path.
    final Masjid? userDefault = await _db.getUserDefaultMasjid(userMobile);
    if (userDefault != null) {
      await _persistLocal(prefs: prefs, masjid: userDefault, updatedAtMs: null);
      await prefs.setBool(_refreshRequiredKey, false);
      return userDefault;
    }

    if (defaultMasjidId == null || defaultMasjidId.isEmpty) {
      final Masjid? any = await _db.getAnyApprovedMasjid();
      if (any != null) {
        await _persistLocal(prefs: prefs, masjid: any, updatedAtMs: null);
      }
      await prefs.setBool(_refreshRequiredKey, false);
      return any;
    }

    await prefs.setBool(_refreshRequiredKey, false);
    return null;
  }

  Future<void> persistDefaultMasjid(
    Masjid masjid, {
    int? updatedAtMs,
    bool setAsDefault = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _persistLocal(
      prefs: prefs,
      masjid: masjid,
      updatedAtMs: updatedAtMs,
      setAsDefault: setAsDefault,
    );
  }

  Future<void> _persistLocal({
    required SharedPreferences prefs,
    required Masjid masjid,
    int? updatedAtMs,
    bool setAsDefault = true,
    bool keepExistingUpdatedAt = false,
  }) async {
    final String villageKey = _toVillageKey(masjid.village);
    await _cache.upsertMasjids(villageKey, [masjid]);
    if (setAsDefault) {
      await prefs.setString('cached_default_masjid_id', masjid.id);
    }
    if (updatedAtMs != null) {
      await prefs.setInt('cached_default_masjid_updated_ms', updatedAtMs);
    } else if (!keepExistingUpdatedAt) {
      await prefs.remove('cached_default_masjid_updated_ms');
    }
  }

  Masjid _mergeWithLocal({required Masjid base, Masjid? local}) {
    if (local == null) return base;
    return Masjid(
      id: base.id,
      name: base.name.isNotEmpty ? base.name : local.name,
      isApproved: base.isApproved,
      geoHash: local.geoHash,
      ownerMobile: local.ownerMobile,
      isTimingConfigured: base.isTimingConfigured,
      salahs: local.salahs,
      address: (local.address ?? '').isNotEmpty ? local.address : base.address,
      latitude: local.latitude,
      longitude: local.longitude,
      state: (local.state ?? '').isNotEmpty ? local.state : base.state,
      district: (local.district ?? '').isNotEmpty ? local.district : base.district,
      mandal: (local.mandal ?? '').isNotEmpty ? local.mandal : base.mandal,
      village: (local.village ?? '').isNotEmpty ? local.village : base.village,
      colony: local.colony,
      fajr: local.fajr,
      dhuhr: local.dhuhr,
      asr: local.asr,
      maghrib: local.maghrib,
      isha: local.isha,
      juma: local.juma,
      fajr_azan: base.fajr_azan,
      fajr_jamat: base.fajr_jamat,
      dhuhr_azan: base.dhuhr_azan,
      dhuhr_jamat: base.dhuhr_jamat,
      asar_azan: base.asar_azan,
      asar_jamat: base.asar_jamat,
      maghrib_azan: base.maghrib_azan,
      maghrib_jamat: base.maghrib_jamat,
      isha_azan: base.isha_azan,
      isha_jamat: base.isha_jamat,
      juma_azan: base.juma_azan,
      juma_jamat: base.juma_jamat,
      sunriseOffsetMinutes: local.sunriseOffsetMinutes ?? base.sunriseOffsetMinutes,
      sunriseOffsetDirection:
          (local.sunriseOffsetDirection ?? '').isNotEmpty
              ? local.sunriseOffsetDirection
              : base.sunriseOffsetDirection,
      sunsetOffsetMinutes: local.sunsetOffsetMinutes ?? base.sunsetOffsetMinutes,
      sunsetOffsetDirection:
          (local.sunsetOffsetDirection ?? '').isNotEmpty
              ? local.sunsetOffsetDirection
              : base.sunsetOffsetDirection,
    );
  }
}
