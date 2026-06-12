import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/nearby_masjid_repository.dart';

class NearbyMasjidsScreen extends StatefulWidget {
  const NearbyMasjidsScreen({super.key});

  @override
  State<NearbyMasjidsScreen> createState() => _NearbyMasjidsScreenState();
}

class _NearbyMasjidsScreenState extends State<NearbyMasjidsScreen> {
  NearbyMasjidResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await NearbyMasjidRepository.instance.fetchNearbyMasjids(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyErrorMessage(e);
      });
    }
  }

  String _friendlyErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Permission denied while reading nearby masjids.';
      }
      if (error.code == 'unavailable') {
        return 'Network issue. Please check internet and try again.';
      }
      if (error.code == 'failed-precondition') {
        return 'Nearby query index is not ready yet. Please retry shortly.';
      }
      return error.message ?? error.code;
    }
    return error.toString();
  }

  void _openMaps(NearbyMasjidItem item) async {
    final masjid = item.masjid;
    if (masjid.latitude == null || masjid.longitude == null) {
      _showMessage('Location not available');
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${masjid.latitude},${masjid.longitude}'
      '&travelmode=driving',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showMessage('Could not open maps');
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nearby Masjids (10 km)')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unable to load nearby masjids.\n$_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _loadData(forceRefresh: true),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final items = _result?.items ?? const <NearbyMasjidItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Masjids (10 km)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadData(forceRefresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No approved masjids found within 10 km'))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final masjid = item.masjid;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        elevation: 3,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          title: Text(
                            masjid.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${masjid.address ?? ''}\n${item.distanceKm.toStringAsFixed(2)} km away',
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.directions, color: Colors.blue),
                            onPressed: () => _openMaps(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
