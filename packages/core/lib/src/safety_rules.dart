import 'body_site.dart';
import 'intake.dart';
import 'urgency.dart';

/// What a rule can see: where the concern is and what the person answered.
class SafetyContext {
  const SafetyContext(this.site, this.answers);

  final BodySite site;
  final IntakeAnswers answers;

  Domain get domain => site.domain;

  bool has(String questionId, String optionId) =>
      answers.has(questionId, optionId);

  bool any(String questionId, Set<String> optionIds) =>
      answers.hasAny(questionId, optionIds);

  bool get infant => has(Q.ageBand, 'lt_3m');
  bool get underTwo => any(Q.ageBand, {'lt_3m', '3m_2y'});
  bool get fever => has(Q.generalSymptoms, 'fever');
  bool skinKind(Set<String> kinds) => any(Q.skinKind, kinds);
}

/// A deterministic rule that sets a minimum urgency. Rules can only ever make
/// the final advice more cautious; the model cannot talk its way below them.
class SafetyRule {
  const SafetyRule({
    required this.id,
    required this.floor,
    required this.reason,
    required this.when,
    this.action,
    this.careSetting,
  });

  final String id;
  final Urgency floor;

  /// Plain-language explanation shown to the person.
  final String reason;

  /// An immediate step to take, if there is one (e.g. rinse the eye).
  final String? action;

  final CareSetting? careSetting;
  final bool Function(SafetyContext c) when;
}

class SafetyEvaluation {
  SafetyEvaluation(List<SafetyRule> triggered)
    : triggered = List<SafetyRule>.unmodifiable(
        <SafetyRule>[...triggered]
          ..sort((a, b) => b.floor.index - a.floor.index),
      );

  /// Triggered rules, most urgent first.
  final List<SafetyRule> triggered;

  Urgency? get floor => triggered.isEmpty ? null : triggered.first.floor;

  bool get isEmergency => floor == Urgency.emergency;

  /// The care setting named by the most urgent rule that names one.
  CareSetting? get careSetting {
    for (final r in triggered) {
      if (r.careSetting != null) return r.careSetting;
    }
    return null;
  }

  /// Immediate actions from the triggered rules, most urgent first.
  List<String> get actions => [
    for (final r in triggered)
      if (r.action != null) r.action!,
  ];
}

abstract final class SafetyRules {
  static SafetyEvaluation evaluate(BodySite site, IntakeAnswers answers) {
    final ctx = SafetyContext(site, answers);
    return SafetyEvaluation([
      for (final rule in all)
        if (rule.when(ctx)) rule,
    ]);
  }

  static final List<SafetyRule> all = [
    // ---- Emergency -------------------------------------------------------
    SafetyRule(
      id: 'trouble_breathing',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason: 'Trouble breathing needs emergency care.',
      when: (c) => c.has(Q.generalSymptoms, 'trouble_breathing'),
    ),
    SafetyRule(
      id: 'anaphylaxis_swelling',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'Swelling of the lips or tongue, or a tight throat, can be a severe '
          'allergic reaction (anaphylaxis).',
      action:
          'If an epinephrine auto-injector (such as an EpiPen) has been '
          'prescribed, use it now.',
      when: (c) => c.has(Q.generalSymptoms, 'lip_tongue_swelling'),
    ),
    SafetyRule(
      id: 'infant_fever',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'Any fever in a baby under 3 months needs to be checked by a doctor '
          'right away.',
      when: (c) => c.infant && c.fever,
    ),
    SafetyRule(
      id: 'non_blanching_rash_fever',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          "A rash that doesn't fade under a glass, together with a fever, can "
          'be a sign of a serious infection such as meningitis or sepsis.',
      when: (c) => c.has(Q.glassTest, 'stays') && c.fever,
    ),
    SafetyRule(
      id: 'severe_skin_reaction',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'Blistering or peeling skin with sores in the mouth, eyes, or '
          'genitals can be a severe reaction such as Stevens-Johnson '
          'syndrome, often caused by a medicine.',
      when: (c) =>
          c.has(Q.generalSymptoms, 'mucosal_sores') &&
          (c.has(Q.localSymptoms, 'peeling') || c.skinKind({'blisters'})),
    ),
    SafetyRule(
      id: 'rapid_spread_systemic',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'Redness that spreads within hours, with a fever or feeling very '
          'unwell, can be a serious infection.',
      when: (c) =>
          c.has(Q.generalSymptoms, 'rapid_spread') &&
          (c.fever || c.has(Q.generalSymptoms, 'very_unwell')),
    ),
    SafetyRule(
      id: 'eye_chemical',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason: 'Chemicals in the eye can cause lasting damage within minutes.',
      action:
          'Rinse the eye with clean running water for at least 15 minutes, '
          'then get emergency care.',
      when: (c) => c.has(Q.eyeSymptoms, 'chemical'),
    ),
    SafetyRule(
      id: 'eye_vision_pain',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'A sudden change in vision with eye pain or an injury needs '
          'emergency eye care.',
      when: (c) =>
          c.has(Q.eyeSymptoms, 'vision_worse') &&
          c.any(Q.eyeSymptoms, {'eye_pain', 'injury'}),
    ),
    SafetyRule(
      id: 'burn_deep',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason: 'Deep, chemical, or electrical burns need emergency care.',
      action:
          'Cool or rinse the burn under cool running water for 20 minutes '
          '(not ice) while you get help.',
      when: (c) =>
          c.skinKind({'burn'}) &&
          c.any(Q.burnDetails, {'white_charred', 'chemical_electrical'}),
    ),
    SafetyRule(
      id: 'airway_mouth_swelling',
      floor: Urgency.emergency,
      careSetting: CareSetting.emergencyRoom,
      reason:
          'Swelling in the mouth or neck with trouble swallowing can block '
          'the airway.',
      when: (c) =>
          c.has(Q.mouthSymptoms, 'trouble_swallowing') &&
          c.has(Q.mouthSymptoms, 'swelling'),
    ),

    // ---- Urgent: today ---------------------------------------------------
    SafetyRule(
      id: 'rapid_spread',
      floor: Urgency.urgent,
      reason: 'Redness that spreads within hours needs to be seen today.',
      when: (c) => c.has(Q.generalSymptoms, 'rapid_spread'),
    ),
    SafetyRule(
      id: 'very_unwell',
      floor: Urgency.urgent,
      reason: 'Feeling very unwell alongside this should be checked today.',
      when: (c) => c.has(Q.generalSymptoms, 'very_unwell'),
    ),
    SafetyRule(
      id: 'non_blanching_rash',
      floor: Urgency.urgent,
      reason:
          "Spots that don't fade under pressure should be checked by a "
          'doctor today.',
      when: (c) => c.has(Q.glassTest, 'stays'),
    ),
    SafetyRule(
      id: 'eye_vision_change',
      floor: Urgency.urgent,
      careSetting: CareSetting.eyeDoctor,
      reason: 'A sudden change in vision should be checked today.',
      when: (c) => c.has(Q.eyeSymptoms, 'vision_worse'),
    ),
    SafetyRule(
      id: 'eye_flashes_floaters',
      floor: Urgency.urgent,
      careSetting: CareSetting.eyeDoctor,
      reason:
          'New flashes or floaters can be a sign of a retinal tear or '
          'detachment and need a same-day eye exam.',
      when: (c) => c.has(Q.eyeSymptoms, 'flashes_floaters'),
    ),
    SafetyRule(
      id: 'eye_pain',
      floor: Urgency.urgent,
      reason:
          'Eye pain (more than grittiness) should be checked today to rule '
          'out problems that can threaten vision.',
      when: (c) => c.has(Q.eyeSymptoms, 'eye_pain'),
    ),
    SafetyRule(
      id: 'eye_contacts_pain',
      floor: Urgency.urgent,
      careSetting: CareSetting.eyeDoctor,
      reason:
          'A painful or light-sensitive eye in a contact lens wearer needs '
          'same-day care to rule out a corneal infection.',
      action: "Take the lenses out and don't wear them until you're checked.",
      when: (c) =>
          c.has(Q.eyeSymptoms, 'contacts') &&
          c.any(Q.eyeSymptoms, {'eye_pain', 'light_sensitive'}),
    ),
    SafetyRule(
      id: 'eye_light_sensitivity',
      floor: Urgency.urgent,
      reason:
          'Light sensitivity in a red or sore eye can mean inflammation '
          'inside the eye and needs same-day care.',
      when: (c) =>
          c.has(Q.eyeSymptoms, 'light_sensitive') &&
          c.any(Q.eyeSymptoms, {'red', 'eye_pain'}),
    ),
    SafetyRule(
      id: 'eye_injury',
      floor: Urgency.urgent,
      reason: 'Eye injuries should be examined today.',
      when: (c) => c.has(Q.eyeSymptoms, 'injury'),
    ),
    SafetyRule(
      id: 'newborn_eye',
      floor: Urgency.urgent,
      reason: 'Red or sticky eyes in a newborn should be checked today.',
      when: (c) =>
          c.infant &&
          c.domain == Domain.eye &&
          c.any(Q.eyeSymptoms, {'discharge', 'red'}),
    ),
    SafetyRule(
      id: 'newborn_jaundice',
      floor: Urgency.urgent,
      reason: 'Yellow eyes or skin in a baby need to be checked today.',
      when: (c) => c.infant && c.has(Q.eyeSymptoms, 'yellow_whites'),
    ),
    SafetyRule(
      id: 'immunocompromised_fever',
      floor: Urgency.urgent,
      reason: 'A fever with a weakened immune system needs same-day advice.',
      when: (c) => c.has(Q.healthContext, 'immunocompromised') && c.fever,
    ),
    SafetyRule(
      id: 'burn_significant',
      floor: Urgency.urgent,
      reason:
          'Large blistered burns, or blistered burns on the face, hands, or '
          'feet, need medical care today.',
      action: 'Cool the burn under cool running water for 20 minutes.',
      when: (c) =>
          c.skinKind({'burn'}) &&
          c.has(Q.burnDetails, 'blistered') &&
          (c.has(Q.burnDetails, 'larger_than_palm') ||
              {BodySite.face, BodySite.hand, BodySite.foot}.contains(c.site)),
    ),
    SafetyRule(
      id: 'burn_young_child',
      floor: Urgency.urgent,
      reason: 'Burns in babies and toddlers should be checked today.',
      when: (c) => c.skinKind({'burn'}) && c.underTwo,
    ),
    SafetyRule(
      id: 'infection_with_fever',
      floor: Urgency.urgent,
      reason:
          'A warm or oozing area together with a fever can be a spreading '
          'infection.',
      when: (c) => c.any(Q.localSymptoms, {'warm', 'oozing'}) && c.fever,
    ),
    SafetyRule(
      id: 'mouth_abscess',
      floor: Urgency.urgent,
      reason:
          'Swelling, or trouble opening the mouth, together with a fever can '
          'be an abscess that needs same-day care.',
      when: (c) => c.any(Q.mouthSymptoms, {'swelling', 'cant_open'}) && c.fever,
    ),
    SafetyRule(
      id: 'diabetic_foot_infection',
      floor: Urgency.urgent,
      reason:
          'With diabetes, a foot sore that is warm or oozing needs to be '
          'seen today.',
      when: (c) =>
          c.has(Q.healthContext, 'diabetes') &&
          c.site == BodySite.foot &&
          c.any(Q.localSymptoms, {'warm', 'oozing'}),
    ),

    // ---- Soon: 1-3 days --------------------------------------------------
    SafetyRule(
      id: 'fever',
      floor: Urgency.soon,
      reason:
          'A fever alongside this is worth a doctor\'s check in the next few '
          'days, sooner if it gets worse.',
      when: (c) => c.fever,
    ),
    SafetyRule(
      id: 'cellulitis_signs',
      floor: Urgency.soon,
      reason:
          'A warm, painful area that is spreading can be a skin infection '
          '(cellulitis) that may need antibiotics.',
      when: (c) =>
          c.has(Q.localSymptoms, 'warm') &&
          c.has(Q.localSymptoms, 'painful') &&
          c.has(Q.change, 'spreading'),
    ),
    SafetyRule(
      id: 'wound_infection',
      floor: Urgency.soon,
      reason: 'Signs of infection in a wound, bite, or burn should be checked.',
      when: (c) =>
          c.skinKind({'wound', 'bite', 'burn'}) &&
          (c.any(Q.localSymptoms, {'warm', 'oozing'}) ||
              c.has(Q.change, 'spreading')),
    ),
    SafetyRule(
      id: 'diabetic_foot',
      floor: Urgency.soon,
      reason:
          'With diabetes, wounds and blisters on the feet should be checked '
          'promptly because they can heal slowly.',
      when: (c) =>
          c.has(Q.healthContext, 'diabetes') &&
          c.site == BodySite.foot &&
          c.skinKind({'wound', 'blisters', 'burn', 'bite'}),
    ),
    SafetyRule(
      id: 'tick_rash',
      floor: Urgency.soon,
      reason:
          'A rash after a tick bite can be early Lyme disease, which is '
          'treated with antibiotics.',
      when: (c) => c.has(Q.exposures, 'tick'),
    ),
    SafetyRule(
      id: 'pregnancy_rash',
      floor: Urgency.soon,
      reason:
          'New rashes or blisters during pregnancy should be checked by your '
          'doctor or midwife.',
      when: (c) =>
          c.has(Q.healthContext, 'pregnant') &&
          c.skinKind({'rash', 'blisters'}),
    ),
    SafetyRule(
      id: 'eye_contacts_red',
      floor: Urgency.soon,
      reason: 'A red eye in a contact lens wearer should be checked.',
      action: "Take the lenses out and don't wear them until you're checked.",
      when: (c) =>
          c.has(Q.eyeSymptoms, 'contacts') && c.has(Q.eyeSymptoms, 'red'),
    ),
    SafetyRule(
      id: 'jaundice',
      floor: Urgency.soon,
      reason:
          'Yellowing of the whites of the eyes can be a sign of a liver '
          'problem and should be checked soon.',
      when: (c) => c.has(Q.eyeSymptoms, 'yellow_whites'),
    ),
    SafetyRule(
      id: 'strep_test',
      floor: Urgency.soon,
      reason:
          'A sore throat with a fever may be strep throat. Only a swab test '
          'can tell strep from a virus; a photo can\'t.',
      when: (c) => c.has(Q.mouthSymptoms, 'sore_throat') && c.fever,
    ),
    SafetyRule(
      id: 'scalp_infection',
      floor: Urgency.soon,
      reason:
          'Pus bumps or a boggy swelling on the scalp can be an infection '
          'that needs prescription treatment.',
      when: (c) => c.has(Q.scalpSymptoms, 'pus_bumps'),
    ),
    SafetyRule(
      id: 'nail_fold_infection',
      floor: Urgency.soon,
      reason:
          'A red, swollen, painful nail fold may be infected and might need '
          'draining or antibiotics.',
      when: (c) => c.has(Q.nailSymptoms, 'painful_swelling'),
    ),
    SafetyRule(
      id: 'facial_blisters',
      floor: Urgency.soon,
      reason:
          'Painful blisters on the face can be shingles, which is best '
          'treated within 3 days, especially near the eye.',
      when: (c) =>
          c.site == BodySite.face &&
          c.skinKind({'blisters'}) &&
          c.any(Q.localSymptoms, {'painful', 'burning'}),
    ),

    // ---- Routine: within 2 weeks -----------------------------------------
    SafetyRule(
      id: 'mole_warning_signs',
      floor: Urgency.routine,
      careSetting: CareSetting.dermatologist,
      reason:
          'A mole with any ABCDE warning sign should be checked by a '
          'dermatologist.',
      when: (c) =>
          c.skinKind({'mole'}) &&
          c.any(Q.moleFeatures, {
            'asymmetric',
            'irregular_border',
            'multi_color',
            'larger_6mm',
            'evolving',
            'ugly_duckling',
          }),
    ),
    SafetyRule(
      id: 'changing_spot',
      floor: Urgency.routine,
      careSetting: CareSetting.dermatologist,
      reason:
          'A spot or growth that is getting bigger, changing, or bleeding '
          'should be checked by a dermatologist.',
      when: (c) =>
          c.skinKind({'mole', 'bump'}) &&
          c.any(Q.change, {'growing', 'color', 'shape', 'bleeding'}),
    ),
    SafetyRule(
      id: 'non_healing',
      floor: Urgency.routine,
      careSetting: CareSetting.dermatologist,
      reason:
          "A sore or spot that bleeds or hasn't healed in 3 weeks should be "
          'checked for skin cancer.',
      when: (c) =>
          c.domain == Domain.skin &&
          c.has(Q.change, 'bleeding') &&
          c.any(Q.duration, {'3w_3m', '3m_1y', 'gt_1y'}),
    ),
    SafetyRule(
      id: 'mouth_persistent',
      floor: Urgency.routine,
      reason:
          'Mouth sores, patches, or lumps that last more than 3 weeks should '
          'be checked by a doctor or dentist.',
      when: (c) =>
          c.any(Q.mouthSymptoms, {'sore_3_weeks', 'white_red_patch', 'lump'}),
    ),
    SafetyRule(
      id: 'mouth_numbness',
      floor: Urgency.routine,
      reason: 'Unexplained numbness of the lip or tongue should be checked.',
      when: (c) => c.has(Q.mouthSymptoms, 'numbness'),
    ),
    SafetyRule(
      id: 'nail_dark_streak',
      floor: Urgency.routine,
      careSetting: CareSetting.dermatologist,
      reason:
          'A dark stripe in a nail, especially a new or widening one, should '
          'be checked by a dermatologist to rule out melanoma.',
      when: (c) => c.any(Q.nailSymptoms, {'dark_streak', 'pigment_on_skin'}),
    ),
    SafetyRule(
      id: 'nail_clubbing',
      floor: Urgency.routine,
      reason:
          'Nail clubbing can be linked to lung, heart, or gut conditions and '
          'should be checked.',
      when: (c) => c.has(Q.nailSymptoms, 'clubbing'),
    ),
    SafetyRule(
      id: 'scarring_hair_loss',
      floor: Urgency.routine,
      careSetting: CareSetting.dermatologist,
      reason:
          'Hair loss with smooth, shiny patches can be scarring, which is '
          'best treated early.',
      when: (c) => c.has(Q.scalpSymptoms, 'scarred_patches'),
    ),
    SafetyRule(
      id: 'immunocompromised',
      floor: Urgency.routine,
      reason:
          'With a weakened immune system, new skin, nail, or scalp problems '
          'are best checked by a doctor.',
      when: (c) =>
          c.has(Q.healthContext, 'immunocompromised') &&
          c.domain != Domain.eye &&
          c.domain != Domain.mouth,
    ),
    SafetyRule(
      id: 'young_infant',
      floor: Urgency.routine,
      reason:
          'Babies under 3 months should have new skin, eye, or mouth '
          'problems checked by their doctor.',
      when: (c) => c.infant,
    ),
  ];
}
