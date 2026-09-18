import 'dart:async';
import 'dart:convert';
import 'package:floorsense_app/models/available_locker.dart';
import 'package:floorsense_app/widgets/connection_banner.dart';
import 'package:floorsense_app/widgets/filter_sheet.dart';
import 'package:floorsense_app/widgets/locker_tile.dart';
import 'package:floorsense_app/widgets/reservation_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bank.dart';
import '../models/locker_reservation.dart';
import '../models/locker_section.dart';
import '../services/auth_service.dart';
import '../services/locker_cache.dart';
import '../services/websocket_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<AvailableLocker>? _availableLockers;
  List<Bank> _banks = [];
  Set<int> _enabledBankCids = {};
  // Bank cid -> locker names from the floor plan (what lockers exist in a bank).
  Map<int, List<String>> _lockerNames = {};
  bool _loading = true;
  // A background refresh while data is already on screen — drives a non-displacing
  // progress bar instead of wiping the list for a centered spinner.
  bool _refreshing = false;
  String? _error;

  // Reopening the app after a while often finds a socket the OS quietly
  // killed while backgrounded: status flips disconnected -> connecting ->
  // connected within a couple hundred ms once reconnect kicks in. Showing
  // the banner immediately for that turns into a jolt (grows, then
  // immediately collapses). Only show it once "not connected" has held for
  // a bit, so quick reconnects stay invisible.
  Timer? _connectionBannerDelay;
  bool _showConnectionBanner = false;
  WebSocketService? _ws;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFilterConfig().then((_) => _loadCache()).then((_) => _loadData());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ws = context.read<AuthService>().ws;
      _ws!.status.addListener(_onWsStatusChanged);
      _onWsStatusChanged();
    });
  }

  void _onWsStatusChanged() {
    _connectionBannerDelay?.cancel();
    if (_ws!.status.value == WsStatus.connected) {
      if (_showConnectionBanner) setState(() => _showConnectionBanner = false);
      return;
    }
    _connectionBannerDelay = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _showConnectionBanner = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(context.read<AuthService>().refreshLockerReservations());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectionBannerDelay?.cancel();
    _ws?.status.removeListener(_onWsStatusChanged);
    super.dispose();
  }

  /// Paint the last known data immediately so an app open isn't a blank spinner.
  Future<void> _loadCache() async {
    final cachedLockers = await LockerCache.readAvailableLockers();
    final cachedNames = await LockerCache.readLockerNames();
    if (!mounted) return;
    setState(() {
      if (cachedLockers != null) {
        _availableLockers = cachedLockers;
        _loading = false; // we have something to show; refresh in background
      }
      if (cachedNames != null) _lockerNames = cachedNames;
    });
  }

  Future<void> _loadFilterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('floorsense.bank_filter');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _enabledBankCids = list.map((e) => (e as num).toInt()).toSet();
      } catch (_) {
        _enabledBankCids = {};
      }
    }
  }

  Future<void> _saveFilterConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'floorsense.bank_filter',
      jsonEncode(_enabledBankCids.toList()),
    );
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthService>();
    final ws = auth.ws;
    try {
      if (!ws.isConnected || !ws.isAuthenticated) {
        final ok = await ws.reconnect();
        if (!ok) {
          if (mounted) {
            setState(() {
              _error =
                  "Couldn't reach the locker server. Check your "
                  'connection and try again.';
              _loading = false;
              _refreshing = false;
            });
          }
          return;
        }
      }
      await auth.refreshLockerReservations();
      final banks = await ws.getBankList();
      _banks = banks;

      final filteredBanks = _enabledBankCids.isEmpty
          ? banks
          : banks.where((b) => _enabledBankCids.contains(b.cid)).toList();

      final allLockers = <AvailableLocker>[];

      for (final bank in filteredBanks) {
        try {
          final status = await ws.getLockerStatus(bank.cid);
          _parseSections(status, bank, allLockers);
        } catch (_) {}
      }

      allLockers.sort((a, b) {
        final nameCmp = a.bankName.compareTo(b.bankName);
        if (nameCmp != 0) return nameCmp;
        return a.sectionName.compareTo(b.sectionName);
      });

      if (mounted) {
        setState(() {
          _availableLockers = allLockers;
          _loading = false;
          _refreshing = false;
        });
      }
      await LockerCache.saveAvailableLockers(allLockers);
      _maybeRefreshLockerNames(ws, auth.controller?.webURI ?? '');
    } on WsAuthRejectedException {
      // Session is no longer valid — clearing it flips auth state to initial,
      // which routes to login via the app-root listener in main.dart.
      await auth.logout();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  /// Rebuild the bank -> locker-name map from the floor plans when the cache is
  /// missing or stale. Best-effort and off the critical path: the list already
  /// rendered, and names just won't appear this run if it fails.
  Future<void> _maybeRefreshLockerNames(
    WebSocketService ws,
    String webUri,
  ) async {
    try {
      if (webUri.isEmpty) return;
      if (!await LockerCache.lockerNamesStale()) return;
      final names = await ws.buildLockerNameMap(webUri);
      if (names.isEmpty) return;
      await LockerCache.saveLockerNames(names);
      if (mounted) setState(() => _lockerNames = names);
    } catch (_) {
      // Ignore — names are a non-essential enhancement.
    }
  }

  void _parseSections(
    Map<String, dynamic> status,
    Bank bank,
    List<AvailableLocker> result,
  ) {
    final info = status['info'];
    if (info is! Map<String, dynamic>) return;
    final types = info['types'];
    if (types is! List) return;
    for (final s in types) {
      final section = LockerSection.fromJson(s as Map<String, dynamic>);
      if (section.availableCount > 0) {
        result.add(
          AvailableLocker(
            bankCid: bank.cid,
            bankName: bank.name,
            sectionName: section.name,
            typeCode: section.typeCode,
            availableCount: section.availableCount,
            lockerCount: section.lockerCount,
          ),
        );
      }
    }
  }

  Future<void> _unlockLocker(LockerReservation res) async {
    final ws = context.read<AuthService>().ws;
    try {
      final result = await ws.unlockLocker(res.cid, res.key);
      if (!mounted) return;
      if (result['result'] == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Locker ${res.key} unlocked')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Unlock failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _releaseReservation(LockerReservation res) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Reservation'),
        content: Text('Release locker ${res.key}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Release'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ws = context.read<AuthService>().ws;
    try {
      final result = await ws.releaseReservation(res.resid);
      if (!mounted) return;
      if (result['result'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reservation ${res.resid} released')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Release failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _createReservation(AvailableLocker locker) async {
    final ws = context.read<AuthService>().ws;
    try {
      final result = await ws.createReservation(
        locker.bankCid,
        locker.typeCode,
      );
      if (!mounted) return;
      if (result['result'] == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reservation created')));
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Create failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showFilterDialog() async {
    if (_banks.isEmpty) return;

    final fullSet = _banks.map((b) => b.cid).toSet();
    final disabled = _enabledBankCids.isEmpty
        ? <int>{}
        : fullSet.difference(_enabledBankCids);

    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => FilterSheet(banks: _banks, initialDisabled: disabled),
    );

    if (result != null && mounted) {
      _enabledBankCids = result.isEmpty ? <int>{} : fullSet.difference(result);
      await _saveFilterConfig();
      setState(() => _refreshing = true);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final myReservations = auth.authPayload?.reservations ?? [];
    final wsStatus = auth.ws.status.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.controller?.name ?? 'FloorSense'),
        // A thin, fixed-height bar for background refreshes: it reserves its own
        // space so showing/hiding it never shifts the list below.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: SizedBox(
            height: 3,
            child: _refreshing ? const LinearProgressIndicator() : null,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Filter banks',
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              // Clearing the session routes to login via the app-root listener.
              auth.logout();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _refreshing = true);
          await _loadData();
        },
        child: ListView(
          children: [
            // Animate the banner's height so connect/disconnect eases the list
            // down/up instead of snapping it.
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _showConnectionBanner && wsStatus != WsStatus.connected
                  ? ConnectionBanner(status: wsStatus)
                  : const SizedBox(width: double.infinity),
            ),
            if (myReservations.isNotEmpty) ...[
              ...myReservations.map(
                (r) => ReservationCard(
                  reservation: r,
                  onUnlock: () => _unlockLocker(r),
                  onRelease: () => _releaseReservation(r),
                ),
              ),
              const Divider(height: 32),
            ],
            if (_loading)
              // Fixed-height placeholders rather than a centered spinner, so the
              // swap to real tiles doesn't change the list height or jump.
              ...List.generate(5, (_) => const _SkeletonTile())
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _error = null;
                            _loading = true;
                          });
                          _loadData();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_availableLockers == null || _availableLockers!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No lockers available')),
              )
            else
              ..._availableLockers!.map(
                (l) => LockerTile(
                  locker: l,
                  lockerNames: _lockerNames[l.bankCid],
                  onReserve: () => _createReservation(l),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A non-animated placeholder shaped like a [LockerTile], shown while the first
/// load is in flight (only when there's no cached data to display).
class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [bar(140, 16), const SizedBox(height: 8), bar(220, 12)],
      ),
    );
  }
}
