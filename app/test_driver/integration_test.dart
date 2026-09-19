import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async => integrationDriver(
  onScreenshot: (name, image, [args]) async {
    final outputDir = Platform.environment['PRESSURE_PLATE_SCREENSHOT_DIR'];
    if (outputDir == null || outputDir.isEmpty) {
      throw StateError('PRESSURE_PLATE_SCREENSHOT_DIR must be set');
    }

    final file = await File('$outputDir/$name.png').create(recursive: true);
    await file.writeAsBytes(image);
    return true;
  },
  writeResponseOnFailure: true,
);
