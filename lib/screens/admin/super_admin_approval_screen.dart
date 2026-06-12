import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/firebase_db.dart';
import '../auth/auth_screen.dart';
import '../../services/masjid_timing_cache.dart';

class SuperAdminApprovalScreen extends StatefulWidget {
  const SuperAdminApprovalScreen({super.key});

  @override
  State<SuperAdminApprovalScreen> createState() =>
      _SuperAdminApprovalScreenState();
}

class _SuperAdminApprovalScreenState extends State<SuperAdminApprovalScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> pendingAdmins = [];

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() => _loading = true);

    final db = FirebaseDB.instance;

    final pending = await db.getPendingMasjidApplications();

    setState(() {
      pendingAdmins = pending;
      _loading = false;
    });
  }

  Future<void> _approve(Map<String, dynamic> admin) async {
    final String masjidId = (admin['id'] as String? ?? '').trim();
    final String ownerMobile =
        (admin['adminMobileNumber'] as String?) ??
        (admin['ownerMobile'] as String?) ??
        '';
    final String village = (admin['village'] as String? ?? '').trim();
    final String district = (admin['district'] as String? ?? '').trim();
    final String mandal = (admin['mandal'] as String? ?? '').trim();
    if (masjidId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to approve: missing masjid id')),
      );
      return;
    }
    final String villageKey = FirebaseDB.instance.normalizeVillageKey(village);
    if (villageKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to approve: missing village')),
      );
      return;
    }

    Map<String, dynamic>? offsets =
        await FirebaseDB.instance.getVillageOffsets(villageKey);
    if (offsets == null) {
      offsets = await _promptOffsetsForVillage(
        villageName: village,
      );
      if (offsets == null) {
        return;
      }
      await FirebaseDB.instance.setVillageOffsets(
        villageKey: villageKey,
        villageName: village,
        sunriseMinutes: offsets['sunriseOffsetMinutes'] as int? ?? 0,
        sunriseDirection:
            (offsets['sunriseOffsetDirection'] as String? ?? 'less'),
        sunsetMinutes: offsets['sunsetOffsetMinutes'] as int? ?? 0,
        sunsetDirection:
            (offsets['sunsetOffsetDirection'] as String? ?? 'less'),
      );
    }

    await FirebaseDB.instance.approveMasjidApplication(
      masjidId: masjidId,
      ownerMobile: ownerMobile,
      masjidData: admin,
      villageOffsets: offsets,
    );
    _loadAdmins();
  }

  Future<Map<String, dynamic>?> _promptOffsetsForVillage({
    required String villageName,
  }) async {
    final sunriseController = TextEditingController(text: '0');
    final sunsetController = TextEditingController(text: '0');
    String sunriseDirection = 'less';
    String sunsetDirection = 'less';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Set Offsets for $villageName'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: sunriseController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sunrise Offset (minutes)',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sunriseDirection,
                items: const [
                  DropdownMenuItem(value: 'less', child: Text('Less')),
                  DropdownMenuItem(value: 'more', child: Text('More')),
                ],
                onChanged: (v) => sunriseDirection = v ?? 'less',
                decoration: const InputDecoration(
                  labelText: 'Sunrise Direction',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sunsetController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sunset Offset (minutes)',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sunsetDirection,
                items: const [
                  DropdownMenuItem(value: 'less', child: Text('Less')),
                  DropdownMenuItem(value: 'more', child: Text('More')),
                ],
                onChanged: (v) => sunsetDirection = v ?? 'less',
                decoration: const InputDecoration(
                  labelText: 'Sunset Direction',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final sunrise = int.tryParse(sunriseController.text.trim()) ?? 0;
                final sunset = int.tryParse(sunsetController.text.trim()) ?? 0;
                Navigator.pop(ctx, {
                  'sunriseOffsetMinutes': sunrise,
                  'sunriseOffsetDirection': sunriseDirection,
                  'sunsetOffsetMinutes': sunset,
                  'sunsetOffsetDirection': sunsetDirection,
                });
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    sunriseController.dispose();
    sunsetController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masjid Approvals'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAdmins,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context),
          ),
        ],
      ),
      body: _buildPendingApprovalsTab(),
    );
  }

  Widget _buildPendingApprovalsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Masjid Requests',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          if (pendingAdmins.isEmpty)
            const Text('No pending Masjid requests'),

          ...pendingAdmins.map((admin) {
            String address =
                [admin['mandal'], admin['district'], admin['state']]
                    .where((s) => s != null && s.toString().isNotEmpty)
                    .join(', ');

            // Fallback to basic address if specific fields are empty
            if (address.isEmpty)
              address = (admin['masjidAddress'] as String?) ?? '';

            return Card(
              child: ExpansionTile(
                title: Text(
                  (admin['name'] as String?) ?? 'Unknown Masjid',
                ),
                subtitle: Text(
                  address.isNotEmpty ? address : 'Unknown Address',
                ),
                children: [
                  ListTile(
                    title: Text(
                      'Name: ${admin['adminName'] ?? admin['name'] ?? 'Unknown'}',
                    ),
                    subtitle: Text(
                      'Mobile: ${admin['adminMobileNumber'] ?? admin['ownerMobile'] ?? 'Unknown'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton(
                          onPressed: () => _approve(admin),
                          child: const Text('Approve'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _confirmDelete(admin),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }


  void _confirmDelete(Map<String, dynamic> admin) {
    final String masjidId = (admin['id'] as String? ?? '').trim();
    if (masjidId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete: missing masjid id')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Request'),
        content: const Text(
          'Delete this pending masjid request? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await FirebaseDB.instance.deletePendingMasjidApplication(masjidId);
              _loadAdmins();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }


  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('userMobile');
    await prefs.remove('userRole');
    await prefs.remove('adminUsernameLower');
    await prefs.remove('masjidId');
    await prefs.remove('cached_default_masjid_id');
    await prefs.remove('cached_default_masjid_updated_ms');
    await prefs.remove('__default_masjid_refresh_required__');
    await MasjidTimingCache.instance.clearAll();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

}
