import 'dart:math';

class GeoHashUtils {
  GeoHashUtils._();

  static const String _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  static const double _earthRadiusKm = 6371.0;

  static String encode(
    double latitude,
    double longitude, {
    int precision = 6,
  }) {
    final StringBuffer geohash = StringBuffer();
    List<double> latRange = [-90.0, 90.0];
    List<double> lonRange = [-180.0, 180.0];

    bool evenBit = true;
    int bit = 0;
    int ch = 0;

    while (geohash.length < precision) {
      if (evenBit) {
        final double mid = (lonRange[0] + lonRange[1]) / 2;
        if (longitude >= mid) {
          ch |= 1 << (4 - bit);
          lonRange = [mid, lonRange[1]];
        } else {
          lonRange = [lonRange[0], mid];
        }
      } else {
        final double mid = (latRange[0] + latRange[1]) / 2;
        if (latitude >= mid) {
          ch |= 1 << (4 - bit);
          latRange = [mid, latRange[1]];
        } else {
          latRange = [latRange[0], mid];
        }
      }

      evenBit = !evenBit;
      if (bit < 4) {
        bit++;
      } else {
        geohash.write(_base32[ch]);
        bit = 0;
        ch = 0;
      }
    }

    return geohash.toString();
  }

  static double haversineKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    final double dLat = _toRadians(toLat - fromLat);
    final double dLng = _toRadians(toLng - fromLng);
    final double a =
        pow(sin(dLat / 2), 2).toDouble() +
        cos(_toRadians(fromLat)) *
            cos(_toRadians(toLat)) *
            pow(sin(dLng / 2), 2).toDouble();
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static Set<String> buildGeoHashPrefixesForRadius({
    required double latitude,
    required double longitude,
    required double radiusKm,
    int prefixLength = 5,
  }) {
    // Query only center cell + 8 directional boundary cells.
    const List<double> bearings = [0, 45, 90, 135, 180, 225, 270, 315];
    final Set<String> prefixes = {
      encode(latitude, longitude, precision: prefixLength),
    };
    for (final bearing in bearings) {
      final p = _destinationPoint(
        latitude: latitude,
        longitude: longitude,
        distanceKm: radiusKm,
        bearingDegrees: bearing,
      );
      prefixes.add(encode(p.latitude, p.longitude, precision: prefixLength));
    }
    return prefixes;
  }

  static _GeoPoint _destinationPoint({
    required double latitude,
    required double longitude,
    required double distanceKm,
    required double bearingDegrees,
  }) {
    final double angularDistance = distanceKm / _earthRadiusKm;
    final double bearing = _toRadians(bearingDegrees);
    final double lat1 = _toRadians(latitude);
    final double lon1 = _toRadians(longitude);

    final double sinLat1 = sin(lat1);
    final double cosLat1 = cos(lat1);
    final double sinAd = sin(angularDistance);
    final double cosAd = cos(angularDistance);

    final double lat2 =
        asin(sinLat1 * cosAd + cosLat1 * sinAd * cos(bearing));
    final double lon2 =
        lon1 +
        atan2(
          sin(bearing) * sinAd * cosLat1,
          cosAd - sinLat1 * sin(lat2),
        );

    final double normalizedLon = ((lon2 + pi) % (2 * pi)) - pi;
    return _GeoPoint(
      latitude: _toDegrees(lat2),
      longitude: _toDegrees(normalizedLon),
    );
  }

  static double _toRadians(double value) => value * (pi / 180.0);
  static double _toDegrees(double value) => value * (180.0 / pi);
}

class _GeoPoint {
  final double latitude;
  final double longitude;

  const _GeoPoint({required this.latitude, required this.longitude});
}
