import 'package:floorsense_app/services/websocket_service.dart';
import 'package:flutter/material.dart';

class ConnectionBanner extends StatelessWidget {
  final WsStatus status;
  const ConnectionBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reconnecting = status == WsStatus.connecting;
    final bg = reconnecting ? scheme.secondaryContainer : scheme.errorContainer;
    final fg = reconnecting
        ? scheme.onSecondaryContainer
        : scheme.onErrorContainer;
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: reconnecting
                ? CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(fg),
                  )
                : Icon(Icons.cloud_off, size: 14, color: fg),
          ),
          const SizedBox(width: 8),
          Text(
            reconnecting ? 'Reconnecting…' : 'Offline',
            style: TextStyle(color: fg, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
