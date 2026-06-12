import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../../services/firebase_db.dart';
import '../../services/notification_service.dart';
import '../../services/location_service.dart';

class MasjidRegistrationScreen extends StatefulWidget {
  const MasjidRegistrationScreen({super.key});

  @override
  State<MasjidRegistrationScreen> createState() =>
      _MasjidRegistrationScreenState();
}

class _MasjidRegistrationScreenState extends State<MasjidRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for Masjid info
  final TextEditingController _masjidNameController = TextEditingController();
  final TextEditingController _colonyController = TextEditingController();
  final TextEditingController _villageController = TextEditingController();
  final TextEditingController _mandalController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _personNameController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();

  final TextEditingController _offsetController = TextEditingController(
    text: '0',
  );

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _securityAnswerController =
      TextEditingController();

  static const List<String> _securityQuestions = [
    'What is your childhood nickname',
    'Favorite Place',
  ];
  String? _selectedSecurityQuestion;

  static final TextInputFormatter _upperCaseFormatter =
      TextInputFormatter.withFunction((oldValue, newValue) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(text: upper, selection: newValue.selection);
  });

  // Salah timings
  final Map<String, String> _timings = {
    'fajr_azan': '',
    'fajr_jamat': '',
    'dhuhr_azan': '',
    'dhuhr_jamat': '',
    'asr_azan': '',
    'asr_jamat': '',
    'maghrib_azan': '',
    'maghrib_jamat': '',
    'isha_azan': '',
    'isha_jamat': '',
    'juma_azan': '',
    'juma_jamat': '',
  };

  String? _generatedLoginId;
  bool _isLoading = false;
  String _suggestedUsername = '';
  bool _locationLocked = false;

  @override
  void initState() {
    super.initState();
    _masjidNameController.addListener(_suggestUsername);
    _villageController.addListener(_suggestUsername);
  }

  @override
  void dispose() {
    _masjidNameController.dispose();
    _colonyController.dispose();
    _villageController.dispose();
    _mandalController.dispose();
    _districtController.dispose();
    _stateController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _personNameController.dispose();
    _mobileController.dispose();
    _offsetController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _securityAnswerController.dispose();
    super.dispose();
  }

  String _caps(String value) => value.toUpperCase();

  String _upperValue(String value) => value.trim().toUpperCase();

  String _normalizeUsername(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  }

  String _buildUsernameFromInputs() {
    String joinWords(
      String raw, {
      bool dropMasjidWord = false,
      bool capitalizeOnlyFirst = false,
    }) {
      final parts = raw
          .trim()
          .split(RegExp(r'[^A-Za-z]+'))
          .where((p) => p.trim().isNotEmpty)
          .toList();
      final cleaned = <String>[];
      for (final p in parts) {
        final lower = p.toLowerCase();
        if (dropMasjidWord &&
            (lower == 'masjid' || lower == 'masjide' || lower == 'e')) {
          continue;
        }
        cleaned.add(p);
      }
      if (cleaned.isEmpty) return '';
      if (capitalizeOnlyFirst) {
        final first =
            '${cleaned.first[0].toUpperCase()}${cleaned.first.substring(1).toLowerCase()}';
        final rest =
            cleaned.skip(1).map((w) => w.toLowerCase()).join();
        return '$first$rest';
      }
      return cleaned
          .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join();
    }

    final village = joinWords(_villageController.text);
    final masjid = joinWords(
      _masjidNameController.text,
      dropMasjidWord: true,
      capitalizeOnlyFirst: true,
    );
    return '$village$masjid';
  }

  void _suggestUsername() {
    final String suggested = _buildUsernameFromInputs();
    if (_suggestedUsername != suggested) {
      setState(() {
        _suggestedUsername = suggested;
      });
    }
  }

  Future<void> _pickTime(String key) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _timings[key] = picked.format(context);
      });
    }
  }

  Future<void> _getLocation() async {
    setState(() => _isLoading = true);
    try {
      final position = await LocationService.instance.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
        _locationLocked = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_caps('Location captured successfully.'))),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('disabled')) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_caps('Enable Location')),
            content: Text(
              _caps(
                'Location services are disabled. Please enable location and try again.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_caps('OK')),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_caps('Location failed: $e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerMasjid() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(_caps('Passwords do not match'))),
      );
      return;
    }

    _suggestUsername();

    final String rawUsername =
        _suggestedUsername.isNotEmpty ? _suggestedUsername : _buildUsernameFromInputs();
    final String usernameLower = _normalizeUsername(rawUsername);
    if (usernameLower.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_caps('Please enter a valid admin username'))),
      );
      return;
    }
    if ((_selectedSecurityQuestion ?? '').trim().isEmpty ||
        _securityAnswerController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_caps('Please set a security question and answer')),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 1. Generate Random User ID (5 chars alphanumeric)
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final String newMasjidId = List.generate(
      5,
      (index) => chars[random.nextInt(chars.length)],
    ).join();

    // 2. Prepare Data
    final Map<String, dynamic> masjidData = {
      'masjidId': newMasjidId,
      'masjidName': _upperValue(_masjidNameController.text),
      'colony': _upperValue(_colonyController.text),
      'village': _upperValue(_villageController.text),
      'mandal': _upperValue(_mandalController.text),
      'district': _upperValue(_districtController.text),
      'state': _upperValue(_stateController.text),
      'latitude': _latitudeController.text.trim(),
      'longitude': _longitudeController.text.trim(),
      'contactPerson': _upperValue(_personNameController.text),
      'mobile': _mobileController.text.trim(),
      'username': rawUsername,
      'usernameLower': usernameLower,

      'offset': int.tryParse(_offsetController.text.trim()) ?? 0,

      'password': _passwordController.text,
      'role': 'masjid_admin',
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'securityQuestion': (_selectedSecurityQuestion ?? '').trim(),
      'securityAnswer': _securityAnswerController.text.trim(),

      // Include Salah timings
      ..._timings,
    };

    // Map jamat timings to main columns
    final jamatFields = [
      'fajr_jamat',
      'dhuhr_jamat',
      'asr_jamat',
      'maghrib_jamat',
      'isha_jamat',
      'juma_jamat',
    ];

    for (var field in jamatFields) {
      if (masjidData[field] != null &&
          masjidData[field].toString().isNotEmpty) {
        final mainField = field.replaceAll('_jamat', '');
        masjidData[mainField] = masjidData[field];
      }
    }

    try {
      final success = await FirebaseDB.instance.registerMasjidAdmin(masjidData);

      if (!success) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _caps('Mobile number or username already registered'),
              ),
            ),
          );
        }
        return;
      }

      await NotificationService.instance.syncRoleBasedFcmSubscriptions(
        role: 'masjid_admin',
        mobile: _mobileController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _generatedLoginId = rawUsername;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(_caps('Registration failed: $e'))),
        );
      }
    }
  }

  void _copyToClipboard() {
    if (_generatedLoginId != null) {
      Clipboard.setData(ClipboardData(text: _generatedLoginId!));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text(_caps('Username copied to clipboard'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_generatedLoginId != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_caps('Registration Successful'))),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: Colors.green,
                          size: 80,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _caps('Masjid Registered Successfully!'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          _caps('Admin Username (Login ID)'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _caps(_generatedLoginId!),
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: _copyToClipboard,
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(_caps('Go to Login')),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_caps('Masjid Registration'))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      _buildTextField(
                        _masjidNameController,
                        'Name of the Masjid',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _colonyController,
                        'Colony',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _villageController,
                        'Village',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _mandalController,
                        'Mandal',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _districtController,
                        'District',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _stateController,
                        'State',
                        forceUppercase: true,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _latitudeController,
                              'Latitude',
                              isNumber: true,
                              enabled: !_locationLocked,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildTextField(
                              _longitudeController,
                              'Longitude',
                              isNumber: true,
                              enabled: !_locationLocked,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: _isLoading ? null : _getLocation,
                          icon: const Icon(Icons.my_location),
                          label: Text(_caps('Get Location')),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _caps('(Select this option when you are in masjid)'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      _buildTextField(
                        _personNameController,
                        'Name of the Person',
                        forceUppercase: true,
                      ),
                      _buildTextField(
                        _mobileController,
                        'Contact Mobile Number',
                        isNumber: true,
                      ),

                      _buildDropdownField(
                        'Security Question',
                        _securityQuestions,
                        _selectedSecurityQuestion,
                        (v) => setState(() => _selectedSecurityQuestion = v),
                      ),
                      _buildTextField(
                        _securityAnswerController,
                        'Security Answer (one word)',
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        forceUppercase: true,
                      ),

                      _buildTextField(
                        _passwordController,
                        'Password',
                        isObscure: true,
                      ),
                      _buildTextField(
                        _confirmPasswordController,
                        'Confirm Password',
                        isObscure: true,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _registerMasjid,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: Text(_caps('Register')),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool isNumber = false,
    bool isObscure = false,
    String? hintText,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    bool forceUppercase = false,
  }) {
    final formatters = <TextInputFormatter>[];
    if (inputFormatters != null) {
      formatters.addAll(inputFormatters);
    }
    if (forceUppercase) {
      formatters.add(_upperCaseFormatter);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: _caps(label),
          hintText: hintText == null ? null : _caps(hintText),
          border: const OutlineInputBorder(),
        ),
        keyboardType: isNumber
            ? const TextInputType.numberWithOptions(signed: true, decimal: true)
            : TextInputType.text,
        textCapitalization:
            forceUppercase ? TextCapitalization.characters : TextCapitalization.none,
        obscureText: isObscure,
        inputFormatters: formatters.isEmpty ? null : formatters,
        validator: (val) =>
            val == null || val.isEmpty ? _caps("$label is required") : null,
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    List<String> items,
    String? value,
    void Function(String?) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: _caps(label),
          border: const OutlineInputBorder(),
        ),
        value: items.contains(value) ? value : null,
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(_caps(e)),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: (val) =>
            val == null || val.isEmpty ? _caps("$label is required") : null,
      ),
    );
  }
}

