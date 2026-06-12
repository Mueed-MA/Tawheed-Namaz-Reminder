import 'package:my_masjid_two/models/salah.dart';

class Masjid {
  final String id;
  final String name;
  final String? geoHash;
  final String? ownerMobile;
  final dynamic isTimingConfigured;
  final bool isApproved;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? state;
  final String? district;
  final String? mandal;
  final String? village;
  final String? colony;
  final String? fajr;
  final String? dhuhr;
  final String? asr;
  final String? maghrib;
  final String? isha;
  final String? juma;
  final String? fajr_azan;
  final String? fajr_jamat;
  final String? dhuhr_azan;
  final String? dhuhr_jamat;
  final String? asar_azan;
  final String? asar_jamat;
  final String? maghrib_azan;
  final String? maghrib_jamat;
  final String? isha_azan;
  final String? isha_jamat;
  final String? juma_azan;
  final String? juma_jamat;
  final int? sunriseOffsetMinutes;
  final String? sunriseOffsetDirection;
  final int? sunsetOffsetMinutes;
  final String? sunsetOffsetDirection;
  final List<Salah>? salahs;

  Masjid({
    required this.id,
    required this.name,
    required this.isApproved,
    this.geoHash,
    this.ownerMobile,
    this.isTimingConfigured,
    this.salahs,
    this.address,
    this.latitude,
    this.longitude,
    this.state,
    this.district,
    this.mandal,
    this.village,
    this.colony,
    this.fajr,
    this.dhuhr,
    this.asr,
    this.maghrib,
    this.isha,
    this.juma,
    this.fajr_azan,
    this.fajr_jamat,
    this.dhuhr_azan,
    this.dhuhr_jamat,
    this.asar_azan,
    this.asar_jamat,
    this.maghrib_azan,
    this.maghrib_jamat,
    this.isha_azan,
    this.isha_jamat,
    this.juma_azan,
    this.juma_jamat,
    this.sunriseOffsetMinutes,
    this.sunriseOffsetDirection,
    this.sunsetOffsetMinutes,
    this.sunsetOffsetDirection,
  });

  /// Factory constructor to create a Masjid instance from a map (e.g., from Firebase).
  /// [id] is the document ID from Firestore or key from Realtime Database.
  /// The 'salahs' field in Firebase can be a List of salah maps or a Map of salah maps.
  factory Masjid.fromMap(Map<String, dynamic> map, String id) {
    List<Salah>? salahList;
    if (map['salahs'] != null) {
      if (map['salahs'] is Map) {
        final salahsMap = map['salahs'] as Map<String, dynamic>;
        salahList = salahsMap.values
            .map(
              (salahData) => Salah.fromMap(salahData as Map<String, dynamic>),
            )
            .toList();
      } else if (map['salahs'] is List) {
        salahList = (map['salahs'] as List)
            .map(
              (salahData) => Salah.fromMap(salahData as Map<String, dynamic>),
            )
            .toList();
      }
      salahList?.sort((a, b) => a.id.compareTo(b.id));
    }

    // Helper for safe type casting from any numeric type or a string.
    double? toDouble(dynamic val) {
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    int? toInt(dynamic val) {
      if (val is int) return val;
      if (val is double) return val.round();
      if (val is String) return int.tryParse(val.trim());
      return null;
    }

    return Masjid(
      id: id,
      name: map['name'] as String? ?? '',
      ownerMobile: map['ownerMobile'] as String?,
      geoHash: map['geoHash'] as String?,
      isApproved: map['approved'] as bool? ?? false,
      isTimingConfigured: map['isTimingConfigured'],
      salahs: salahList,
      address: map['address'] as String?,
      latitude: toDouble(map['latitude']),
      longitude: toDouble(map['longitude']),
      state: map['state'] as String?,
      district: map['district'] as String?,
      mandal: map['mandal'] as String?,
      village: map['village'] as String?,
      colony: map['colony'] as String?,
      fajr: map['fajr'] as String?,
      dhuhr: map['dhuhr'] as String?,
      asr: map['asar'] as String?,
      maghrib: map['maghrib'] as String?,
      isha: map['isha'] as String?,
      juma: map['juma'] as String?,
      fajr_azan: map['fajr_azan'] as String?,
      fajr_jamat: map['fajr_jamat'] as String?,
      dhuhr_azan: map['dhuhr_azan'] as String?,
      dhuhr_jamat: map['dhuhr_jamat'] as String?,
      asar_azan: map['asar_azan'] as String?,
      asar_jamat: map['asar_jamat'] as String?,
      maghrib_azan: map['maghrib_azan'] as String?,
      maghrib_jamat: map['maghrib_jamat'] as String?,
      isha_azan: map['isha_azan'] as String?,
      isha_jamat: map['isha_jamat'] as String?,
      juma_azan: map['juma_azan'] as String?,
      juma_jamat: map['juma_jamat'] as String?,
      sunriseOffsetMinutes: toInt(map['sunriseOffsetMinutes']),
      sunriseOffsetDirection: map['sunriseOffsetDirection'] as String?,
      sunsetOffsetMinutes: toInt(map['sunsetOffsetMinutes']),
      sunsetOffsetDirection: map['sunsetOffsetDirection'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'geoHash': geoHash,
      'ownerMobile': ownerMobile,
      'approved': isApproved,
      'isTimingConfigured': isTimingConfigured,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'state': state,
      'district': district,
      'mandal': mandal,
      'village': village,
      'colony': colony,
      'fajr': fajr,
      'dhuhr': dhuhr,
      'asar': asr,
      'maghrib': maghrib,
      'isha': isha,
      'juma': juma,
      'fajr_azan': fajr_azan,
      'fajr_jamat': fajr_jamat,
      'dhuhr_azan': dhuhr_azan,
      'dhuhr_jamat': dhuhr_jamat,
      'asar_azan': asar_azan,
      'asar_jamat': asar_jamat,
      'maghrib_azan': maghrib_azan,
      'maghrib_jamat': maghrib_jamat,
      'isha_azan': isha_azan,
      'isha_jamat': isha_jamat,
      'juma_azan': juma_azan,
      'juma_jamat': juma_jamat,
      'sunriseOffsetMinutes': sunriseOffsetMinutes,
      'sunriseOffsetDirection': sunriseOffsetDirection,
      'sunsetOffsetMinutes': sunsetOffsetMinutes,
      'sunsetOffsetDirection': sunsetOffsetDirection,
    };
  }
}
