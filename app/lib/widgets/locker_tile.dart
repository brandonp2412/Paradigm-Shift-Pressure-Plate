import 'package:floorsense_app/models/available_locker.dart';
import 'package:flutter/material.dart';

class LockerTile extends StatelessWidget {
  final AvailableLocker locker;
  final VoidCallback onReserve;

  /// Floor-plan label(s) for this bank's locker zone (e.g. `Lockers 01-56`).
  /// The floor plan only labels the bank's area, not individual lockers, and the
  /// API can't say which specific locker is free — so this is location context,
  /// not a per-locker name. Null until the labels load.
  final List<String>? lockerNames;

  const LockerTile({
    super.key,
    required this.locker,
    required this.onReserve,
    this.lockerNames,
  });

  @override
  Widget build(BuildContext context) {
    final names = lockerNames;
    return ListTile(
      isThreeLine: names != null && names.isNotEmpty,
      title: Text(locker.sectionName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${locker.bankName} · ${locker.availableCount}/${locker.lockerCount} available',
          ),
          if (names != null && names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final name in names)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
      onTap: onReserve,
    );
  }
}
