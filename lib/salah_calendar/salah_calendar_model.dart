// lib/salah_calendar/salah_calendar_model.dart

class SalahCalendarModel {
  final int month;
  final int day;

  final String sunrise;
  final String fajrAzan;
  final String fajrJamat;

  final String dhuhrAzan;
  final String dhuhrJamat;

  final String asrAzan;
  final String asrJamat;

  final String maghribAzan;
  final String maghribJamat;

  final String ishaAzan;
  final String ishaJamat;

  SalahCalendarModel({
    required this.month,
    required this.day,
    required this.sunrise,
    required this.fajrAzan,
    required this.fajrJamat,
    required this.dhuhrAzan,
    required this.dhuhrJamat,
    required this.asrAzan,
    required this.asrJamat,
    required this.maghribAzan,
    required this.maghribJamat,
    required this.ishaAzan,
    required this.ishaJamat,
  });

  factory SalahCalendarModel.fromMap(Map<String, dynamic> map) {
    return SalahCalendarModel(
      month: map['month'] ?? 0,
      day: map['start_day'] ?? 0,
      sunrise: map['sunrise'] ?? '',
      fajrAzan: map['fajr_start'] ?? '',
      fajrJamat: map['fajr_end'] ?? '',
      dhuhrAzan: map['zohar_start'] ?? '',
      dhuhrJamat: map['zohar_start'] ?? '', // temporary, no end column
      asrAzan: map['asar_start'] ?? '',
      asrJamat: map['asar_start'] ?? '', // temporary
      maghribAzan: map['maghrib_start'] ?? '',
      maghribJamat: map['maghrib_start'] ?? '', // temporary
      ishaAzan: map['isha_start'] ?? '',
      ishaJamat: map['isha_start'] ?? '', // temporary
    );
  }
}
