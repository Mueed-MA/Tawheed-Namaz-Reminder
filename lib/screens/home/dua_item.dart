class DuaItem {
  final String title;
  final String arabic;
  final String romanEnglish;
  final String? romanTelugu;
  final String? arabicFontFamily;

  const DuaItem({
    required this.title,
    required this.arabic,
    required this.romanEnglish,
    this.romanTelugu,
    this.arabicFontFamily = 'MuhammadiQuranic',
  });
}
