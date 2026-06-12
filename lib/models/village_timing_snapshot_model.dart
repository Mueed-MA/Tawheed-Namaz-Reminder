import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

import 'masjid.dart';

class VillageTimingEntry {
  final String masjidId;
  final String name;
  final String village;
  final String fajrAzan;
  final String fajrJamat;
  final String dhuhrAzan;
  final String dhuhrJamat;
  final String asarAzan;
  final String asarJamat;
  final String maghribAzan;
  final String maghribJamat;
  final String ishaAzan;
  final String ishaJamat;
  final String jumaAzan;
  final String jumaJamat;
  final double? latitude;
  final double? longitude;

  const VillageTimingEntry({
    required this.masjidId,
    required this.name,
    required this.village,
    required this.fajrAzan,
    required this.fajrJamat,
    required this.dhuhrAzan,
    required this.dhuhrJamat,
    required this.asarAzan,
    required this.asarJamat,
    required this.maghribAzan,
    required this.maghribJamat,
    required this.ishaAzan,
    required this.ishaJamat,
    required this.jumaAzan,
    required this.jumaJamat,
    required this.latitude,
    required this.longitude,
  });

  factory VillageTimingEntry.fromMap(Map<String, dynamic> map) {
    String gs(String key) => map[key]?.toString() ?? '';
    double? gd(String key) {
      final dynamic raw = map[key];
      if (raw is double) return raw;
      if (raw is int) return raw.toDouble();
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw.trim());
      return null;
    }
    return VillageTimingEntry(
      masjidId: gs('masjidId'),
      name: gs('name'),
      village: gs('village'),
      fajrAzan: gs('fajr_azan'),
      fajrJamat: gs('fajr_jamat'),
      dhuhrAzan: gs('dhuhr_azan'),
      dhuhrJamat: gs('dhuhr_jamat'),
      asarAzan: gs('asar_azan'),
      asarJamat: gs('asar_jamat'),
      maghribAzan: gs('maghrib_azan'),
      maghribJamat: gs('maghrib_jamat'),
      ishaAzan: gs('isha_azan'),
      ishaJamat: gs('isha_jamat'),
      jumaAzan: gs('juma_azan'),
      jumaJamat: gs('juma_jamat'),
      latitude: gd('latitude'),
      longitude: gd('longitude'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'masjidId': masjidId,
      'name': name,
      'village': village,
      'fajr_azan': fajrAzan,
      'fajr_jamat': fajrJamat,
      'dhuhr_azan': dhuhrAzan,
      'dhuhr_jamat': dhuhrJamat,
      'asar_azan': asarAzan,
      'asar_jamat': asarJamat,
      'maghrib_azan': maghribAzan,
      'maghrib_jamat': maghribJamat,
      'isha_azan': ishaAzan,
      'isha_jamat': ishaJamat,
      'juma_azan': jumaAzan,
      'juma_jamat': jumaJamat,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  Masjid toMasjid() {
    return Masjid(
      id: masjidId,
      name: name,
      village: village,
      latitude: latitude,
      longitude: longitude,
      isApproved: true,
      isTimingConfigured: 1,
      fajr_azan: fajrAzan,
      fajr_jamat: fajrJamat,
      dhuhr_azan: dhuhrAzan,
      dhuhr_jamat: dhuhrJamat,
      asar_azan: asarAzan,
      asar_jamat: asarJamat,
      maghrib_azan: maghribAzan,
      maghrib_jamat: maghribJamat,
      isha_azan: ishaAzan,
      isha_jamat: ishaJamat,
      juma_azan: jumaAzan,
      juma_jamat: jumaJamat,
    );
  }
}

class VillageTimingSnapshotModel {
  final String villageKey;
  final String villageName;
  final int activeMasjidCount;
  final int version;
  final DateTime? updatedAt;
  final DateTime cacheTimestamp;
  final List<VillageTimingEntry> timings;

  const VillageTimingSnapshotModel({
    required this.villageKey,
    required this.villageName,
    required this.activeMasjidCount,
    required this.version,
    required this.updatedAt,
    required this.cacheTimestamp,
    required this.timings,
  });

  factory VillageTimingSnapshotModel.fromFirestoreDoc(
    String villageKey,
    Map<String, dynamic> data, {
    DateTime? cacheTimestamp,
  }
  ) {
    final dynamic rawUpdatedAt = data['updatedAt'];
    final DateTime? updatedAt = rawUpdatedAt is Timestamp
        ? rawUpdatedAt.toDate()
        : null;
    final dynamic rawTimings = data['timings'];
    final List<VillageTimingEntry> timings = (rawTimings is List)
        ? rawTimings
              .whereType<Map>()
              .map((e) => VillageTimingEntry.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : <VillageTimingEntry>[];

    return VillageTimingSnapshotModel(
      villageKey: villageKey,
      villageName: data['villageName']?.toString() ?? '',
      activeMasjidCount: _toInt(data['activeMasjidCount']),
      version: _toInt(data['version']),
      updatedAt: updatedAt,
      cacheTimestamp: cacheTimestamp ?? DateTime.now(),
      timings: timings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'villageKey': villageKey,
      'villageName': villageName,
      'activeMasjidCount': activeMasjidCount,
      'version': version,
      'updatedAtMs': updatedAt?.millisecondsSinceEpoch,
      'cacheTimestampMs': cacheTimestamp.millisecondsSinceEpoch,
      'timings': timings.map((e) => e.toMap()).toList(),
    };
  }

  factory VillageTimingSnapshotModel.fromJson(Map<dynamic, dynamic> map) {
    final dynamic rawUpdatedAt = map['updatedAtMs'];
    final DateTime? updatedAt = rawUpdatedAt is int
        ? DateTime.fromMillisecondsSinceEpoch(rawUpdatedAt)
        : null;
    final dynamic rawCacheTimestamp = map['cacheTimestampMs'];
    final DateTime cacheTimestamp = rawCacheTimestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(rawCacheTimestamp)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final dynamic rawTimings = map['timings'];
    final List<VillageTimingEntry> timings = (rawTimings is List)
        ? rawTimings
              .whereType<Map>()
              .map((e) => VillageTimingEntry.fromMap(Map<String, dynamic>.from(e)))
              .toList()
        : <VillageTimingEntry>[];

    return VillageTimingSnapshotModel(
      villageKey: map['villageKey']?.toString() ?? '',
      villageName: map['villageName']?.toString() ?? '',
      activeMasjidCount: _toInt(map['activeMasjidCount']),
      version: _toInt(map['version']),
      updatedAt: updatedAt,
      cacheTimestamp: cacheTimestamp,
      timings: timings,
    );
  }

  List<Masjid> toMasjids() => timings.map((e) => e.toMasjid()).toList();

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class VillageTimingSnapshotModelAdapter
    extends TypeAdapter<VillageTimingSnapshotModel> {
  @override
  final int typeId = 40;

  @override
  VillageTimingSnapshotModel read(BinaryReader reader) {
    final map = reader.readMap();
    return VillageTimingSnapshotModel.fromJson(map);
  }

  @override
  void write(BinaryWriter writer, VillageTimingSnapshotModel obj) {
    writer.writeMap(obj.toJson());
  }
}
