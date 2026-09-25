import 'body_site.dart';
import 'check_result.dart';
import 'intake.dart';

/// A plain-text summary a person can share with a clinician. It reports what
/// was asked, seen, and suggested; it never presents a diagnosis.
String formatDoctorSummary({
  required BodySite site,
  required IntakeAnswers answers,
  required CheckResult result,
  String note = '',
}) {
  final b = StringBuffer()
    ..writeln('SpotCheck summary')
    ..writeln('Date: ${_date(result.createdAt)}')
    ..writeln('Area: ${site.label}')
    ..writeln();

  final history = IntakeCatalog.describe(site.domain, answers);
  if (history.isNotEmpty || note.isNotEmpty) {
    b.writeln('Reported by the person');
    for (final line in history) {
      b.writeln('- $line');
    }
    if (note.isNotEmpty) b.writeln('- Note: $note');
    b.writeln();
  }

  final a = result.assessment;
  if (result.status == CheckStatus.complete && a != null) {
    if (a.observationSummary.isNotEmpty || a.observedFeatures.isNotEmpty) {
      b.writeln('What the photo analysis noted');
      if (a.observationSummary.isNotEmpty) b.writeln(a.observationSummary);
      for (final f in a.observedFeatures) {
        b.writeln('- $f');
      }
      b.writeln();
    }
    if (a.possibilities.isNotEmpty) {
      b.writeln('Possibilities suggested (not a diagnosis)');
      for (final p in a.possibilities) {
        final term = p.medicalTerm.isNotEmpty && p.medicalTerm != p.name
            ? ' (${p.medicalTerm})'
            : '';
        final code = p.icd10.isNotEmpty ? ' [${p.icd10}]' : '';
        b.writeln('- ${p.name}$term$code: ${p.likelihood.label.toLowerCase()}');
      }
      b.writeln();
    }
    if (a.redFlags.isNotEmpty) {
      b.writeln('Concerning features');
      for (final f in a.redFlags) {
        b.writeln('- $f');
      }
      b.writeln();
    }
  }

  if (result.urgency case final urgency?) {
    b.writeln('Suggested urgency: ${urgency.title} (${urgency.timeframe})');
  }
  for (final n in result.safetyNotes) {
    b.writeln('- ${n.reason}');
  }
  if (result.demo) {
    b
      ..writeln()
      ..writeln(
        'DEMO RESULT: generated for demonstration, not from a real '
        'analysis.',
      );
  }
  b
    ..writeln()
    ..writeln(
      'SpotCheck is an informational tool, not a medical device, and does '
      'not provide a diagnosis.',
    );
  return b.toString();
}

String _date(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}
