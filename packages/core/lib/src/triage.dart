import 'check_result.dart';
import 'safety_rules.dart';
import 'urgency.dart';

/// Merges the model's assessment with the deterministic safety rules.
///
/// The merge is one-directional: rules can raise urgency, never lower it, and
/// a retake or decline still carries whatever urgency the answers alone
/// require (a blurry photo of a rash with a fever is still a fever).
abstract final class Triage {
  static const defaultRetakeMessage =
      "The photo wasn't clear enough to assess. Retake it in bright, even "
      'light, hold steady, and fill most of the frame with the area.';

  static const defaultDeclinedMessage =
      "We couldn't analyze this check. If you're worried about it, please "
      'contact a doctor or pharmacist.';

  static CheckResult merge({
    required String id,
    required ModelAssessment assessment,
    required SafetyEvaluation safety,
    required DateTime createdAt,
    String model = '',
    bool demo = false,
  }) {
    if (!assessment.imageQuality.usable) {
      return retake(
        id: id,
        safety: safety,
        createdAt: createdAt,
        assessment: assessment,
        model: model,
        demo: demo,
      );
    }
    final floor = safety.floor;
    final urgency = Urgency.maxOf(assessment.urgency, floor)!;
    return CheckResult(
      id: id,
      status: CheckStatus.complete,
      createdAt: createdAt,
      urgency: urgency,
      careSetting: careSettingFor(urgency, safety, assessment.careSetting),
      escalatedBySafetyRules:
          floor != null && floor.isMoreUrgentThan(assessment.urgency),
      safetyNotes: notesFor(safety),
      assessment: assessment,
      model: model,
      demo: demo,
    );
  }

  static CheckResult retake({
    required String id,
    required SafetyEvaluation safety,
    required DateTime createdAt,
    ModelAssessment? assessment,
    String model = '',
    bool demo = false,
  }) {
    final advice = assessment?.imageQuality.retakeAdvice ?? '';
    final floor = safety.floor;
    return CheckResult(
      id: id,
      status: CheckStatus.retake,
      createdAt: createdAt,
      urgency: floor,
      careSetting: floor == null ? null : careSettingFor(floor, safety, null),
      safetyNotes: notesFor(safety),
      assessment: assessment,
      message: advice.isEmpty ? defaultRetakeMessage : advice,
      model: model,
      demo: demo,
    );
  }

  static CheckResult declined({
    required String id,
    required SafetyEvaluation safety,
    required DateTime createdAt,
    String message = defaultDeclinedMessage,
    String model = '',
  }) {
    final floor = safety.floor;
    return CheckResult(
      id: id,
      status: CheckStatus.declined,
      createdAt: createdAt,
      urgency: floor,
      careSetting: floor == null ? null : careSettingFor(floor, safety, null),
      safetyNotes: notesFor(safety),
      message: message,
      model: model,
    );
  }

  /// Prefers the setting named by a rule that drives the final urgency, then
  /// the model's choice if it fits the urgency, then a sensible default.
  static CareSetting careSettingFor(
    Urgency urgency,
    SafetyEvaluation safety,
    CareSetting? modelChoice,
  ) {
    for (final rule in safety.triggered) {
      if (rule.floor == urgency &&
          rule.careSetting != null &&
          rule.careSetting!.fits(urgency)) {
        return rule.careSetting!;
      }
    }
    if (modelChoice != null && modelChoice.fits(urgency)) return modelChoice;
    return CareSetting.defaultFor(urgency);
  }

  static List<SafetyNote> notesFor(SafetyEvaluation safety) => [
    for (final r in safety.triggered)
      SafetyNote(
        ruleId: r.id,
        urgency: r.floor,
        reason: r.reason,
        action: r.action,
      ),
  ];
}
