/// The clinical domain a check belongs to. It decides which intake questions
/// are asked, which safety rules apply, and how the photo is read.
enum Domain {
  skin('skin', 'skin'),
  eye('eye', 'eye'),
  mouth('mouth', 'mouth and throat'),
  nail('nail', 'nail'),
  scalp('scalp', 'scalp and hair');

  const Domain(this.id, this.noun);

  final String id;

  /// Lower-case noun used in sentences ("a skin concern").
  final String noun;

  static Domain? fromId(String? id) {
    for (final d in values) {
      if (d.id == id) return d;
    }
    return null;
  }
}

/// Where on the body the concern is. Intimate areas are intentionally not
/// supported: the app routes those to a clinician instead of analysing photos.
enum BodySite {
  face('face', 'Face', Domain.skin),
  scalp('scalp', 'Scalp & hair', Domain.scalp),
  eye('eye', 'Eye', Domain.eye),
  mouth('mouth', 'Mouth & throat', Domain.mouth),
  neck('neck', 'Neck', Domain.skin),
  torso('torso', 'Chest & belly', Domain.skin),
  back('back', 'Back', Domain.skin),
  arm('arm', 'Arm', Domain.skin),
  hand('hand', 'Hand', Domain.skin),
  leg('leg', 'Leg', Domain.skin),
  foot('foot', 'Foot', Domain.skin),
  nail('nail', 'Nail', Domain.nail);

  const BodySite(this.id, this.label, this.domain);

  final String id;
  final String label;
  final Domain domain;

  static BodySite? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}
