import 'package:flutter/material.dart';

import '../../models/masjid.dart';
import '../../services/firebase_db.dart';
import '../../services/masjid_timing_cache.dart';
import 'masjid/masjid_details_screen.dart';

class RegisteredMasjidsScreen extends StatefulWidget {
  const RegisteredMasjidsScreen({super.key});

  @override
  State<RegisteredMasjidsScreen> createState() =>
      _RegisteredMasjidsScreenState();
}

class _RegisteredMasjidsScreenState extends State<RegisteredMasjidsScreen>
    with WidgetsBindingObserver {
  // Session-only cache so selections persist while the app is open.
  static String? _sessionState;
  static String? _sessionDistrict;
  static String? _sessionMandal;
  static String? _sessionVillage;
  static String _sessionSelectedVillage = '';
  static bool _sessionHasSearched = false;
  static String _sessionSearchQuery = '';
  static List<Masjid> _sessionAllMasjids = [];

  final MasjidTimingCache _masjidTimingCache = MasjidTimingCache.instance;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, String>> _catalogLocations = [];
  List<Masjid> _allMasjids = [];
  List<Masjid> _filteredMasjids = [];

  bool _isLoading = false;
  bool _isCatalogLoading = false;
  bool _hasSearched = false;
  String _selectedVillage = '';
  String? _state;
  String? _district;
  String? _mandal;
  String? _village;

  List<String> _states = [];
  List<String> _districts = [];
  List<String> _mandals = [];
  List<String> _villages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _searchController.addListener(_filterByName);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshFromCacheIfNeeded();
    }
  }

  Future<void> _initialize() async {
    setState(() => _isCatalogLoading = true);
    await _loadCatalogMasjids();
    if (!mounted) return;
    _restoreSessionState();
    setState(() => _isCatalogLoading = false);
  }

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
      if (seen.add(lower)) {
        result.add(v.trim());
      }
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  List<Map<String, String>> _locationRowsFromMasjids(Iterable<Masjid> masjids) {
    final seen = <String>{};
    final rows = <Map<String, String>>[];
    for (final m in masjids) {
      final state = (m.state ?? '').trim();
      final district = (m.district ?? '').trim();
      final mandal = (m.mandal ?? '').trim();
      final village = (m.village ?? '').trim();
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
      });
    }
    return rows;
  }

  Future<void> _loadCatalogMasjids() async {
    final cachedAll = await _masjidTimingCache.getAllMasjids();
    final approvedCached = cachedAll.where((m) => m.isApproved).toList();
    if (mounted && cachedAll.isNotEmpty) {
      setState(() {
        _catalogLocations = _locationRowsFromMasjids(approvedCached);
        _states = _unique(approvedCached.map((m) => m.state));
        _districts = _unique(approvedCached.map((m) => m.district));
        _mandals = _unique(approvedCached.map((m) => m.mandal));
        _villages = _unique(approvedCached.map((m) => m.village));
      });
    }

    try {
      final snapshot = await FirebaseDB.instance.getRegisteredCatalogSnapshot();
      if (snapshot != null) {
        final bool hasApprovedKeysField = snapshot.containsKey(
          'approvedVillageKeys',
        );

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
          final approvedKeys = toList(
            snapshot['approvedVillageKeys'],
          ).map(_toVillageKey).where((k) => k.isNotEmpty).toSet();
          final locations = toLocations(snapshot['locations']);
          final filteredLocations = locations.where((row) {
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
        } else {
          final approvedKeys = approvedCached
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
        return;
      }
    } catch (_) {}

    // Read-saving behavior: avoid full Firestore catalog scan in user flow.
    // If snapshot is unavailable, keep using local cache only.
    final latestCatalog = await _masjidTimingCache.getAllMasjids();
    if (!mounted) return;
    setState(() {
      final approvedLatest = latestCatalog.where((m) => m.isApproved).toList();
      _catalogLocations = _locationRowsFromMasjids(approvedLatest);
      _states = _unique(approvedLatest.map((m) => m.state));
      _districts = _unique(approvedLatest.map((m) => m.district));
      _mandals = _unique(approvedLatest.map((m) => m.mandal));
      _villages = _unique(approvedLatest.map((m) => m.village));
      _syncSelectedValuesWithOptions();
    });
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

  void _selectState(String? v) {
    setState(() {
      _state = v;
      _district = null;
      _mandal = null;
      _village = null;
      _syncSelectedValuesWithOptions();
      _clearResults();
    });
    _saveSessionState();
  }

  void _selectDistrict(String? v) {
    setState(() {
      _district = v;
      _mandal = null;
      _village = null;
      _syncSelectedValuesWithOptions();
      _clearResults();
    });
    _saveSessionState();
  }

  void _selectMandal(String? v) {
    setState(() {
      _mandal = v;
      _village = null;
      _syncSelectedValuesWithOptions();
      _clearResults();
    });
    _saveSessionState();
  }

  Future<void> _selectVillage(String? v) async {
    setState(() {
      _village = v;
    });
    _saveSessionState();
    if (v == null || v.trim().isEmpty) {
      setState(_clearResults);
      return;
    }
    await _loadForVillage(v.trim());
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
      final byVillageKey = await FirebaseDB.instance
          .getApprovedMasjidsByVillage(
            villageKey: villageKey,
            updatedAfter: null,
          );
      if (byVillageKey.isNotEmpty) {
        return byVillageKey;
      }
    }

    // Fallback for older docs where `villagekey` may be missing/stale.
    final byExactFields = await FirebaseDB.instance.filterMasjids(
      state: _state,
      district: _district,
      mandal: _mandal,
      village: village,
    );
    return byExactFields.where((m) => m.isApproved).toList();
  }

  Future<void> _loadForVillage(String village) async {
    final villageKey = _toVillageKey(village);
    if (villageKey.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _selectedVillage = village;
      _allMasjids = [];
      _filteredMasjids = [];
    });

    try {
      // Lowest-read path: village snapshot doc (single document read).
      final snapshotItems = await FirebaseDB.instance
          .getRegisteredVillageSnapshot(
            villageKey: villageKey,
            approvedOnly: true,
          );
      if (snapshotItems.isNotEmpty) {
        await _masjidTimingCache.upsertMasjids(villageKey, snapshotItems);
      }

      // Local cache fallback before broad queries.
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
      _sortMasjids(approvedOnly);
      if (!mounted) return;
      setState(() {
        _allMasjids = approvedOnly;
        _filteredMasjids = List<Masjid>.from(approvedOnly);
        _isLoading = false;
      });
      _filterByName();
      _saveSessionState();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearResults() {
    _hasSearched = false;
    _selectedVillage = '';
    _allMasjids = [];
    _filteredMasjids = [];
    _saveSessionState();
  }

  void _filterByName() {
    final q = _searchController.text.trim().toLowerCase().replaceAll(' ', '');
    setState(() {
      _filteredMasjids = _allMasjids.where((m) {
        if (q.isEmpty) return true;
        return m.name.toLowerCase().replaceAll(' ', '').contains(q);
      }).toList();
    });
    _saveSessionState();
  }

  void _saveSessionState() {
    _sessionState = _state;
    _sessionDistrict = _district;
    _sessionMandal = _mandal;
    _sessionVillage = _village;
    _sessionSelectedVillage = _selectedVillage;
    _sessionHasSearched = _hasSearched;
    _sessionSearchQuery = _searchController.text;
    _sessionAllMasjids = List<Masjid>.from(_allMasjids);
  }

  void _restoreSessionState() {
    if (!_sessionHasSearched && _sessionSelectedVillage.isEmpty) return;
    _state = _sessionState;
    _district = _sessionDistrict;
    _mandal = _sessionMandal;
    _village = _sessionVillage;
    _selectedVillage = _sessionSelectedVillage;
    _hasSearched = _sessionHasSearched;
    _allMasjids = List<Masjid>.from(_sessionAllMasjids);
    _filteredMasjids = List<Masjid>.from(_sessionAllMasjids);
    if (_sessionSearchQuery.isNotEmpty) {
      _searchController.text = _sessionSearchQuery;
      _filterByName();
    }
  }

  Future<void> _refreshFromCacheIfNeeded() async {
    if (!_hasSearched || _selectedVillage.trim().isEmpty) return;
    final villageKey = _toVillageKey(_selectedVillage);
    if (villageKey.isEmpty) return;
    final cached = await _getCachedMasjidsByVillage(villageKey);
    _sortMasjids(cached);
    if (!mounted) return;
    setState(() {
      _allMasjids = cached;
    });
    _filterByName();
  }

  void _sortMasjids(List<Masjid> items) {
    items.sort((a, b) {
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  }

  bool _hasConfiguredTimings(Masjid m) {
    bool hasText(String? v) => v != null && v.trim().isNotEmpty;

    return hasText(m.fajr_azan) &&
        hasText(m.fajr_jamat) &&
        hasText(m.dhuhr_azan) &&
        hasText(m.dhuhr_jamat) &&
        hasText(m.asar_azan) &&
        hasText(m.asar_jamat) &&
        hasText(m.isha_azan) &&
        hasText(m.isha_jamat) &&
        hasText(m.juma_azan) &&
        hasText(m.juma_jamat);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registered Masjids'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildVillageFilterCard(),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_isCatalogLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (!_hasSearched)
            const Expanded(
              child: Center(
                child: Text(
                  'Select state, district, mandal and village.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            )
          else if (_filteredMasjids.isEmpty)
            Expanded(child: _emptyState())
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _filteredMasjids.length,
                itemBuilder: (context, index) =>
                    _masjidCard(_filteredMasjids[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVillageFilterCard() {
    final districtOptions = _districtOptions();
    final mandalOptions = _mandalOptions();
    final villageOptions = _villageOptions();
    final bool districtEnabled = _state != null && districtOptions.isNotEmpty;
    final bool mandalEnabled =
        _state != null && _district != null && mandalOptions.isNotEmpty;
    final bool villageEnabled =
        _state != null &&
        _district != null &&
        _mandal != null &&
        villageOptions.isNotEmpty;

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _state,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'State',
              prefixIcon: Icon(Icons.map_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _states
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: _states.isEmpty ? null : _selectState,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _district,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'District',
              prefixIcon: Icon(Icons.account_balance_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Select state first',
            ),
            items: districtOptions
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: districtEnabled ? _selectDistrict : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _mandal,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Mandal',
              prefixIcon: Icon(Icons.location_city_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Select district first',
            ),
            items: mandalOptions
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: mandalEnabled ? _selectMandal : null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _village,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Village',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Select mandal first',
            ),
            items: villageOptions
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: villageEnabled ? _selectVillage : null,
          ),
          if (_hasSearched) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search by Masjid Name',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _masjidCard(Masjid m) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MasjidDetailsScreen(masjid: m)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.green.withOpacity(0.15),
                child: const Icon(Icons.mosque, color: Colors.green, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.address ?? '',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            _selectedVillage.isEmpty
                ? 'No masjids found'
                : 'Check your internet connection or No approved masjids found for "$_selectedVillage"',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
