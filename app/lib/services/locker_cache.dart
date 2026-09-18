import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/available_locker.dart';

/// On-disk cache for the home screen, so an app open can render instantly from
/// the last known data while a fresh fetch happens in the background.
///
/// Two payloads:
///  * The available-locker list — short lived; we always show it on open and then
///    refresh, so it exists mainly to avoid a blocking spinner.
///  * The bank `cid` -> locker names map — derived from floor plans, which change
///    rarely, so it has a long TTL and avoids re-walking every floor plan on each
///    launch.
class LockerCache {
  LockerCache._();

  static const _lockersKey = 'floorsense.cache.available_lockers';
  static const _namesKey = 'floorsense.cache.locker_names';

  /// Floor plans are effectively static; only rebuild the name map weekly.
  static const Duration lockerNamesTtl = Duration(days: 7);

  // --- Available lockers (instant first paint) ---------------------------

  static Future<void> saveAvailableLockers(
    List<AvailableLocker> lockers,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lockersKey,
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'lockers': lockers.map((l) => l.toJson()).toList(),
      }),
    );
  }

  /// Returns the cached available lockers, or null if nothing is cached or it
  /// can't be decoded. Age is not enforced — the caller renders these
  /// immediately and refreshes regardless.
  static Future<List<AvailableLocker>?> readAvailableLockers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lockersKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final list = map['lockers'] as List;
      return list
          .map((e) => AvailableLocker.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  // --- Locker names per bank (long lived) --------------------------------

  static Future<void> saveLockerNames(Map<int, List<String>> names) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _namesKey,
      jsonEncode({
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'names': names.map((k, v) => MapEntry(k.toString(), v)),
      }),
    );
  }

  /// Cached bank `cid` -> sorted locker names, or null if missing/unreadable.
  static Future<Map<int, List<String>>?> readLockerNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namesKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final names = map['names'] as Map<String, dynamic>;
      return names.map(
        (k, v) => MapEntry(
          int.parse(k),
          (v as List).map((e) => e as String).toList(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// True when the locker-name map is absent or older than [lockerNamesTtl], so
  /// the caller should rebuild it from the floor plans.
  static Future<bool> lockerNamesStale() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_namesKey);
    if (raw == null) return true;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = (map['savedAt'] as num).toInt();
      final age = DateTime.now().millisecondsSinceEpoch - savedAt;
      return age > lockerNamesTtl.inMilliseconds;
    } catch (_) {
      return true;
    }
  }
}
