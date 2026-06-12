import 'dart:convert';
import 'package:flutter/material.dart';

import 'dua_item.dart';

class DuaDetailScreen extends StatelessWidget {
  final DuaItem dua;

  const DuaDetailScreen({super.key, required this.dua});

  String _normalizeInput(String input) {
    var s = input;
    s = s.replaceAll('â€™', "'");
    s = s.replaceAll('â€˜', "'");
    s = s.replaceAll('â€œ', '"');
    s = s.replaceAll('â€', '"');
    s = s.replaceAll('â€“', '-');
    s = s.replaceAll('â€”', '-');
    s = s.replaceAll('…', '...');
    s = s.replaceAll('’', "'");
    s = s.replaceAll('‘', "'");
    s = s.replaceAll('“', '"');
    s = s.replaceAll('”', '"');
    return s;
  }

  bool _looksLikeMojibake(String input) {
    return input.contains('Ø') ||
        input.contains('Ù') ||
        input.contains('Ã') ||
        input.contains('Â') ||
        input.contains('â');
  }

  bool _hasArabicChars(String input) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(input);
  }

  String _fixMojibakeArabic(String input) {
    if (!_looksLikeMojibake(input)) return input;
    try {
      final decoded = utf8.decode(latin1.encode(input));
      return _hasArabicChars(decoded) ? decoded : input;
    } catch (_) {
      return input;
    }
  }

  String _autoTeluguScript(String input) {
    final s = _normalizeInput(input);
    final buffer = StringBuffer();
    final wordBuffer = StringBuffer();

    bool isLetter(String ch) =>
        (ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90) ||
        (ch.codeUnitAt(0) >= 97 && ch.codeUnitAt(0) <= 122) ||
        ch == "'" ||
        ch == '’';

    void flushWord() {
      if (wordBuffer.isEmpty) return;
      buffer.write(_latinToTelugu(wordBuffer.toString()));
      wordBuffer.clear();
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (isLetter(ch)) {
        wordBuffer.write(ch);
      } else {
        flushWord();
        buffer.write(ch);
      }
    }
    flushWord();
    return buffer.toString();
  }

  String _latinToTelugu(String word) {
    final w = word.toLowerCase().replaceAll("'", '').replaceAll('’', '');

    const vowels = <String, String>{
      'a': 'అ',
      'aa': 'ఆ',
      'i': 'ఇ',
      'ii': 'ఈ',
      'ee': 'ఈ',
      'u': 'ఉ',
      'uu': 'ఊ',
      'oo': 'ఊ',
      'e': 'ఎ',
      'ai': 'ఐ',
      'o': 'ఒ',
      'au': 'ఔ',
    };

    const vowelMarks = <String, String>{
      'a': '',
      'aa': 'ా',
      'i': 'ి',
      'ii': 'ీ',
      'ee': 'ీ',
      'u': 'ు',
      'uu': 'ూ',
      'oo': 'ూ',
      'e': 'ె',
      'ai': 'ై',
      'o': 'ొ',
      'au': 'ౌ',
    };

    const consonants = <String, String>{
      'kh': 'ఖ',
      'gh': 'ఘ',
      'ch': 'చ',
      'sh': 'శ',
      'th': 'థ',
      'dh': 'ధ',
      'ph': 'ఫ',
      'bh': 'భ',
      'k': 'క',
      'g': 'గ',
      'j': 'జ',
      't': 'త',
      'd': 'ద',
      'n': 'న',
      'p': 'ప',
      'b': 'బ',
      'm': 'మ',
      'y': 'య',
      'r': 'ర',
      'l': 'ల',
      'v': 'వ',
      'w': 'వ',
      's': 'స',
      'h': 'హ',
      'f': 'ఫ',
      'q': 'క',
      'z': 'జ',
    };

    String matchAny(List<String> options, String src, int index) {
      for (final opt in options) {
        if (src.startsWith(opt, index)) return opt;
      }
      return '';
    }

    final vowelKeys = vowels.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final consonantKeys = consonants.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final out = StringBuffer();
    var i = 0;
    while (i < w.length) {
      final v = matchAny(vowelKeys, w, i);
      if (v.isNotEmpty) {
        out.write(vowels[v]);
        i += v.length;
        continue;
      }

      final c = matchAny(consonantKeys, w, i);
      if (c.isNotEmpty) {
        final base = consonants[c]!;
        i += c.length;
        final v2 = matchAny(vowelKeys, w, i);
        if (v2.isNotEmpty) {
          out.write(base);
          out.write(vowelMarks[v2]);
          i += v2.length;
        } else {
          out.write(base);
          out.write('్');
        }
        continue;
      }

      out.write(w[i]);
      i += 1;
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final String normalizedRomanEnglish = _normalizeInput(dua.romanEnglish);
    final String normalizedRomanTelugu =
        dua.romanTelugu == null ? '' : _normalizeInput(dua.romanTelugu!);
    final String fixedArabic = _fixMojibakeArabic(dua.arabic);
    final String arabicFontFamily =
        dua.arabicFontFamily ?? 'MuhammadiQuranic';
    return Scaffold(
      appBar: AppBar(title: Text(dua.title), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Arabic',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              fixedArabic,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 20,
                height: 1.6,
                fontFamily: arabicFontFamily,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Roman English',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              normalizedRomanEnglish,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Roman Telugu',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              normalizedRomanTelugu,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
