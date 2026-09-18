import 'package:floorsense_app/models/locker_reservation.dart';
import 'package:flutter/material.dart';

class ReservationCard extends StatelessWidget {
  final LockerReservation reservation;
  final VoidCallback onUnlock;
  final VoidCallback onRelease;

  const ReservationCard({
    super.key,
    required this.reservation,
    required this.onUnlock,
    required this.onRelease,
  });

  String _formatDate(int ts) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reservation.closed ? Icons.lock : Icons.lock_open,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Text(
                reservation.key,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
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
            '${_formatDate(reservation.start)} → ${_formatDate(reservation.finish)}',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.lock_open, size: 18),
                  label: const Text('Unlock'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRelease,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Release'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
