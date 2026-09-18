import 'package:floorsense_app/models/bank.dart';
import 'package:floorsense_app/services/background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FilterSheet extends StatefulWidget {
  final List<Bank> banks;
  final Set<int> initialDisabled;

  const FilterSheet({
    super.key,
    required this.banks,
    required this.initialDisabled,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late Set<int> _disabled;
  bool _watchEnabled = false;
  bool _watchBusy = false;

  @override
  void initState() {
    super.initState();
    _disabled = Set<int>.from(widget.initialDisabled);
    BackgroundWatch.isEnabled().then((v) {
      if (mounted) setState(() => _watchEnabled = v);
    });
  }

  Future<void> _toggleWatch(bool value) async {
    setState(() {
      _watchEnabled = value;
      _watchBusy = true;
    });
    try {
      if (value) {
        await BackgroundWatch.enable();
      } else {
        await BackgroundWatch.disable();
      }
    } finally {
      if (mounted) setState(() => _watchBusy = false);
    }
  }

  /// Debug-only: fire the real background check now and report the outcome.
  /// Watch for a system notification for each currently-free selected bank.
  Future<void> _debugRunCheck() async {
    setState(() => _watchBusy = true);
    bool ok = false;
    Object? error;
    try {
      ok = await BackgroundWatch.debugForceCheck();
    } catch (e) {
      error = e;
    } finally {
      if (mounted) setState(() => _watchBusy = false);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? 'Check threw: $error'
              : ok
              ? 'Check ran — watch for a notification'
              : 'Check failed (connect/auth). See logs.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Locker Banks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: widget.banks.map((bank) {
                  final enabled = !_disabled.contains(bank.cid);
                  return SwitchListTile(
                    value: enabled,
                    title: Text(bank.name),
                    subtitle: Text(
                      [
                        if (bank.location1.isNotEmpty) bank.location1,
                        if (bank.altLocation1 != null &&
                            bank.altLocation1!.isNotEmpty)
                          bank.altLocation1!,
                      ].join(' · '),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v) {
                          _disabled.remove(bank.cid);
                        } else {
                          _disabled.add(bank.cid);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const Divider(),
            SwitchListTile(
              value: _watchEnabled,
              onChanged: _watchBusy ? null : _toggleWatch,
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Notify me when a locker frees up'),
              subtitle: const Text(
                'Checks the selected banks roughly every 15 minutes',
              ),
            ),
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: OutlinedButton.icon(
                  onPressed: _watchBusy ? null : _debugRunCheck,
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Debug: run check now'),
                ),
              ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _disabled),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
