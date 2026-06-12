import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/masjid.dart';
import 'firebase_read_counter.dart';
import 'geo_hash_utils.dart';

class FirebaseDB {
  FirebaseDB._();
  static final FirebaseDB instance = FirebaseDB._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _villageOffsetsCollection = 'village_offsets';
  String _toVillageKey(String? village) {
    if (village == null) return '';
    return village.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _normalizeAdminUsername(String? input) {
    final raw = (input ?? '').trim().toLowerCase();
    if (raw.isEmpty) return '';
    final normalized = raw.replaceAll(RegExp(r'[^a-z0-9_]'), '');
    return normalized.replaceAll(RegExp(r'_+'), '_');
  }

  String _buildAdminUsernameBase({
    required String? fullName,
    required String mobile,
  }) {
    final parts = (fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    final rawLastName = parts.isEmpty ? 'admin' : parts.last;
    final normalizedLastName = _normalizeAdminUsername(rawLastName);
    final baseLastName = normalizedLastName.isEmpty ? 'admin' : normalizedLastName;
    final digits = mobile.replaceAll(RegExp(r'[^0-9]'), '');
    final suffix = digits.length >= 3
        ? digits.substring(digits.length - 3)
        : digits.padLeft(3, '0');
    return '$baseLastName$suffix';
  }

  double? _parseCoordinate(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  String _normalizeOffsetDirection(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v == 'more' || v == 'less') return v;
    return 'less';
  }

  bool _isVillageMatch(String? value, String target) {
    final v = (value ?? '').trim().toLowerCase();
    return v == target.toLowerCase();
  }

  bool _isNalgonda(String? value) => _isVillageMatch(value, 'nalgonda');

  bool _isNarketpally(String? value) => _isVillageMatch(value, 'narketpally');

  String normalizeVillageKey(String? village) => _toVillageKey(village);

  // Helper to hash passwords
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  bool _looksLikeSha256(String value) {
    final v = value.trim();
    if (v.length != 64) return false;
    return RegExp(r'^[a-f0-9]{64}$').hasMatch(v);
  }

  bool _passwordMatches(String inputPassword, String? storedPassword) {
    if (storedPassword == null || storedPassword.isEmpty) return false;
    final String inputHash = _hashPassword(inputPassword);
    return storedPassword == inputHash || storedPassword == inputPassword;
  }


  String _mobileDigits(String mobile) =>
      mobile.replaceAll(RegExp(r'[^0-9]'), '');

  String _authEmailForUser(String mobile) {
    final digits = _mobileDigits(mobile);
    if (digits.isEmpty) return '';
    return 'user_$digits@tawheed.local';
  }

  String _authEmailForAdmin(String mobile) {
    final digits = _mobileDigits(mobile);
    if (digits.isEmpty) return '';
    return 'admin_$digits@tawheed.local';
  }

  String _authEmailForAdminUsername(String usernameLower) {
    final normalized = _normalizeAdminUsername(usernameLower);
    if (normalized.isEmpty) return '';
    return 'adminu_$normalized@tawheed.local';
  }

  String _authPasswordForAuth({
    required String role,
    required String mobile,
    required String password,
  }) {
    final String raw = password.trim();
    if (raw.length >= 6) return raw;
    final String seed = '$role|${_mobileDigits(mobile)}|$raw';
    final String derived = sha256.convert(utf8.encode(seed)).toString();
    return 'pw_${derived.substring(0, 10)}';
  }

  String _authPasswordForAdminUsername({
    required String usernameLower,
    required String password,
  }) {
    final String raw = password.trim();
    if (raw.length >= 6) return raw;
    final String seed = 'masjid_admin|$usernameLower|$raw';
    final String derived = sha256.convert(utf8.encode(seed)).toString();
    return 'pw_${derived.substring(0, 10)}';
  }

  String _normalizeHintAnswer(String input) {
    final raw = input.trim().toLowerCase();
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\s+'), '');
  }

  Future<UserCredential?> _signInOrCreateAuth({
    required String email,
    required String password,
    bool allowCreate = true,
  }) async {
    if (email.isEmpty || password.isEmpty) return null;
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' && allowCreate) {
        try {
          return await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
        } on FirebaseAuthException catch (createError) {
          if (createError.code == 'email-already-in-use') {
            try {
              return await _auth.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
            } catch (_) {
              return null;
            }
          }
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _linkAuthToUserDocs({
    required String role,
    required String mobile,
    required User user,
    String? adminUsernameLower,
  }) async {
    final String uid = user.uid;
    final String normalizedMobile = mobile.trim();
    if (uid.isEmpty || normalizedMobile.isEmpty) return;

    if (role == 'user') {
      await _db.collection('users').doc(normalizedMobile).set({
        'authUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    if (role == 'masjid_admin') {
      await _db.collection('masjid_admin_auth').doc(normalizedMobile).set({
        'authUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (adminUsernameLower != null && adminUsernameLower.isNotEmpty) {
        await _db.collection('admin_usernames').doc(adminUsernameLower).set({
          'authUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final legacy = await _db.collection('users').doc(normalizedMobile).getCounted();
      if (legacy.exists && legacy.data()?['role'] == 'masjid_admin') {
        await _db.collection('users').doc(normalizedMobile).set({
          'authUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  Future<void> _linkAuthToAdminUsername({
    required String adminUsernameLower,
    required User user,
  }) async {
    final String uid = user.uid;
    final String normalized = _normalizeAdminUsername(adminUsernameLower);
    if (uid.isEmpty || normalized.isEmpty) return;
    await _db.collection('admin_usernames').doc(normalized).set({
      'authUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _ensureAuthForRole({
    required String role,
    required String mobile,
    required String password,
    String? adminUsernameLower,
    bool allowCreate = true,
  }) async {
    final String email = role == 'masjid_admin'
        ? _authEmailForAdmin(mobile)
        : _authEmailForUser(mobile);
    if (email.isEmpty) return;
    final String authPassword = _authPasswordForAuth(
      role: role,
      mobile: mobile,
      password: password,
    );
    final credential = await _signInOrCreateAuth(
      email: email,
      password: authPassword,
      allowCreate: allowCreate,
    );
    final user = credential?.user;
    if (user == null) return;
    await _linkAuthToUserDocs(
      role: role,
      mobile: mobile,
      user: user,
      adminUsernameLower: adminUsernameLower,
    );
  }

  Future<void> _ensureAuthForAdminUsername({
    required String usernameLower,
    required String password,
    bool allowCreate = true,
  }) async {
    final String normalized = _normalizeAdminUsername(usernameLower);
    if (normalized.isEmpty) return;
    final String email = _authEmailForAdminUsername(normalized);
    if (email.isEmpty) return;
    final String authPassword = _authPasswordForAdminUsername(
      usernameLower: normalized,
      password: password,
    );
    final credential = await _signInOrCreateAuth(
      email: email,
      password: authPassword,
      allowCreate: allowCreate,
    );
    final user = credential?.user;
    if (user == null) return;
    await _linkAuthToAdminUsername(adminUsernameLower: normalized, user: user);
  }

  Future<bool> ensureAuthSessionForRole({
    required String role,
    required String mobile,
  }) async {
    if (_auth.currentUser != null) return true;
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) return false;

    try {
      if (role == 'masjid_admin') {
        final doc =
            await _db.collection('masjid_admin_auth').doc(normalizedMobile).getCounted();
        final data = doc.data() ?? <String, dynamic>{};
        final String fallback =
            (data['password'] as String? ?? '').trim();
        final String password = fallback;
        if (password.isEmpty) return false;
        final String authPassword = _authPasswordForAuth(
          role: 'masjid_admin',
          mobile: normalizedMobile,
          password: password,
        );

        final String usernameLower =
            _normalizeAdminUsername(data['usernameLower'] as String? ?? data['username'] as String? ?? '');
        await _ensureAuthForRole(
          role: 'masjid_admin',
          mobile: normalizedMobile,
          password: authPassword,
          adminUsernameLower: usernameLower.isEmpty ? null : usernameLower,
          allowCreate: true,
        );
        return _auth.currentUser != null;
      }

      final userDoc =
          await _db.collection('users').doc(normalizedMobile).getCounted();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final String fallback =
          (userData['password'] as String? ?? '').trim();
      final String password = fallback;
      if (password.isEmpty) return false;
      final String authPassword = _authPasswordForAuth(
        role: 'user',
        mobile: normalizedMobile,
        password: password,
      );
      await _ensureAuthForRole(
        role: 'user',
        mobile: normalizedMobile,
        password: authPassword,
        allowCreate: true,
      );
      return _auth.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> tryUpdateAuthPassword({
    required String role,
    required String identifier,
    required String oldPassword,
    required String newPassword,
  }) async {
    if (role == 'masjid_admin') {
      final String usernameLower = _normalizeAdminUsername(identifier);
      if (usernameLower.isEmpty) return;
      final String email = _authEmailForAdminUsername(usernameLower);
      if (email.isEmpty) return;
      try {
        final String oldAuthPassword = _authPasswordForAdminUsername(
          usernameLower: usernameLower,
          password: oldPassword,
        );
        await _auth.signInWithEmailAndPassword(
          email: email,
          password: oldAuthPassword,
        );
        final currentUser = _auth.currentUser;
        if (currentUser == null) return;
        final String newAuthPassword = _authPasswordForAdminUsername(
          usernameLower: usernameLower,
          password: newPassword,
        );
        await currentUser.updatePassword(newAuthPassword);
        return;
      } catch (_) {
        // Fallback to legacy mobile-based auth if available.
        try {
          final String mobile =
              (await getAdminMobileByUsername(identifier) ?? '').trim();
          if (mobile.isEmpty) return;
          final String legacyEmail = _authEmailForAdmin(mobile);
          if (legacyEmail.isEmpty) return;
          final String oldAuthPassword = _authPasswordForAuth(
            role: role,
            mobile: mobile,
            password: oldPassword,
          );
          await _auth.signInWithEmailAndPassword(
            email: legacyEmail,
            password: oldAuthPassword,
          );
          final currentUser = _auth.currentUser;
          if (currentUser == null) return;
          final String newAuthPassword = _authPasswordForAuth(
            role: role,
            mobile: mobile,
            password: newPassword,
          );
          await currentUser.updatePassword(newAuthPassword);
        } catch (_) {
          // Best-effort: do not block password reset if auth update fails.
        }
      }
      return;
    }

    final String mobile = identifier.trim();
    if (mobile.isEmpty) return;
    final String email = _authEmailForUser(mobile);
    if (email.isEmpty) return;

    try {
      final String oldAuthPassword = _authPasswordForAuth(
        role: role,
        mobile: mobile,
        password: oldPassword,
      );
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: oldAuthPassword,
      );
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;
      final String newAuthPassword = _authPasswordForAuth(
        role: role,
        mobile: mobile,
        password: newPassword,
      );
      await currentUser.updatePassword(newAuthPassword);
    } catch (_) {
      // Best-effort: do not block password reset if auth update fails.
    }
  }
  // ... existing code ...

  // ==============================
  // USER REGISTRATION (Updated with Hashing)
  // ==============================
  Future<bool> userExistsByMobile(String mobile) async {
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) return false;

    final doc = await _db.collection('users').doc(normalizedMobile).getCounted();
    if (doc.exists) return true;

    // Legacy users may have a different doc id but store mobile as a field.
    final snapshot = await _db
        .collection('users')
        .where('mobile', isEqualTo: normalizedMobile)
        .limit(1)
        .getCounted();
    return snapshot.docs.isNotEmpty;
  }

  Future<bool> registerUser(
    String mobile,
    String name,
    String password,
    String? securityQuestion,
    String? securityAnswer,
  ) async {
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) return false;

    final exists = await userExistsByMobile(normalizedMobile);
    if (exists) return false;

    // Hash the password before saving to match the login logic
    final hashedPassword = _hashPassword(password);
    final String normalizedAnswer =
        _normalizeHintAnswer(securityAnswer ?? '');

    await _db.collection('users').doc(normalizedMobile).set({
      'name': name,
      'mobile': normalizedMobile,
      'password': hashedPassword, // Saved as Hash
      if ((securityQuestion ?? '').trim().isNotEmpty)
        'securityQuestion': (securityQuestion ?? '').trim(),
      if (normalizedAnswer.isNotEmpty) 'securityAnswer': normalizedAnswer,
      'role': 'user',
      'createdAt': Timestamp.now(),
    });

    // Best-effort: create/sign-in auth user for secure rules later.
    await _ensureAuthForRole(
      role: 'user',
      mobile: normalizedMobile,
      password: password,
      allowCreate: true,
    );

    return true;
  }

  // ... rest of the file ...

  // ==============================
  // MASJID REGISTRATION
  // ==============================
  Future<bool> registerMasjidAdmin(Map<String, dynamic> data) async {
    try {
      final String village = (data['village'] as String? ?? '').trim();
      final String villageKey = _toVillageKey(village);
      final String mobile = (data['mobile'] as String? ?? '').trim();
      final String password = (data['password'] as String? ?? '').trim();
      final String username = (data['username'] as String? ?? '').trim();
      final String usernameLower = _normalizeAdminUsername(
        data['usernameLower'] as String? ?? username,
      );
      final String securityQuestion =
          (data['securityQuestion'] as String? ?? '').trim();
      final String securityAnswer =
          _normalizeHintAnswer(data['securityAnswer'] as String? ?? '');
      if (mobile.isEmpty || password.isEmpty || usernameLower.isEmpty) {
        return false;
      }

      final existingAdmin = await _db
          .collection('masjid_admin_auth')
          .doc(mobile)
          .getCounted();
      if (existingAdmin.exists) return false;
      final existingUsername = await _db
          .collection('admin_usernames')
          .doc(usernameLower)
          .getCounted();
      if (existingUsername.exists) return false;

      final double? latitude = _parseCoordinate(data['latitude']);
      final double? longitude = _parseCoordinate(data['longitude']);
      final String? geoHash =
          latitude != null && longitude != null
          ? GeoHashUtils.encode(latitude, longitude, precision: 6)
          : null;
      final bool hasSunriseOffset =
          data.containsKey('sunriseOffsetMinutes') ||
          data.containsKey('sunriseOffsetDirection');
      final bool hasSunsetOffset =
          data.containsKey('sunsetOffsetMinutes') ||
          data.containsKey('sunsetOffsetDirection');
      final int sunriseOffsetMinutes =
          _parseInt(data['sunriseOffsetMinutes']);
      final int sunsetOffsetMinutes =
          _parseInt(data['sunsetOffsetMinutes']);
      final String sunriseOffsetDirection = _normalizeOffsetDirection(
        data['sunriseOffsetDirection'] as String?,
      );
      final String sunsetOffsetDirection = _normalizeOffsetDirection(
        data['sunsetOffsetDirection'] as String?,
      );
      // 1. Create Masjid Admin Auth Document (separate from user auth)
      await _db.collection('masjid_admin_auth').doc(mobile).set({
        'name': data['contactPerson'],
        'masjidName': data['masjidName'],
        'mobile': mobile,
        'password': _hashPassword(password),
        if (securityQuestion.isNotEmpty) 'securityQuestion': securityQuestion,
        if (securityAnswer.isNotEmpty) 'securityAnswer': securityAnswer,
        'role': 'masjid_admin',
        'username': username,
        'usernameLower': usernameLower,
        'approved': false, // Admin approval status
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _db.collection('admin_usernames').doc(usernameLower).set({
        'mobile': mobile,
        'role': 'masjid_admin',
        'username': username,
        'password': _hashPassword(password),
        if (securityQuestion.isNotEmpty) 'securityQuestion': securityQuestion,
        if (securityAnswer.isNotEmpty) 'securityAnswer': securityAnswer,
        'approved': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Create Masjid Document (Public Info - NO PASSWORD)
      await _db.collection('masjids').add({
        'masjidId': data['masjidId'],
        'publicId': data['masjidId'], // Matches SQLite 'publicId'
        'name': data['masjidName'],
        'adminName': data['contactPerson'],
        'address': "${data['colony']}, $village",
        'colony': data['colony'],
        'village': village,
        'villagekey': villageKey,
        'mandal': data['mandal'],
        'district': data['district'],
        'state': data['state'],
        'latitude': latitude,
        'longitude': longitude,
        'geoHash': geoHash,
        'adminMobileNumber': mobile,
        'adminUsername': username,
        'adminUsernameLower': usernameLower,
        'ownerMobile': mobile, // Foreign key to masjid admin auth
        'approved': false, // Masjid approval status
        'approvalStatus': 'pending',
        'isTimingConfigured': 0,
        if (hasSunriseOffset) 'sunriseOffsetMinutes': sunriseOffsetMinutes,
        if (hasSunriseOffset)
          'sunriseOffsetDirection': sunriseOffsetDirection,
        if (hasSunsetOffset) 'sunsetOffsetMinutes': sunsetOffsetMinutes,
        if (hasSunsetOffset) 'sunsetOffsetDirection': sunsetOffsetDirection,
        'maghrib_azan': '',
        'maghrib_jamat': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Keep registered-masjid filter snapshots in sync without Cloud Functions.
      if (villageKey.isNotEmpty) {
        try {
          await _upsertRegisteredVillageSnapshot(villageKey);
          await _upsertRegisteredCatalogEntry(
            state: (data['state'] as String? ?? '').trim(),
            district: (data['district'] as String? ?? '').trim(),
            mandal: (data['mandal'] as String? ?? '').trim(),
            village: village,
            villageKey: villageKey,
          );
        } catch (_) {}
      }

      // Best-effort: create/sign-in auth user for the admin.
      await _ensureAuthForRole(
        role: 'masjid_admin',
        mobile: mobile,
        password: password,
        adminUsernameLower: usernameLower,
        allowCreate: true,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // ==============================
  // GET APPROVED MASJIDS
  // ==============================
  Future<List<Masjid>> getApprovedMasjids() async {
    try {
      final byId = <String, Masjid>{};

      final approvedBool = await _db
          .collection('masjids')
          .where('approved', isEqualTo: true)
          .getCounted();
      for (final doc in approvedBool.docs) {
        final masjid = _safeMasjidFromDoc(doc);
        if (masjid != null) byId[masjid.id] = masjid;
      }

      final approvedStatus = await _db
          .collection('masjids')
          .where('approvalStatus', isEqualTo: 'approved')
          .getCounted();
      for (final doc in approvedStatus.docs) {
        final masjid = _safeMasjidFromDoc(doc);
        if (masjid != null) byId[masjid.id] = masjid;
      }

      return byId.values.toList();
    } catch (_) {
      return [];
    }
  }

  Future<Masjid?> getAnyApprovedMasjid() async {
    try {
      final snapshot = await _db
          .collection('masjids')
          .where('approved', isEqualTo: true)
          .limit(1)
          .getCounted();
      if (snapshot.docs.isNotEmpty) {
        return _safeMasjidFromDoc(snapshot.docs.first);
      }

      final snapshotByStatus = await _db
          .collection('masjids')
          .where('approvalStatus', isEqualTo: 'approved')
          .limit(1)
          .getCounted();
      if (snapshotByStatus.docs.isEmpty) return null;
      return _safeMasjidFromDoc(snapshotByStatus.docs.first);
    } catch (_) {
      return null;
    }
  }

  // ==============================
  // GET ALL MASJIDS (NEARBY)
  // ==============================
  Future<List<Masjid>> getAllMasjids() async {
    final snapshot = await _db.collection('masjids').getCounted();

    return snapshot.docs
        .map((doc) => _safeMasjidFromDoc(doc))
        .whereType<Masjid>()
        .toList();
  }

  Future<String?> getAdminMobileByUsername(String username) async {
    final String usernameLower = _normalizeAdminUsername(username);
    if (usernameLower.isEmpty) return null;
    final usernameDoc = await _db
        .collection('admin_usernames')
        .doc(usernameLower)
        .getCounted();
    String mobile = (usernameDoc.data()?['mobile'] as String? ?? '').trim();
    if (mobile.isNotEmpty) return mobile;

    final byUsername = await _db
        .collection('masjid_admin_auth')
        .where('usernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (byUsername.docs.isEmpty) return null;
    final data = byUsername.docs.first.data();
    mobile = (data['mobile'] as String? ?? byUsername.docs.first.id).trim();
    if (mobile.isEmpty) return null;

    await _db.collection('admin_usernames').doc(usernameLower).set({
      'mobile': mobile,
      'role': 'masjid_admin',
      'username': (data['username'] as String? ?? usernameLower),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
      return mobile;
    }

  Future<bool> adminExistsByUsername(String username) async {
    final String usernameLower = _normalizeAdminUsername(username);
    if (usernameLower.isEmpty) return false;

    final usernameDoc = await _db
        .collection('admin_usernames')
        .doc(usernameLower)
        .getCounted();
    if (usernameDoc.exists) return true;

    final byUsername = await _db
        .collection('masjid_admin_auth')
        .where('usernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (byUsername.docs.isNotEmpty) return true;

    final legacy = await _db
        .collection('users')
        .where('role', isEqualTo: 'masjid_admin')
        .where('adminUsernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (legacy.docs.isNotEmpty) return true;

    final masjidSnap = await _db
        .collection('masjids')
        .where('adminUsernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    return masjidSnap.docs.isNotEmpty;
  }

  Future<Map<String, String>?> getSecurityHintForUser(String mobile) async {
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) return null;
    final doc = await _db.collection('users').doc(normalizedMobile).getCounted();
    if (!doc.exists) return null;
    final data = doc.data() ?? <String, dynamic>{};
    final String question = (data['securityQuestion'] as String? ?? '').trim();
    final String answer = (data['securityAnswer'] as String? ?? '').trim();
    if (question.isEmpty || answer.isEmpty) return null;
    return {'question': question, 'answer': answer};
  }

  Future<Map<String, String>?> getSecurityHintForAdmin(String username) async {
    final String usernameLower = _normalizeAdminUsername(username);
    if (usernameLower.isEmpty) return null;

    final usernameDoc = await _db
        .collection('admin_usernames')
        .doc(usernameLower)
        .getCounted();
    if (usernameDoc.exists) {
      final raw = usernameDoc.data();
      final data = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      final String question = (data['securityQuestion'] as String? ?? '').trim();
      final String answer = (data['securityAnswer'] as String? ?? '').trim();
      if (question.isNotEmpty && answer.isNotEmpty) {
        return {'question': question, 'answer': answer};
      }
    }

    final byUsername = await _db
        .collection('masjid_admin_auth')
        .where('usernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (byUsername.docs.isNotEmpty) {
      final data = byUsername.docs.first.data();
      final String question = (data['securityQuestion'] as String? ?? '').trim();
      final String answer = (data['securityAnswer'] as String? ?? '').trim();
      if (question.isNotEmpty && answer.isNotEmpty) {
        return {'question': question, 'answer': answer};
      }
    }

    final legacy = await _db
        .collection('users')
        .where('role', isEqualTo: 'masjid_admin')
        .where('adminUsernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (legacy.docs.isNotEmpty) {
      final data = legacy.docs.first.data();
      final String question = (data['securityQuestion'] as String? ?? '').trim();
      final String answer = (data['securityAnswer'] as String? ?? '').trim();
      if (question.isNotEmpty && answer.isNotEmpty) {
        return {'question': question, 'answer': answer};
      }
    }

    final masjidSnap = await _db
        .collection('masjids')
        .where('adminUsernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (masjidSnap.docs.isNotEmpty) {
      final data = masjidSnap.docs.first.data();
      final String question = (data['securityQuestion'] as String? ?? '').trim();
      final String answer = (data['securityAnswer'] as String? ?? '').trim();
      if (question.isNotEmpty && answer.isNotEmpty) {
        return {'question': question, 'answer': answer};
      }
    }

    return null;
  }

  Future<bool> verifySecurityHint({
    required String role,
    required String identifier,
    required String answer,
  }) async {
    final normalizedAnswer = _normalizeHintAnswer(answer);
    if (normalizedAnswer.isEmpty) return false;
    if (role == 'masjid_admin') {
      final hint = await getSecurityHintForAdmin(identifier);
      if (hint == null) return false;
      return _normalizeHintAnswer(hint['answer'] ?? '') == normalizedAnswer;
    }
    final hint = await getSecurityHintForUser(identifier);
    if (hint == null) return false;
    return _normalizeHintAnswer(hint['answer'] ?? '') == normalizedAnswer;
  }

  Future<int> seedDefaultSecurityHintsForAll({
    required String question,
    required String answer,
  }) async {
    final String q = question.trim();
    final String a = _normalizeHintAnswer(answer);
    if (q.isEmpty || a.isEmpty) return 0;

    Future<int> seedCollection(String collection) async {
      int updated = 0;
      DocumentSnapshot? last;
      const int batchLimit = 400;
      while (true) {
        Query query = _db.collection(collection).limit(batchLimit);
        if (last != null) {
          query = query.startAfterDocument(last);
        }
        final snap = await query.getCounted();
        if (snap.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.set(doc.reference, {
            'securityQuestion': q,
            'securityAnswer': a,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
        updated += snap.docs.length;
        last = snap.docs.last;
        if (snap.docs.length < batchLimit) break;
      }
      return updated;
    }

    final usersUpdated = await seedCollection('users');
    final adminsUpdated = await seedCollection('masjid_admin_auth');
    return usersUpdated + adminsUpdated;
  }

  Future<int> seedDefaultSecurityHintsForAdminUsernames({
    required String question,
    required String answer,
    bool overwrite = false,
  }) async {
    final String q = question.trim();
    final String a = _normalizeHintAnswer(answer);
    if (q.isEmpty || a.isEmpty) return 0;

    int updated = 0;
    DocumentSnapshot? last;
    const int batchLimit = 400;

    while (true) {
      Query query = _db.collection('admin_usernames').limit(batchLimit);
      if (last != null) {
        query = query.startAfterDocument(last);
      }
      final snap = await query.getCounted();
      if (snap.docs.isEmpty) break;

      final batch = _db.batch();
      for (final doc in snap.docs) {
        final raw = doc.data();
        final data = raw is Map<String, dynamic>
            ? raw
            : Map<String, dynamic>.from(raw as Map);
        final String existingQ =
            (data['securityQuestion'] as String? ?? '').trim();
        final String existingA =
            (data['securityAnswer'] as String? ?? '').trim();
        if (!overwrite && existingQ.isNotEmpty && existingA.isNotEmpty) {
          continue;
        }

        batch.set(doc.reference, {
          'securityQuestion': q,
          'securityAnswer': a,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        updated++;
      }
      await batch.commit();
      last = snap.docs.last;
    }

    return updated;
  }

  Future<int> hashPlainPasswordsForAll() async {
    Future<int> hashCollection(String collection) async {
      int updated = 0;
      DocumentSnapshot? last;
      const int batchLimit = 400;
      while (true) {
        Query query = _db.collection(collection).limit(batchLimit);
        if (last != null) {
          query = query.startAfterDocument(last);
        }
        final snap = await query.getCounted();
        if (snap.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          final String password = (data['password'] as String? ?? '').trim();
          final String plain =
              (data['plainPassword'] as String? ?? '').trim();
          if (password.isEmpty && plain.isEmpty) continue;

          if (_looksLikeSha256(password)) {
            if (plain.isNotEmpty) {
              batch.set(doc.reference, {
                'plainPassword': FieldValue.delete(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
            continue;
          }

          final String source = password.isNotEmpty ? password : plain;
          final String hashed = _hashPassword(source);
          batch.set(doc.reference, {
            'password': hashed,
            'plainPassword': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        }
        await batch.commit();
        updated += snap.docs.length;
        last = snap.docs.last;
        if (snap.docs.length < batchLimit) break;
      }
      return updated;
    }

    final usersUpdated = await hashCollection('users');
    final adminsUpdated = await hashCollection('masjid_admin_auth');
    return usersUpdated + adminsUpdated;
  }

  Future<int> clearEmailDataForAll() async {
    Future<int> clearCollection(String collection, Map<String, dynamic> fields) async {
      int updated = 0;
      DocumentSnapshot? last;
      const int batchLimit = 400;
      while (true) {
        Query query = _db.collection(collection).limit(batchLimit);
        if (last != null) {
          query = query.startAfterDocument(last);
        }
        final snap = await query.getCounted();
        if (snap.docs.isEmpty) break;

        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.set(doc.reference, fields, SetOptions(merge: true));
        }
        await batch.commit();
        updated += snap.docs.length;
        last = snap.docs.last;
        if (snap.docs.length < batchLimit) break;
      }
      return updated;
    }

    final usersUpdated = await clearCollection('users', {
      'email': FieldValue.delete(),
      'authEmail': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final adminsUpdated = await clearCollection('masjid_admin_auth', {
      'email': FieldValue.delete(),
      'authEmail': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final masjidsUpdated = await clearCollection('masjids', {
      'email': FieldValue.delete(),
      'adminEmail': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final usernameUpdated = await clearCollection('admin_usernames', {
      'authEmail': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return usersUpdated + adminsUpdated + masjidsUpdated + usernameUpdated;
  }

  Future<Map<String, dynamic>> getAdminUsernameMigrationState(
    String mobile,
  ) async {
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) {
      return {
        'isAdmin': false,
        'username': null,
        'usernameLower': null,
        'suggestedUsername': null,
      };
    }

    final authDoc = await _db
        .collection('masjid_admin_auth')
        .doc(normalizedMobile)
        .getCounted();

    Map<String, dynamic>? adminData = authDoc.data();

    if (adminData == null) {
      final legacyDoc = await _db
          .collection('users')
          .doc(normalizedMobile)
          .getCounted();
      final legacyData = legacyDoc.data();
      if (legacyData != null && legacyData['role'] == 'masjid_admin') {
        adminData = legacyData;
      }
    }

    if (adminData == null) {
      return {
        'isAdmin': false,
        'username': null,
        'usernameLower': null,
        'suggestedUsername': null,
      };
    }

    final String username = (adminData['username'] as String? ?? '').trim();
    final String usernameLower = _normalizeAdminUsername(
      adminData['usernameLower'] as String? ?? username,
    );
    final String adminName = (adminData['name'] as String? ?? '').trim();
    final String suggestion = _buildAdminUsernameBase(
      fullName: adminName,
      mobile: normalizedMobile,
    );

    return {
      'isAdmin': true,
      'username': username.isNotEmpty ? username : null,
      'usernameLower': usernameLower.isNotEmpty ? usernameLower : null,
      'suggestedUsername': suggestion,
    };
  }

  Future<String> createAdminUsernameForMobile(String mobile) async {
    final String normalizedMobile = mobile.trim();
    if (normalizedMobile.isEmpty) {
      throw StateError('Invalid mobile number');
    }

    final adminRef = _db.collection('masjid_admin_auth').doc(normalizedMobile);
    final legacyRef = _db.collection('users').doc(normalizedMobile);
    final adminSnapshot = await adminRef.getCounted();
    final legacySnapshot = await legacyRef.getCounted();
    final legacyData = legacySnapshot.data();

    final bool hasLegacyAdmin =
        legacyData != null && legacyData['role'] == 'masjid_admin';

    Map<String, dynamic>? adminData = adminSnapshot.data();
    if (adminData == null && !hasLegacyAdmin) {
      throw StateError('Admin account not found');
    }
    adminData ??= legacyData;

    final String existingUsername = (adminData?['username'] as String? ?? '')
        .trim();
    final String existingUsernameLower = _normalizeAdminUsername(
      adminData?['usernameLower'] as String? ?? existingUsername,
    );

    if (existingUsernameLower.isNotEmpty) {
      final indexRef = _db.collection('admin_usernames').doc(existingUsernameLower);
      final indexSnap = await indexRef.getCounted();
      if (!indexSnap.exists) {
        await indexRef.set({
          'mobile': normalizedMobile,
          'role': 'masjid_admin',
          'username': existingUsername.isEmpty
              ? existingUsernameLower
              : existingUsername,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return existingUsername.isEmpty ? existingUsernameLower : existingUsername;
    }

    final String adminName = (adminData?['name'] as String? ?? '').trim();
    final String base = _buildAdminUsernameBase(
      fullName: adminName,
      mobile: normalizedMobile,
    );

    String? chosen;
    for (int i = 0; i < 100; i++) {
      final candidate = i == 0 ? base : '${base}_$i';
      final usernameLower = _normalizeAdminUsername(candidate);
      if (usernameLower.isEmpty) continue;

      try {
        await _db.runTransaction((txn) async {
          final currentAdmin = await txn.get(adminRef);
          if (!currentAdmin.exists && !hasLegacyAdmin) {
            throw StateError('Admin account no longer exists');
          }
          final currentData = currentAdmin.data() ?? <String, dynamic>{};
          final currentLower = _normalizeAdminUsername(
            currentData['usernameLower'] as String? ??
                currentData['username'] as String?,
          );
          if (currentLower.isNotEmpty) {
            chosen = currentData['username'] as String? ?? currentLower;
            return;
          }

          final usernameRef = _db.collection('admin_usernames').doc(usernameLower);
          final usernameSnap = await txn.get(usernameRef);
          final takenBy = (usernameSnap.data()?['mobile'] as String? ?? '').trim();
          if (usernameSnap.exists && takenBy.isNotEmpty && takenBy != normalizedMobile) {
            throw StateError('username_taken');
          }

          txn.set(usernameRef, {
            'mobile': normalizedMobile,
            'role': 'masjid_admin',
            'username': candidate,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          txn.set(adminRef, {
            'username': candidate,
            'usernameLower': usernameLower,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          if (hasLegacyAdmin) {
            txn.set(legacyRef, {
              'username': candidate,
              'usernameLower': usernameLower,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }

          chosen = candidate;
        });
      } catch (e) {
        if (e is StateError && e.message == 'username_taken') {
          continue;
        }
        rethrow;
      }

      if (chosen != null && chosen!.isNotEmpty) {
        break;
      }
    }

    if (chosen == null || chosen!.isEmpty) {
      throw StateError('Could not allocate a unique username');
    }

    final masjidSnap = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: normalizedMobile)
        .getCounted();
    if (masjidSnap.docs.isNotEmpty) {
      final batch = _db.batch();
      final lower = _normalizeAdminUsername(chosen);
      for (final doc in masjidSnap.docs) {
        batch.set(doc.reference, {
          'adminUsername': chosen,
          'adminUsernameLower': lower,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    return chosen!;
  }

  // ==============================
  // GET MASJIDS BY OWNER
  // ==============================
  Future<List<Masjid>> getMasjidsByOwner(String ownerMobile) async {
    final snapshot = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: ownerMobile)
        .getCounted();

    return snapshot.docs
        .map((doc) => _safeMasjidFromDoc(doc))
        .whereType<Masjid>()
        .toList();
  }

  QueryDocumentSnapshot<Map<String, dynamic>> _selectPreferredMasjidDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    QueryDocumentSnapshot<Map<String, dynamic>> selected = docs.first;
    int selectedUpdatedMs = _toMillis(selected.data()['updatedAt']);

    for (final doc in docs) {
      final data = doc.data();
      final bool approved =
          (data['approved'] as bool?) ??
          ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');
      final int updatedMs = _toMillis(data['updatedAt']);
      final bool selectedApproved =
          (selected.data()['approved'] as bool?) ??
          ((selected.data()['approvalStatus'] as String?)?.toLowerCase() ==
              'approved');

      if (approved && !selectedApproved) {
        selected = doc;
        selectedUpdatedMs = updatedMs;
        continue;
      }
      if (approved == selectedApproved && updatedMs > selectedUpdatedMs) {
        selected = doc;
        selectedUpdatedMs = updatedMs;
      }
    }

    return selected;
  }

  // ==============================
  // ONE-TIME ADMIN USERNAME MAPPING REPAIR
  // ==============================
  Future<bool> repairAdminUsernameMapping(String usernameLower) async {
    final String lower = _normalizeAdminUsername(usernameLower);
    if (lower.isEmpty) return false;

    try {
      final usernameRef = _db.collection('admin_usernames').doc(lower);
      final usernameSnap = await usernameRef.getCounted();
      if (!usernameSnap.exists) return false;
      final usernameData = usernameSnap.data() ?? <String, dynamic>{};
      String? resolvedMasjidId;
      final byUsername = await _db
          .collection('masjids')
          .where('adminUsernameLower', isEqualTo: lower)
          .getCounted();
      if (byUsername.docs.isNotEmpty) {
        final selected = _selectPreferredMasjidDoc(byUsername.docs);
        resolvedMasjidId = selected.id;
      } else {
        final String indexed =
            (usernameData['masjidId'] as String? ?? '').trim();
        if (indexed.isNotEmpty) {
          final doc = await _db.collection('masjids').doc(indexed).getCounted();
          if (doc.exists) resolvedMasjidId = doc.id;
        }
      }

      if (resolvedMasjidId == null || resolvedMasjidId.isEmpty) {
        return false;
      }

      final String currentIndexed =
          (usernameData['masjidId'] as String? ?? '').trim();
      if (currentIndexed != resolvedMasjidId) {
        await usernameRef.set({
          'masjidId': resolvedMasjidId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final masjidDoc =
          await _db.collection('masjids').doc(resolvedMasjidId).getCounted();
      if (masjidDoc.exists) {
        final data = masjidDoc.data() ?? <String, dynamic>{};
        final String adminLower =
            (data['adminUsernameLower'] as String? ?? '').trim();
        final String adminName =
            (data['adminUsername'] as String? ?? '').trim();
        final String storedUsername =
            (usernameData['username'] as String? ?? '').trim();
        if (adminLower != lower || adminName.isEmpty) {
          await _db.collection('masjids').doc(resolvedMasjidId).update({
            'adminUsernameLower': lower,
            if (adminName.isEmpty && storedUsername.isNotEmpty)
              'adminUsername': storedUsername,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int?> backfillAdminUsernameMappingsOnce() async {
    try {
      final snapshot = await _db.collection('admin_usernames').getCounted();
      int updated = 0;
      for (final doc in snapshot.docs) {
        final String lower = _normalizeAdminUsername(doc.id);
        if (lower.isEmpty) continue;
        final bool ok = await repairAdminUsernameMapping(lower);
        if (ok) updated++;
      }
      return updated;
    } catch (_) {
      return null;
    }
  }

  // Prefer this to repair all mappings based on masjid docs (source of truth).
  Future<int?> backfillAdminUsernameMappingsFromMasjidsOnce() async {
    try {
      final snapshot = await _db.collection('masjids').getCounted();
      int updated = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final String adminLower = _normalizeAdminUsername(
          data['adminUsernameLower'] as String? ??
              data['adminUsername'] as String? ??
              '',
        );
        if (adminLower.isEmpty) continue;

        final String storedLower =
            (data['adminUsernameLower'] as String? ?? '').trim();
        if (storedLower != adminLower) {
          await _db.collection('masjids').doc(doc.id).update({
            'adminUsernameLower': adminLower,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          updated++;
        }

        final usernameRef = _db.collection('admin_usernames').doc(adminLower);
        await usernameRef.set({
          'masjidId': doc.id,
          if ((data['ownerMobile'] as String? ?? '').trim().isNotEmpty)
            'mobile': (data['ownerMobile'] as String).trim(),
          if ((data['adminUsername'] as String? ?? '').trim().isNotEmpty)
            'username': (data['adminUsername'] as String).trim(),
          'role': 'masjid_admin',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        updated++;
      }

      return updated;
    } catch (_) {
      return null;
    }
  }

  // One-time backfill for admin login: copies passwords from masjid_admin_auth
  // into admin_usernames, and seeds bulk-added admins with default 123.
  Future<int?> backfillAdminUsernamesForLoginOnce() async {
    try {
      int updated = 0;
      final Set<String> authUsernames = <String>{};

      // 1) Copy from masjid_admin_auth (source of real passwords).
      final authSnap = await _db.collection('masjid_admin_auth').getCounted();
      for (final doc in authSnap.docs) {
        final data = doc.data();
        final String lower = _normalizeAdminUsername(
          data['usernameLower'] as String? ??
              data['username'] as String? ??
              '',
        );
        if (lower.isEmpty) continue;
        authUsernames.add(lower);

        final usernameRef = _db.collection('admin_usernames').doc(lower);
        final usernameSnap = await usernameRef.getCounted();
        final existing = usernameSnap.data() ?? <String, dynamic>{};
        final String existingPassword =
            (existing['password'] as String? ?? '').trim();
        final String authPassword =
            (data['password'] as String? ?? '').trim();

        if (existingPassword.isEmpty && authPassword.isNotEmpty) {
          await usernameRef.set({
            'password': authPassword,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          updated++;
        }

        // Fill missing metadata without overwriting existing values.
        await usernameRef.set({
          if ((existing['username'] as String? ?? '').trim().isEmpty)
            'username': (data['username'] as String? ?? '').trim(),
          if ((existing['mobile'] as String? ?? '').trim().isEmpty)
            'mobile': (data['mobile'] as String? ?? '').trim(),
          if ((existing['masjidId'] as String? ?? '').trim().isEmpty)
            'masjidId': (data['masjidId'] as String? ?? '').trim(),
          if (!existing.containsKey('approved') && data.containsKey('approved'))
            'approved': data['approved'],
          'role': 'masjid_admin',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 2) Seed bulk-added admins from masjids (default password 123).
      final masjidSnap = await _db.collection('masjids').getCounted();
      for (final doc in masjidSnap.docs) {
        final data = doc.data();
        final String lower = _normalizeAdminUsername(
          data['adminUsernameLower'] as String? ??
              data['adminUsername'] as String? ??
              '',
        );
        if (lower.isEmpty) continue;
        if (authUsernames.contains(lower)) continue;

        final usernameRef = _db.collection('admin_usernames').doc(lower);
        final usernameSnap = await usernameRef.getCounted();
        final existing = usernameSnap.data() ?? <String, dynamic>{};
        final String existingPassword =
            (existing['password'] as String? ?? '').trim();

        if (existingPassword.isEmpty) {
          await usernameRef.set({
            'password': _hashPassword('123'),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          updated++;
        }

        await usernameRef.set({
          if ((existing['username'] as String? ?? '').trim().isEmpty)
            'username': (data['adminUsername'] as String? ?? '').trim(),
          if ((existing['mobile'] as String? ?? '').trim().isEmpty)
            'mobile': (data['ownerMobile'] as String? ?? '').trim(),
          if ((existing['masjidId'] as String? ?? '').trim().isEmpty)
            'masjidId': doc.id,
          if (!existing.containsKey('approved') && data.containsKey('approved'))
            'approved': data['approved'],
          'role': 'masjid_admin',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return updated;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> auditAdminUsernameMappings() async {
    try {
      final snapshot = await _db.collection('masjids').getCounted();
      final Map<String, List<String>> byUsername = {};
      final List<String> missingIds = [];
      int total = 0;
      int missingUsername = 0;

      for (final doc in snapshot.docs) {
        total++;
        final data = doc.data();
        final String adminLower = _normalizeAdminUsername(
          data['adminUsernameLower'] as String? ??
              data['adminUsername'] as String? ??
              '',
        );
        if (adminLower.isEmpty) {
          missingUsername++;
          missingIds.add(doc.id);
          continue;
        }
        byUsername.putIfAbsent(adminLower, () => <String>[]).add(doc.id);
      }

      final List<String> duplicates = [];
      final Map<String, List<String>> duplicateDetails = {};
      int duplicateCount = 0;
      byUsername.forEach((key, ids) {
        if (ids.length > 1) {
          duplicateCount++;
          if (duplicates.length < 5) {
            duplicates.add('$key(${ids.length})');
          }
          duplicateDetails[key] = ids;
        }
      });

      return {
        'total': total,
        'missingUsername': missingUsername,
        'missingIds': missingIds,
        'duplicateCount': duplicateCount,
        'duplicateSamples': duplicates,
        'duplicateDetails': duplicateDetails,
      };
    } catch (_) {
      return null;
    }
  }

  // ==============================
  // GET MASJID DETAILS
  // ==============================
  Future<Map<String, dynamic>?> getMasjidDetails(String ownerMobile) async {
    final snapshot = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: ownerMobile)
        .getCounted();

    if (snapshot.docs.isEmpty) return null;
    final selected = _selectPreferredMasjidDoc(snapshot.docs);
    return selected.data();
  }

  // ==============================
  // GET MASJID DETAILS BY ID
  // ==============================
  Future<Map<String, dynamic>?> getMasjidDetailsById(String masjidId) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return null;

    final doc = await _db.collection('masjids').doc(id).getCounted();
    if (!doc.exists) return null;
    return doc.data();
  }

  // ==============================
  // GET MASJID BY ID
  // ==============================
  Future<Masjid?> getMasjidById(String masjidId) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return null;

    final doc = await _db.collection('masjids').doc(id).getCounted();
    if (!doc.exists) return null;
    return _safeMasjidFromDoc(doc);
  }

  // ==============================
  // UPDATE PASSWORD
  // ==============================
  Future<void> updatePassword(String mobile, String newPassword) async {
    final String hashedPassword = _hashPassword(newPassword);
    await _db.collection('users').doc(mobile).update({
      'password': hashedPassword,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAdminPasswordByUsername(
    String username,
    String newPassword,
  ) async {
    final String usernameLower = _normalizeAdminUsername(username);
    if (usernameLower.isEmpty) {
      throw StateError('Admin account not found');
    }

    final String hashedPassword = _hashPassword(newPassword);
    await _db.collection('admin_usernames').doc(usernameLower).set({
      'password': hashedPassword,
      'role': 'masjid_admin',
      'username': username,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final adminAuthSnap = await _db
        .collection('masjid_admin_auth')
        .where('usernameLower', isEqualTo: usernameLower)
        .limit(1)
        .getCounted();
    if (adminAuthSnap.docs.isNotEmpty) {
      await adminAuthSnap.docs.first.reference.set({
        'password': hashedPassword,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // ==============================
  // UPDATE MASJID
  // ==============================
  Future<void> updateMasjid(Masjid masjid) async {
    final String? geoHash =
        masjid.latitude != null && masjid.longitude != null
        ? GeoHashUtils.encode(masjid.latitude!, masjid.longitude!, precision: 6)
        : null;

    String previousVillageKey = '';
    try {
      final oldDoc = await _db.collection('masjids').doc(masjid.id).getCounted();
      final oldData = oldDoc.data();
      previousVillageKey = _toVillageKey(oldData?['village'] as String?);
    } catch (_) {}

    await _db.collection('masjids').doc(masjid.id).update({
      'name': masjid.name,
      'address': masjid.address,
      'latitude': masjid.latitude,
      'longitude': masjid.longitude,
      'geoHash': geoHash,
      'state': masjid.state,
      'district': masjid.district,
      'village': masjid.village,
      'villagekey': _toVillageKey(masjid.village),
      'fajr': masjid.fajr,
      'dhuhr': masjid.dhuhr,
      'asar': masjid.asr,
      'maghrib': masjid.maghrib,
      'isha': masjid.isha,
      'juma': masjid.juma,
      'fajr_azan': masjid.fajr_azan,
      'fajr_jamat': masjid.fajr_jamat,
      'dhuhr_azan': masjid.dhuhr_azan,
      'dhuhr_jamat': masjid.dhuhr_jamat,
      'asar_azan': masjid.asar_azan,
      'asar_jamat': masjid.asar_jamat,
      'maghrib_azan': masjid.maghrib_azan,
      'maghrib_jamat': masjid.maghrib_jamat,
      'isha_azan': masjid.isha_azan,
      'isha_jamat': masjid.isha_jamat,
      'juma_azan': masjid.juma_azan,
      'juma_jamat': masjid.juma_jamat,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final String ownerMobile = (masjid.ownerMobile ?? '').trim();
    if (ownerMobile.isNotEmpty) {
      await _db.collection('masjid_admin_auth').doc(ownerMobile).set({
        'masjidName': masjid.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final legacyDoc = await _db.collection('users').doc(ownerMobile).getCounted();
      if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
        await _db.collection('users').doc(ownerMobile).set({
          'masjidName': masjid.name,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    final newVillageKey = _toVillageKey(masjid.village ?? '');
    final Set<String> impactedVillageKeys = <String>{
      if (previousVillageKey.isNotEmpty) previousVillageKey,
      if (newVillageKey.isNotEmpty) newVillageKey,
    };
    for (final key in impactedVillageKeys) {
      try {
        await _upsertVillageTimingSnapshot(key);
      } catch (_) {}
    }
    if (newVillageKey.isNotEmpty) {
      try {
        await _upsertRegisteredCatalogEntry(
          state: (masjid.state ?? '').trim(),
          district: (masjid.district ?? '').trim(),
          mandal: (masjid.mandal ?? '').trim(),
          village: (masjid.village ?? '').trim(),
          villageKey: newVillageKey,
        );
      } catch (_) {}
    }
  }

  // ==============================
  // UPDATE MASJID LOCATION
  // ==============================
  Future<void> updateMasjidLocationById({
    required String masjidId,
    required double latitude,
    required double longitude,
  }) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return;

    final doc = await _db.collection('masjids').doc(id).getCounted();
    if (!doc.exists) return;
    final data = doc.data() ?? <String, dynamic>{};
    final String villageKey = _toVillageKey(data['village'] as String?);
    final String? geoHash = GeoHashUtils.encode(
      latitude,
      longitude,
      precision: 6,
    );

    await _db.collection('masjids').doc(id).update({
      'latitude': latitude,
      'longitude': longitude,
      'geoHash': geoHash,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (villageKey.isNotEmpty) {
      try {
        await _upsertVillageTimingSnapshot(villageKey);
        await _upsertRegisteredVillageSnapshot(villageKey);
      } catch (_) {}
    }
  }

  Future<void> updateMasjidLocation({
    required String ownerMobile,
    required double latitude,
    required double longitude,
  }) async {
    final String mobile = ownerMobile.trim();
    if (mobile.isEmpty) return;

    final snapshot = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: mobile)
        .getCounted();
    if (snapshot.docs.isEmpty) return;

    final String? geoHash = GeoHashUtils.encode(
      latitude,
      longitude,
      precision: 6,
    );
    final WriteBatch batch = _db.batch();
    final Set<String> villageKeys = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final String villageKey = _toVillageKey(data['village'] as String?);
      if (villageKey.isNotEmpty) villageKeys.add(villageKey);
      batch.update(doc.reference, {
        'latitude': latitude,
        'longitude': longitude,
        'geoHash': geoHash,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    for (final key in villageKeys) {
      try {
        await _upsertVillageTimingSnapshot(key);
        await _upsertRegisteredVillageSnapshot(key);
      } catch (_) {}
    }
  }

  // ==============================
  // UPDATE SALAH TIMINGS
  // ==============================
  Future<void> updateMasjidTimings(
    String ownerMobile,
    Map<String, dynamic> timings,
  ) async {
    final snapshot = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: ownerMobile)
        .getCounted();

    if (snapshot.docs.isEmpty) return;

    final WriteBatch batch = _db.batch();
    final Map<String, List<_TimingUpdate>> updatesByVillage = {};

    for (final masjidDoc in snapshot.docs) {
      final String villageKey =
          _toVillageKey(masjidDoc.data()['village'] as String?);
      final Map<String, dynamic> merged = {
        ...masjidDoc.data(),
        ...timings,
        'isTimingConfigured': 1,
        if (villageKey.isNotEmpty) 'villagekey': villageKey,
      };
      batch.update(masjidDoc.reference, {
        ...timings,
        'isTimingConfigured': 1,
        if (villageKey.isNotEmpty) 'villagekey': villageKey,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (villageKey.isNotEmpty) {
        updatesByVillage
            .putIfAbsent(villageKey, () => <_TimingUpdate>[])
            .add(_TimingUpdate(masjidDoc.id, merged));
      }
    }

    await batch.commit();
    print(
      'updateMasjidTimings: updated ${snapshot.docs.length} masjid docs for owner $ownerMobile',
    );

    // Keep timing snapshots in sync after each timing change, without
    // re-reading the full village collection when possible.
    for (final entry in updatesByVillage.entries) {
      try {
        await _applyTimingUpdatesToVillageSnapshots(
          villageKey: entry.key,
          updates: entry.value,
        );
        print('Snapshot sync success for ${entry.key}');
      } catch (e) {
        print('Snapshot sync failed for ${entry.key}: $e');
      }
    }
  }

  // ==============================
  // UPDATE SALAH TIMINGS (BY MASJID ID)
  // ==============================
  Future<void> updateMasjidTimingsById(
    String masjidId,
    Map<String, dynamic> timings,
  ) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return;

    final doc = await _db.collection('masjids').doc(id).getCounted();
    if (!doc.exists) return;
    final data = doc.data() ?? <String, dynamic>{};
    final String villageKey = _toVillageKey(data['village'] as String?);
    final Map<String, dynamic> merged = {
      ...data,
      ...timings,
      'isTimingConfigured': 1,
      if (villageKey.isNotEmpty) 'villagekey': villageKey,
    };

    await _db.collection('masjids').doc(id).update({
      ...timings,
      'isTimingConfigured': 1,
      if (villageKey.isNotEmpty) 'villagekey': villageKey,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (villageKey.isNotEmpty) {
      try {
        await _applyTimingUpdatesToVillageSnapshots(
          villageKey: villageKey,
          updates: [ _TimingUpdate(id, merged) ],
        );
        print('Snapshot sync success for $villageKey');
      } catch (e) {
        print('Snapshot sync failed for $villageKey: $e');
      }
    }
  }

  Future<void> _applyTimingUpdatesToVillageSnapshots({
    required String villageKey,
    required List<_TimingUpdate> updates,
  }) async {
    if (villageKey.isEmpty || updates.isEmpty) return;

    final timingRef =
        _db.collection('village_timing_snapshots').doc(villageKey);
    final timingSnap = await timingRef.getCounted();
    final timingData = timingSnap.data();
    if (timingData == null || timingData['timings'] is! List) {
      await _upsertVillageTimingSnapshot(villageKey);
    } else {
      final List<Map<String, dynamic>> timings = (timingData['timings'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      for (final update in updates) {
        final data = update.data;
        final bool approved =
            (data['approved'] as bool?) ??
            ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');
        final dynamic configured = data['isTimingConfigured'];
        final bool isConfigured = configured == 1 || configured == true;

        final int idx = timings.indexWhere(
          (e) => (e['masjidId'] as String? ?? '') == update.id,
        );

        if (!approved || !isConfigured) {
          if (idx >= 0) timings.removeAt(idx);
          continue;
        }

        final double? latitude = _parseCoordinate(data['latitude']);
        final double? longitude = _parseCoordinate(data['longitude']);
        final String village = (data['village'] as String? ?? '').trim();

        final Map<String, dynamic> item = {
          'masjidId': update.id,
          'name': data['name'] as String? ?? '',
          'village': village,
          'fajr_azan': data['fajr_azan'] as String? ?? '',
          'fajr_jamat': data['fajr_jamat'] as String? ?? '',
          'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
          'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
          'asar_azan': data['asar_azan'] as String? ?? '',
          'asar_jamat': data['asar_jamat'] as String? ?? '',
          'maghrib_azan': data['maghrib_azan'] as String? ?? '',
          'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
          'isha_azan': data['isha_azan'] as String? ?? '',
          'isha_jamat': data['isha_jamat'] as String? ?? '',
          'juma_azan': data['juma_azan'] as String? ?? '',
          'juma_jamat': data['juma_jamat'] as String? ?? '',
          'latitude': latitude,
          'longitude': longitude,
        };

        if (idx >= 0) {
          timings[idx] = item;
        } else {
          timings.add(item);
        }
      }

      await timingRef.set({
        'timings': timings,
        'activeMasjidCount': timings.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'version': FieldValue.increment(1),
      }, SetOptions(merge: true));
      print(
        'Snapshot timing updated for $villageKey: timings=${timings.length}',
      );
    }

    final regRef =
        _db.collection('registered_village_snapshots').doc(villageKey);
    final regSnap = await regRef.getCounted();
    final regData = regSnap.data();
    if (regData == null || regData['items'] is! List) {
      await _upsertRegisteredVillageSnapshot(villageKey);
      return;
    }

    final List<Map<String, dynamic>> items = (regData['items'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    for (final update in updates) {
      final data = update.data;
      final int idx = items.indexWhere(
        (e) => (e['masjidId'] as String? ?? '') == update.id,
      );
      final bool approved =
          (data['approved'] as bool?) ??
          ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');

      final String village = (data['village'] as String? ?? '').trim();
      final Map<String, dynamic> item = {
        'masjidId': update.id,
        'name': data['name'] as String? ?? '',
        'address': data['address'] as String? ?? '',
        'state': data['state'] as String? ?? '',
        'district': data['district'] as String? ?? '',
        'mandal': data['mandal'] as String? ?? '',
        'village': village,
        'villagekey': villageKey,
        'approved': approved,
        'approvalStatus': data['approvalStatus'] as String? ?? '',
        'isTimingConfigured': data['isTimingConfigured'],
        'latitude': _parseCoordinate(data['latitude']),
        'longitude': _parseCoordinate(data['longitude']),
        'fajr_azan': data['fajr_azan'] as String? ?? '',
        'fajr_jamat': data['fajr_jamat'] as String? ?? '',
        'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
        'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
        'asar_azan':
            (data['asar_azan'] as String? ?? data['asr_azan'] as String?) ?? '',
        'asar_jamat':
            (data['asar_jamat'] as String? ?? data['asr_jamat'] as String?) ??
            '',
        'maghrib_azan': data['maghrib_azan'] as String? ?? '',
        'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
        'isha_azan': data['isha_azan'] as String? ?? '',
        'isha_jamat': data['isha_jamat'] as String? ?? '',
        'juma_azan': data['juma_azan'] as String? ?? '',
        'juma_jamat': data['juma_jamat'] as String? ?? '',
      };

      if (idx >= 0) {
        items[idx] = item;
      } else {
        items.add(item);
      }
    }

    await regRef.set({
      'items': items,
      'totalMasjids': items.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print(
      'Registered snapshot updated for $villageKey: items=${items.length}',
    );
  }

  Future<void> _upsertVillageTimingSnapshot(String villageKey) async {
    // Query only by village key, then filter locally to avoid composite index
    // failures that can silently block snapshot updates.
    final snapshot = await _db
        .collection('masjids')
        .where('villagekey', isEqualTo: villageKey)
        .getCounted();

    if (snapshot.docs.isEmpty) {
      await _db.collection('registered_village_snapshots').doc(villageKey).delete();
      await _db.collection('village_timing_snapshots').doc(villageKey).set({
        'villageName': villageKey.replaceAll('_', ' '),
        'activeMasjidCount': 0,
        'timings': const [],
        'version': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _db
          .collection('registered_catalog_snapshots')
          .doc('global')
          .set({
        'approvedVillageKeys': FieldValue.arrayRemove([villageKey]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final villageMasjids = snapshot.docs.where((doc) {
      final data = doc.data();
      final bool approved =
          (data['approved'] as bool?) ??
          ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');
      final dynamic configured = data['isTimingConfigured'];
      final bool isConfigured = configured == 1 || configured == true;
      return approved && isConfigured;
    }).toList();

    final List<Map<String, dynamic>> timings = [];
    String villageName = '';

    for (final doc in villageMasjids) {
      final data = doc.data();
      final double? latitude = _parseCoordinate(data['latitude']);
      final double? longitude = _parseCoordinate(data['longitude']);

      final currentVillage = (data['village'] as String? ?? '').trim();
      if (villageName.isEmpty && currentVillage.isNotEmpty) {
        villageName = currentVillage;
      }

      timings.add({
        'masjidId': doc.id,
        'name': data['name'] as String? ?? '',
        'village': currentVillage,
        'fajr_azan': data['fajr_azan'] as String? ?? '',
        'fajr_jamat': data['fajr_jamat'] as String? ?? '',
        'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
        'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
        'asar_azan': data['asar_azan'] as String? ?? '',
        'asar_jamat': data['asar_jamat'] as String? ?? '',
        'maghrib_azan': data['maghrib_azan'] as String? ?? '',
        'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
        'isha_azan': data['isha_azan'] as String? ?? '',
        'isha_jamat': data['isha_jamat'] as String? ?? '',
        'juma_azan': data['juma_azan'] as String? ?? '',
        'juma_jamat': data['juma_jamat'] as String? ?? '',
        'latitude': latitude,
        'longitude': longitude,
      });
    }

    final List<Map<String, dynamic>> registeredItems = <Map<String, dynamic>>[];
    String registeredVillageName = '';
    int approvedCount = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final String village = (data['village'] as String? ?? '').trim();
      if (registeredVillageName.isEmpty && village.isNotEmpty) {
        registeredVillageName = village;
      }

      final bool approved =
          (data['approved'] as bool?) ??
          ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');
      if (approved) approvedCount++;

      registeredItems.add({
        'masjidId': doc.id,
        'name': data['name'] as String? ?? '',
        'address': data['address'] as String? ?? '',
        'state': data['state'] as String? ?? '',
        'district': data['district'] as String? ?? '',
        'mandal': data['mandal'] as String? ?? '',
        'village': village,
        'villagekey': villageKey,
        'approved': approved,
        'approvalStatus': data['approvalStatus'] as String? ?? '',
        'isTimingConfigured': data['isTimingConfigured'],
        'latitude': _parseCoordinate(data['latitude']),
        'longitude': _parseCoordinate(data['longitude']),
        'fajr_azan': data['fajr_azan'] as String? ?? '',
        'fajr_jamat': data['fajr_jamat'] as String? ?? '',
        'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
        'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
        'asar_azan':
            (data['asar_azan'] as String? ?? data['asr_azan'] as String?) ?? '',
        'asar_jamat':
            (data['asar_jamat'] as String? ?? data['asr_jamat'] as String?) ?? '',
        'maghrib_azan': data['maghrib_azan'] as String? ?? '',
        'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
        'isha_azan': data['isha_azan'] as String? ?? '',
        'isha_jamat': data['isha_jamat'] as String? ?? '',
        'juma_azan': data['juma_azan'] as String? ?? '',
        'juma_jamat': data['juma_jamat'] as String? ?? '',
      });
    }

    await _db.collection('village_timing_snapshots').doc(villageKey).set({
      'villageName': villageName.isEmpty
          ? villageKey.replaceAll('_', ' ')
          : villageName,
      'activeMasjidCount': timings.length,
      'timings': timings,
      'version': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    print(
      '_upsertVillageTimingSnapshot: wrote ${timings.length} timings for villageKey=$villageKey',
    );

    await _db.collection('registered_village_snapshots').doc(villageKey).set({
      'villageKey': villageKey,
      'villageName':
          registeredVillageName.isEmpty ? villageKey : registeredVillageName,
      'totalMasjids': registeredItems.length,
      'items': registeredItems,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db
        .collection('registered_catalog_snapshots')
        .doc('global')
        .set({
      'approvedVillageKeys': approvedCount > 0
          ? FieldValue.arrayUnion([villageKey])
          : FieldValue.arrayRemove([villageKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================
  // GET DEFAULT MASJID ID (For Notifications)
  // ==============================
  Future<String?> getDefaultMasjidId(String userMobile) async {
    try {
      final doc = await _db.collection('users').doc(userMobile).getCounted();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['defaultMasjidId'] as String?;
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // ==============================
  // SET DEFAULT MASJID FOR USER
  // ==============================
  Future<void> setDefaultMasjid(String userMobile, String masjidId) async {
    await _db.collection('users').doc(userMobile).update({
      'defaultMasjidId': masjidId,
    });
  }

  // ==============================
  // GET USER DEFAULT MASJID
  // ==============================
  Future<Masjid?> getUserDefaultMasjid(String userMobile) async {
    try {
      final userDoc = await _db.collection('users').doc(userMobile).getCounted();
      if (!userDoc.exists) return null;

      final data = userDoc.data();
      if (data == null || !data.containsKey('defaultMasjidId')) return null;

      final String masjidId = data['defaultMasjidId'];
      final masjidDoc = await _db.collection('masjids').doc(masjidId).getCounted();

      if (!masjidDoc.exists) return null;

      return _safeMasjidFromDoc(masjidDoc);
    } catch (e) {
      return null;
    }
  }

  // ==============================
  // LOGIN (USER / ADMIN / SUPER ADMIN)
  // ==============================
  Future<String?> _resolveMasjidIdForAdminUsername(
    String usernameLower, {
    String? preferredMasjidName,
    ReadCounter? readCounter,
  }) async {
    if (usernameLower.isEmpty) return null;
    try {
      final ReadCounter counter =
          readCounter ?? FirebaseReadCounter.instance;
      final snapshot = await _db
          .collection('masjids')
          .where('adminUsernameLower', isEqualTo: usernameLower)
          .getCountedWith(counter);
      if (snapshot.docs.isEmpty) return null;
      final String preferred = (preferredMasjidName ?? '').trim().toLowerCase();
      if (preferred.isNotEmpty) {
        for (final doc in snapshot.docs) {
          final String name =
              (doc.data()['name'] as String? ?? '').trim().toLowerCase();
          if (name == preferred) {
            return doc.id;
          }
        }
      }

      final selected = _selectPreferredMasjidDoc(snapshot.docs);
      return selected.id;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> login(
    String identifier,
    String password, {
    ReadCounter? readCounter,
  }) async {
    try {
      final ReadCounter counter =
          readCounter ?? FirebaseReadCounter.instance;
      final String input = identifier.trim();
      if (input.isEmpty) return null;
      final userDoc = await _db
          .collection('users')
          .doc(input)
          .getCountedWith(counter);

      final userData = userDoc.data();
      final String userRole = (userData?['role'] as String? ?? '').trim();
      if (userData != null &&
          userRole != 'masjid_admin' &&
          _passwordMatches(password, userData['password'])) {
        final String resolvedMobile = (userData['mobile'] as String? ?? input).trim();
        await _ensureAuthForRole(
          role: 'user',
          mobile: resolvedMobile,
          password: password,
          allowCreate: true,
        );
        return {
          ...userData,
          'mobile': resolvedMobile,
          'role': userData['role'] ?? 'user',
        };
      }

        final String usernameLower = _normalizeAdminUsername(input);
        if (usernameLower.isEmpty) return null;

        // Admin login via masjids collection (source of truth for bulk-added).
        try {
          final masjidSnap = await _db
              .collection('masjids')
              .where('adminUsernameLower', isEqualTo: usernameLower)
              .limit(1)
              .getCountedWith(counter);
          if (masjidSnap.docs.isNotEmpty) {
            final masjidDoc = masjidSnap.docs.first;
            final masjidData = masjidDoc.data();
            final String ownerMobile =
                (masjidData['ownerMobile'] as String? ?? '').trim();
            final bool approved =
                (masjidData['approved'] as bool?) ??
                ((masjidData['approvalStatus'] as String?)?.toLowerCase() ==
                    'approved');
            final String adminUsername =
                (masjidData['adminUsername'] as String? ?? input).trim();

            String storedPassword = '';
            if (ownerMobile.isNotEmpty) {
              final adminAuthDoc = await _db
                  .collection('masjid_admin_auth')
                  .doc(ownerMobile)
                  .getCountedWith(counter);
              storedPassword =
                  (adminAuthDoc.data()?['password'] as String? ?? '').trim();
            }

            // Bulk-added admins may not have auth docs; fall back to default 123.
            if (storedPassword.isEmpty) {
              storedPassword = _hashPassword('123');
            }

            if (_passwordMatches(password, storedPassword)) {
              await _ensureAuthForAdminUsername(
                usernameLower: usernameLower,
                password: password,
                allowCreate: true,
              );

              return {
                'role': 'masjid_admin',
                'approved': approved,
                'masjidId': masjidDoc.id,
                if (ownerMobile.isNotEmpty) 'mobile': ownerMobile,
                'adminUsernameLower': usernameLower,
                if (adminUsername.isNotEmpty) 'adminUsername': adminUsername,
                'password': storedPassword,
              };
            }
          }
        } catch (_) {}

        // Admin login is username-based via admin_usernames/{usernameLower}.
        final usernameRef = _db.collection('admin_usernames').doc(usernameLower);
        var usernameDoc = await usernameRef.getCountedWith(counter);
        Map<String, dynamic>? usernameData = usernameDoc.data();

      // Backfill admin_usernames from masjid_admin_auth or masjids if missing.
      if (!usernameDoc.exists) {
        Map<String, dynamic>? adminData;
        try {
          final byUsername = await _db
              .collection('masjid_admin_auth')
              .where('usernameLower', isEqualTo: usernameLower)
              .limit(1)
              .getCountedWith(counter);
          if (byUsername.docs.isNotEmpty) {
            adminData = byUsername.docs.first.data();
          }
        } catch (_) {}

        if (adminData != null) {
          await usernameRef.set({
            'role': 'masjid_admin',
            'username': (adminData['username'] as String? ?? '').trim(),
            'password': (adminData['password'] as String? ?? '').trim(),
            if ((adminData['mobile'] as String? ?? '').trim().isNotEmpty)
              'mobile': (adminData['mobile'] as String?)?.trim(),
            if ((adminData['masjidId'] as String? ?? '').trim().isNotEmpty)
              'masjidId': (adminData['masjidId'] as String?)?.trim(),
            if (adminData.containsKey('approved')) 'approved': adminData['approved'],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          // Bulk-added masjid: create username with default password 123.
          try {
            final masjidSnap = await _db
                .collection('masjids')
                .where('adminUsernameLower', isEqualTo: usernameLower)
                .limit(1)
                .getCountedWith(counter);
            if (masjidSnap.docs.isNotEmpty) {
              final masjidDoc = masjidSnap.docs.first;
              final masjidData = masjidDoc.data();
              await usernameRef.set({
                'role': 'masjid_admin',
                'username': (masjidData['adminUsername'] as String? ?? '').trim(),
                'password': _hashPassword('123'),
                if ((masjidData['ownerMobile'] as String? ?? '').trim().isNotEmpty)
                  'mobile': (masjidData['ownerMobile'] as String?)?.trim(),
                if (masjidDoc.id.trim().isNotEmpty) 'masjidId': masjidDoc.id.trim(),
                'approved': (masjidData['approved'] as bool?) ?? false,
                'createdAt': FieldValue.serverTimestamp(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
            }
          } catch (_) {}
        }

        usernameDoc = await usernameRef.getCountedWith(counter);
        usernameData = usernameDoc.data();
      }

      final String usernamePassword =
          (usernameData?['password'] as String? ?? '').trim();
      final bool usernamePasswordOk =
          usernamePassword.isNotEmpty && _passwordMatches(password, usernamePassword);

        if (usernamePasswordOk) {
          String masjidIdFromIndex =
              (usernameData?['masjidId'] as String? ?? '').trim();
          if (masjidIdFromIndex.isNotEmpty) {
            try {
              final doc = await _db
                  .collection('masjids')
                  .doc(masjidIdFromIndex)
                  .getCounted();
              final data = doc.data();
              final String adminLower =
                  (data?['adminUsernameLower'] as String? ?? '').trim();
              if (!doc.exists || adminLower.isEmpty || adminLower != usernameLower) {
                masjidIdFromIndex = '';
              }
            } catch (_) {
              masjidIdFromIndex = '';
            }
          }

          String? masjidId =
              masjidIdFromIndex.isNotEmpty ? masjidIdFromIndex : null;
          if (masjidId == null || masjidId.isEmpty) {
            masjidId = await _resolveMasjidIdForAdminUsername(
              usernameLower,
              preferredMasjidName: '',
              readCounter: counter,
            );
            if (masjidId != null && masjidId.isNotEmpty) {
              masjidIdFromIndex = masjidId;
            }
          }

          // Enforce that the username is the current one on the masjid doc.
          if (masjidId == null || masjidId.isEmpty) {
            return null;
          }

          await _ensureAuthForAdminUsername(
            usernameLower: usernameLower,
            password: password,
            allowCreate: true,
          );

          bool approved = (usernameData?['approved'] as bool?) ?? false;
          if (!approved && masjidId.isNotEmpty) {
            try {
              final doc =
                  await _db.collection('masjids').doc(masjidId).getCounted();
              if (doc.exists) {
                final data = doc.data();
                approved =
                    (data?['approved'] as bool?) ??
                    ((data?['approvalStatus'] as String?)?.toLowerCase() ==
                        'approved');
              }
            } catch (_) {}
          }

          final String adminUsername =
              (usernameData?['username'] as String? ?? input).trim();
          final String adminMobile =
              (usernameData?['mobile'] as String? ?? '').trim();

          await _db.collection('admin_usernames').doc(usernameLower).set({
            'role': 'masjid_admin',
            'username': adminUsername.isEmpty ? usernameLower : adminUsername,
            'password': _hashPassword(password),
            if (adminMobile.isNotEmpty) 'mobile': adminMobile,
            if (masjidId.isNotEmpty) 'masjidId': masjidId,
            'approved': approved,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          return {
            ...(usernameData ?? <String, dynamic>{}),
            if (adminMobile.isNotEmpty) 'mobile': adminMobile,
            'role': 'masjid_admin',
            'approved': approved,
            if (masjidId.isNotEmpty) 'masjidId': masjidId,
            'adminUsernameLower': usernameLower,
            if (adminUsername.isNotEmpty) 'adminUsername': adminUsername,
            if (usernamePasswordOk) 'password': usernamePassword,
          };
        }

        // Legacy fallback: admin password may still exist in users collection.
        final legacyAdminDoc = await _db
            .collection('users')
            .where('role', isEqualTo: 'masjid_admin')
            .where('adminUsernameLower', isEqualTo: usernameLower)
            .limit(1)
            .getCountedWith(counter);
        if (legacyAdminDoc.docs.isNotEmpty) {
          final legacyAdminData = legacyAdminDoc.docs.first.data();
          if (_passwordMatches(password, legacyAdminData['password'])) {
            String? masjidId =
                (legacyAdminData['masjidId'] as String? ?? '').trim();
            if (masjidId == null || masjidId.isEmpty) {
              masjidId = await _resolveMasjidIdForAdminUsername(
                usernameLower,
                preferredMasjidName:
                    (legacyAdminData['masjidName'] as String? ?? '').trim(),
                readCounter: counter,
              );
            }
            if (masjidId == null || masjidId.isEmpty) {
              return null;
            }
            await _ensureAuthForAdminUsername(
              usernameLower: usernameLower,
              password: password,
              allowCreate: true,
            );
            return {
              ...legacyAdminData,
              'role': 'masjid_admin',
              if (masjidId != null) 'masjidId': masjidId,
              'adminUsernameLower': usernameLower,
          };
        }
      }

      return null;
    } catch (e) {
      print("LOGIN ERROR: $e");
      return null;
    }
  }

  Stream<Masjid?> watchMasjidById(String masjidId) {
    final String id = masjidId.trim();
    if (id.isEmpty) return const Stream<Masjid?>.empty();

    return _db.collection('masjids').doc(id).snapshotsCounted().map((doc) {
      if (!doc.exists) return null;
      return _safeMasjidFromDoc(doc);
    });
  }

  // ==============================
  // ADMIN: GET PENDING
  // ==============================
  Future<List<Map<String, dynamic>>> getPendingAdmins() async {
    try {
      final authSnap = await _db
          .collection('masjid_admin_auth')
          .where('approved', isEqualTo: false)
          .getCounted();
      final legacySnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'masjid_admin')
          .where('approved', isEqualTo: false)
          .getCounted();

      final Map<String, Map<String, dynamic>> mergedByMobile = {};
      for (final doc in authSnap.docs) {
        final data = doc.data();
        final mobile = (data['mobile'] as String? ?? '').trim();
        if (mobile.isEmpty) continue;
        mergedByMobile[mobile] = data;
      }
      for (final doc in legacySnap.docs) {
        final data = doc.data();
        final mobile = (data['mobile'] as String? ?? '').trim();
        if (mobile.isEmpty) continue;
        mergedByMobile.putIfAbsent(mobile, () => data);
      }

      List<Map<String, dynamic>> results = [];

      for (final userData in mergedByMobile.values) {
        final mobile = userData['mobile'];

        final masjidSnap = await _db
            .collection('masjids')
            .where('ownerMobile', isEqualTo: mobile)
            .limit(1)
            .getCounted();

        Map<String, dynamic> masjidData = {};
        if (masjidSnap.docs.isNotEmpty) {
          masjidData = masjidSnap.docs.first.data();
        }

        results.add({
          ...userData,
          'masjidName': masjidData['name'],
          'masjidAddress': masjidData['address'],
          'village': masjidData['village'],
          'colony': masjidData['colony'],
          'mandal': masjidData['mandal'],
          'district': masjidData['district'],
          'state': masjidData['state'],
        });
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  // ==============================
  // ADMIN: GET APPROVED
  // ==============================
  Future<List<Map<String, dynamic>>> getApprovedAdmins() async {
    try {
      final authSnap = await _db
          .collection('masjid_admin_auth')
          .where('approved', isEqualTo: true)
          .getCounted();
      final legacySnap = await _db
          .collection('users')
          .where('role', isEqualTo: 'masjid_admin')
          .where('approved', isEqualTo: true)
          .getCounted();

      final Map<String, Map<String, dynamic>> mergedByMobile = {};
      for (final doc in authSnap.docs) {
        final data = doc.data();
        final mobile = (data['mobile'] as String? ?? '').trim();
        if (mobile.isEmpty) continue;
        mergedByMobile[mobile] = data;
      }
      for (final doc in legacySnap.docs) {
        final data = doc.data();
        final mobile = (data['mobile'] as String? ?? '').trim();
        if (mobile.isEmpty) continue;
        mergedByMobile.putIfAbsent(mobile, () => data);
      }

      List<Map<String, dynamic>> results = [];

      for (final userData in mergedByMobile.values) {
        final mobile = userData['mobile'];

        final masjidSnap = await _db
            .collection('masjids')
            .where('ownerMobile', isEqualTo: mobile)
            .limit(1)
            .getCounted();

        Map<String, dynamic> masjidData = {};
        if (masjidSnap.docs.isNotEmpty) {
          masjidData = masjidSnap.docs.first.data();
        }

        results.add({
          ...userData,
          'masjidName': masjidData['name'],
          'masjidAddress': masjidData['address'],
          'village': masjidData['village'],
          'colony': masjidData['colony'],
          'mandal': masjidData['mandal'],
          'district': masjidData['district'],
          'state': masjidData['state'],
        });
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  // ==============================
  // ADMIN: APPROVE
  // ==============================
  Future<List<Map<String, dynamic>>> getPendingMasjidApplications() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _db
            .collection('masjids')
            .where('approvalStatus', isEqualTo: 'pending')
            .orderBy('createdAt', descending: true)
            .limit(200)
            .getCounted();
      } on FirebaseException catch (e) {
        // Fallback when composite index for approvalStatus + createdAt is missing.
        if (e.code != 'failed-precondition') rethrow;
        snapshot = await _db
            .collection('masjids')
            .where('approvalStatus', isEqualTo: 'pending')
            .limit(200)
            .getCounted();
      }

      final Map<String, Map<String, dynamic>> byId = {
        for (final doc in snapshot.docs) doc.id: {'id': doc.id, ...doc.data()},
      };

      // Legacy fallback: older docs may use `status` instead of `approvalStatus`.
      final legacy = await _db
          .collection('masjids')
          .where('status', isEqualTo: 'pending')
          .limit(200)
          .getCounted();
      for (final doc in legacy.docs) {
        byId.putIfAbsent(doc.id, () => {'id': doc.id, ...doc.data()});
      }

      final items = byId.values.toList(growable: false);
      items.sort(
        (a, b) => _toMillis(b['createdAt']).compareTo(_toMillis(a['createdAt'])),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getApprovedMasjidApplications() async {
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _db
            .collection('masjids')
            .where('approvalStatus', isEqualTo: 'approved')
            .orderBy('updatedAt', descending: true)
            .limit(200)
            .getCounted();
      } on FirebaseException catch (e) {
        // Fallback when composite index for approvalStatus + updatedAt is missing.
        if (e.code != 'failed-precondition') rethrow;
        snapshot = await _db
            .collection('masjids')
            .where('approvalStatus', isEqualTo: 'approved')
            .limit(200)
            .getCounted();
      }

      final Map<String, Map<String, dynamic>> byId = {
        for (final doc in snapshot.docs) doc.id: {'id': doc.id, ...doc.data()},
      };

      // Legacy fallback: older docs may only have boolean approval field.
      final legacy = await _db
          .collection('masjids')
          .where('approved', isEqualTo: true)
          .limit(200)
          .getCounted();
      for (final doc in legacy.docs) {
        byId.putIfAbsent(doc.id, () => {'id': doc.id, ...doc.data()});
      }

      final items = byId.values.toList(growable: false);
      items.sort(
        (a, b) => _toMillis(b['updatedAt']).compareTo(_toMillis(a['updatedAt'])),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  int _toMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is String) {
      final dt = DateTime.tryParse(value);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return 0;
  }

  Future<void> approveAdmin(String mobile) async {
    await _db.collection('masjid_admin_auth').doc(mobile).set({
      'approved': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Backward compatibility: keep legacy admin docs in sync when present.
    final legacyDoc = await _db.collection('users').doc(mobile).getCounted();
    if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
      await _db.collection('users').doc(mobile).update({'approved': true});
    }

    final masjidSnap = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: mobile)
        .limit(1)
        .getCounted();

    if (masjidSnap.docs.isNotEmpty) {
      final masjidDoc = masjidSnap.docs.first;
      final villageKey = _toVillageKey(masjidDoc.data()['village'] as String?);
      await _db.collection('masjids').doc(masjidDoc.id).update({
        'approved': true,
        'approvalStatus': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (villageKey.isNotEmpty) {
        try {
          await _upsertVillageTimingSnapshot(villageKey);
          final data = masjidDoc.data();
          await _upsertRegisteredCatalogEntry(
            state: (data['state'] as String? ?? '').trim(),
            district: (data['district'] as String? ?? '').trim(),
            mandal: (data['mandal'] as String? ?? '').trim(),
            village: (data['village'] as String? ?? '').trim(),
            villageKey: villageKey,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> approveMasjidApplication({
    required String masjidId,
    required String ownerMobile,
    Map<String, dynamic>? masjidData,
    Map<String, dynamic>? villageOffsets,
  }) async {
    final String id = masjidId.trim();
    String villageKey = '';
    String villageName = '';
    if (masjidData != null) {
      villageName = (masjidData['village'] as String? ?? '').trim();
      villageKey = _toVillageKey(villageName);
    }

    Map<String, dynamic>? resolvedOffsets = villageOffsets;
    if (resolvedOffsets == null && villageKey.isNotEmpty) {
      resolvedOffsets = await getVillageOffsets(villageKey);
    }

    if (id.isNotEmpty) {
      final Map<String, dynamic> update = {
        'approved': true,
        'approvalStatus': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (resolvedOffsets != null) {
        update.addAll({
          'sunriseOffsetMinutes':
              _parseInt(resolvedOffsets['sunriseOffsetMinutes']),
          'sunriseOffsetDirection': _normalizeOffsetDirection(
            resolvedOffsets['sunriseOffsetDirection'] as String?,
          ),
          'sunsetOffsetMinutes':
              _parseInt(resolvedOffsets['sunsetOffsetMinutes']),
          'sunsetOffsetDirection': _normalizeOffsetDirection(
            resolvedOffsets['sunsetOffsetDirection'] as String?,
          ),
        });
      }
      await _db.collection('masjids').doc(id).update(update);
    }

    final String mobile = ownerMobile.trim();
    if (mobile.isNotEmpty) {
      await _db.collection('masjid_admin_auth').doc(mobile).set({
        'approved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final legacyDoc = await _db.collection('users').doc(mobile).getCounted();
      if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
        await _db.collection('users').doc(mobile).update({'approved': true});
      }
    }

    try {
      final data = masjidData;
      if (data != null) {
        final villageKey = _toVillageKey(data['village'] as String?);
        if (villageKey.isNotEmpty) {
          await _upsertVillageTimingSnapshot(villageKey);
          await _upsertRegisteredCatalogEntry(
            state: (data['state'] as String? ?? '').trim(),
            district: (data['district'] as String? ?? '').trim(),
            mandal: (data['mandal'] as String? ?? '').trim(),
            village: (data['village'] as String? ?? '').trim(),
            villageKey: villageKey,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> deleteMasjidAndCleanup(
    String masjidId, {
    bool deleteOwnerAuthIfNoMasjid = false,
  }) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return;

    final masjidRef = _db.collection('masjids').doc(id);
    final masjidDoc = await masjidRef.getCounted();
    if (!masjidDoc.exists) return;

    final data = masjidDoc.data() ?? <String, dynamic>{};
    final String ownerMobile = (data['ownerMobile'] as String? ?? '').trim();
    final String villageKey = _toVillageKey(data['village'] as String?);
    final String adminUsernameLower =
        (data['adminUsernameLower'] as String? ?? '').trim();

    await masjidRef.delete();

    if (ownerMobile.isNotEmpty) {
      final remainingMasjids = await _db
          .collection('masjids')
          .where('ownerMobile', isEqualTo: ownerMobile)
          .limit(1)
          .getCounted();

      if (remainingMasjids.docs.isEmpty) {
        if (deleteOwnerAuthIfNoMasjid) {
          await _db.collection('masjid_admin_auth').doc(ownerMobile).delete();

          final legacyDoc = await _db
              .collection('users')
              .doc(ownerMobile)
              .getCounted();
          if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
            await _db.collection('users').doc(ownerMobile).delete();
          }
          if (adminUsernameLower.isNotEmpty) {
            await _db.collection('admin_usernames').doc(adminUsernameLower).delete();
          }
        }
      } else {
        final nextMasjidName =
            (remainingMasjids.docs.first.data()['name'] as String? ?? '').trim();
        if (nextMasjidName.isNotEmpty) {
          await _db.collection('masjid_admin_auth').doc(ownerMobile).set({
            'masjidName': nextMasjidName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    }

    if (villageKey.isNotEmpty) {
      try {
        await _upsertVillageTimingSnapshot(villageKey);
      } catch (_) {}
    }

    // Ensure registered catalog snapshots drop removed villages/locations too.
    try {
      await rebuildRegisteredSnapshots();
    } catch (_) {}
  }

  Future<void> deleteMasjidAdminAccount(String ownerMobile) async {
    final String mobile = ownerMobile.trim();
    if (mobile.isEmpty) return;

    final masjids = await getMasjidsByOwner(mobile);
    if (masjids.isNotEmpty) {
      for (final masjid in masjids) {
        await deleteMasjidAndCleanup(
          masjid.id,
          deleteOwnerAuthIfNoMasjid: true,
        );
      }
      return;
    }

    // No masjid docs found; still delete auth/account artifacts if present.
    String usernameLower = '';
    try {
      final authDoc =
          await _db.collection('masjid_admin_auth').doc(mobile).getCounted();
      if (authDoc.exists) {
        usernameLower =
            (authDoc.data()?['usernameLower'] as String? ?? '').trim();
        await _db.collection('masjid_admin_auth').doc(mobile).delete();
      }
    } catch (_) {}

    try {
      final legacyDoc = await _db.collection('users').doc(mobile).getCounted();
      if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
        await _db.collection('users').doc(mobile).delete();
        if (usernameLower.isEmpty) {
          usernameLower =
              (legacyDoc.data()?['adminUsernameLower'] as String? ?? '').trim();
        }
      }
    } catch (_) {}

    if (usernameLower.isNotEmpty) {
      try {
        await _db.collection('admin_usernames').doc(usernameLower).delete();
      } catch (_) {}
    }
  }

  Future<void> deletePendingMasjidApplication(String masjidId) async {
    final String id = masjidId.trim();
    if (id.isEmpty) return;

    final masjidRef = _db.collection('masjids').doc(id);
    final masjidDoc = await masjidRef.getCounted();
    if (!masjidDoc.exists) return;

    final data = masjidDoc.data() ?? <String, dynamic>{};
    final String approvalStatus =
        (data['approvalStatus'] as String? ?? '').toLowerCase();
    final String status = (data['status'] as String? ?? '').toLowerCase();
    final bool approved = (data['approved'] as bool?) ?? false;
    final bool isPending =
        (!approved) &&
        (approvalStatus == 'pending' ||
            status == 'pending' ||
            approvalStatus.isEmpty);

    if (!isPending) {
      throw StateError('Only pending masjid applications can be deleted.');
    }

    await deleteMasjidAndCleanup(id, deleteOwnerAuthIfNoMasjid: true);
  }

  // Returns a masjid plus updatedAt metadata.
  Future<Map<String, dynamic>?> getMasjidWithMetaById(String masjidId) async {
    try {
      final doc = await _db.collection('masjids').doc(masjidId).getCounted();
      if (!doc.exists) return null;
      final masjid = _safeMasjidFromDoc(doc);
      if (masjid == null) return null;
      final data = doc.data();
      final ts = data?['updatedAt'];
      final int? updatedAtMs = ts is Timestamp ? ts.millisecondsSinceEpoch : null;
      return {'masjid': masjid, 'updatedAtMs': updatedAtMs};
    } catch (e) {
      return null;
    }
  }

  // Returns masjid only if it changed after the given timestamp.
  Future<Map<String, dynamic>?> getMasjidWithMetaByIdIfUpdatedAfter({
    required String masjidId,
    required DateTime updatedAfter,
  }) async {
    try {
      final snapshot = await _db
          .collection('masjids')
          .where(FieldPath.documentId, isEqualTo: masjidId)
          .where('updatedAt', isGreaterThan: Timestamp.fromDate(updatedAfter))
          .limit(1)
          .getCounted();

      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      final masjid = _safeMasjidFromDoc(doc);
      if (masjid == null) return null;
      final data = doc.data();
      final ts = data['updatedAt'];
      final int? updatedAtMs = ts is Timestamp ? ts.millisecondsSinceEpoch : null;
      return {'masjid': masjid, 'updatedAtMs': updatedAtMs};
    } catch (e) {
      return null;
    }
  }

  // ==============================
  // ADMIN: DISAPPROVE
  // ==============================
  Future<void> disapproveAdmin(String mobile) async {
    await _db.collection('masjid_admin_auth').doc(mobile).set({
      'approved': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Backward compatibility: keep legacy admin docs in sync when present.
    final legacyDoc = await _db.collection('users').doc(mobile).getCounted();
    if (legacyDoc.exists && legacyDoc.data()?['role'] == 'masjid_admin') {
      await _db.collection('users').doc(mobile).update({'approved': false});
    }

    final masjidSnap = await _db
        .collection('masjids')
        .where('ownerMobile', isEqualTo: mobile)
        .limit(1)
        .getCounted();

    if (masjidSnap.docs.isNotEmpty) {
      final masjidDoc = masjidSnap.docs.first;
      final villageKey = _toVillageKey(masjidDoc.data()['village'] as String?);
      await _db.collection('masjids').doc(masjidDoc.id).update({
        'approved': false,
        'approvalStatus': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (villageKey.isNotEmpty) {
        try {
          await _upsertVillageTimingSnapshot(villageKey);
          final data = masjidDoc.data();
          await _upsertRegisteredCatalogEntry(
            state: (data['state'] as String? ?? '').trim(),
            district: (data['district'] as String? ?? '').trim(),
            mandal: (data['mandal'] as String? ?? '').trim(),
            village: (data['village'] as String? ?? '').trim(),
            villageKey: villageKey,
          );
        } catch (_) {}
      }
    }
  }

  // ==============================
  // VILLAGE TIMINGS (INCREMENTAL)
  // ==============================
  Future<List<Masjid>> getVillageMasjids({
    required String villageKey,
    DateTime? updatedAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db
          .collection('masjids')
          .where('villagekey', isEqualTo: villageKey)
          .where('approved', isEqualTo: true);

      if (updatedAfter != null) {
        query = query.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromDate(updatedAfter),
        );
      }

      final snapshot = await query.getCounted();
      return snapshot.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .where((m) => m.isTimingConfigured == 1 || m.isTimingConfigured == true)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Masjid>> getApprovedMasjidsByVillage({
    required String villageKey,
    DateTime? updatedAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> boolQuery = _db
          .collection('masjids')
          .where('villagekey', isEqualTo: villageKey)
          .where('approved', isEqualTo: true);

      if (updatedAfter != null) {
        final ts = Timestamp.fromDate(updatedAfter);
        boolQuery = boolQuery.where('updatedAt', isGreaterThan: ts);
      }

      QuerySnapshot<Map<String, dynamic>> boolSnap;
      try {
        boolSnap = await boolQuery.getCounted();
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition' || updatedAfter == null) rethrow;
        boolSnap = await _db
            .collection('masjids')
            .where('villagekey', isEqualTo: villageKey)
            .where('approved', isEqualTo: true)
            .getCounted();
      }

      // Fast path: approved=true schema (current data model).
      if (boolSnap.docs.isNotEmpty) {
        return boolSnap.docs
            .map((doc) => _safeMasjidFromDoc(doc))
            .whereType<Masjid>()
            .toList();
      }

      // Legacy fallback: approvalStatus-only docs.
      Query<Map<String, dynamic>> statusQuery = _db
          .collection('masjids')
          .where('villagekey', isEqualTo: villageKey)
          .where('approvalStatus', isEqualTo: 'approved');
      if (updatedAfter != null) {
        statusQuery = statusQuery.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromDate(updatedAfter),
        );
      }

      QuerySnapshot<Map<String, dynamic>> statusSnap;
      try {
        statusSnap = await statusQuery.getCounted();
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition' || updatedAfter == null) rethrow;
        statusSnap = await _db
            .collection('masjids')
            .where('villagekey', isEqualTo: villageKey)
            .where('approvalStatus', isEqualTo: 'approved')
            .getCounted();
      }

      return statusSnap.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ==============================
  // GLOBAL MASJIDS (INCREMENTAL)
  // ==============================
  Future<List<Masjid>> getMasjidsUpdatedAfter({
    DateTime? updatedAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection('masjids');
      if (updatedAfter != null) {
        query = query.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromDate(updatedAfter),
        );
      }
      final snapshot = await query.getCounted();
      return snapshot.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Masjid>> getApprovedMasjidsUpdatedAfter({
    DateTime? updatedAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> boolQuery = _db
          .collection('masjids')
          .where('approved', isEqualTo: true);
      if (updatedAfter != null) {
        final ts = Timestamp.fromDate(updatedAfter);
        boolQuery = boolQuery.where('updatedAt', isGreaterThan: ts);
      }

      QuerySnapshot<Map<String, dynamic>> boolSnap;
      try {
        boolSnap = await boolQuery.getCounted();
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition' || updatedAfter == null) rethrow;
        // Missing composite index for approved+updatedAt.
        // Fallback to updatedAt-only incremental query, then filter approved
        // client-side to avoid full collection reads on each screen open.
        final changedSnap = await _db
            .collection('masjids')
            .where(
              'updatedAt',
              isGreaterThan: Timestamp.fromDate(updatedAfter),
            )
            .getCounted();
        return changedSnap.docs
            .where((doc) {
              final data = doc.data();
              return (data['approved'] as bool?) ??
                  ((data['approvalStatus'] as String?)?.toLowerCase() ==
                      'approved');
            })
            .map((doc) => _safeMasjidFromDoc(doc))
            .whereType<Masjid>()
            .toList();
      }

      // Fast path: approved=true schema (current data model).
      if (boolSnap.docs.isNotEmpty) {
        return boolSnap.docs
            .map((doc) => _safeMasjidFromDoc(doc))
            .whereType<Masjid>()
            .toList();
      }

      // Legacy fallback: approvalStatus-only docs.
      Query<Map<String, dynamic>> statusQuery = _db
          .collection('masjids')
          .where('approvalStatus', isEqualTo: 'approved');
      if (updatedAfter != null) {
        statusQuery = statusQuery.where(
          'updatedAt',
          isGreaterThan: Timestamp.fromDate(updatedAfter),
        );
      }

      QuerySnapshot<Map<String, dynamic>> statusSnap;
      try {
        statusSnap = await statusQuery.getCounted();
      } on FirebaseException catch (e) {
        if (e.code != 'failed-precondition' || updatedAfter == null) rethrow;
        // Same fallback for legacy approvalStatus path.
        final changedSnap = await _db
            .collection('masjids')
            .where(
              'updatedAt',
              isGreaterThan: Timestamp.fromDate(updatedAfter),
            )
            .getCounted();
        return changedSnap.docs
            .where((doc) {
              final data = doc.data();
              return (data['approved'] as bool?) ??
                  ((data['approvalStatus'] as String?)?.toLowerCase() ==
                      'approved');
            })
            .map((doc) => _safeMasjidFromDoc(doc))
            .whereType<Masjid>()
            .toList();
      }

      return statusSnap.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Masjid>> getApprovedMasjidsByGeoHashPrefix(
    String geoHashPrefix, {
    int limit = 150,
  }) async {
    try {
      final snapshot = await _db
          .collection('masjids')
          .where('approved', isEqualTo: true)
          .orderBy('geoHash')
          .startAt([geoHashPrefix])
          .endAt(['$geoHashPrefix\uf8ff'])
          .limit(limit)
          .getCounted();

      return snapshot.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ==============================
  // ONE-TIME BACKFILL (SYNC FIELDS)
  // ==============================
  Future<int?> backfillMasjidSyncFieldsOnce() async {
    try {
      final snapshot = await _db.collection('masjids').getCounted();
      int updated = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final String village = (data['village'] as String? ?? '').trim();
        final String expectedVillageKey = _toVillageKey(village);
        final String currentVillageKey =
            (data['villagekey'] as String? ?? '').trim();
        final bool missingUpdatedAt =
            !data.containsKey('updatedAt') || data['updatedAt'] == null;

        if (expectedVillageKey.isEmpty) continue;
        if (currentVillageKey == expectedVillageKey && !missingUpdatedAt) {
          continue;
        }

        await _db.collection('masjids').doc(doc.id).update({
          'villagekey': expectedVillageKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      }

      return updated;
    } catch (_) {
      return null;
    }
  }

  Future<int?> backfillMasjidGeoHashOnce() async {
    try {
      final snapshot = await _db.collection('masjids').getCounted();
      int updated = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final double? lat = _parseCoordinate(data['latitude']);
        final double? lng = _parseCoordinate(data['longitude']);
        if (lat == null || lng == null) continue;

        final String expected = GeoHashUtils.encode(lat, lng, precision: 6);
        final String current = (data['geoHash'] as String? ?? '').trim();
        if (current == expected) continue;

        await _db.collection('masjids').doc(doc.id).update({
          'geoHash': expected,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        updated++;
      }

      return updated;
    } catch (_) {
      return null;
    }
  }

  // ==============================
  // VILLAGE OFFSETS
  // ==============================
  Future<Map<String, dynamic>?> getVillageOffsets(String villageKey) async {
    final String key = _toVillageKey(villageKey);
    if (key.isEmpty) return null;
    try {
      final doc = await _db
          .collection(_villageOffsetsCollection)
          .doc(key)
          .getCounted();
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<void> setVillageOffsets({
    required String villageKey,
    required String villageName,
    required int sunriseMinutes,
    required String sunriseDirection,
    required int sunsetMinutes,
    required String sunsetDirection,
  }) async {
    final String key = _toVillageKey(villageKey);
    if (key.isEmpty) return;
    final String name = villageName.trim();
    await _db.collection(_villageOffsetsCollection).doc(key).set({
      'villageKey': key,
      if (name.isNotEmpty) 'villageName': name,
      'sunriseOffsetMinutes': sunriseMinutes,
      'sunriseOffsetDirection': _normalizeOffsetDirection(sunriseDirection),
      'sunsetOffsetMinutes': sunsetMinutes,
      'sunsetOffsetDirection': _normalizeOffsetDirection(sunsetDirection),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================
  // ONE-TIME BACKFILL (NALGONDA SUNRISE/SUNSET OFFSETS)
  // ==============================
  Future<int?> backfillNalgondaSunriseSunsetOffsets({
    int sunriseMinutes = 3,
    int sunsetMinutes = 3,
    String direction = 'less',
  }) async {
    try {
      final snapshot = await _db.collection('masjids').getCounted();
      int updated = 0;
      WriteBatch batch = _db.batch();
      int ops = 0;
      final String dir = direction.trim().isEmpty
          ? 'less'
          : direction.trim().toLowerCase();

      Future<void> flush() async {
        if (ops == 0) return;
        await batch.commit();
        batch = _db.batch();
        ops = 0;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final String district = (data['district'] as String? ?? '').trim();
        final String mandal = (data['mandal'] as String? ?? '').trim();
        final String village = (data['village'] as String? ?? '').trim();
        if (!(_isNalgonda(district) ||
            _isNalgonda(mandal) ||
            _isNalgonda(village))) {
          continue;
        }

        batch.set(doc.reference, {
          'sunriseOffsetMinutes': sunriseMinutes,
          'sunriseOffsetDirection': dir,
          'sunsetOffsetMinutes': sunsetMinutes,
          'sunsetOffsetDirection': dir,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        updated++;
        ops++;

        if (ops >= 400) {
          await flush();
        }
      }

      await flush();
      return updated;
    } catch (_) {
      return null;
    }
  }

  // ==============================
  // SYNC EXISTING MASJIDS (FIRESTORE)
  // ==============================
  Future<Map<String, int>?> syncExistingMasjidsFromFirestore({
    int sunriseMinutes = 3,
    int sunsetMinutes = 3,
    String direction = 'less',
    bool rebuildSnapshots = true,
  }) async {
    try {
      final String dir = direction.trim().isEmpty
          ? 'less'
          : direction.trim().toLowerCase();

      final int nalgondaUpdated =
          await backfillNalgondaSunriseSunsetOffsets(
                sunriseMinutes: sunriseMinutes,
                sunsetMinutes: sunsetMinutes,
                direction: dir,
              ) ??
              0;

      int snapshotMasjids = 0;
      int snapshotVillages = 0;
      if (rebuildSnapshots) {
        final snapshot = await rebuildRegisteredSnapshots();
        snapshotMasjids = snapshot['masjids'] ?? 0;
        snapshotVillages = snapshot['villages'] ?? 0;
      }

      return {
        'nalgondaUpdated': nalgondaUpdated,
        'snapshotMasjids': snapshotMasjids,
        'snapshotVillages': snapshotVillages,
      };
    } catch (_) {
      return null;
    }
  }

  // ==============================
  // FILTER MASJIDS (STATE / DISTRICT / MANDAL / VILLAGE)
  // ==============================
  Future<List<Masjid>> filterMasjids({
    String? state,
    String? district,
    String? mandal,
    String? village,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db
          .collection('masjids')
          .where('approved', isEqualTo: true);

      if (state != null && state.isNotEmpty) {
        query = query.where('state', isEqualTo: state);
      }

      if (district != null && district.isNotEmpty) {
        query = query.where('district', isEqualTo: district);
      }

      if (mandal != null && mandal.isNotEmpty) {
        query = query.where('mandal', isEqualTo: mandal);
      }

      if (village != null && village.isNotEmpty) {
        query = query.where('village', isEqualTo: village);
      }

      final snapshot = await query.getCounted();

      return snapshot.docs
          .map((doc) => _safeMasjidFromDoc(doc))
          .whereType<Masjid>()
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getRegisteredCatalogSnapshot() async {
    try {
      final ReadCounter counter = CompositeReadCounter(
        FirebaseReadCounter.instance,
        FirebaseRegisteredMasjidReadCounter.instance,
      );
      final doc = await _db
          .collection('registered_catalog_snapshots')
          .doc('global')
          .getCountedWith(counter);
      return doc.data();
    } catch (_) {
      return null;
    }
  }

  Future<List<Masjid>> getRegisteredVillageSnapshot({
    required String villageKey,
    bool approvedOnly = true,
  }) async {
    final String key = _toVillageKey(villageKey);
    if (key.isEmpty) return [];

    try {
      final ReadCounter counter = CompositeReadCounter(
        FirebaseReadCounter.instance,
        FirebaseRegisteredMasjidReadCounter.instance,
      );
      final doc = await _db
          .collection('registered_village_snapshots')
          .doc(key)
          .getCountedWith(counter);
      final data = doc.data();
      if (data == null) return [];
      final rawItems = data['items'];
      if (rawItems is! List) return [];

      final List<Masjid> result = [];
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final bool approved =
            (map['approved'] as bool?) ??
            ((map['approvalStatus'] as String?)?.toLowerCase() == 'approved');
        if (approvedOnly && !approved) continue;

        final String id = (map['masjidId'] as String? ?? '').trim();
        if (id.isEmpty) continue;
        final normalized = <String, dynamic>{
          'name': map['name'] as String? ?? '',
          'address': map['address'] as String? ?? '',
          'state': map['state'] as String? ?? '',
          'district': map['district'] as String? ?? '',
          'mandal': map['mandal'] as String? ?? '',
          'village': map['village'] as String? ?? '',
          'approved': approved,
          'approvalStatus': map['approvalStatus'] as String? ?? '',
          'isTimingConfigured': map['isTimingConfigured'],
          'latitude': map['latitude'],
          'longitude': map['longitude'],
          'fajr_azan': map['fajr_azan'] as String? ?? '',
          'fajr_jamat': map['fajr_jamat'] as String? ?? '',
          'dhuhr_azan': map['dhuhr_azan'] as String? ?? '',
          'dhuhr_jamat': map['dhuhr_jamat'] as String? ?? '',
          'asar_azan':
              (map['asar_azan'] as String? ?? map['asr_azan'] as String?) ?? '',
          'asar_jamat':
              (map['asar_jamat'] as String? ?? map['asr_jamat'] as String?) ?? '',
          'maghrib_azan': map['maghrib_azan'] as String? ?? '',
          'maghrib_jamat': map['maghrib_jamat'] as String? ?? '',
          'isha_azan': map['isha_azan'] as String? ?? '',
          'isha_jamat': map['isha_jamat'] as String? ?? '',
          'juma_azan': map['juma_azan'] as String? ?? '',
          'juma_jamat': map['juma_jamat'] as String? ?? '',
        };
        result.add(Masjid.fromMap(normalized, id));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// One-time/occasional maintenance job:
  /// Builds lightweight snapshot docs to support low-read registered-masjid UI.
  /// Writes:
  /// - registered_catalog_snapshots/global
  /// - registered_village_snapshots/{villageKey}
  Future<Map<String, int>> rebuildRegisteredSnapshots() async {
    final snapshot = await _db.collection('masjids').getCounted();

    final Map<String, String> states = <String, String>{};
    final Map<String, String> districts = <String, String>{};
    final Map<String, String> mandals = <String, String>{};
    final Map<String, String> villages = <String, String>{};
    final Map<String, List<Map<String, dynamic>>> byVillage = {};
    final Map<String, String> villageNames = {};
    final Map<String, Map<String, String>> locations = {};
    final Set<String> approvedVillageKeys = <String>{};

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final String state = (data['state'] as String? ?? '').trim();
      final String district = (data['district'] as String? ?? '').trim();
      final String mandal = (data['mandal'] as String? ?? '').trim();
      final String village = (data['village'] as String? ?? '').trim();
      final String villageKey = _toVillageKey(village);
      if (villageKey.isEmpty) continue;

      if (state.isNotEmpty) states.putIfAbsent(state.toLowerCase(), () => state);
      if (district.isNotEmpty) {
        districts.putIfAbsent(district.toLowerCase(), () => district);
      }
      if (mandal.isNotEmpty) mandals.putIfAbsent(mandal.toLowerCase(), () => mandal);
      if (village.isNotEmpty) villages.putIfAbsent(village.toLowerCase(), () => village);
      villageNames.putIfAbsent(villageKey, () => village);
      if (state.isNotEmpty &&
          district.isNotEmpty &&
          mandal.isNotEmpty &&
          village.isNotEmpty) {
        final locKey =
            '${state.toLowerCase()}|${district.toLowerCase()}|${mandal.toLowerCase()}|${village.toLowerCase()}';
        locations.putIfAbsent(locKey, () {
          return {
            'state': state,
            'district': district,
            'mandal': mandal,
            'village': village,
            'villageKey': villageKey,
          };
        });
      }

      final bool approved =
          (data['approved'] as bool?) ??
          ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved');
      if (approved) {
        approvedVillageKeys.add(villageKey);
      }

      final item = <String, dynamic>{
        'masjidId': doc.id,
        'name': data['name'] as String? ?? '',
        'address': data['address'] as String? ?? '',
        'state': state,
        'district': district,
        'mandal': mandal,
        'village': village,
        'villagekey': villageKey,
        'approved': approved,
        'approvalStatus': data['approvalStatus'] as String? ?? '',
        'isTimingConfigured': data['isTimingConfigured'],
        'latitude': _parseCoordinate(data['latitude']),
        'longitude': _parseCoordinate(data['longitude']),
        'fajr_azan': data['fajr_azan'] as String? ?? '',
        'fajr_jamat': data['fajr_jamat'] as String? ?? '',
        'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
        'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
        'asar_azan':
            (data['asar_azan'] as String? ?? data['asr_azan'] as String?) ?? '',
        'asar_jamat':
            (data['asar_jamat'] as String? ?? data['asr_jamat'] as String?) ?? '',
        'maghrib_azan': data['maghrib_azan'] as String? ?? '',
        'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
        'isha_azan': data['isha_azan'] as String? ?? '',
        'isha_jamat': data['isha_jamat'] as String? ?? '',
        'juma_azan': data['juma_azan'] as String? ?? '',
        'juma_jamat': data['juma_jamat'] as String? ?? '',
      };
      byVillage.putIfAbsent(villageKey, () => <Map<String, dynamic>>[]).add(item);
    }

    List<String> sorted(Map<String, String> values) {
      final list = values.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return list;
    }

    final Map<String, dynamic> catalogPayload = {
      'states': sorted(states),
      'districts': sorted(districts),
      'mandals': sorted(mandals),
      'villages': sorted(villages),
      'locations': locations.values.toList(),
      'villageKeys': byVillage.keys.toList()..sort(),
      'approvedVillageKeys': approvedVillageKeys.toList()..sort(),
      'totalMasjids': snapshot.docs.length,
      'totalVillages': byVillage.length,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    WriteBatch batch = _db.batch();
    int ops = 0;
    int batchesCommitted = 0;

    void queueSet(DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data) {
      batch.set(ref, data, SetOptions(merge: true));
      ops++;
    }

    Future<void> flushIfNeeded() async {
      if (ops < 425) return;
      await batch.commit();
      batchesCommitted++;
      batch = _db.batch();
      ops = 0;
    }

    queueSet(
      _db.collection('registered_catalog_snapshots').doc('global'),
      catalogPayload,
    );

    for (final entry in byVillage.entries) {
      final String key = entry.key;
      queueSet(
        _db.collection('registered_village_snapshots').doc(key),
        {
          'villageKey': key,
          'villageName': villageNames[key] ?? key,
          'totalMasjids': entry.value.length,
          'items': entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );
      await flushIfNeeded();
    }

    if (ops > 0) {
      await batch.commit();
      batchesCommitted++;
    }

    return {
      'masjids': snapshot.docs.length,
      'villages': byVillage.length,
      'batches': batchesCommitted,
    };
  }

  Future<void> _upsertRegisteredCatalogEntry({
    required String state,
    required String district,
    required String mandal,
    required String village,
    required String villageKey,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (state.isNotEmpty) updates['states'] = FieldValue.arrayUnion([state]);
    if (district.isNotEmpty) {
      updates['districts'] = FieldValue.arrayUnion([district]);
    }
    if (mandal.isNotEmpty) updates['mandals'] = FieldValue.arrayUnion([mandal]);
    if (village.isNotEmpty) updates['villages'] = FieldValue.arrayUnion([village]);
    if (villageKey.isNotEmpty) {
      updates['villageKeys'] = FieldValue.arrayUnion([villageKey]);
    }
    if (state.isNotEmpty &&
        district.isNotEmpty &&
        mandal.isNotEmpty &&
        village.isNotEmpty) {
      updates['locations'] = FieldValue.arrayUnion([
        {
          'state': state,
          'district': district,
          'mandal': mandal,
          'village': village,
          'villageKey': villageKey,
        },
      ]);
    }
    await _db
        .collection('registered_catalog_snapshots')
        .doc('global')
        .set(updates, SetOptions(merge: true));
  }

  Future<void> _upsertRegisteredVillageSnapshot(String villageKey) async {
    final String key = _toVillageKey(villageKey);
    if (key.isEmpty) return;

    final snapshot = await _db
        .collection('masjids')
        .where('villagekey', isEqualTo: key)
        .getCounted();

    if (snapshot.docs.isEmpty) {
      await _db.collection('registered_village_snapshots').doc(key).delete();
      return;
    }

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    String villageName = '';

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final String village = (data['village'] as String? ?? '').trim();
      if (villageName.isEmpty && village.isNotEmpty) villageName = village;

      items.add({
        'masjidId': doc.id,
        'name': data['name'] as String? ?? '',
        'address': data['address'] as String? ?? '',
        'state': data['state'] as String? ?? '',
        'district': data['district'] as String? ?? '',
        'mandal': data['mandal'] as String? ?? '',
        'village': village,
        'villagekey': key,
        'approved':
            (data['approved'] as bool?) ??
            ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved'),
        'approvalStatus': data['approvalStatus'] as String? ?? '',
        'isTimingConfigured': data['isTimingConfigured'],
        'latitude': _parseCoordinate(data['latitude']),
        'longitude': _parseCoordinate(data['longitude']),
        'fajr_azan': data['fajr_azan'] as String? ?? '',
        'fajr_jamat': data['fajr_jamat'] as String? ?? '',
        'dhuhr_azan': data['dhuhr_azan'] as String? ?? '',
        'dhuhr_jamat': data['dhuhr_jamat'] as String? ?? '',
        'asar_azan':
            (data['asar_azan'] as String? ?? data['asr_azan'] as String?) ?? '',
        'asar_jamat':
            (data['asar_jamat'] as String? ?? data['asr_jamat'] as String?) ?? '',
        'maghrib_azan': data['maghrib_azan'] as String? ?? '',
        'maghrib_jamat': data['maghrib_jamat'] as String? ?? '',
        'isha_azan': data['isha_azan'] as String? ?? '',
        'isha_jamat': data['isha_jamat'] as String? ?? '',
        'juma_azan': data['juma_azan'] as String? ?? '',
        'juma_jamat': data['juma_jamat'] as String? ?? '',
      });
    }

    await _db.collection('registered_village_snapshots').doc(key).set({
      'villageKey': key,
      'villageName': villageName.isEmpty ? key : villageName,
      'totalMasjids': items.length,
      'items': items,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ==============================
  // GET RAMADAN TIMINGS
  // ==============================
  Future<Map<String, dynamic>?> getRamadanTimings(int year) async {
    try {
      final doc = await _db
          .collection('ramadan_timings')
          .doc('ramadan_$year')
          .getCounted();
      return doc.data();
    } catch (e) {
      return null;
    }
  }

  // ==============================
  // HELPER: SAFE MASJID PARSING
  // ==============================
  Masjid? _safeMasjidFromDoc(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;

      // Helper to safely get string from map
      String gs(String key) => data[key] as String? ?? '';

      // Construct Salah list from flat fields if 'salahs' doesn't exist in DB.
      // This ensures the NotificationService can iterate over them.
      List<Map<String, dynamic>> salahsList = [];
      if (data['salahs'] == null) {
        salahsList = [
          {
            'id': 1,
            'name': 'Fajr',
            'azanTime': gs('fajr_azan'),
            'jamatTime': gs('fajr_jamat'),
            'endTime': '',
          },
          {
            'id': 2,
            'name': 'Dhuhr',
            'azanTime': gs('dhuhr_azan'),
            'jamatTime': gs('dhuhr_jamat'),
            'endTime': '',
          },
          {
            'id': 3,
            'name': 'Asr',
            'azanTime': gs('asar_azan'),
            'jamatTime': gs('asar_jamat'),
            'endTime': '',
          },
          {
            'id': 4,
            'name': 'Maghrib',
            'azanTime': gs('maghrib_azan'),
            'jamatTime': gs('maghrib_jamat'),
            'endTime': '',
          },
          {
            'id': 5,
            'name': 'Isha',
            'azanTime': gs('isha_azan'),
            'jamatTime': gs('isha_jamat'),
            'endTime': '',
          },
          {
            'id': 6,
            'name': 'Juma',
            'azanTime': gs('juma_azan'),
            'jamatTime': gs('juma_jamat'),
            'endTime': '',
          },
        ];
      }

      // Merge with defaults for potentially missing fields to prevent crashes
      final safeData = {
        'fajr': '',
        'dhuhr': '',
        'asar': '',
        'maghrib': '',
        'isha': '',
        'juma': '',
        'fajr_azan': '',
        'dhuhr_azan': '',
        'asar_azan': '',
        'maghrib_azan': '',
        'isha_azan': '',
        'juma_azan': '',
        'fajr_jamat': '',
        'dhuhr_jamat': '',
        'asar_jamat': '',
        'maghrib_jamat': '',
        'isha_jamat': '',
        'juma_jamat': '',
        'sunriseOffsetMinutes': 0,
        'sunriseOffsetDirection': 'less',
        'sunsetOffsetMinutes': 0,
        'sunsetOffsetDirection': 'less',
        'name': '',
        'address': '',
        'village': '',
        'mandal': '',
        'district': '',
        'state': '',
        ...data, // Actual data overrides defaults
        // Treat either field as approval source for legacy compatibility.
        'approved':
            (data['approved'] as bool?) ??
            ((data['approvalStatus'] as String?)?.toLowerCase() == 'approved'),
        'id': doc.id,
        // Inject the constructed list if original didn't have it
        if (data['salahs'] == null) 'salahs': salahsList,
      };

      return Masjid.fromMap(safeData, doc.id);
    } catch (e) {
      print("Error parsing Masjid ${doc.id}: $e");
      return null;
    }
  }
}

class _TimingUpdate {
  final String id;
  final Map<String, dynamic> data;
  const _TimingUpdate(this.id, this.data);
}

