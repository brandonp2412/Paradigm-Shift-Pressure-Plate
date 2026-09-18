import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/bank.dart';
import '../models/controller.dart';
import '../models/locker_section.dart';
import 'websocket_service.dart';
import '../logging.dart';

/// Background watcher: periodically checks whether any of the locker banks the
/// user has selected (the home-screen filter) has a free locker, and fires a
/// local notification when one becomes available.
///
/// Caveats: Android runs periodic tasks at a ~15 minute minimum; iOS executes
/// them opportunistically and may delay them significantly. This is best-effort
/// and not real-time.
class BackgroundWatch {
  BackgroundWatch._();

  static const String taskName = 'floorsense.watch_lockers';
  static const String _uniqueName = 'floorsense.watch_lockers.periodic';

  // SharedPreferences keys (shared with AuthService / HomeScreen).
  static const String sessionKey = 'floorsense.session';
  static const String filterKey = 'floorsense.bank_filter';
  static const String enabledKey = 'floorsense.watch_enabled';
  static const String watchStateKey = 'floorsense.watch_state';

  static const _channelId = 'locker_availability';
  static const _channelName = 'Locker availability';

  static final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

  /// Initialise Workmanager + notifications. Call once from `main()`.
  static Future<void> init() async {
    talker.info('Initializing background locker watch');
    await Workmanager().initialize(callbackDispatcher);
    await _initNotifications();
  }

  static Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await notifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  /// Whether the user has opted into background watching.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  /// Turn watching on: persist the flag, request permission and register the
  /// periodic task.
  static Future<void> enable() async {
    talker.info('Enabling background locker watch');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, true);
    await _requestPermission();
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      taskName,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  /// Turn watching off and cancel the periodic task.
  static Future<void> disable() async {
    talker.info('Disabling background locker watch');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, false);
    await prefs.remove(watchStateKey);
    await Workmanager().cancelByUniqueName(_uniqueName);
  }

  /// Re-register (or cancel) the task to match the persisted flag. Call from
  /// `main()` so the task survives reinstalls / setting changes.
  static Future<void> syncRegistration() async {
    if (await isEnabled()) {
      talker.info('Syncing enabled background locker watch');
      await enable();
    } else {
      talker.info('Cancelling disabled background locker watch');
      await Workmanager().cancelByUniqueName(_uniqueName);
    }
  }

  static Future<void> _requestPermission() async {
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    final ios = notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  /// Debug-only: run the *real* check immediately on the calling isolate,
  /// forcing every currently-free watched bank to notify.
  ///
  /// It clears the saved watch state (so `previous` is empty → any bank with a
  /// free locker counts as a fresh transition) and bypasses the opt-in gate.
  /// This exercises the entire pipeline — session decode, websocket connect,
  /// bank list, locker status parse, and the notification — without reserving
  /// or releasing a real locker. Each press re-clears the state, so a
  /// notification fires for every currently-free watched bank every time. The
  /// once-only transition logic is covered separately by [becameAvailable]'s
  /// unit test.
  static Future<bool> debugForceCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(watchStateKey);
    return runCheck(ignoreEnabled: true);
  }

  /// The work itself: runs in a background isolate. Returns true on success so
  /// Workmanager doesn't retry needlessly.
  ///
  /// [ignoreEnabled] bypasses the opt-in gate; used only by [debugForceCheck]
  /// so the debug trigger works regardless of the toggle state.
  static Future<bool> runCheck({bool ignoreEnabled = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!ignoreEnabled && !(prefs.getBool(enabledKey) ?? false)) return true;

    final sessionJson = prefs.getString(sessionKey);
    if (sessionJson == null) return true;
    talker.info('Running background locker availability check');

    Controller controller;
    String? ssoAccessToken;
    String? ssoIdToken;
    try {
      final data = jsonDecode(sessionJson) as Map<String, dynamic>;
      final ctrlJson = data['controller'] as Map<String, dynamic>?;
      if (ctrlJson == null) return true;
      controller = Controller.fromJson(ctrlJson);
      ssoAccessToken = data['sso_access_token'] as String?;
      ssoIdToken = data['sso_id_token'] as String?;
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Could not restore background watch session',
      );
      return true;
    }

    final enabledCids = _readFilter(prefs);
    final ws = WebSocketService();
    try {
      await ws.connect(
        socketUri: controller.socketURI,
        token: controller.token,
        uid: controller.uid,
        uidToken: controller.uidToken,
        idToken: ssoIdToken,
        accessToken: ssoAccessToken,
      );

      final banks = await ws.getBankList();
      final watched = enabledCids.isEmpty
          ? banks
          : banks.where((b) => enabledCids.contains(b.cid)).toList();
      talker.info('Checking ${watched.length} locker banks');

      // bankCid -> whether it currently has at least one free locker.
      final previous = _readWatchState(prefs);
      final current = <int, bool>{};
      final newlyAvailable = <Bank>[];

      for (final bank in watched) {
        int available = 0;
        try {
          final status = await ws.getLockerStatus(bank.cid);
          available = availableCount(status);
        } catch (error, stackTrace) {
          talker.handle(
            error,
            stackTrace,
            'Could not check a watched locker bank',
          );
          // Skip banks that fail; preserve their previous state so we don't
          // re-notify on a transient blip.
          current[bank.cid] = previous[bank.cid] ?? false;
          continue;
        }
        final hasFree = available > 0;
        current[bank.cid] = hasFree;
        if (becameAvailable(previous[bank.cid], hasFree)) {
          newlyAvailable.add(bank);
        }
      }

      await _saveWatchState(prefs, current);

      for (final bank in newlyAvailable) {
        await _notify(bank);
      }
      talker.info(
        'Background locker check completed; ${newlyAvailable.length} availability alerts',
      );
      return true;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Background locker check failed');
      return false;
    } finally {
      ws.dispose();
    }
  }

  static Set<int> _readFilter(SharedPreferences prefs) {
    final raw = prefs.getString(filterKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => (e as num).toInt()).toSet();
    } catch (_) {
      return {};
    }
  }

  static Map<int, bool> _readWatchState(SharedPreferences prefs) {
    final raw = prefs.getString(watchStateKey);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(int.parse(k), v == true));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveWatchState(
    SharedPreferences prefs,
    Map<int, bool> state,
  ) async {
    final encoded = state.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(watchStateKey, jsonEncode(encoded));
  }

  /// True the first time a bank goes from having no free locker to having one,
  /// so we notify on the transition only (not repeatedly while it stays free).
  @visibleForTesting
  static bool becameAvailable(bool? previousHadFree, bool nowHasFree) =>
      nowHasFree && !(previousHadFree ?? false);

  /// Mirror of HomeScreen._parseSections: sum available lockers across sections.
  @visibleForTesting
  static int availableCount(Map<String, dynamic> status) {
    final info = status['info'];
    if (info is! Map<String, dynamic>) return 0;
    final types = info['types'];
    if (types is! List) return 0;
    var total = 0;
    for (final s in types) {
      final section = LockerSection.fromJson(s as Map<String, dynamic>);
      total += section.availableCount;
    }
    return total;
  }

  static Future<void> _notify(Bank bank) async {
    talker.info('Sending locker availability notification');
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when a locker frees up in a watched bank',
      importance: Importance.high,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await notifications.show(
      bank.cid,
      'Locker available',
      'A locker is free in ${bank.name}',
      const NotificationDetails(android: android, iOS: ios),
    );
  }
}

/// Workmanager entry point. Must be a top-level function annotated for the
/// AOT/background isolate.
@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  installTalkerErrorHandlers();
  Workmanager().executeTask((task, inputData) async {
    if (task != BackgroundWatch.taskName) return true;
    try {
      await BackgroundWatch._initNotifications();
      return await BackgroundWatch.runCheck();
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Workmanager background watch failed');
      return false;
    }
  });
}
