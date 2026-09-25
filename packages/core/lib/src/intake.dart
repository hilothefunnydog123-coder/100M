import 'body_site.dart';

enum QuestionKind { single, multi }

/// Questions about the person are asked once and can be prefilled from the
/// user's saved profile when they check themselves.
enum QuestionGroup { person, concern, symptoms }

class IntakeOption {
  const IntakeOption(this.id, this.label, {this.exclusive = false});

  final String id;
  final String label;

  /// Picking this option clears every other option ("None of these").
  final bool exclusive;
}

/// Shows a question only when another question has one of [anyOf] selected.
class ShowIf {
  const ShowIf(this.questionId, this.anyOf);

  final String questionId;
  final Set<String> anyOf;

  bool matches(IntakeAnswers answers) => answers.hasAny(questionId, anyOf);
}

class IntakeQuestion {
  const IntakeQuestion({
    required this.id,
    required this.prompt,
    required this.kind,
    required this.options,
    this.help,
    this.domains = allDomains,
    this.showIf,
    this.group = QuestionGroup.concern,
    this.optional = false,
  });

  static const allDomains = {
    Domain.skin,
    Domain.eye,
    Domain.mouth,
    Domain.nail,
    Domain.scalp,
  };

  final String id;
  final String prompt;
  final String? help;
  final QuestionKind kind;
  final List<IntakeOption> options;
  final Set<Domain> domains;
  final ShowIf? showIf;
  final QuestionGroup group;
  final bool optional;

  bool appliesTo(Domain domain, IntakeAnswers answers) =>
      domains.contains(domain) && (showIf?.matches(answers) ?? true);

  IntakeOption? option(String optionId) {
    for (final o in options) {
      if (o.id == optionId) return o;
    }
    return null;
  }
}

/// Question ids, so rules and UI code can't drift apart on spelling.
abstract final class Q {
  static const ageBand = 'age_band';
  static const sex = 'sex';
  static const skinTone = 'skin_tone';
  static const healthContext = 'health_context';
  static const skinKind = 'skin_kind';
  static const moleFeatures = 'mole_features';
  static const glassTest = 'glass_test';
  static const burnDetails = 'burn_details';
  static const eyeSymptoms = 'eye_symptoms';
  static const mouthSymptoms = 'mouth_symptoms';
  static const nailSymptoms = 'nail_symptoms';
  static const scalpSymptoms = 'scalp_symptoms';
  static const duration = 'duration';
  static const change = 'change';
  static const localSymptoms = 'local_symptoms';
  static const exposures = 'exposures';
  static const generalSymptoms = 'general_symptoms';
}

/// Immutable answers: question id -> selected option ids.
class IntakeAnswers {
  IntakeAnswers([Map<String, Set<String>> values = const {}])
    : _values = Map.unmodifiable({
        for (final e in values.entries)
          if (e.value.isNotEmpty) e.key: Set<String>.unmodifiable(e.value),
      });

  static final empty = IntakeAnswers();

  final Map<String, Set<String>> _values;

  Set<String> operator [](String questionId) =>
      _values[questionId] ?? const <String>{};

  Iterable<String> get answeredQuestionIds => _values.keys;

  bool isAnswered(String questionId) => _values.containsKey(questionId);

  bool has(String questionId, String optionId) {
    assert(
      IntakeCatalog.byId(questionId)?.option(optionId) != null,
      'Unknown intake option $questionId.$optionId',
    );
    return this[questionId].contains(optionId);
  }

  bool hasAny(String questionId, Iterable<String> optionIds) =>
      optionIds.any((o) => has(questionId, o));

  /// The selected option of a single-choice question, if any.
  String? single(String questionId) {
    final v = this[questionId];
    return v.isEmpty ? null : v.first;
  }

  IntakeAnswers withAnswer(String questionId, Set<String> optionIds) =>
      IntakeAnswers({..._values, questionId: optionIds});

  IntakeAnswers without(String questionId) =>
      IntakeAnswers({..._values}..remove(questionId));

  /// Toggles [optionId] on a multi-choice question, honouring exclusive
  /// options such as "None of these".
  IntakeAnswers toggle(IntakeQuestion question, String optionId) {
    final option = question.option(optionId);
    if (option == null) return this;
    if (question.kind == QuestionKind.single) {
      return withAnswer(question.id, {optionId});
    }
    final current = {...this[question.id]};
    if (current.contains(optionId)) {
      current.remove(optionId);
    } else if (option.exclusive) {
      current
        ..clear()
        ..add(optionId);
    } else {
      current
        ..removeWhere((id) => question.option(id)?.exclusive ?? false)
        ..add(optionId);
    }
    return withAnswer(question.id, current);
  }

  /// Keeps only answers to questions that are visible for [domain] given the
  /// other answers, e.g. dropping mole questions after switching to "rash".
  IntakeAnswers prunedFor(Domain domain) {
    var result = this;
    // Visibility can cascade, so iterate until stable.
    for (var i = 0; i < 4; i++) {
      final visible = IntakeCatalog.visibleQuestions(
        domain,
        result,
      ).map((q) => q.id).toSet();
      final next = IntakeAnswers({
        for (final e in result._values.entries)
          if (visible.contains(e.key)) e.key: e.value,
      });
      if (next == result) return next;
      result = next;
    }
    return result;
  }

  Map<String, List<String>> toJson() => {
    for (final e in _values.entries) e.key: (e.value.toList()..sort()),
  };

  /// Parses answers, silently dropping unknown questions and options and
  /// enforcing single-choice questions. Never trusts client input.
  factory IntakeAnswers.fromJson(Object? json) {
    if (json is! Map) return IntakeAnswers.empty;
    final values = <String, Set<String>>{};
    for (final entry in json.entries) {
      final question = IntakeCatalog.byId('${entry.key}');
      final raw = entry.value;
      if (question == null || raw is! List) continue;
      final selected = <String>{
        for (final id in raw)
          if (id is String && question.option(id) != null) id,
      };
      if (selected.isEmpty) continue;
      final exclusive = selected.where((id) => question.option(id)!.exclusive);
      if (question.kind == QuestionKind.single || exclusive.isNotEmpty) {
        values[question.id] = {
          exclusive.isNotEmpty ? exclusive.first : selected.first,
        };
      } else {
        values[question.id] = selected;
      }
    }
    return IntakeAnswers(values);
  }

  @override
  bool operator ==(Object other) {
    if (other is! IntakeAnswers) return false;
    if (other._values.length != _values.length) return false;
    for (final e in _values.entries) {
      final o = other._values[e.key];
      if (o == null || o.length != e.value.length || !o.containsAll(e.value)) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    _values.entries.map(
      (e) => Object.hash(e.key, Object.hashAllUnordered(e.value)),
    ),
  );

  @override
  String toString() => 'IntakeAnswers(${toJson()})';
}

abstract final class IntakeCatalog {
  static IntakeQuestion? byId(String id) => _byId[id];

  static final Map<String, IntakeQuestion> _byId = {
    for (final q in all) q.id: q,
  };

  /// Questions to ask for [domain], in order, given the answers so far.
  static List<IntakeQuestion> visibleQuestions(
    Domain domain,
    IntakeAnswers answers,
  ) => [
    for (final q in all)
      if (q.appliesTo(domain, answers)) q,
  ];

  /// Human-readable "question: answer" lines, used in the model prompt and
  /// the doctor summary.
  static List<String> describe(Domain domain, IntakeAnswers answers) => [
    for (final q in visibleQuestions(domain, answers))
      if (answers.isAnswered(q.id))
        '${q.prompt} ${[for (final o in q.options)
          if (answers[q.id].contains(o.id)) o.label].join('; ')}',
  ];

  static const all = <IntakeQuestion>[
    // ---- About the person ------------------------------------------------
    IntakeQuestion(
      id: Q.ageBand,
      prompt: 'How old is the person?',
      kind: QuestionKind.single,
      group: QuestionGroup.person,
      options: [
        IntakeOption('lt_3m', 'Under 3 months'),
        IntakeOption('3m_2y', '3 months to 2 years'),
        IntakeOption('2_12', '2 to 12 years'),
        IntakeOption('13_17', '13 to 17 years'),
        IntakeOption('18_39', '18 to 39 years'),
        IntakeOption('40_64', '40 to 64 years'),
        IntakeOption('65p', '65 or older'),
      ],
    ),
    IntakeQuestion(
      id: Q.sex,
      prompt: 'Sex assigned at birth',
      kind: QuestionKind.single,
      group: QuestionGroup.person,
      optional: true,
      options: [
        IntakeOption('female', 'Female'),
        IntakeOption('male', 'Male'),
        IntakeOption('intersex', 'Intersex'),
        IntakeOption('unspecified', 'Prefer not to say'),
      ],
    ),
    IntakeQuestion(
      id: Q.skinTone,
      prompt: 'Which best describes their natural skin?',
      help:
          'Conditions can look different on different skin tones, so this '
          'helps the analysis.',
      kind: QuestionKind.single,
      group: QuestionGroup.person,
      optional: true,
      options: [
        IntakeOption('fst1', 'Very fair: always burns, never tans'),
        IntakeOption('fst2', 'Fair: usually burns, tans a little'),
        IntakeOption('fst3', 'Medium: sometimes burns, tans gradually'),
        IntakeOption('fst4', 'Olive or light brown: rarely burns'),
        IntakeOption('fst5', 'Brown: very rarely burns'),
        IntakeOption('fst6', 'Dark brown or black: never burns'),
      ],
    ),
    IntakeQuestion(
      id: Q.healthContext,
      prompt: 'Do any of these apply?',
      kind: QuestionKind.multi,
      group: QuestionGroup.person,
      options: [
        IntakeOption(
          'immunocompromised',
          'Weakened immune system (chemo, transplant, HIV, long-term '
              'steroids)',
        ),
        IntakeOption('diabetes', 'Diabetes'),
        IntakeOption('pregnant', 'Pregnant'),
        IntakeOption('eczema_history', 'Eczema or very sensitive skin'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),

    // ---- What it is ------------------------------------------------------
    IntakeQuestion(
      id: Q.skinKind,
      prompt: 'What best describes it?',
      kind: QuestionKind.single,
      domains: {Domain.skin},
      options: [
        IntakeOption('mole', 'A mole or dark spot'),
        IntakeOption('rash', 'A rash or red patch'),
        IntakeOption('bump', 'A bump, lump, or growth'),
        IntakeOption('acne', 'Pimples or a breakout'),
        IntakeOption('blisters', 'Blisters'),
        IntakeOption('dry_patch', 'A dry, scaly, or flaky patch'),
        IntakeOption('bite', 'A bite or sting'),
        IntakeOption('wound', 'A cut, scrape, or wound'),
        IntakeOption('burn', 'A burn'),
        IntakeOption('color_change', 'Lighter or darker patches of skin'),
        IntakeOption('other', 'Something else'),
      ],
    ),
    IntakeQuestion(
      id: Q.moleFeatures,
      prompt: 'Is any of this true about the spot?',
      help: 'These are the ABCDE warning signs dermatologists look for.',
      kind: QuestionKind.multi,
      domains: {Domain.skin},
      showIf: ShowIf(Q.skinKind, {'mole'}),
      options: [
        IntakeOption('asymmetric', "One half doesn't match the other"),
        IntakeOption('irregular_border', 'Ragged, notched, or blurry edges'),
        IntakeOption(
          'multi_color',
          'More than one color (brown, black, red, white, or blue)',
        ),
        IntakeOption('larger_6mm', 'Bigger than a pencil eraser (6 mm)'),
        IntakeOption('evolving', 'Changing in size, shape, color, or height'),
        IntakeOption('ugly_duckling', 'Looks different from their other moles'),
        IntakeOption('none', 'None of these', exclusive: true),
        IntakeOption('unsure', 'Not sure', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.glassTest,
      prompt:
          'If you press a clear glass firmly against the rash, do the spots '
          'stay visible?',
      help:
          'A rash that does not fade under pressure can be a sign of a '
          'serious infection, especially with a fever.',
      kind: QuestionKind.single,
      domains: {Domain.skin},
      showIf: ShowIf(Q.skinKind, {'rash'}),
      options: [
        IntakeOption('stays', "Yes, the spots don't fade"),
        IntakeOption('fades', 'No, they fade'),
        IntakeOption('not_tried', "Haven't tried or can't tell"),
      ],
    ),
    IntakeQuestion(
      id: Q.burnDetails,
      prompt: 'About the burn:',
      kind: QuestionKind.multi,
      domains: {Domain.skin},
      showIf: ShowIf(Q.skinKind, {'burn'}),
      options: [
        IntakeOption('larger_than_palm', "Bigger than the person's palm"),
        IntakeOption('blistered', 'Blistered'),
        IntakeOption('white_charred', 'White, leathery, or charred areas'),
        IntakeOption('chemical_electrical', 'Chemical or electrical burn'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.eyeSymptoms,
      prompt: 'Which of these apply?',
      kind: QuestionKind.multi,
      domains: {Domain.eye},
      options: [
        IntakeOption('red', 'Redness'),
        IntakeOption('discharge', 'Discharge or crusting'),
        IntakeOption('itchy_watery', 'Itchy or watery'),
        IntakeOption('eye_pain', 'Eye pain (more than gritty)'),
        IntakeOption('light_sensitive', 'Light hurts the eye'),
        IntakeOption(
          'vision_worse',
          "Vision suddenly worse (doesn't clear with blinking)",
        ),
        IntakeOption(
          'flashes_floaters',
          'New flashes of light or a shower of floaters',
        ),
        IntakeOption('lid_lump', 'Lump or swelling on the eyelid'),
        IntakeOption('yellow_whites', 'Whites of the eyes look yellow'),
        IntakeOption('injury', 'Something hit or got into the eye'),
        IntakeOption('chemical', 'Chemical splash in the eye'),
        IntakeOption('contacts', 'Wears contact lenses'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.mouthSymptoms,
      prompt: 'Which of these apply?',
      kind: QuestionKind.multi,
      domains: {Domain.mouth},
      options: [
        IntakeOption('sore_throat', 'Sore throat'),
        IntakeOption('mouth_ulcer', 'A mouth sore or ulcer'),
        IntakeOption('sore_3_weeks', "A sore that hasn't healed in 3 weeks"),
        IntakeOption(
          'white_red_patch',
          "A white or red patch that doesn't wipe off",
        ),
        IntakeOption('lump', 'A lump or thickening'),
        IntakeOption('tooth_gum_pain', 'Tooth or gum pain'),
        IntakeOption(
          'swelling',
          'Swelling in the jaw, neck, or under the tongue',
        ),
        IntakeOption('trouble_swallowing', 'Trouble swallowing or drooling'),
        IntakeOption('cant_open', "Can't fully open the mouth"),
        IntakeOption('numbness', 'Numbness of the lip or tongue'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.nailSymptoms,
      prompt: 'Which of these apply?',
      kind: QuestionKind.multi,
      domains: {Domain.nail},
      options: [
        IntakeOption('dark_streak', 'A dark stripe running along the nail'),
        IntakeOption(
          'pigment_on_skin',
          'Dark color spreading onto the skin around the nail',
        ),
        IntakeOption('thick_yellow', 'Thick, yellow, or crumbly'),
        IntakeOption('lifting', 'Nail lifting off the nail bed'),
        IntakeOption('pitting', 'Tiny pits or dents'),
        IntakeOption(
          'painful_swelling',
          'Red, swollen, painful skin around the nail',
        ),
        IntakeOption(
          'clubbing',
          'Rounded fingertip with the nail curving around it',
        ),
        IntakeOption('recent_injury', 'Recent injury to the nail'),
        IntakeOption('one_nail', 'Only one nail is affected'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.scalpSymptoms,
      prompt: 'Which of these apply?',
      kind: QuestionKind.multi,
      domains: {Domain.scalp},
      options: [
        IntakeOption('patchy_loss', 'Round or patchy bald spots'),
        IntakeOption('thinning', 'Overall thinning'),
        IntakeOption('flaking', 'Flaking or scaling'),
        IntakeOption('pus_bumps', 'Pus bumps or a boggy, swollen area'),
        IntakeOption(
          'scarred_patches',
          "Smooth, shiny patches where hair won't regrow",
        ),
        IntakeOption('lice', 'Seeing lice or nits'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),

    // ---- History ---------------------------------------------------------
    IntakeQuestion(
      id: Q.duration,
      prompt: 'How long has it been there?',
      kind: QuestionKind.single,
      group: QuestionGroup.symptoms,
      options: [
        IntakeOption('lt_1d', 'Less than a day'),
        IntakeOption('1_6d', '1 to 6 days'),
        IntakeOption('1_3w', '1 to 3 weeks'),
        IntakeOption('3w_3m', '3 weeks to 3 months'),
        IntakeOption('3m_1y', '3 months to a year'),
        IntakeOption('gt_1y', 'Over a year'),
        IntakeOption('unknown', 'Not sure'),
      ],
    ),
    IntakeQuestion(
      id: Q.change,
      prompt: 'How has it changed?',
      kind: QuestionKind.multi,
      group: QuestionGroup.symptoms,
      domains: {Domain.skin, Domain.mouth, Domain.nail, Domain.scalp},
      options: [
        IntakeOption('growing', 'Getting bigger'),
        IntakeOption('color', 'Changing color'),
        IntakeOption('shape', 'Changing shape'),
        IntakeOption('spreading', 'Spreading to new areas'),
        IntakeOption('bleeding', 'Bleeding or crusting without an injury'),
        IntakeOption('no_change', 'Staying the same', exclusive: true),
        IntakeOption('improving', 'Getting better', exclusive: true),
        IntakeOption('unsure', 'Not sure', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.localSymptoms,
      prompt: 'Does it…',
      kind: QuestionKind.multi,
      group: QuestionGroup.symptoms,
      domains: {Domain.skin, Domain.nail, Domain.scalp},
      options: [
        IntakeOption('itchy', 'Itch'),
        IntakeOption('painful', 'Hurt'),
        IntakeOption('burning', 'Burn or sting'),
        IntakeOption('warm', 'Feel warm or hot'),
        IntakeOption('oozing', 'Ooze pus or fluid'),
        IntakeOption('peeling', 'Blister or peel over a large area'),
        IntakeOption('numb', 'Feel numb'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.exposures,
      prompt: 'Could any of these be related?',
      kind: QuestionKind.multi,
      group: QuestionGroup.symptoms,
      domains: {Domain.skin},
      showIf: ShowIf(Q.skinKind, {
        'rash',
        'blisters',
        'dry_patch',
        'bite',
        'acne',
        'bump',
        'other',
      }),
      options: [
        IntakeOption(
          'new_product',
          'New soap, cosmetic, detergent, or jewelry',
        ),
        IntakeOption('new_medicine', 'A new medicine in the last 2 months'),
        IntakeOption('plants_outdoors', 'Plants, woods, or gardening'),
        IntakeOption('tick', 'A tick was attached'),
        IntakeOption('sun', 'Lots of sun recently'),
        IntakeOption('contact_similar', 'Someone nearby has a similar rash'),
        IntakeOption('travel', 'Recent travel abroad'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
    IntakeQuestion(
      id: Q.generalSymptoms,
      prompt: 'Any of these right now?',
      kind: QuestionKind.multi,
      group: QuestionGroup.symptoms,
      options: [
        IntakeOption('fever', 'Fever or chills'),
        IntakeOption('very_unwell', 'Feeling very unwell'),
        IntakeOption('trouble_breathing', 'Trouble breathing'),
        IntakeOption(
          'lip_tongue_swelling',
          'Swelling of the lips or tongue, or a tight throat',
        ),
        IntakeOption('mucosal_sores', 'Sores in the mouth, eyes, or genitals'),
        IntakeOption('rapid_spread', 'Redness spreading fast (within hours)'),
        IntakeOption('joint_pain', 'Joint pain'),
        IntakeOption('none', 'None of these', exclusive: true),
      ],
    ),
  ];
}
