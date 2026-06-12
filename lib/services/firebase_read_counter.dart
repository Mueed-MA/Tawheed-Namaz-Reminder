import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

abstract class ReadCounter {
  ValueNotifier<int> get totalReads;
  void addReads(int count);
  void reset();
}

class CompositeReadCounter implements ReadCounter {
  CompositeReadCounter(this.primary, this.secondary);

  final ReadCounter primary;
  final ReadCounter secondary;

  @override
  ValueNotifier<int> get totalReads => primary.totalReads;

  @override
  void addReads(int count) {
    primary.addReads(count);
    secondary.addReads(count);
  }

  @override
  void reset() {
    primary.reset();
    secondary.reset();
  }
}

class FirebaseReadCounter implements ReadCounter {
  FirebaseReadCounter._();
  static final FirebaseReadCounter instance = FirebaseReadCounter._();

  @override
  final ValueNotifier<int> totalReads = ValueNotifier<int>(0);

  @override
  void addReads(int count) {
    if (count <= 0) return;
    totalReads.value = totalReads.value + count;
  }

  @override
  void reset() {
    totalReads.value = 0;
  }
}

class FirebaseAuthReadCounter implements ReadCounter {
  FirebaseAuthReadCounter._();
  static final FirebaseAuthReadCounter instance = FirebaseAuthReadCounter._();

  @override
  final ValueNotifier<int> totalReads = ValueNotifier<int>(0);

  @override
  void addReads(int count) {
    if (count <= 0) return;
    totalReads.value = totalReads.value + count;
  }

  @override
  void reset() {
    totalReads.value = 0;
  }
}

class FirebaseNearbyReadCounter implements ReadCounter {
  FirebaseNearbyReadCounter._();
  static final FirebaseNearbyReadCounter instance = FirebaseNearbyReadCounter._();

  @override
  final ValueNotifier<int> totalReads = ValueNotifier<int>(0);

  @override
  void addReads(int count) {
    if (count <= 0) return;
    totalReads.value = totalReads.value + count;
  }

  @override
  void reset() {
    totalReads.value = 0;
  }
}

class FirebaseVillageSnapshotReadCounter implements ReadCounter {
  FirebaseVillageSnapshotReadCounter._();
  static final FirebaseVillageSnapshotReadCounter instance =
      FirebaseVillageSnapshotReadCounter._();

  @override
  final ValueNotifier<int> totalReads = ValueNotifier<int>(0);

  @override
  void addReads(int count) {
    if (count <= 0) return;
    totalReads.value = totalReads.value + count;
  }

  @override
  void reset() {
    totalReads.value = 0;
  }
}

class FirebaseRegisteredMasjidReadCounter implements ReadCounter {
  FirebaseRegisteredMasjidReadCounter._();
  static final FirebaseRegisteredMasjidReadCounter instance =
      FirebaseRegisteredMasjidReadCounter._();

  @override
  final ValueNotifier<int> totalReads = ValueNotifier<int>(0);

  @override
  void addReads(int count) {
    if (count <= 0) return;
    totalReads.value = totalReads.value + count;
  }

  @override
  void reset() {
    totalReads.value = 0;
  }
}

extension CountedDocRead<T> on DocumentReference<T> {
  Future<DocumentSnapshot<T>> getCounted([GetOptions? options]) async {
    final snap = await get(options);
    FirebaseReadCounter.instance.addReads(snap.exists ? 1 : 0);
    return snap;
  }

  Future<DocumentSnapshot<T>> getCountedWith(
    ReadCounter counter, [
    GetOptions? options,
  ]) async {
    final snap = await get(options);
    counter.addReads(snap.exists ? 1 : 0);
    return snap;
  }

  Stream<DocumentSnapshot<T>> snapshotsCounted({
    bool includeMetadataChanges = false,
  }) {
    return snapshots(
      includeMetadataChanges: includeMetadataChanges,
    ).map((snap) {
      FirebaseReadCounter.instance.addReads(snap.exists ? 1 : 0);
      return snap;
    });
  }

  Stream<DocumentSnapshot<T>> snapshotsCountedWith(
    ReadCounter counter, {
    bool includeMetadataChanges = false,
  }) {
    return snapshots(
      includeMetadataChanges: includeMetadataChanges,
    ).map((snap) {
      counter.addReads(snap.exists ? 1 : 0);
      return snap;
    });
  }
}

extension CountedQueryReads<T> on Query<T> {
  Future<QuerySnapshot<T>> getCounted([GetOptions? options]) async {
    final snap = await get(options);
    FirebaseReadCounter.instance.addReads(snap.docs.length);
    return snap;
  }

  Future<QuerySnapshot<T>> getCountedWith(
    ReadCounter counter, [
    GetOptions? options,
  ]) async {
    final snap = await get(options);
    counter.addReads(snap.docs.length);
    return snap;
  }

  Stream<QuerySnapshot<T>> snapshotsCounted({
    bool includeMetadataChanges = false,
  }) {
    return snapshots(
      includeMetadataChanges: includeMetadataChanges,
    ).map((snap) {
      FirebaseReadCounter.instance.addReads(snap.docs.length);
      return snap;
    });
  }

  Stream<QuerySnapshot<T>> snapshotsCountedWith(
    ReadCounter counter, {
    bool includeMetadataChanges = false,
  }) {
    return snapshots(
      includeMetadataChanges: includeMetadataChanges,
    ).map((snap) {
      counter.addReads(snap.docs.length);
      return snap;
    });
  }
}
