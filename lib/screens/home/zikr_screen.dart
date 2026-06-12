import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> _tasbihOptions = [
  'Teesra Kalma',
  'Astagfar',
  'Durood',
  'Custom 1',
  'Custom 2',
];

class ZikrScreen extends StatefulWidget {
  const ZikrScreen({super.key});

  @override
  State<ZikrScreen> createState() => _ZikrScreenState();
}

class _ZikrScreenState extends State<ZikrScreen> {
  static const String _prefsPrefix = 'zikr_count_';
  static const String _prefsTargetPrefix = 'zikr_target_';

  int _count = 0;
  int _target = 1000;
  bool _vibrateEnabled = true;
  bool _soundEnabled = true;
  final TextEditingController _custom1Controller = TextEditingController();
  final TextEditingController _custom2Controller = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  String _selectedTasbih = 'Teesra Kalma';
  final AudioPlayer _tapPlayer = AudioPlayer();
  Map<String, int> _countsByZikr = {};
  Map<String, int> _targetsByZikr = {};

  String _prefsKeyFor(String tasbih) => '$_prefsPrefix$tasbih';
  String _prefsTargetKeyFor(String tasbih) => '$_prefsTargetPrefix$tasbih';

  Future<void> _loadCounts() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, int> counts = {
      for (final option in _tasbihOptions)
        option: prefs.getInt(_prefsKeyFor(option)) ?? 0,
    };
    final Map<String, int> targets = {
      for (final option in _tasbihOptions)
        option: prefs.getInt(_prefsTargetKeyFor(option)) ?? _target,
    };
    final int savedTarget = targets[_selectedTasbih] ?? _target;

    if (!mounted) return;
    setState(() {
      _countsByZikr = counts;
      _targetsByZikr = targets;
      _count = counts[_selectedTasbih] ?? 0;
      _target = savedTarget;
    });
    _targetController.text = savedTarget.toString();
  }

  Future<void> _persistCount(String tasbih, int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsKeyFor(tasbih), count);
  }

  Future<void> _persistTarget(String tasbih, int target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsTargetKeyFor(tasbih), target);
  }

  Future<void> _editTarget() async {
    _targetController.text = _target.toString();
    final int? updatedTarget = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Target'),
          content: TextField(
            controller: _targetController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter target (e.g. 1000)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final parsed = int.tryParse(_targetController.text.trim());
                if (parsed == null || parsed <= 0) {
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updatedTarget == null) return;
    setState(() {
      _target = updatedTarget;
      _targetsByZikr[_selectedTasbih] = updatedTarget;
    });
    await _persistTarget(_selectedTasbih, updatedTarget);
  }

  Future<void> _handleTap() async {
    setState(() {
      _count += 1;
      _countsByZikr[_selectedTasbih] = _count;
    });
    await _persistCount(_selectedTasbih, _count);

    if (_vibrateEnabled) {
      await _triggerVibration();
    }
    if (_soundEnabled) {
      await _playTapSound();
    }
  }

  Future<void> _triggerVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) {
        await HapticFeedback.mediumImpact();
        return;
      }
      final hasCustom = await Vibration.hasCustomVibrationsSupport() ?? false;
      if (hasCustom) {
        Vibration.vibrate(pattern: [0, 40], intensities: [0, 255]);
      } else {
        Vibration.vibrate(duration: 40);
      }
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  Future<void> _playTapSound() async {
    try {
      await _tapPlayer.stop();
      await _tapPlayer.play(AssetSource('audio/tap.wav'), volume: 1.0);
    } catch (_) {
      // Fallback: at least give a haptic tick if audio fails.
      await HapticFeedback.selectionClick();
    }
  }

  @override
  void initState() {
    super.initState();
    _tapPlayer.setReleaseMode(ReleaseMode.stop);
    _tapPlayer.setPlayerMode(PlayerMode.lowLatency);
    _tapPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          stayAwake: false,
          isSpeakerphoneOn: false,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
        ),
      ),
    );
    _loadCounts();
  }

  @override
  void dispose() {
    _custom1Controller.dispose();
    _custom2Controller.dispose();
    _targetController.dispose();
    _tapPlayer.dispose();
    super.dispose();
  }

  String _effectiveTasbihLabel() {
    if (_selectedTasbih == 'Custom 1') {
      final text = _custom1Controller.text.trim();
      return text.isEmpty ? 'Custom 1' : text;
    }
    if (_selectedTasbih == 'Custom 2') {
      final text = _custom2Controller.text.trim();
      return text.isEmpty ? 'Custom 2' : text;
    }
    return _selectedTasbih;
  }

  String? _effectiveTasbihSubtitle() {
    if (_selectedTasbih == 'Custom 1' || _selectedTasbih == 'Custom 2') {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String tasbihLabel = _effectiveTasbihLabel();
    final String? tasbihSubtitle = _effectiveTasbihSubtitle();
    final double keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardOpen = keyboardInset > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _ZikrColors.bg,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double width = constraints.maxWidth;
              final double height =
                  (constraints.maxHeight - keyboardInset).clamp(
                    0.0,
                    constraints.maxHeight,
                  );
              final double ringSize = math
                  .min(width * 0.78, height * (isKeyboardOpen ? 0.34 : 0.46))
                  .clamp(isKeyboardOpen ? 180.0 : 230.0, 360.0);
              final double progress = (_count / _target)
                  .clamp(0.0, 1.0)
                  .toDouble();

              return Stack(
                children: [
                  const _ZikrBackground(),
                  AnimatedPadding(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(bottom: keyboardInset),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.only(bottom: 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_rounded),
                                    color: _ZikrColors.gold,
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  const Expanded(
                                    child: Center(
                                      child: Text(
                                        'Zikr Counter',
                                        style: TextStyle(
                                          color: _ZikrColors.gold,
                                          fontSize: 18,
                                          letterSpacing: 0.6,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _ZikrHeader(
                              title: tasbihLabel,
                              subtitle: tasbihSubtitle,
                            ),
                            SizedBox(height: isKeyboardOpen ? 8 : 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: _TasbihPicker(
                                selected: _selectedTasbih,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _selectedTasbih = value;
                                    _count = _countsByZikr[value] ?? 0;
                                    _target = _targetsByZikr[value] ?? _target;
                                  });
                                  _targetController.text = _target.toString();
                                },
                              ),
                            ),
                            if (_selectedTasbih == 'Custom 1')
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24,
                                  right: 24,
                                  top: 10,
                                ),
                                child: _CustomTasbihField(
                                  label: 'Custom 1',
                                  controller: _custom1Controller,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            if (_selectedTasbih == 'Custom 2')
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 24,
                                  right: 24,
                                  top: 10,
                                ),
                                child: _CustomTasbihField(
                                  label: 'Custom 2',
                                  controller: _custom2Controller,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            SizedBox(height: isKeyboardOpen ? 12 : 8),
                            Center(
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: _handleTap,
                                child: SizedBox(
                                  width: ringSize,
                                  height: ringSize,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      CustomPaint(
                                        size: Size.square(ringSize),
                                        painter: _BeadsPainter(),
                                      ),
                                      Container(
                                        width: ringSize * 0.72,
                                        height: ringSize * 0.72,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const RadialGradient(
                                            colors: [
                                              Color(0xFF1A2A1F),
                                              Color(0xFF0B1410),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: _ZikrColors.gold,
                                            width: 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: _ZikrColors.gold
                                                  .withOpacity(0.28),
                                              blurRadius: 22,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              '$_count',
                                              style: TextStyle(
                                                color: _ZikrColors.gold,
                                                fontSize:
                                                    isKeyboardOpen ? 44 : 56,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Tap anywhere\nto count',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: _ZikrColors.goldSoft,
                                                fontSize:
                                                    isKeyboardOpen ? 12 : 13,
                                                height: 1.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: isKeyboardOpen ? 10 : 6),
                            Text(
                              'Target: $_target',
                              style: const TextStyle(
                                color: _ZikrColors.goldSoft,
                                fontSize: 13,
                                letterSpacing: 0.4,
                              ),
                            ),
                            TextButton(
                              onPressed: _editTarget,
                              child: const Text(
                                'Change target',
                                style: TextStyle(
                                  color: _ZikrColors.gold,
                                  fontSize: 12,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 10,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 10,
                                  backgroundColor: _ZikrColors.progressTrack,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        _ZikrColors.gold,
                                      ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _ZikrActionButton(
                                    icon: Icons.refresh_rounded,
                                    label: 'Reset',
                                    onTap: () async {
                                      setState(() {
                                        _count = 0;
                                        _countsByZikr[_selectedTasbih] = 0;
                                      });
                                      await _persistCount(_selectedTasbih, 0);
                                    },
                                  ),
                                  _ZikrActionButton(
                                    icon: Icons.vibration_rounded,
                                    label: 'Vibrate',
                                    isOn: _vibrateEnabled,
                                    onTap: () => setState(
                                      () => _vibrateEnabled = !_vibrateEnabled,
                                    ),
                                  ),
                                  _ZikrActionButton(
                                    icon: Icons.volume_up_rounded,
                                    label: 'Sound',
                                    isOn: _soundEnabled,
                                    onTap: () => setState(
                                      () => _soundEnabled = !_soundEnabled,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ZikrHeader extends StatelessWidget {
  const _ZikrHeader({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF1C3B2A), Color(0xFF0D1E16)],
                  ),
                  border: Border.all(color: _ZikrColors.gold, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: _ZikrColors.gold.withOpacity(0.3),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.mosque_rounded,
                color: _ZikrColors.gold,
                size: 34,
              ),
              const Positioned(
                right: 2,
                top: 6,
                child: Icon(
                  Icons.nights_stay_rounded,
                  color: _ZikrColors.goldSoft,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            color: _ZikrColors.gold,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(color: _ZikrColors.goldSoft, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _TasbihPicker extends StatelessWidget {
  const _TasbihPicker({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _ZikrColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _ZikrColors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          dropdownColor: _ZikrColors.surface,
          iconEnabledColor: _ZikrColors.gold,
          style: const TextStyle(
            color: _ZikrColors.goldSoft,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
          items: _tasbihOptions
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _CustomTasbihField extends StatelessWidget {
  const _CustomTasbihField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: _ZikrColors.goldSoft, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _ZikrColors.goldSoft),
        filled: true,
        fillColor: _ZikrColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _ZikrColors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _ZikrColors.gold),
        ),
      ),
      cursorColor: _ZikrColors.gold,
    );
  }
}

class _ZikrActionButton extends StatelessWidget {
  const _ZikrActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isOn,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool? isOn;

  @override
  Widget build(BuildContext context) {
    final bool showToggle = isOn != null;
    final bool enabled = isOn ?? false;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 82,
            decoration: BoxDecoration(
              color: _ZikrColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _ZikrColors.surfaceBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: _ZikrColors.gold),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: _ZikrColors.goldSoft,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                if (showToggle) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: enabled
                          ? _ZikrColors.toggleOn
                          : _ZikrColors.toggleOff,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      enabled ? 'ON' : 'OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZikrBackground extends StatelessWidget {
  const _ZikrBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1812), Color(0xFF0A120E), Color(0xFF0A0F0B)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _ZikrColors.gold.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _ZikrColors.emerald.withOpacity(0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BeadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width * 0.42;
    final beadRadius = size.width * 0.035;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..color = _ZikrColors.gold.withOpacity(0.55);

    canvas.drawCircle(center, radius, ringPaint);

    for (int i = 0; i < 36; i++) {
      final angle = (2 * math.pi / 36) * i;
      final offset = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final bool highlight = i % 6 == 0;
      final Paint beadPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            highlight ? _ZikrColors.gold : _ZikrColors.beadLight,
            highlight ? _ZikrColors.goldDark : _ZikrColors.beadDark,
          ],
        ).createShader(Rect.fromCircle(center: offset, radius: beadRadius));

      canvas.drawCircle(offset, beadRadius, beadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZikrColors {
  static const Color bg = Color(0xFF08100C);
  static const Color surface = Color(0xFF0F1913);
  static const Color surfaceBorder = Color(0xFF2A3328);
  static const Color gold = Color(0xFFD9B86C);
  static const Color goldSoft = Color(0xFFC6AE83);
  static const Color goldDark = Color(0xFF8C6A2A);
  static const Color beadLight = Color(0xFF2E5D4A);
  static const Color beadDark = Color(0xFF163628);
  static const Color progressTrack = Color(0xFF233127);
  static const Color toggleOn = Color(0xFF3C6A3C);
  static const Color toggleOff = Color(0xFF5A2E2A);
  static const Color emerald = Color(0xFF2E5F4B);
}
