import 'package:flutter_test/flutter_test.dart';
import 'package:floorsense_app/models/floor_plan.dart';
import 'package:floorsense_app/services/websocket_service.dart';

void main() {
  group('FloorPlan.fromJson', () {
    test('parses planid and lockPolys (id + cid)', () {
      final plan = FloorPlan.fromJson({
        'planid': 7,
        'lockPolys': [
          {'id': 'L036', 'cid': 12, 'points': []},
          {'id': 'L035', 'cid': 12},
        ],
      });
      expect(plan.planId, 7);
      expect(plan.lockerPolygons.map((p) => p.id), ['L036', 'L035']);
      expect(plan.lockerPolygons.first.cid, 12);
    });

    test('drops polygons with empty ids and tolerates missing lockPolys', () {
      final plan = FloorPlan.fromJson({
        'planid': 1,
        'lockPolys': [
          {'id': '', 'cid': 3},
          {'cid': 3},
        ],
      });
      expect(plan.lockerPolygons, isEmpty);

      final none = FloorPlan.fromJson({'planid': 2});
      expect(none.lockerPolygons, isEmpty);
    });
  });

  group('WebSocketService.groupLockerNames', () {
    test('groups by cid, deduped and sorted', () {
      final plans = [
        FloorPlan.fromJson({
          'planid': 1,
          'lockPolys': [
            {'id': 'L035', 'cid': 12},
            {'id': 'L034', 'cid': 12},
            {'id': 'L100', 'cid': 99},
          ],
        }),
        FloorPlan.fromJson({
          'planid': 2,
          'lockPolys': [
            {'id': 'L034', 'cid': 12}, // duplicate across plans
            {'id': 'L036', 'cid': 12},
          ],
        }),
      ];

      final map = WebSocketService.groupLockerNames(plans);
      expect(map[12], ['L034', 'L035', 'L036']);
      expect(map[99], ['L100']);
    });

    test('drops lockers with no cid', () {
      final plans = [
        FloorPlan.fromJson({
          'planid': 1,
          'lockPolys': [
            {'id': 'L001'}, // no cid
            {'id': 'L002', 'cid': 5},
          ],
        }),
      ];
      final map = WebSocketService.groupLockerNames(plans);
      expect(map.keys, [5]);
      expect(map[5], ['L002']);
    });
  });
}
