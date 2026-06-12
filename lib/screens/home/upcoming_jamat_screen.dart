import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/masjid.dart';

class UpcomingJamatScreen extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final String salahLabel;
  final String? village;

  const UpcomingJamatScreen({
    super.key,
    required this.items,
    required this.salahLabel,
    this.village,
  });

  String _fmtTime12H(DateTime dt) {
    int h = dt.hour;
    final String m = dt.minute.toString().padLeft(2, '0');
    final String period = h >= 12 ? 'PM' : 'AM';
    if (h > 12) h -= 12;
    if (h == 0) h = 12;
    return '$h:$m $period';
  }

  Future<void> _openMaps(BuildContext context, Masjid masjid) async {
    final double? lat = masjid.latitude;
    final double? lng = masjid.longitude;
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available for this masjid.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = 'Upcoming Jamat - $salahLabel';
    final String? villageLabel =
        (village != null && village!.trim().isNotEmpty) ? village : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: const Color(0xFF1A5C38),
        foregroundColor: const Color(0xFFEAD9A8),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF3F8F4), Color(0xFFF7F3E7)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (villageLabel != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A5C38).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF1A5C38).withOpacity(0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 16,
                          color: Color(0xFF1A5C38),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            villageLabel,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1A2B22),
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 0),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A5C38).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Icon(
                                  Icons.mosque_rounded,
                                  color: Color(0xFF1A5C38),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No upcoming jamats right now',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(0xFF1A2B22),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Check back later for the next schedules.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                    final item = items[index];
                    final Masjid masjid = item['masjid'] as Masjid;
                    final DateTime jamatTime = item['jamatTime'] as DateTime;
                    final bool isDefault = (item['isDefault'] as bool?) ?? false;

                    final String subtitle = [
                      if (masjid.colony != null && masjid.colony!.isNotEmpty)
                        masjid.colony!,
                      if (masjid.address != null && masjid.address!.isNotEmpty)
                        masjid.address!,
                    ].where((e) => e.isNotEmpty).join(' | ');

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _openMaps(context, masjid),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF1A5C38).withOpacity(0.08),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A5C38).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.mosque_rounded,
                                  color: Color(0xFF1A5C38),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            masjid.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: Color(0xFF1A2B22),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isDefault)
                                          Container(
                                            margin: const EdgeInsets.only(left: 6),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFB8963E)
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: const Color(0xFFB8963E)
                                                    .withOpacity(0.35),
                                              ),
                                            ),
                                            child: const Text(
                                              'Home',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFB8963E),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    if (subtitle.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB8963E).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFB8963E).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  'Jamat : ${_fmtTime12H(jamatTime)}',
                                  style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                            color: const Color(0xFF7A5A1D),
                                          ) ??
                                      const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                        color: Color(0xFF7A5A1D),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: Color(0xFF8CA39B),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
