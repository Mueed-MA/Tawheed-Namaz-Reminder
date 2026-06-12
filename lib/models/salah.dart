class Salah {
  final int id;
  final String name;
  final String azanTime;
  final String jamatTime;
  final String endTime;

  Salah({
    required this.id,
    required this.name,
    required this.azanTime,
    required this.jamatTime,
    required this.endTime,
  });

  /// Factory constructor to create a Salah instance from a map (e.g., from Firebase).
  /// Assumes the data from Firebase for a salah looks something like:
  /// { 'id': 1, 'name': 'Fajr', 'azanTime': '05:00', 'jamatTime': '05:30', 'endTime': '06:15' }
  factory Salah.fromMap(Map<String, dynamic> map) {
    return Salah(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: map['name'] as String? ?? '',
      azanTime: map['azanTime'] as String? ?? '',
      jamatTime: map['jamatTime'] as String? ?? '',
      endTime: map['endTime'] as String? ?? '',
    );
  }
}
