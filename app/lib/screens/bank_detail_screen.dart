import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bank.dart';
import '../models/locker_reservation.dart';
import '../models/locker_section.dart';
import '../services/auth_service.dart';

class BankDetailScreen extends StatefulWidget {
  final Bank bank;
  const BankDetailScreen({super.key, required this.bank});

  @override
  State<BankDetailScreen> createState() => _BankDetailScreenState();
}

class _BankDetailScreenState extends State<BankDetailScreen> {
  List<LockerReservation>? _reservations;
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final ws = context.read<AuthService>().ws;
    if (!ws.isConnected) {
      await ws.reconnect();
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ws.getReservations(widget.bank.cid),
        ws.getLockerStatus(widget.bank.cid),
      ]);
      if (mounted) {
        setState(() {
          _reservations = results[0] as List<LockerReservation>;
          _status = results[1] as Map<String, dynamic>;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
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
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Unlock failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
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
    if (confirm != true) return;
    if (!mounted) return;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _createReservation(String typeCode) async {
    final ws = context.read<AuthService>().ws;
    try {
      final result = await ws.createReservation(widget.bank.cid, typeCode);
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
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.bank.name),
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Reservations'),
              Tab(text: 'Status'),
            ],
            onTap: (i) => setState(() => _tabIndex = i),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : IndexedStack(
                index: _tabIndex,
                children: [_buildReservationsTab(), _buildStatusTab()],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCreateDialog(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildReservationsTab() {
    if (_reservations == null || _reservations!.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No reservations')),
        ],
      );
    }

    final activeRes = _reservations!.where((r) => r.isActive).toList();
    final inactiveRes = _reservations!.where((r) => !r.isActive).toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        children: [
          if (activeRes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...activeRes.map(
              (r) => _ReservationCard(
                reservation: r,
                onUnlock: () => _unlockLocker(r),
                onRelease: () => _releaseReservation(r),
              ),
            ),
          ],
          if (inactiveRes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'PAST/FUTURE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ...inactiveRes.map(
              (r) => _ReservationCard(
                reservation: r,
                onUnlock: null,
                onRelease: null,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusTab() {
    if (_status == null) return const SizedBox();

    final info = _status!['info'];
    List<LockerSection> sections = [];

    if (info is Map<String, dynamic>) {
      final types = info['types'];
      if (types is List) {
        sections = types
            .map((s) => LockerSection.fromJson(s as Map<String, dynamic>))
            .toList();
      }
    }

    final availableSections = sections
        .where((s) => s.availableCount > 0)
        .toList();

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        children: [
          const SizedBox(height: 8),
          ...availableSections.map(
            (s) => _SectionCard(
              section: s,
              onCreate: () => _createReservation(s.typeCode),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() {
    if (_status == null) return;

    final info = _status!['info'];
    List<LockerSection> sections = [];

    if (info is Map<String, dynamic>) {
      final types = info['types'];
      if (types is List) {
        sections = types
            .map((s) => LockerSection.fromJson(s as Map<String, dynamic>))
            .toList();
      }
    }

    final availableSections = sections
        .where((s) => s.availableCount > 0)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Create Reservation'),
        children: availableSections.map((s) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _createReservation(s.typeCode);
            },
            child: ListTile(
              title: Text(s.name),
              subtitle: Text(
                '${s.availableCount} available of ${s.lockerCount}',
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final LockerReservation reservation;
  final VoidCallback? onUnlock;
  final VoidCallback? onRelease;

  const _ReservationCard({
    required this.reservation,
    this.onUnlock,
    this.onRelease,
  });

  String _formatDate(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  reservation.closed ? Icons.lock : Icons.lock_open,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  reservation.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Chip(
                  label: Text(
                    reservation.restype.toUpperCase(),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'PIN: ${reservation.pin}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatDate(reservation.start)} → ${_formatDate(reservation.finish)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            if (reservation.bankname != null) ...[
              const SizedBox(height: 2),
              Text(
                reservation.bankname!,
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
            if (onUnlock != null || onRelease != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onUnlock != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onUnlock,
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: const Text('Unlock'),
                      ),
                    ),
                  if (onUnlock != null && onRelease != null)
                    const SizedBox(width: 8),
                  if (onRelease != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRelease,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Release'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final LockerSection section;
  final VoidCallback onCreate;

  const _SectionCard({required this.section, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(section.name),
        subtitle: Text(
          '${section.availableCount}/${section.lockerCount} available',
        ),
        trailing: TextButton(onPressed: onCreate, child: const Text('Reserve')),
      ),
    );
  }
}
