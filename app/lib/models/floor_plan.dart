/// A single locker on a floor plan (`lockPolys` entry from `/floorplan`).
///
/// The floor plan describes the *names* and bank of every locker, but carries no
/// free/occupied state — the API never exposes which specific locker is free, so
/// these are used only to list the lockers that exist in a bank.
class LockerPolygon {
  /// The locker key / name, e.g. `L036`.
  final String id;

  /// The bank (controller id) this locker belongs to, when present.
  final int? cid;

  const LockerPolygon({required this.id, this.cid});

  factory LockerPolygon.fromJson(Map<String, dynamic> json) {
    return LockerPolygon(
      id: json['id'] as String? ?? '',
      cid: (json['cid'] as num?)?.toInt(),
    );
  }
}

/// Minimal floor plan: its id, the static file that holds its geometry
/// (`deskLoc`), and the lockers on it. Polygon points and image metadata are
/// intentionally ignored — we only need locker names per bank.
///
/// The `/floorplan-list` socket response carries `planid`/`deskloc` but no
/// geometry; the lockers live in the static file at `<webURI>/floorplans/<deskLoc>`
/// (parsed via [lockersFromDetails]).
class FloorPlan {
  final int planId;
  final String deskLoc;
  final List<LockerPolygon> lockerPolygons;

  const FloorPlan({
    required this.planId,
    this.deskLoc = '',
    this.lockerPolygons = const [],
  });

  factory FloorPlan.fromJson(Map<String, dynamic> json) {
    return FloorPlan(
      planId: (json['planid'] as num?)?.toInt() ?? 0,
      deskLoc: json['deskloc'] as String? ?? '',
      lockerPolygons: lockersFromDetails(json),
    );
  }

  /// Parses the `lockPolys` array (present in the static floor-details file, and
  /// occasionally inline) into locker polygons, dropping unnamed entries.
  static List<LockerPolygon> lockersFromDetails(Map<String, dynamic> json) {
    final polys = json['lockPolys'];
    if (polys is! List) return const [];
    return polys
        .whereType<Map<String, dynamic>>()
        .map(LockerPolygon.fromJson)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }
}
