import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/firebase_db.dart';
import '../../services/masjid_timing_cache.dart';
import '../../models/masjid.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final MasjidTimingCache _masjidTimingCache = MasjidTimingCache.instance;

  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _securityAnswerController = TextEditingController();

  static const List<String> _securityQuestions = [
    'What is your childhood nickname',
    'Favorite Place',
  ];
  String? _selectedSecurityQuestion;

  // ---------------- LOCATION ----------------
  String? _state;
  String? _district;
  String? _mandal;
  String? _village;
  Masjid? _masjid;

  bool _loading = false;
  bool _isCatalogLoading = false;

  List<Map<String, String>> _catalogLocations = [];

  List<String> _states = [];
  List<String> _districts = [];
  List<String> _mandals = [];
  List<String> _villages = [];
  List<Masjid> _masjids = [];

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  // ---------------- LOAD ----------------
  Future<void> _loadCatalog() async {
    setState(() => _isCatalogLoading = true);
    final cachedAll = await _masjidTimingCache.getAllMasjids();
    final cachedApproved = cachedAll.where((m) => m.isApproved).toList();
    if (mounted && cachedApproved.isNotEmpty) {
      setState(() {
        _catalogLocations = _locationRowsFromMasjids(cachedApproved);
        _states = _unique(cachedApproved.map((m) => m.state));
        _districts = _unique(cachedApproved.map((m) => m.district));
        _mandals = _unique(cachedApproved.map((m) => m.mandal));
        _villages = _unique(cachedApproved.map((m) => m.village));
      });
    }

    try {
      final snapshot = await FirebaseDB.instance.getRegisteredCatalogSnapshot();
      if (snapshot != null) {
        final bool hasApprovedKeysField =
            snapshot.containsKey('approvedVillageKeys');

        List<String> toList(dynamic value) {
          if (value is! List) return const [];
          final raw = value
              .map((e) => e?.toString() ?? '')
              .where((e) => e.trim().isNotEmpty)
              .toList();
          return _unique(raw);
        }

        List<Map<String, String>> toLocations(dynamic value) {
          if (value is! List) return const [];
          final seen = <String>{};
          final rows = <Map<String, String>>[];
          for (final raw in value) {
            if (raw is! Map) continue;
            final map = Map<String, dynamic>.from(raw as Map);
            final state = (map['state'] as String? ?? '').trim();
            final district = (map['district'] as String? ?? '').trim();
            final mandal = (map['mandal'] as String? ?? '').trim();
            final village = (map['village'] as String? ?? '').trim();
            final villageKey = (map['villageKey'] as String? ?? '').trim();
            if (state.isEmpty ||
                district.isEmpty ||
                mandal.isEmpty ||
                village.isEmpty) {
              continue;
            }
            final key =
                '${state.toLowerCase()}|${district.toLowerCase()}|${mandal.toLowerCase()}|${village.toLowerCase()}';
            if (!seen.add(key)) continue;
            rows.add({
              'state': state,
              'district': district,
              'mandal': mandal,
              'village': village,
              'villageKey': villageKey,
            });
          }
          return rows;
        }

        if (!mounted) return;
        if (hasApprovedKeysField) {
          final approvedKeys = toList(snapshot['approvedVillageKeys'])
              .map(_toVillageKey)
              .where((k) => k.isNotEmpty)
              .toSet();
          final locations = toLocations(snapshot['locations']);
          final filteredLocations = locations.where((row) {
            final key = _toVillageKey(row['villageKey'] ?? row['village'] ?? '');
            if (key.isEmpty) return false;
            return approvedKeys.contains(key);
          }).toList();
          setState(() {
            _catalogLocations = filteredLocations;
            _states = _unique(filteredLocations.map((r) => r['state']));
            _districts = _unique(filteredLocations.map((r) => r['district']));
            _mandals = _unique(filteredLocations.map((r) => r['mandal']));
            _villages = _unique(filteredLocations.map((r) => r['village']));
            _syncSelectedValuesWithOptions();
          });
        } else {
          final approvedKeys = cachedApproved
              .map((m) => _toVillageKey(m.village ?? ''))
              .where((k) => k.isNotEmpty)
              .toSet();
          final locations = toLocations(snapshot['locations']);
          final filteredLocations = approvedKeys.isEmpty
              ? <Map<String, String>>[]
              : locations.where((row) {
                  final key = _toVillageKey(
                    row['villageKey'] ?? row['village'] ?? '',
                  );
                  if (key.isEmpty) return false;
                  return approvedKeys.contains(key);
                }).toList();
          setState(() {
            _catalogLocations = filteredLocations;
            _states = _unique(filteredLocations.map((r) => r['state']));
            _districts = _unique(filteredLocations.map((r) => r['district']));
            _mandals = _unique(filteredLocations.map((r) => r['mandal']));
            _villages = _unique(filteredLocations.map((r) => r['village']));
            _syncSelectedValuesWithOptions();
          });
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isCatalogLoading = false);
  }

  // ---------------- HELPERS ----------------
  String _toVillageKey(String village) {
    return village.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _match(String? a, String? b) =>
      a?.trim().toLowerCase() == b?.trim().toLowerCase();

  List<String> _unique(Iterable<String?> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final v in values) {
      if (v == null || v.trim().isEmpty) continue;
      final lower = v.trim().toLowerCase();
      if (!seen.contains(lower)) {
        seen.add(lower);
        result.add(v.trim());
      }
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  String _displayCaps(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return '';
    return v.toUpperCase();
  }

  List<Masjid> _sortMasjidsByName(List<Masjid> input) {
    final sorted = List<Masjid>.from(input);
    sorted.sort((a, b) {
      final aName = (a.name ?? '').trim().toLowerCase();
      final bName = (b.name ?? '').trim().toLowerCase();
      if (aName.isEmpty && bName.isEmpty) return 0;
      if (aName.isEmpty) return 1;
      if (bName.isEmpty) return -1;
      return aName.compareTo(bName);
    });
    return sorted;
  }

  List<Map<String, String>> _locationRowsFromMasjids(Iterable<Masjid> masjids) {
    final seen = <String>{};
    final rows = <Map<String, String>>[];
    for (final m in masjids) {
      final state = (m.state ?? '').trim();
      final district = (m.district ?? '').trim();
      final mandal = (m.mandal ?? '').trim();
      final village = (m.village ?? '').trim();
      if (state.isEmpty || district.isEmpty || mandal.isEmpty || village.isEmpty) {
        continue;
      }
      final key =
          '${state.toLowerCase()}|${district.toLowerCase()}|${mandal.toLowerCase()}|${village.toLowerCase()}';
      if (!seen.add(key)) continue;
      rows.add({
        'state': state,
        'district': district,
        'mandal': mandal,
        'village': village,
      });
    }
    return rows;
  }

  void _syncSelectedValuesWithOptions() {
    final districtOptions = _districtOptions();
    final mandalOptions = _mandalOptions();
    final villageOptions = _villageOptions();

    if (_state != null && !_states.contains(_state)) {
      _state = null;
      _district = null;
      _mandal = null;
      _village = null;
      _syncSelectedValuesWithOptions();
      return;
    }
    if (_district != null && !districtOptions.contains(_district)) {
      _district = null;
      _mandal = null;
      _village = null;
      _syncSelectedValuesWithOptions();
      return;
    }
    if (_mandal != null && !mandalOptions.contains(_mandal)) {
      _mandal = null;
      _village = null;
      _syncSelectedValuesWithOptions();
      return;
    }
    if (_village != null && !villageOptions.contains(_village)) {
      _village = null;
    }
  }

  List<String> _districtOptions() {
    if (_state == null || _state!.trim().isEmpty) return const [];
    final options = _unique(
      _catalogLocations
          .where((r) => _match(r['state'], _state))
          .map((r) => r['district']),
    );
    if (options.isNotEmpty) return options;
    return _districts;
  }

  List<String> _mandalOptions() {
    if (_state == null ||
        _state!.trim().isEmpty ||
        _district == null ||
        _district!.trim().isEmpty) {
      return const [];
    }
    final options = _unique(
      _catalogLocations
          .where((r) => _match(r['state'], _state))
          .where((r) => _match(r['district'], _district))
          .map((r) => r['mandal']),
    );
    if (options.isNotEmpty) return options;
    return _mandals;
  }

  List<String> _villageOptions() {
    if (_state == null ||
        _state!.trim().isEmpty ||
        _district == null ||
        _district!.trim().isEmpty ||
        _mandal == null ||
        _mandal!.trim().isEmpty) {
      return const [];
    }
    final options = _unique(
      _catalogLocations
          .where((r) => _match(r['state'], _state))
          .where((r) => _match(r['district'], _district))
          .where((r) => _match(r['mandal'], _mandal))
          .map((r) => r['village']),
    );
    if (options.isNotEmpty) return options;
    return _villages;
  }

  Future<List<Masjid>> _getCachedMasjidsByVillage(String villageKey) async {
    final all = await _masjidTimingCache.getAllMasjids();
    return all
        .where((m) => m.isApproved)
        .where((m) => _toVillageKey(m.village ?? '') == villageKey)
        .toList();
  }

  Future<List<Masjid>> _fetchRemoteBySelectedLocation({
    required String village,
    required String villageKey,
  }) async {
    if (villageKey.isNotEmpty) {
      final byVillageKey = await FirebaseDB.instance.getApprovedMasjidsByVillage(
        villageKey: villageKey,
        updatedAfter: null,
      );
      if (byVillageKey.isNotEmpty) {
        return byVillageKey;
      }
    }

    final byExactFields = await FirebaseDB.instance.filterMasjids(
      state: _state,
      district: _district,
      mandal: _mandal,
      village: village,
    );
    return byExactFields.where((m) => m.isApproved).toList();
  }

  Future<void> _loadMasjidsForVillage(String village) async {
    final villageKey = _toVillageKey(village);
    if (villageKey.isEmpty) return;

    setState(() {
      _loading = true;
      _masjids = [];
      _masjid = null;
    });

    try {
      final snapshotItems = await FirebaseDB.instance.getRegisteredVillageSnapshot(
        villageKey: villageKey,
        approvedOnly: true,
      );
      if (snapshotItems.isNotEmpty) {
        await _masjidTimingCache.upsertMasjids(villageKey, snapshotItems);
      }

      final cached = await _getCachedMasjidsByVillage(villageKey);
      final remote = snapshotItems.isNotEmpty
          ? snapshotItems
          : (cached.isNotEmpty
                ? cached
                : await _fetchRemoteBySelectedLocation(
                    village: village,
                    villageKey: villageKey,
                  ));
      final approvedOnly = remote.where((m) => m.isApproved).toList();

      if (!mounted) return;
      setState(() {
        _masjids = _sortMasjidsByName(approvedOnly);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _toast('Error loading masjids');
    }
  }

  // ---------------- FILTERS ----------------
  void _selectState(String? v) {
    setState(() {
      _state = v;
      _district = _mandal = _village = null;
      _masjid = null;
      _syncSelectedValuesWithOptions();
      _masjids = [];
    });
  }

  void _selectDistrict(String? v) {
    setState(() {
      _district = v;
      _mandal = _village = null;
      _masjid = null;
      _syncSelectedValuesWithOptions();
      _masjids = [];
    });
  }

  void _selectMandal(String? v) {
    setState(() {
      _mandal = v;
      _village = null;
      _masjid = null;
      _syncSelectedValuesWithOptions();
      _masjids = [];
    });
  }

  void _selectVillage(String? v) {
    setState(() {
      _village = v;
      _masjid = null;
      _masjids = [];
    });
    if (v == null || v.trim().isEmpty) return;
    _loadMasjidsForVillage(v.trim());
  }

  // ---------------- REGISTER ----------------
  Future<void> _register() async {
    if (_masjid == null ||
        _masjid!.id == null ||
        _nameController.text.isEmpty ||
        _mobileController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty ||
        (_selectedSecurityQuestion ?? '').trim().isEmpty ||
        _securityAnswerController.text.isEmpty) {
      _toast('Please fill all fields');
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _toast('Passwords do not match');
      return;
    }

    final mobile = _mobileController.text.trim();
    final exists = await FirebaseDB.instance.userExistsByMobile(mobile);
    if (exists) {
      _toast('User already exists');
      return;
    }

    setState(() => _loading = true);

    final ok = await FirebaseDB.instance.registerUser(
      mobile,
      _nameController.text.trim(),
      _passwordController.text.trim(),
      _selectedSecurityQuestion,
      _securityAnswerController.text.trim(),
    );

    if (!ok) {
      setState(() => _loading = false);
      _toast('User already exists');
      return;
    }

    await FirebaseDB.instance.setDefaultMasjid(
      _mobileController.text.trim(),
      _masjid!.id!,
    );

    if (!mounted) return;

    _toast('Successfully registered. Please login');

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HomeScreen(userMobile: _mobileController.text.trim(), role: 'user'),
      ),
      (_) => false,
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _securityAnswerController.dispose();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('USER REGISTRATION')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _field(_nameController, 'Name'),
              _field(
                _mobileController,
                'Mobile Number',
                keyboard: TextInputType.phone,
              ),
              _dropdown(
                'Security Question',
                _securityQuestions,
                _selectedSecurityQuestion,
                (v) => setState(() => _selectedSecurityQuestion = v),
              ),
              _field(
                _securityAnswerController,
                'Security Answer (one word)',
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
              ),
              _field(_passwordController, 'Password', obscure: true),
              _field(
                _confirmPasswordController,
                'Confirm Password',
                obscure: true,
              ),

              const SizedBox(height: 20),

              if (_isCatalogLoading || _loading)
                const CircularProgressIndicator()
              else ...[
                _dropdown('Select State', _states, _state, _selectState),
                _dropdown(
                  'Select District',
                  _districtOptions(),
                  _district,
                  _selectDistrict,
                ),
                _dropdown('Select Mandal', _mandalOptions(), _mandal, _selectMandal),
                _dropdown(
                  'Select Village',
                  _villageOptions(),
                  _village,
                  _selectVillage,
                ),

                if (_masjids.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(
                        'masjid_dropdown_${_village}_${_masjids.length}',
                      ),
                      decoration: _dec('Select Masjid'),
                      value: _masjids.any((m) => m.id == _masjid?.id)
                          ? _masjid?.id
                          : null,
                      items: _masjids
                          .where((m) => m.id != null) // Ensure ID exists
                          .map(
                            (m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                _displayCaps(
                                  m.name?.isNotEmpty == true
                                      ? m.name!
                                      : 'Unnamed Masjid',
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {
                          _masjid = _masjids.firstWhere((m) => m.id == v);
                        });
                      },
                    ),
                  )
                else if (_village != null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'NO APPROVED MASJIDS FOUND IN THIS VILLAGE.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
              ],

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _register,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('REGISTER'),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- WIDGETS ----------------
  Widget _dropdown(
    String label,
    List<String> items,
    String? value,
    void Function(String?) onChanged,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();

    final validValue = items.contains(value) ? value : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        decoration: _dec(label),
        value: validValue,
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(_displayCaps(e)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: _displayCaps(label),
        border: const OutlineInputBorder(),
      );

  Widget _field(
    TextEditingController c,
    String label, {
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        decoration: _dec(label),
      ),
    );
  }

}
