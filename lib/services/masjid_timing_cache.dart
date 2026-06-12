import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/masjid.dart';

class MasjidTimingCache {
  MasjidTimingCache._();
  static final MasjidTimingCache instance = MasjidTimingCache._();

  static Database? _db;

  String _toVillageKey(String? village) {
    if (village == null) return '';
    return village.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'masjid_timing_cache.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE masjid_timing_cache (
            masjid_id TEXT PRIMARY KEY,
            villagekey TEXT NOT NULL,
            name TEXT,
            address TEXT,
            village TEXT,
            mandal TEXT,
            district TEXT,
            state TEXT,
            approved INTEGER,
            is_timing_configured INTEGER,
            fajr_azan TEXT,
            fajr_jamat TEXT,
            dhuhr_azan TEXT,
            dhuhr_jamat TEXT,
            asar_azan TEXT,
            asar_jamat TEXT,
            maghrib_azan TEXT,
            maghrib_jamat TEXT,
            isha_azan TEXT,
            isha_jamat TEXT,
            juma_azan TEXT,
            juma_jamat TEXT,
            sunrise_offset_minutes INTEGER,
            sunrise_offset_direction TEXT,
            sunset_offset_minutes INTEGER,
            sunset_offset_direction TEXT,
            latitude TEXT,
            longitude TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE masjid_sync_meta (
            villagekey TEXT PRIMARY KEY,
            last_sync_ms INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE masjid_timing_cache ADD COLUMN address TEXT');
          await db.execute('ALTER TABLE masjid_timing_cache ADD COLUMN mandal TEXT');
          await db.execute('ALTER TABLE masjid_timing_cache ADD COLUMN district TEXT');
          await db.execute('ALTER TABLE masjid_timing_cache ADD COLUMN state TEXT');
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE masjid_timing_cache ADD COLUMN sunrise_offset_minutes INTEGER',
          );
          await db.execute(
            'ALTER TABLE masjid_timing_cache ADD COLUMN sunrise_offset_direction TEXT',
          );
          await db.execute(
            'ALTER TABLE masjid_timing_cache ADD COLUMN sunset_offset_minutes INTEGER',
          );
          await db.execute(
            'ALTER TABLE masjid_timing_cache ADD COLUMN sunset_offset_direction TEXT',
          );
        }
      },
    );
    return _db!;
  }

  Future<void> upsertMasjids(String villageKey, List<Masjid> masjids) async {
    if (masjids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final m in masjids) {
      final String resolvedVillageKey = (m.village ?? '').trim().isNotEmpty
          ? _toVillageKey(m.village)
          : villageKey;
      batch.insert('masjid_timing_cache', {
        'masjid_id': m.id,
        'villagekey': resolvedVillageKey,
        'name': m.name,
        'address': m.address ?? '',
        'village': m.village ?? '',
        'mandal': m.mandal ?? '',
        'district': m.district ?? '',
        'state': m.state ?? '',
        'approved': m.isApproved ? 1 : 0,
        'is_timing_configured': (m.isTimingConfigured == 1 || m.isTimingConfigured == true)
            ? 1
            : 0,
        'fajr_azan': m.fajr_azan ?? '',
        'fajr_jamat': m.fajr_jamat ?? '',
        'dhuhr_azan': m.dhuhr_azan ?? '',
        'dhuhr_jamat': m.dhuhr_jamat ?? '',
        'asar_azan': m.asar_azan ?? '',
        'asar_jamat': m.asar_jamat ?? '',
        'maghrib_azan': m.maghrib_azan ?? '',
        'maghrib_jamat': m.maghrib_jamat ?? '',
        'isha_azan': m.isha_azan ?? '',
        'isha_jamat': m.isha_jamat ?? '',
        'juma_azan': m.juma_azan ?? '',
        'juma_jamat': m.juma_jamat ?? '',
        'sunrise_offset_minutes': m.sunriseOffsetMinutes ?? 0,
        'sunrise_offset_direction': m.sunriseOffsetDirection ?? 'less',
        'sunset_offset_minutes': m.sunsetOffsetMinutes ?? 0,
        'sunset_offset_direction': m.sunsetOffsetDirection ?? 'less',
        'latitude': m.latitude?.toString() ?? '',
        'longitude': m.longitude?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Masjid?> getMasjidById(String masjidId) async {
    final id = masjidId.trim();
    if (id.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'masjid_timing_cache',
      where: 'masjid_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToMasjid(rows.first);
  }

  Future<Masjid?> getAnyConfiguredMasjid() async {
    final db = await database;
    final rows = await db.query(
      'masjid_timing_cache',
      where: 'approved = 1 AND is_timing_configured = 1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _rowToMasjid(rows.first);
  }

  Future<List<Masjid>> getAllMasjids() async {
    final db = await database;
    final rows = await db.query('masjid_timing_cache');

    return rows.map(_rowToMasjid).toList();
  }

  Future<List<Masjid>> getVillageMasjids(String villageKey) async {
    final db = await database;
    final rows = await db.query(
      'masjid_timing_cache',
      where: 'villagekey = ? AND approved = 1 AND is_timing_configured = 1',
      whereArgs: [villageKey],
    );

    return rows.map(_rowToMasjid).toList();
  }

  Future<int?> getLastSyncMs(String villageKey) async {
    final db = await database;
    final rows = await db.query(
      'masjid_sync_meta',
      where: 'villagekey = ?',
      whereArgs: [villageKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['last_sync_ms'] as int?;
  }

  Future<void> setLastSyncMs(String villageKey, int syncMs) async {
    final db = await database;
    await db.insert('masjid_sync_meta', {
      'villagekey': villageKey,
      'last_sync_ms': syncMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAll() async {
    final db = await database;
    final batch = db.batch();
    batch.delete('masjid_timing_cache');
    batch.delete('masjid_sync_meta');
    await batch.commit(noResult: true);
  }

  Masjid _rowToMasjid(Map<String, Object?> r) {
    final data = <String, dynamic>{
      'id': r['masjid_id'],
      'name': r['name'] ?? '',
      'address': r['address'] ?? '',
      'village': r['village'] ?? '',
      'mandal': r['mandal'] ?? '',
      'district': r['district'] ?? '',
      'state': r['state'] ?? '',
      'approved': (r['approved'] as int? ?? 0) == 1,
      'isTimingConfigured': (r['is_timing_configured'] as int? ?? 0) == 1 ? 1 : 0,
      'fajr_azan': r['fajr_azan'] ?? '',
      'fajr_jamat': r['fajr_jamat'] ?? '',
      'dhuhr_azan': r['dhuhr_azan'] ?? '',
      'dhuhr_jamat': r['dhuhr_jamat'] ?? '',
      'asar_azan': r['asar_azan'] ?? '',
      'asar_jamat': r['asar_jamat'] ?? '',
      'maghrib_azan': r['maghrib_azan'] ?? '',
      'maghrib_jamat': r['maghrib_jamat'] ?? '',
      'isha_azan': r['isha_azan'] ?? '',
      'isha_jamat': r['isha_jamat'] ?? '',
      'juma_azan': r['juma_azan'] ?? '',
      'juma_jamat': r['juma_jamat'] ?? '',
      'sunriseOffsetMinutes': r['sunrise_offset_minutes'] ?? 0,
      'sunriseOffsetDirection': r['sunrise_offset_direction'] ?? 'less',
      'sunsetOffsetMinutes': r['sunset_offset_minutes'] ?? 0,
      'sunsetOffsetDirection': r['sunset_offset_direction'] ?? 'less',
      'latitude': r['latitude'] ?? '',
      'longitude': r['longitude'] ?? '',
    };
    return Masjid.fromMap(data, (r['masjid_id'] as String?) ?? '');
  }
}
