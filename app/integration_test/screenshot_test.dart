import 'package:floorsense_app/models/available_locker.dart';
import 'package:floorsense_app/models/locker_reservation.dart';
import 'package:floorsense_app/widgets/locker_tile.dart';
import 'package:floorsense_app/widgets/reservation_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

ThemeData _theme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: colorScheme.surfaceTint,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

const _reservation = LockerReservation(
  resid: 'demo-reservation',
  cid: 101,
  key: 'Locker 42',
  restype: 'adhoc',
  bankname: 'North Hub',
  created: 1760000000,
  start: 1760003600,
  finish: 1760032400,
  closed: true,
  active: 1,
  released: 0,
  pin: '',
  device: 'floorsense',
);

const _lockers = [
  AvailableLocker(
    bankCid: 101,
    bankName: 'North Hub',
    sectionName: 'Standard',
    typeCode: 'S',
    availableCount: 8,
    lockerCount: 24,
  ),
  AvailableLocker(
    bankCid: 102,
    bankName: 'Atrium',
    sectionName: 'Large',
    typeCode: 'L',
    availableCount: 3,
    lockerCount: 12,
  ),
  AvailableLocker(
    bankCid: 103,
    bankName: 'Level 4',
    sectionName: 'Standard',
    typeCode: 'S',
    availableCount: 11,
    lockerCount: 30,
  ),
  AvailableLocker(
    bankCid: 104,
    bankName: 'South Wing',
    sectionName: 'Compact',
    typeCode: 'C',
    availableCount: 5,
    lockerCount: 18,
  ),
];

class _OverviewScreen extends StatelessWidget {
  const _OverviewScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paradigm Shift'),
        actions: const [
          IconButton(onPressed: null, icon: Icon(Icons.tune)),
          IconButton(onPressed: null, icon: Icon(Icons.logout)),
        ],
      ),
      body: ListView(
        children: [
          ReservationCard(
            reservation: _reservation,
            onUnlock: () {},
            onRelease: () {},
          ),
          const Divider(height: 32),
          ..._lockers
              .take(3)
              .map(
                (locker) => LockerTile(
                  locker: locker,
                  lockerNames: switch (locker.bankCid) {
                    101 => const ['N01–N24'],
                    102 => const ['A01–A12'],
                    _ => const ['L4-01–L4-30'],
                  },
                  onReserve: () {},
                ),
              ),
        ],
      ),
    );
  }
}

class _AvailabilityScreen extends StatelessWidget {
  const _AvailabilityScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Available lockers'),
        actions: const [IconButton(onPressed: null, icon: Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Capacity intelligence',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ..._lockers.map(
            (locker) => LockerTile(
              locker: locker,
              lockerNames: const ['Workplace zone'],
              onReserve: () {},
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsScreen extends StatelessWidget {
  const _ControlsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Locker controls')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Locker Banks',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('North Hub'),
            subtitle: const Text('Level 2 · North wall'),
          ),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('Atrium'),
            subtitle: const Text('Ground floor · East wall'),
          ),
          SwitchListTile(
            value: false,
            onChanged: (_) {},
            title: const Text('South Wing'),
            subtitle: const Text('Level 3 · Quiet zone'),
          ),
          const Divider(),
          SwitchListTile(
            value: true,
            onChanged: (_) {},
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notify me when a locker frees up'),
            subtitle: const Text(
              'Checks selected banks roughly every 15 minutes',
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(onPressed: () {}, child: const Text('Apply')),
          ),
        ],
      ),
    );
  }
}

Future<void> _capture(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
  String name,
  Widget screen,
) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: screen,
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byType(Scaffold), findsOneWidget);

  final supportsScreenshotCapture =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!supportsScreenshotCapture) return;

  await binding.convertFlutterSurfaceToImage();
  await tester.pumpAndSettle();
  await binding.takeScreenshot(name);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('overview screenshot', (tester) async {
    await _capture(binding, tester, 'overview', const _OverviewScreen());
  });

  testWidgets('availability screenshot', (tester) async {
    await _capture(
      binding,
      tester,
      'availability',
      const _AvailabilityScreen(),
    );
  });

  testWidgets('controls screenshot', (tester) async {
    await _capture(binding, tester, 'controls', const _ControlsScreen());
  });
}
