/// Shared domain model for SpotCheck.
///
/// Everything here is pure Dart so the same intake catalog, safety rules, and
/// result model run in the Flutter app, on the server, and in the evaluation
/// harness.
library;

export 'src/body_site.dart';
export 'src/check_request.dart';
export 'src/check_result.dart';
export 'src/demo_assessments.dart';
export 'src/doctor_summary.dart';
export 'src/ids.dart';
export 'src/intake.dart';
export 'src/safety_rules.dart';
export 'src/triage.dart';
export 'src/urgency.dart';
