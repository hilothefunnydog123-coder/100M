/// How soon the person should get the concern seen, ordered from least to
/// most urgent. The order is load-bearing: safety rules and the model's
/// assessment are merged by taking the most urgent level.
enum Urgency {
  selfCare(
    'self_care',
    title: 'Home care & watch it',
    timeframe: 'Monitor at home',
    guidance:
        'This can usually be cared for at home. See a doctor if it gets '
        'worse, spreads, or isn\'t better in 2 weeks.',
  ),
  routine(
    'routine',
    title: 'Book a doctor visit',
    timeframe: 'Within 2 weeks',
    guidance:
        'Schedule a visit in the next 2 weeks, sooner if it changes or you '
        'get new symptoms.',
  ),
  soon(
    'soon',
    title: 'See a doctor soon',
    timeframe: 'Within 1–3 days',
    guidance: 'Book an appointment with a doctor in the next few days.',
  ),
  urgent(
    'urgent',
    title: 'See a doctor today',
    timeframe: 'Today',
    guidance:
        'Go to urgent care or get a same-day appointment. If symptoms get '
        'worse quickly, get emergency care.',
  ),
  emergency(
    'emergency',
    title: 'Get emergency care now',
    timeframe: 'Now',
    guidance:
        'Call emergency services or go to the nearest emergency room now.',
  );

  const Urgency(
    this.id, {
    required this.title,
    required this.timeframe,
    required this.guidance,
  });

  final String id;
  final String title;
  final String timeframe;
  final String guidance;

  bool isAtLeast(Urgency other) => index >= other.index;

  bool isMoreUrgentThan(Urgency other) => index > other.index;

  /// The more urgent of [a] and [b]. A null side is ignored.
  static Urgency? maxOf(Urgency? a, Urgency? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.index >= b.index ? a : b;
  }

  static Urgency? fromId(String? id) {
    for (final u in values) {
      if (u.id == id) return u;
    }
    return null;
  }
}

/// Who the person should see. Ordered roughly by acuity so it can be
/// escalated together with urgency.
enum CareSetting {
  selfCare('self_care', 'Home care'),
  pharmacist('pharmacist', 'Pharmacist'),
  primaryCare('primary_care', 'Primary care doctor'),
  dermatologist('dermatologist', 'Dermatologist'),
  eyeDoctor('eye_doctor', 'Eye doctor'),
  dentist('dentist', 'Dentist'),
  urgentCare('urgent_care', 'Urgent care'),
  emergencyRoom('emergency_room', 'Emergency room');

  const CareSetting(this.id, this.label);

  final String id;
  final String label;

  static CareSetting? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The care setting implied by an urgency level when nothing more
  /// specific is known.
  static CareSetting defaultFor(Urgency urgency) => switch (urgency) {
    Urgency.emergency => CareSetting.emergencyRoom,
    Urgency.urgent => CareSetting.urgentCare,
    Urgency.soon || Urgency.routine => CareSetting.primaryCare,
    Urgency.selfCare => CareSetting.selfCare,
  };

  /// Whether this setting is appropriate for the given urgency. A same-day
  /// or emergency need can't be met by booking a specialist weeks out.
  bool fits(Urgency urgency) => switch (urgency) {
    Urgency.emergency => this == CareSetting.emergencyRoom,
    Urgency.urgent =>
      this == CareSetting.urgentCare ||
          this == CareSetting.emergencyRoom ||
          this == CareSetting.eyeDoctor,
    Urgency.soon || Urgency.routine =>
      this != CareSetting.selfCare && this != CareSetting.pharmacist,
    Urgency.selfCare => true,
  };
}
