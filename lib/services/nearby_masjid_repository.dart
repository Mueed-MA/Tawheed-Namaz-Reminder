import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/masjid.dart';
import 'firebase_read_counter.dart';
import 'geo_hash_utils.dart';
import 'location_service.dart';

class NearbyMasjidRepository {
  NearbyMasjidRepository._();
  static final NearbyMasjidRepository instance = NearbyMasjidRepository._();

  static const double _searchRadiusKm = 10.0;
  static const double _cacheRefreshDistanceMeters = 2500.0;
  static const Duration _cacheTtl = Duration(minutes: 60);
  static const Duration _minRefetchGap = Duration(minutes: 5);
  static const String _cacheKey = 'nearby_masjids_cache_v2';
  static const int _queryPrefixLength = 4;
  static const int _maxDocsPerPrefix = 150;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<NearbyMasjidResult> fetchNearbyMasjids({
    bool forceRefresh = false,
  }) async {
    final Position position = await LocationService.instance.getCurrentPosition();
    final DateTime now = DateTime.now();

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final _NearbyMasjidCache? cached = _readCache(prefs);

    debugPrint(
      'NearbyMasjid: pos=${position.latitude},${position.longitude} '
      'force=$forceRefresh cacheItems=${cached?.items.length ?? 0}',
    );

    if (!forceRefresh && cached != null) {
      final bool tooSoonToRefetch =
          now.difference(cached.cachedAt) < _minRefetchGap;
      final bool isExpired = now.difference(cached.cachedAt) > _cacheTtl;
      final double movedMeters = GeoHashUtils.haversineKm(
            fromLat: cached.centerLat,
            fromLng: cached.centerLng,
            toLat: position.latitude,
            toLng: position.longitude,
          ) *
          1000.0;

      final bool cacheLooksThin = cached.items.length <= 1;
      if ((tooSoonToRefetch && !cacheLooksThin) ||
          (!cacheLooksThin &&
              !isExpired &&
              movedMeters <= _cacheRefreshDistanceMeters)) {
        debugPrint(
          'NearbyMasjid: using cache '
          'items=${cached.items.length} moved=${movedMeters.toStringAsFixed(0)}m '
          'age=${now.difference(cached.cachedAt).inMinutes}m',
        );
        return NearbyMasjidResult(
          userLatitude: position.latitude,
          userLongitude: position.longitude,
          userGeoHash6: GeoHashUtils.encode(
            position.latitude,
            position.longitude,
            precision: 6,
          ),
          items: cached.items,
          fromCache: true,
          fetchedAt: cached.cachedAt,
          queriedPrefixes: const [],
          fetchedDocumentCount: 0,
          uniqueCandidateCount: cached.items.length,
        );
      }
    }

    final String userGeoHash6 = GeoHashUtils.encode(
      position.latitude,
      position.longitude,
      precision: 6,
    );

    final Set<String> prefixes = GeoHashUtils.buildGeoHashPrefixesForRadius(
      latitude: position.latitude,
      longitude: position.longitude,
      radiusKm: _searchRadiusKm,
      prefixLength: _queryPrefixLength,
    );
    debugPrint(
      'NearbyMasjid: prefixes=${prefixes.length} '
      'radiusKm=$_searchRadiusKm prefixLen=$_queryPrefixLength',
    );

    final Map<String, Masjid> masjidById = {};
    int fetchedDocumentCount = 0;
    int missingCoords = 0;

    try {
      final ReadCounter counter = CompositeReadCounter(
        FirebaseReadCounter.instance,
        FirebaseNearbyReadCounter.instance,
      );
      final List<QuerySnapshot<Map<String, dynamic>>> snapshots = await Future.wait([
        ...prefixes.map(
          (prefix) => _firestore
              .collection('masjids')
              .where('approved', isEqualTo: true)
              .orderBy('geoHash')
              .startAt([prefix])
              .endAt(['$prefix\uf8ff'])
              .limit(_maxDocsPerPrefix)
              .getCountedWith(counter),
        ),
        ...prefixes.map(
          (prefix) => _firestore
              .collection('masjids')
              .where('approvalStatus', isEqualTo: 'approved')
              .orderBy('geoHash')
              .startAt([prefix])
              .endAt(['$prefix\uf8ff'])
              .limit(_maxDocsPerPrefix)
              .getCountedWith(counter),
        ),
      ]);

      for (final snapshot in snapshots) {
        fetchedDocumentCount += snapshot.docs.length;
        for (final doc in snapshot.docs) {
          final Masjid? masjid = _safeMasjid(doc);
          if (masjid == null) continue;
          masjidById[masjid.id] = masjid;
        }
      }
    } on FirebaseException catch (e) {
      // Missing composite index for approved + geoHash range query.
      // Fallback keeps feature functional until index is created.
      if (e.code != 'failed-precondition') rethrow;
      // Avoid full collection scan to keep reads low.
      if (cached != null) {
        return NearbyMasjidResult(
          userLatitude: position.latitude,
          userLongitude: position.longitude,
          userGeoHash6: userGeoHash6,
          items: cached.items,
          fromCache: true,
          fetchedAt: cached.cachedAt,
          queriedPrefixes: const [],
          fetchedDocumentCount: 0,
          uniqueCandidateCount: cached.items.length,
        );
      }
      rethrow;
    }

    final List<NearbyMasjidItem> nearbyItems = masjidById.values
        .where((m) => m.latitude != null && m.longitude != null)
        .map((m) {
          final double distanceKm = GeoHashUtils.haversineKm(
            fromLat: position.latitude,
            fromLng: position.longitude,
            toLat: m.latitude!,
            toLng: m.longitude!,
          );
          return NearbyMasjidItem(masjid: m, distanceKm: distanceKm);
        })
        .where((item) => item.distanceKm <= _searchRadiusKm)
        .toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    missingCoords = masjidById.values
        .where((m) => m.latitude == null || m.longitude == null)
        .length;
    debugPrint(
      'NearbyMasjid: fetched=$fetchedDocumentCount unique=${masjidById.length} '
      'missingCoords=$missingCoords within=${nearbyItems.length}',
    );

    await _saveCache(
      prefs,
      centerLat: position.latitude,
      centerLng: position.longitude,
      cachedAt: now,
      items: nearbyItems,
    );

    return NearbyMasjidResult(
      userLatitude: position.latitude,
      userLongitude: position.longitude,
      userGeoHash6: userGeoHash6,
      items: nearbyItems,
      fromCache: false,
      fetchedAt: now,
      queriedPrefixes: prefixes.toList()..sort(),
      fetchedDocumentCount: fetchedDocumentCount,
      uniqueCandidateCount: masjidById.length,
    );
  }

  Masjid? _safeMasjid(DocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      return Masjid.fromMap(doc.data() ?? const {}, doc.id);
    } catch (_) {
      return null;
    }
  }

  _NearbyMasjidCache? _readCache(SharedPreferences prefs) {
    final String? raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final Map<String, dynamic> payload =
          jsonDecode(raw) as Map<String, dynamic>;

      final int cachedAtMs = payload['cachedAtMs'] as int? ?? 0;
      final double centerLat = (payload['centerLat'] as num?)?.toDouble() ?? 0;
      final double centerLng = (payload['centerLng'] as num?)?.toDouble() ?? 0;
      final List<dynamic> list = payload['items'] as List<dynamic>? ?? const [];

      final List<NearbyMasjidItem> items = list
          .whereType<Map<String, dynamic>>()
          .map((entry) {
            final Map<String, dynamic> masjidMap =
                Map<String, dynamic>.from(entry['masjid'] as Map);
            final String id = masjidMap['id'] as String? ?? '';
            final Masjid masjid = Masjid.fromMap(masjidMap, id);
            final double distanceKm =
                (entry['distanceKm'] as num?)?.toDouble() ?? 0;
            return NearbyMasjidItem(masjid: masjid, distanceKm: distanceKm);
          })
          .toList()
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

      return _NearbyMasjidCache(
        cachedAt: DateTime.fromMillisecondsSinceEpoch(cachedAtMs),
        centerLat: centerLat,
        centerLng: centerLng,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(
    SharedPreferences prefs, {
    required double centerLat,
    required double centerLng,
    required DateTime cachedAt,
    required List<NearbyMasjidItem> items,
  }) async {
    final Map<String, dynamic> payload = {
      'cachedAtMs': cachedAt.millisecondsSinceEpoch,
      'centerLat': centerLat,
      'centerLng': centerLng,
      'items': items
          .map((item) => {
                'distanceKm': item.distanceKm,
                'masjid': item.masjid.toMap(),
              })
          .toList(),
    };
    await prefs.setString(_cacheKey, jsonEncode(payload));
  }
}

class NearbyMasjidItem {
  final Masjid masjid;
  final double distanceKm;

  const NearbyMasjidItem({required this.masjid, required this.distanceKm});
}

class NearbyMasjidResult {
  final double userLatitude;
  final double userLongitude;
  final String userGeoHash6;
  final List<NearbyMasjidItem> items;
  final bool fromCache;
  final DateTime fetchedAt;
  final List<String> queriedPrefixes;
  final int fetchedDocumentCount;
  final int uniqueCandidateCount;

  const NearbyMasjidResult({
    required this.userLatitude,
    required this.userLongitude,
    required this.userGeoHash6,
    required this.items,
    required this.fromCache,
    required this.fetchedAt,
    required this.queriedPrefixes,
    required this.fetchedDocumentCount,
    required this.uniqueCandidateCount,
  });
}

class _NearbyMasjidCache {
  final DateTime cachedAt;
  final double centerLat;
  final double centerLng;
  final List<NearbyMasjidItem> items;

  const _NearbyMasjidCache({
    required this.cachedAt,
    required this.centerLat,
    required this.centerLng,
    required this.items,
  });
}
