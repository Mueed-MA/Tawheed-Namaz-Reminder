import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';

// ══════════════════════════════════════════════════════════════
//  DESIGN TOKENS
// ══════════════════════════════════════════════════════════════
class _C {
  static const bg = Color(0xFF060E08);
  static const surface = Color(0xFF0D1F12);
  static const dialBg = Color(0xFF0A180D);
  static const gold = Color(0xFFC9963A);
  static const goldLight = Color(0xFFE8BE6A);
  static const cream = Color(0xFFF0E6CC);
  static const creamFaint = Color(0x55F0E6CC);
  static const green = Color(0xFF27AE60);
  static const greenGlow = Color(0x3327AE60);
  static const red = Color(0xFFE05252);
}

// ══════════════════════════════════════════════════════════════
//  SCREEN
// ══════════════════════════════════════════════════════════════
class QiblaCompassScreen extends StatefulWidget {
  const QiblaCompassScreen({super.key});
  @override
  State<QiblaCompassScreen> createState() => _QiblaCompassScreenState();
}

class _QiblaCompassScreenState extends State<QiblaCompassScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const double _fixedQiblaDirection = 270.0;

  bool _hasPermissions = false;
  bool _locationDisabled = false;
  double? _qiblaDirection;
  double? _smoothedHeading;
  double? _compassAccuracy;
  String _statusMessage = 'Initialising…';
  Stream<CompassEvent>? _compassStream;

  bool _wasAligned = false;
  DateTime? _lastHapticAt;
  static const _hapticCooldown = Duration(seconds: 3);

  late final AnimationController _ringCtrl;
  late final AnimationController _kaabaPulseCtrl;
  late final AnimationController _fadeInCtrl;
  late final Animation<double> _ringAnim;
  late final Animation<double> _kaabaPulse;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _kaabaPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeInCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _ringAnim = Tween<double>(
      begin: 0.94,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _ringCtrl, curve: Curves.easeInOut));
    _kaabaPulse = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _kaabaPulseCtrl, curve: Curves.easeInOut),
    );
    _fadeIn = CurvedAnimation(parent: _fadeInCtrl, curve: Curves.easeOut);

    _fadeInCtrl.forward();
    _initQibla();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ringCtrl.dispose();
    _kaabaPulseCtrl.dispose();
    _fadeInCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _initQibla();
  }

  // ── Permissions + location ─────────────────────────────────
  Future<void> _initQibla() async {
    setState(() {
      _statusMessage = 'Checking permissions…';
      _hasPermissions = false;
      _locationDisabled = false;
      _smoothedHeading = null;
      _compassAccuracy = null;
    });

    bool svcEnabled = await Geolocator.isLocationServiceEnabled();
    if (!svcEnabled) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Location services are disabled.';
          _locationDisabled = true;
        });
        _showLocationDialog();
      }
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        setState(() => _statusMessage = 'Location permission denied.');
        return;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      setState(
        () => _statusMessage = 'Location permission permanently denied.',
      );
      return;
    }

    setState(() => _statusMessage = 'Locating you…');
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final qibla = _fixedQiblaDirection;
      if (mounted) {
        setState(() {
          _hasPermissions = true;
          _qiblaDirection = qibla;
          _compassStream = FlutterCompass.events;
          _statusMessage = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusMessage = 'Error: $e');
    }
  }

  void _showLocationDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Location Disabled',
          style: TextStyle(color: _C.cream, fontFamily: 'Georgia'),
        ),
        content: const Text(
          'Enable location services so we can calculate your Qibla direction.',
          style: TextStyle(
            color: _C.creamFaint,
            fontFamily: 'Georgia',
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _C.gold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: _C.gold),
            ),
          ),
        ],
      ),
    );
  }

  double _normalizeHeading(double heading) {
    final normalized = heading % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  double _deltaAngle(double from, double to) {
    return ((to - from + 540) % 360) - 180;
  }

  String _bearingLabel(double bearing) {
    const labels = <String>[
      'North',
      'North-Northeast',
      'Northeast',
      'East-Northeast',
      'East',
      'East-Southeast',
      'Southeast',
      'South-Southeast',
      'South',
      'South-Southwest',
      'Southwest',
      'West-Southwest',
      'West',
      'West-Northwest',
      'Northwest',
      'North-Northwest',
    ];
    final index = (((bearing % 360) + 11.25) ~/ 22.5) % labels.length;
    return labels[index];
  }

  double _smoothHeading(double heading) {
    if (_smoothedHeading == null) {
      _smoothedHeading = heading;
      return heading;
    }

    final delta = _deltaAngle(_smoothedHeading!, heading);
    _smoothedHeading = _normalizeHeading(_smoothedHeading! + (delta * 0.18));
    return _smoothedHeading!;
  }

  double _resolveTrueHeading(double rawHeading) {
    return _normalizeHeading(rawHeading);
  }

  // ── Alignment + haptic ─────────────────────────────────────
  void _onAlignment(bool aligned) {
    if (aligned == _wasAligned) return;
    _wasAligned = aligned;
    if (aligned) {
      _ringCtrl.repeat(reverse: true);
      _kaabaPulseCtrl.repeat(reverse: true);
      _triggerHaptic();
    } else {
      _ringCtrl.stop();
      _ringCtrl.reset();
      _kaabaPulseCtrl.stop();
      _kaabaPulseCtrl.reset();
    }
  }

  Future<void> _triggerHaptic() async {
    final now = DateTime.now();
    if (_lastHapticAt != null &&
        now.difference(_lastHapticAt!) < _hapticCooldown) {
      return;
    }
    _lastHapticAt = now;

    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (!hasVibrator) {
        HapticFeedback.heavyImpact();
        return;
      }
      final hasAmplitude = await Vibration.hasAmplitudeControl();
      if (hasAmplitude) {
        // pattern: [wait, vibrate, wait, vibrate]
        // intensities: value per segment (0 = silent, 255 = max)
        Vibration.vibrate(
          pattern: [0, 150, 100, 300],
          intensities: [0, 200, 0, 255],
        );
      } else {
        Vibration.vibrate(pattern: [0, 150, 100, 300]);
      }
    } catch (_) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      HapticFeedback.heavyImpact();
    }
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _C.bg,
        body: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _AmbientBgPainter())),
            FadeTransition(
              opacity: _fadeIn,
              child: _hasPermissions ? _buildCompass() : _buildPermState(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermState() {
    return SafeArea(
      child: Column(
        children: [
          _topBar(),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _KaabaWidget(
                      size: 90,
                      color: _C.gold,
                      glowColor: _C.gold.withOpacity(0.15),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _C.creamFaint,
                        fontFamily: 'Georgia',
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                    if (_locationDisabled) ...[
                      const SizedBox(height: 36),
                      _GoldPillButton(
                        label: 'Enable Location',
                        onTap: Geolocator.openLocationSettings,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    return StreamBuilder<CompassEvent>(
      stream: _compassStream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              'Compass error: ${snap.error}',
              style: const TextStyle(color: _C.cream),
            ),
          );
        }
        final event = snap.data;
        final rawHeading = event?.heading ?? event?.headingForCameraMode;

        if (!snap.hasData || rawHeading == null || rawHeading.isNaN) {
          return const Center(child: CircularProgressIndicator(color: _C.gold));
        }

        _compassAccuracy = event?.accuracy;
        final double heading = _smoothHeading(_resolveTrueHeading(rawHeading));
        final double offset = ((_qiblaDirection! - heading) % 360 + 360) % 360;
        final bool aligned = offset < 4 || offset > 356;
        _onAlignment(aligned);

        return SafeArea(
          child: Column(
            children: [
              _topBar(),
              const SizedBox(height: 10),
              _statusChip(aligned),
              const SizedBox(height: 16),
              Expanded(child: Center(child: _buildDial(heading, aligned))),
              _buildMetricsRow(heading),
              const SizedBox(height: 12),
              _buildTip(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  // ── Top bar ────────────────────────────────────────────────
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        children: [
          _ornamentRow(),
          const Spacer(),
          Column(
            children: [
              const Text(
                'QIBLA',
                style: TextStyle(
                  color: _C.cream,
                  fontFamily: 'Georgia',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'COMPASS',
                style: TextStyle(
                  color: _C.gold.withOpacity(0.65),
                  fontFamily: 'Georgia',
                  fontSize: 9,
                  letterSpacing: 5,
                ),
              ),
            ],
          ),
          const Spacer(),
          Transform.flip(flipX: true, child: _ornamentRow()),
        ],
      ),
    );
  }

  Widget _ornamentRow() => Row(
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.gold),
      ),
      const SizedBox(width: 6),
      Container(width: 22, height: 1, color: _C.gold.withOpacity(0.4)),
    ],
  );

  // ── Status chip ────────────────────────────────────────────
  Widget _statusChip(bool aligned) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: aligned ? _C.greenGlow : Colors.white.withOpacity(0.05),
        border: Border.all(
          color: aligned
              ? _C.green.withOpacity(0.5)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            aligned ? Icons.check_circle_rounded : Icons.cached_rounded,
            size: 13,
            color: aligned ? _C.green : _C.creamFaint,
          ),
          const SizedBox(width: 8),
          Text(
            aligned ? '  Facing the Kaaba  ' : '  Rotate to find Qibla  ',
            style: TextStyle(
              color: aligned ? _C.green : _C.creamFaint,
              fontFamily: 'Georgia',
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Dial ──────────────────────────────────────────────────
  Widget _buildDial(double heading, bool aligned) {
    const double dialSize = 296;

    return AnimatedBuilder(
      animation: Listenable.merge([_ringAnim, _kaabaPulse]),
      builder: (_, __) {
        return SizedBox(
          width: dialSize + 60,
          height: dialSize + 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer glow ring when aligned
              if (aligned)
                Transform.scale(
                  scale: _ringAnim.value * 1.25,
                  child: Container(
                    width: dialSize + 28,
                    height: dialSize + 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _C.green.withOpacity(0.35 * _ringAnim.value),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _C.green.withOpacity(0.12 * _ringAnim.value),
                          blurRadius: 40,
                          spreadRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),

              // Static outer decorative ring
              Container(
                width: dialSize + 16,
                height: dialSize + 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: aligned
                        ? _C.green.withOpacity(0.40)
                        : _C.gold.withOpacity(0.20),
                    width: 1,
                  ),
                ),
              ),

              // Main compass disc
              Container(
                width: dialSize,
                height: dialSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.dialBg,
                  border: Border.all(
                    color: aligned
                        ? _C.green.withOpacity(0.55)
                        : _C.gold.withOpacity(0.40),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.7),
                      blurRadius: 32,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: _C.gold.withOpacity(0.05),
                      blurRadius: 16,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating dial
                      Transform.rotate(
                        angle: -heading * math.pi / 180,
                        child: SizedBox(
                          width: dialSize,
                          height: dialSize,
                          child: CustomPaint(painter: _DialPainter()),
                        ),
                      ),
                      // Qibla needle
                      Transform.rotate(
                        angle: _deltaAngle(heading, _qiblaDirection!) *
                            math.pi /
                            180,
                        child: SizedBox(
                          width: dialSize,
                          height: dialSize,
                          child: _buildNeedle(aligned, dialSize),
                        ),
                      ),
                      // Center jewel
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: aligned ? _C.green : _C.gold,
                          boxShadow: [
                            BoxShadow(
                              color: (aligned ? _C.green : _C.gold).withOpacity(
                                0.7,
                              ),
                              blurRadius: 12,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Kaaba badge — floats above dial when aligned
              AnimatedPositioned(
                duration: const Duration(milliseconds: 600),
                curve: Curves.elasticOut,
                top: aligned ? 4 : 30,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: aligned ? 1.0 : 0.0,
                  child: Transform.scale(
                    scale: aligned ? _kaabaPulse.value : 1.0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: _C.bg,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _C.green.withOpacity(0.55),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _C.green.withOpacity(0.30),
                            blurRadius: 22,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _KaabaWidget(
                            size: 24,
                            color: _C.green,
                            glowColor: Colors.transparent,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Qibla',
                            style: TextStyle(
                              color: _C.green,
                              fontFamily: 'Georgia',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Needle ─────────────────────────────────────────────────
  Widget _buildNeedle(bool aligned, double dialSize) {
    final color = aligned ? _C.green : _C.gold;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Kaaba icon at tip
        Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: _KaabaWidget(
              size: 36,
              color: color,
              glowColor: color.withOpacity(0.35),
            ),
          ),
        ),
        // Shaft
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 58),
            width: 3.5,
            height: dialSize * 0.29,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color, color.withOpacity(0.0)],
              ),
              boxShadow: [
                BoxShadow(color: color.withOpacity(0.5), blurRadius: 10),
              ],
            ),
          ),
        ),
        // Arrowhead
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 52),
            child: CustomPaint(
              size: const Size(18, 14),
              painter: _ArrowPainter(color: color),
            ),
          ),
        ),
      ],
    );
  }

  // ── Metrics ────────────────────────────────────────────────
  Widget _buildMetricsRow(double heading) {
    final offset = ((_qiblaDirection! - heading) % 360 + 360) % 360;
    final qiblaLabel = _bearingLabel(_qiblaDirection!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          _metric(
            'QIBLA',
            '${_qiblaDirection!.toStringAsFixed(1)}°\n$qiblaLabel',
          ),
          const SizedBox(width: 10),
          _metric('HEADING', '${heading.toStringAsFixed(1)}°'),
          const SizedBox(width: 10),
          _metric(
            _compassAccuracy == null ? 'OFFSET' : 'ACC',
            _compassAccuracy == null
                ? '${offset.toStringAsFixed(1)}°'
                : '±${_compassAccuracy!.toStringAsFixed(0)}°',
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.gold.withOpacity(0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: _C.gold.withOpacity(0.5),
                fontSize: 8,
                letterSpacing: 2,
                fontFamily: 'Georgia',
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _C.cream,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                fontFamily: 'Georgia',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: _C.gold.withOpacity(0.35),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _compassAccuracy != null && _compassAccuracy! > 15
                  ? 'Compass accuracy is low. Move phone in a figure-eight away from metal objects.'
                  : '',
              style: TextStyle(
                color: _C.creamFaint.withOpacity(0.45),
                fontSize: 11,
                fontFamily: 'Georgia',
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  KAABA WIDGET
// ══════════════════════════════════════════════════════════════
class _KaabaWidget extends StatelessWidget {
  final double size;
  final Color color;
  final Color glowColor;
  const _KaabaWidget({
    required this.size,
    required this.color,
    required this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: glowColor, blurRadius: size * 0.55, spreadRadius: 2),
        ],
      ),
      child: CustomPaint(painter: _KaabaPainter(color: color)),
    );
  }
}

class _KaabaPainter extends CustomPainter {
  final Color color;
  const _KaabaPainter({required this.color});

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    final h = s.height;

    // ── Cube geometry ───────────────────────────────────────
    final side = w * 0.50;
    final hSide = side * 0.56; // right face width foreshortened
    final vOff = side * 0.38; // right face height reduction

    final cx = w * 0.48;
    final cy = h * 0.56;

    // Front face (rectangle)
    final fl = Offset(cx - side / 2, cy);
    final fr = Offset(cx + side / 2, cy);
    final tl = Offset(cx - side / 2, cy - side);
    final tr = Offset(cx + side / 2, cy - side);

    // Right face
    final rr = Offset(fr.dx + hSide, cy - vOff);
    final tr2 = Offset(tr.dx + hSide, cy - side - vOff);

    // Top face
    final tl2 = Offset(tl.dx + hSide, cy - side - vOff);

    // ── Paints ───────────────────────────────────────────────
    final strokeW = w * 0.042;

    Paint filled(double opacity) => Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;

    Paint stroked({double? width}) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width ?? strokeW
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // ── 1. Filled faces ─────────────────────────────────────
    canvas.drawPath(_quad(fl, fr, tr, tl), filled(0.12)); // front
    canvas.drawPath(_quad(fr, rr, tr2, tr), filled(0.07)); // right
    canvas.drawPath(_quad(tl, tr, tr2, tl2), filled(0.17)); // top

    // ── 2. Outline ──────────────────────────────────────────
    canvas.drawPath(_quad(fl, fr, tr, tl), stroked());
    canvas.drawPath(_quad(fr, rr, tr2, tr), stroked());
    canvas.drawPath(_quad(tl, tr, tr2, tl2), stroked());

    // ── 3. Kiswa bands ──────────────────────────────────────
    final bandPaint = stroked(width: strokeW * 0.65)
      ..color = color.withOpacity(0.55);

    for (final f in [0.35, 0.52]) {
      // Front band
      final y = tl.dy + (fl.dy - tl.dy) * f;
      canvas.drawLine(Offset(fl.dx, y), Offset(fr.dx, y), bandPaint);
      // Right band (projected)
      final yF = fr.dy + (rr.dy - fr.dy) * f;
      final yT = tr.dy + (tr2.dy - tr.dy) * f;
      canvas.drawLine(
        Offset(fr.dx, y),
        Offset(rr.dx, yF + (yT - yF) * 0),
        bandPaint,
      );
    }

    // ── 4. Arched door ──────────────────────────────────────
    final dW = side * 0.30;
    final dH = side * 0.38;
    final dL = cx - dW / 2;
    final dB = fl.dy - side * 0.04;
    final dT = dB - dH;
    final aR = dW / 2;

    final doorPath = Path()
      ..moveTo(dL, dB)
      ..lineTo(dL, dT + aR)
      ..arcToPoint(
        Offset(dL + dW, dT + aR),
        radius: Radius.circular(aR),
        clockwise: false,
      )
      ..lineTo(dL + dW, dB)
      ..close();

    canvas.drawPath(doorPath, filled(0.20));
    canvas.drawPath(doorPath, stroked(width: strokeW * 0.80));

    // Door centre line
    canvas.drawLine(
      Offset(cx, dT + aR),
      Offset(cx, dB),
      stroked(width: strokeW * 0.40)..color = color.withOpacity(0.45),
    );

    // ── 5. Hajar al-Aswad dot ───────────────────────────────
    canvas.drawCircle(
      Offset(fl.dx + w * 0.048, fl.dy - side * 0.16),
      w * 0.034,
      filled(0.95),
    );
  }

  Path _quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  @override
  bool shouldRepaint(_KaabaPainter o) => o.color != color;
}

// ══════════════════════════════════════════════════════════════
//  DIAL PAINTER — Islamic geometric compass rose
// ══════════════════════════════════════════════════════════════
class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final cx = s.width / 2;
    final cy = s.height / 2;
    final r = s.width / 2;

    // Background rings
    for (final frac in [0.90, 0.72, 0.50]) {
      canvas.drawCircle(
        Offset(cx, cy),
        r * frac,
        Paint()
          ..color = _C.gold.withOpacity(frac == 0.90 ? 0.14 : 0.07)
          ..style = PaintingStyle.stroke
          ..strokeWidth = frac == 0.90 ? 1.2 : 0.7,
      );
    }

    // Tick marks every 5°
    for (int i = 0; i < 360; i += 5) {
      final isMajor = i % 90 == 0;
      final isQuad = i % 45 == 0 && !isMajor;
      final isMid = i % 10 == 0;

      final len = isMajor
          ? r * 0.14
          : isQuad
          ? r * 0.10
          : isMid
          ? r * 0.07
          : r * 0.04;
      final width = isMajor
          ? 2.5
          : isQuad
          ? 1.8
          : isMid
          ? 1.2
          : 0.8;
      final alpha = isMajor || isQuad
          ? 0.85
          : isMid
          ? 0.35
          : 0.18;

      final angle = i * math.pi / 180;
      final outer = Offset(
        cx + r * 0.90 * math.sin(angle),
        cy - r * 0.90 * math.cos(angle),
      );
      final inner = Offset(
        cx + (r * 0.90 - len) * math.sin(angle),
        cy - (r * 0.90 - len) * math.cos(angle),
      );

      canvas.drawLine(
        outer,
        inner,
        Paint()
          ..color = _C.gold.withOpacity(alpha)
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }

    // 8-pointed star at intercardinals (small diamonds)
    for (final deg in [45, 135, 225, 315]) {
      final angle = deg * math.pi / 180;
      final pos = Offset(
        cx + r * 0.72 * math.sin(angle),
        cy - r * 0.72 * math.cos(angle),
      );
      _drawDiamond(canvas, pos, 4.0, _C.gold.withOpacity(0.50));
    }

    // Cardinal letters
    final labels = {'N': 0, 'E': 90, 'S': 180, 'W': 270};
    for (final e in labels.entries) {
      final angle = e.value * math.pi / 180;
      final dist = r * 0.72;
      final tp = TextPainter(
        text: TextSpan(
          text: e.key,
          style: TextStyle(
            color: e.key == 'N' ? _C.red : _C.gold.withOpacity(0.80),
            fontFamily: 'Georgia',
            fontWeight: FontWeight.bold,
            fontSize: e.key == 'N' ? 22 : 15,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          cx + dist * math.sin(angle) - tp.width / 2,
          cy - dist * math.cos(angle) - tp.height / 2,
        ),
      );
    }
  }

  void _drawDiamond(Canvas canvas, Offset center, double r, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r, center.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_DialPainter o) => false;
}

// ══════════════════════════════════════════════════════════════
//  ARROWHEAD PAINTER
// ══════════════════════════════════════════════════════════════
class _ArrowPainter extends CustomPainter {
  final Color color;
  const _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(s.width / 2, 0)
        ..lineTo(s.width, s.height)
        ..lineTo(s.width / 2, s.height * 0.6)
        ..lineTo(0, s.height)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter o) => o.color != color;
}

// ══════════════════════════════════════════════════════════════
//  AMBIENT BACKGROUND
// ══════════════════════════════════════════════════════════════
class _AmbientBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, s.height),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.55),
          radius: 1.2,
          colors: [const Color(0xFF0F3518).withOpacity(0.95), _C.bg],
        ).createShader(Rect.fromLTWH(0, 0, s.width, s.height)),
    );

    // Concentric circles
    final circle = Paint()
      ..color = _C.gold.withOpacity(0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 6; i++) {
      canvas.drawCircle(
        Offset(s.width / 2, s.height * 0.42),
        50.0 + i * 56,
        circle,
      );
    }

    // Radial spokes
    final spoke = Paint()
      ..color = _C.gold.withOpacity(0.022)
      ..strokeWidth = 0.7;
    final cx = s.width / 2;
    final cy = s.height * 0.42;
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawLine(
        Offset(cx, cy),
        Offset(cx + math.cos(a) * s.width, cy + math.sin(a) * s.width),
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientBgPainter o) => false;
}

// ══════════════════════════════════════════════════════════════
//  GOLD PILL BUTTON
// ══════════════════════════════════════════════════════════════
class _GoldPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GoldPillButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_C.gold, _C.goldLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: _C.gold.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF07130A),
            fontFamily: 'Georgia',
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
