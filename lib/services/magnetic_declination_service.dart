import 'package:flutter/services.dart';

class MagneticDeclinationService {
  MagneticDeclinationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.tawheed.namazreminder/qibla',
  );

  static Future<double> getDeclination({
    required double latitude,
    required double longitude,
    required double altitude,
    required DateTime timestamp,
  }) async {
    try {
      final double? value = await _channel.invokeMethod<double>(
        'getMagneticDeclination',
        <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'altitude': altitude,
          'timeMillis': timestamp.millisecondsSinceEpoch,
        },
      );
      return value ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }
}
