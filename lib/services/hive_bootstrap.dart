import 'package:hive_flutter/hive_flutter.dart';

import '../models/village_timing_snapshot_model.dart';

class HiveBootstrap {
  HiveBootstrap._();

  static const String villageSnapshotBox = 'village_timing_snapshots_cache';

  static Future<void> init() async {
    await Hive.initFlutter();

    if (!Hive.isAdapterRegistered(40)) {
      Hive.registerAdapter(VillageTimingSnapshotModelAdapter());
    }

    if (!Hive.isBoxOpen(villageSnapshotBox)) {
      await Hive.openLazyBox<VillageTimingSnapshotModel>(villageSnapshotBox);
    }
  }
}
