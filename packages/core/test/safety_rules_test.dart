import 'package:spotcheck_core/spotcheck_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

class Scenario {
  const Scenario(this.name, this.site, this.raw, this.floor, this.rules);

  final String name;
  final BodySite site;
  final Map<String, List<String>> raw;
  final Urgency? floor;

  /// Rules that must fire (others may fire too).
  final List<String> rules;
}

const adult = {
  Q.ageBand: ['18_39'],
};

final scenarios = <Scenario>[
  // ---- Emergency ---------------------------------------------------------
  const Scenario(
    'trouble breathing',
    BodySite.arm,
    {
      ...adult,
      Q.generalSymptoms: ['trouble_breathing'],
    },
    Urgency.emergency,
    ['trouble_breathing'],
  ),
  const Scenario(
    'lip or tongue swelling',
    BodySite.face,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['lip_tongue_swelling'],
    },
    Urgency.emergency,
    ['anaphylaxis_swelling'],
  ),
  const Scenario(
    'fever in a baby under 3 months',
    BodySite.torso,
    {
      Q.ageBand: ['lt_3m'],
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.emergency,
    ['infant_fever', 'fever', 'young_infant'],
  ),
  const Scenario(
    'non-blanching rash with fever',
    BodySite.leg,
    {
      Q.ageBand: ['2_12'],
      Q.skinKind: ['rash'],
      Q.glassTest: ['stays'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.emergency,
    ['non_blanching_rash_fever', 'non_blanching_rash', 'fever'],
  ),
  const Scenario(
    'blisters with mucosal sores',
    BodySite.torso,
    {
      ...adult,
      Q.skinKind: ['blisters'],
      Q.exposures: ['new_medicine'],
      Q.generalSymptoms: ['mucosal_sores'],
    },
    Urgency.emergency,
    ['severe_skin_reaction'],
  ),
  const Scenario(
    'peeling rash with mucosal sores',
    BodySite.back,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.localSymptoms: ['peeling'],
      Q.generalSymptoms: ['mucosal_sores'],
    },
    Urgency.emergency,
    ['severe_skin_reaction'],
  ),
  const Scenario(
    'rapidly spreading redness with fever',
    BodySite.leg,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['rapid_spread', 'fever'],
    },
    Urgency.emergency,
    ['rapid_spread_systemic', 'rapid_spread', 'fever'],
  ),
  const Scenario(
    'chemical in the eye',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['chemical'],
    },
    Urgency.emergency,
    ['eye_chemical'],
  ),
  const Scenario(
    'vision loss with eye pain',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['vision_worse', 'eye_pain'],
    },
    Urgency.emergency,
    ['eye_vision_pain', 'eye_vision_change', 'eye_pain'],
  ),
  const Scenario(
    'charred burn',
    BodySite.hand,
    {
      ...adult,
      Q.skinKind: ['burn'],
      Q.burnDetails: ['white_charred'],
    },
    Urgency.emergency,
    ['burn_deep'],
  ),
  const Scenario(
    'mouth swelling with trouble swallowing',
    BodySite.mouth,
    {
      ...adult,
      Q.mouthSymptoms: ['swelling', 'trouble_swallowing'],
    },
    Urgency.emergency,
    ['airway_mouth_swelling'],
  ),

  // ---- Urgent ------------------------------------------------------------
  const Scenario(
    'rapidly spreading redness',
    BodySite.arm,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['rapid_spread'],
    },
    Urgency.urgent,
    ['rapid_spread'],
  ),
  const Scenario(
    'feeling very unwell',
    BodySite.back,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['very_unwell'],
    },
    Urgency.urgent,
    ['very_unwell'],
  ),
  const Scenario(
    'non-blanching rash',
    BodySite.leg,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.glassTest: ['stays'],
    },
    Urgency.urgent,
    ['non_blanching_rash'],
  ),
  const Scenario(
    'sudden vision change',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['vision_worse'],
    },
    Urgency.urgent,
    ['eye_vision_change'],
  ),
  const Scenario(
    'flashes and floaters',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['flashes_floaters'],
    },
    Urgency.urgent,
    ['eye_flashes_floaters'],
  ),
  const Scenario(
    'eye pain',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['eye_pain'],
    },
    Urgency.urgent,
    ['eye_pain'],
  ),
  const Scenario(
    'contact lens wearer with light sensitivity',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['contacts', 'light_sensitive'],
    },
    Urgency.urgent,
    ['eye_contacts_pain'],
  ),
  const Scenario(
    'red eye with light sensitivity',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['red', 'light_sensitive'],
    },
    Urgency.urgent,
    ['eye_light_sensitivity'],
  ),
  const Scenario(
    'eye injury',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['injury'],
    },
    Urgency.urgent,
    ['eye_injury'],
  ),
  const Scenario(
    'sticky eye in a newborn',
    BodySite.eye,
    {
      Q.ageBand: ['lt_3m'],
      Q.eyeSymptoms: ['discharge'],
    },
    Urgency.urgent,
    ['newborn_eye', 'young_infant'],
  ),
  const Scenario(
    'yellow eyes in a newborn',
    BodySite.eye,
    {
      Q.ageBand: ['lt_3m'],
      Q.eyeSymptoms: ['yellow_whites'],
    },
    Urgency.urgent,
    ['newborn_jaundice', 'jaundice', 'young_infant'],
  ),
  const Scenario(
    'fever with a weakened immune system',
    BodySite.arm,
    {
      ...adult,
      Q.healthContext: ['immunocompromised'],
      Q.skinKind: ['rash'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.urgent,
    ['immunocompromised_fever', 'fever', 'immunocompromised'],
  ),
  const Scenario(
    'large blistered burn',
    BodySite.arm,
    {
      ...adult,
      Q.skinKind: ['burn'],
      Q.burnDetails: ['blistered', 'larger_than_palm'],
    },
    Urgency.urgent,
    ['burn_significant'],
  ),
  const Scenario(
    'blistered burn on the face',
    BodySite.face,
    {
      ...adult,
      Q.skinKind: ['burn'],
      Q.burnDetails: ['blistered'],
    },
    Urgency.urgent,
    ['burn_significant'],
  ),
  const Scenario(
    'burn on a toddler',
    BodySite.arm,
    {
      Q.ageBand: ['3m_2y'],
      Q.skinKind: ['burn'],
      Q.burnDetails: ['none'],
    },
    Urgency.urgent,
    ['burn_young_child'],
  ),
  const Scenario(
    'warm area with fever',
    BodySite.leg,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.localSymptoms: ['warm'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.urgent,
    ['infection_with_fever', 'fever'],
  ),
  const Scenario(
    'jaw swelling with fever',
    BodySite.mouth,
    {
      ...adult,
      Q.mouthSymptoms: ['swelling', 'tooth_gum_pain'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.urgent,
    ['mouth_abscess', 'fever'],
  ),
  const Scenario(
    'oozing foot sore with diabetes',
    BodySite.foot,
    {
      ...adult,
      Q.healthContext: ['diabetes'],
      Q.skinKind: ['wound'],
      Q.localSymptoms: ['oozing'],
    },
    Urgency.urgent,
    ['diabetic_foot_infection', 'diabetic_foot', 'wound_infection'],
  ),

  // ---- Soon --------------------------------------------------------------
  const Scenario(
    'fever with a rash',
    BodySite.torso,
    {
      Q.ageBand: ['2_12'],
      Q.skinKind: ['rash'],
      Q.glassTest: ['fades'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.soon,
    ['fever'],
  ),
  const Scenario(
    'warm, painful, spreading patch',
    BodySite.leg,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.localSymptoms: ['warm', 'painful'],
      Q.change: ['spreading'],
    },
    Urgency.soon,
    ['cellulitis_signs'],
  ),
  const Scenario(
    'oozing wound',
    BodySite.arm,
    {
      ...adult,
      Q.skinKind: ['wound'],
      Q.localSymptoms: ['oozing'],
    },
    Urgency.soon,
    ['wound_infection'],
  ),
  const Scenario(
    'foot blister with diabetes',
    BodySite.foot,
    {
      ...adult,
      Q.healthContext: ['diabetes'],
      Q.skinKind: ['blisters'],
    },
    Urgency.soon,
    ['diabetic_foot'],
  ),
  const Scenario(
    'rash after a tick bite',
    BodySite.leg,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.exposures: ['tick'],
    },
    Urgency.soon,
    ['tick_rash'],
  ),
  const Scenario(
    'rash in pregnancy',
    BodySite.torso,
    {
      ...adult,
      Q.healthContext: ['pregnant'],
      Q.skinKind: ['rash'],
    },
    Urgency.soon,
    ['pregnancy_rash'],
  ),
  const Scenario(
    'red eye in a contact lens wearer',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['contacts', 'red'],
    },
    Urgency.soon,
    ['eye_contacts_red'],
  ),
  const Scenario(
    'yellow eyes in an adult',
    BodySite.eye,
    {
      Q.ageBand: ['40_64'],
      Q.eyeSymptoms: ['yellow_whites'],
    },
    Urgency.soon,
    ['jaundice'],
  ),
  const Scenario(
    'sore throat with fever',
    BodySite.mouth,
    {
      Q.ageBand: ['13_17'],
      Q.mouthSymptoms: ['sore_throat'],
      Q.generalSymptoms: ['fever'],
    },
    Urgency.soon,
    ['strep_test', 'fever'],
  ),
  const Scenario(
    'pus bumps on the scalp',
    BodySite.scalp,
    {
      Q.ageBand: ['2_12'],
      Q.scalpSymptoms: ['pus_bumps', 'patchy_loss'],
    },
    Urgency.soon,
    ['scalp_infection'],
  ),
  const Scenario(
    'painful nail fold',
    BodySite.nail,
    {
      ...adult,
      Q.nailSymptoms: ['painful_swelling'],
    },
    Urgency.soon,
    ['nail_fold_infection'],
  ),
  const Scenario(
    'painful facial blisters',
    BodySite.face,
    {
      Q.ageBand: ['65p'],
      Q.skinKind: ['blisters'],
      Q.localSymptoms: ['painful'],
    },
    Urgency.soon,
    ['facial_blisters'],
  ),

  // ---- Routine -----------------------------------------------------------
  const Scenario(
    'asymmetric mole',
    BodySite.back,
    {
      Q.ageBand: ['40_64'],
      Q.skinKind: ['mole'],
      Q.moleFeatures: ['asymmetric'],
    },
    Urgency.routine,
    ['mole_warning_signs'],
  ),
  const Scenario(
    'growing bump',
    BodySite.arm,
    {
      ...adult,
      Q.skinKind: ['bump'],
      Q.change: ['growing'],
    },
    Urgency.routine,
    ['changing_spot'],
  ),
  const Scenario(
    'bleeding spot that will not heal',
    BodySite.face,
    {
      Q.ageBand: ['65p'],
      Q.skinKind: ['bump'],
      Q.duration: ['3w_3m'],
      Q.change: ['bleeding'],
    },
    Urgency.routine,
    ['non_healing', 'changing_spot'],
  ),
  const Scenario(
    'mouth sore for 3 weeks',
    BodySite.mouth,
    {
      Q.ageBand: ['40_64'],
      Q.mouthSymptoms: ['sore_3_weeks'],
    },
    Urgency.routine,
    ['mouth_persistent'],
  ),
  const Scenario(
    'numb lip',
    BodySite.mouth,
    {
      ...adult,
      Q.mouthSymptoms: ['numbness'],
    },
    Urgency.routine,
    ['mouth_numbness'],
  ),
  const Scenario(
    'dark nail streak',
    BodySite.nail,
    {
      ...adult,
      Q.nailSymptoms: ['dark_streak', 'one_nail'],
    },
    Urgency.routine,
    ['nail_dark_streak'],
  ),
  const Scenario(
    'nail clubbing',
    BodySite.nail,
    {
      Q.ageBand: ['65p'],
      Q.nailSymptoms: ['clubbing'],
    },
    Urgency.routine,
    ['nail_clubbing'],
  ),
  const Scenario(
    'scarring hair loss',
    BodySite.scalp,
    {
      ...adult,
      Q.scalpSymptoms: ['scarred_patches'],
    },
    Urgency.routine,
    ['scarring_hair_loss'],
  ),
  const Scenario(
    'skin problem with a weakened immune system',
    BodySite.arm,
    {
      ...adult,
      Q.healthContext: ['immunocompromised'],
      Q.skinKind: ['acne'],
    },
    Urgency.routine,
    ['immunocompromised'],
  ),
  const Scenario(
    'newborn skin spot',
    BodySite.face,
    {
      Q.ageBand: ['lt_3m'],
      Q.skinKind: ['acne'],
    },
    Urgency.routine,
    ['young_infant'],
  ),

  // ---- Nothing should fire -----------------------------------------------
  const Scenario(
    'ordinary acne',
    BodySite.face,
    {
      Q.ageBand: ['13_17'],
      Q.skinKind: ['acne'],
      Q.duration: ['3w_3m'],
      Q.localSymptoms: ['itchy'],
      Q.generalSymptoms: ['none'],
    },
    null,
    [],
  ),
  const Scenario(
    'itchy rash that fades under glass',
    BodySite.torso,
    {
      ...adult,
      Q.skinKind: ['rash'],
      Q.glassTest: ['fades'],
      Q.localSymptoms: ['itchy'],
      Q.generalSymptoms: ['none'],
    },
    null,
    [],
  ),
  const Scenario(
    'stable ordinary mole',
    BodySite.back,
    {
      ...adult,
      Q.skinKind: ['mole'],
      Q.moleFeatures: ['none'],
      Q.change: ['no_change'],
    },
    null,
    [],
  ),
  const Scenario(
    'itchy watery red eye',
    BodySite.eye,
    {
      ...adult,
      Q.eyeSymptoms: ['red', 'itchy_watery'],
    },
    null,
    [],
  ),
  const Scenario(
    'new canker sore',
    BodySite.mouth,
    {
      ...adult,
      Q.mouthSymptoms: ['mouth_ulcer'],
      Q.duration: ['1_6d'],
    },
    null,
    [],
  ),
  const Scenario(
    'thick yellow toenail',
    BodySite.nail,
    {
      Q.ageBand: ['40_64'],
      Q.nailSymptoms: ['thick_yellow'],
    },
    null,
    [],
  ),
  const Scenario(
    'dandruff',
    BodySite.scalp,
    {
      ...adult,
      Q.scalpSymptoms: ['flaking'],
    },
    null,
    [],
  ),
  const Scenario(
    'small clean cut',
    BodySite.hand,
    {
      ...adult,
      Q.skinKind: ['wound'],
      Q.localSymptoms: ['painful'],
    },
    null,
    [],
  ),
  const Scenario(
    'small unblistered burn',
    BodySite.arm,
    {
      ...adult,
      Q.skinKind: ['burn'],
      Q.burnDetails: ['none'],
    },
    null,
    [],
  ),
];

void main() {
  group('SafetyRules scenarios', () {
    for (final s in scenarios) {
      test(s.name, () {
        final result = SafetyRules.evaluate(s.site, answers(s.raw));
        expect(result.floor, s.floor);
        final fired = result.triggered.map((r) => r.id).toList();
        expect(fired, containsAll(s.rules));
        if (s.floor == null) expect(fired, isEmpty);
      });
    }
  });

  test('every rule is exercised by at least one scenario', () {
    final covered = {for (final s in scenarios) ...s.rules};
    final missing = SafetyRules.all
        .map((r) => r.id)
        .where((id) => !covered.contains(id))
        .toList();
    expect(missing, isEmpty, reason: 'Add scenarios for: $missing');
  });

  test('rule ids are unique', () {
    final ids = SafetyRules.all.map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('evaluation is sorted most urgent first', () {
    final result = SafetyRules.evaluate(
      BodySite.leg,
      answers({
        ...adult,
        Q.skinKind: ['rash'],
        Q.glassTest: ['stays'],
        Q.generalSymptoms: ['fever', 'rapid_spread'],
      }),
    );
    final floors = result.triggered.map((r) => r.floor.index).toList();
    final sorted = [...floors]..sort((a, b) => b - a);
    expect(floors, sorted);
    expect(result.isEmergency, isTrue);
  });

  test('care setting and actions come from the triggered rules', () {
    final result = SafetyRules.evaluate(
      BodySite.eye,
      answers({
        ...adult,
        Q.eyeSymptoms: ['contacts', 'eye_pain'],
      }),
    );
    expect(result.floor, Urgency.urgent);
    expect(result.careSetting, CareSetting.eyeDoctor);
    expect(result.actions, isNotEmpty);
  });

  test('no answers means no rules', () {
    for (final site in BodySite.values) {
      expect(SafetyRules.evaluate(site, IntakeAnswers.empty).floor, isNull);
    }
  });
}
