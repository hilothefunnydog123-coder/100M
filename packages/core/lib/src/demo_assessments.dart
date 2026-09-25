import 'body_site.dart';
import 'check_result.dart';
import 'intake.dart';
import 'urgency.dart';

/// Canned, realistic assessments for demo mode and local development.
///
/// Results built from these are always flagged `demo: true` so they can
/// never be mistaken for a real analysis.
ModelAssessment demoAssessmentFor(BodySite site, IntakeAnswers answers) {
  switch (site.domain) {
    case Domain.eye:
      return _conjunctivitis;
    case Domain.mouth:
      return _cankerSore;
    case Domain.nail:
      return _nailFungus;
    case Domain.scalp:
      return _dandruff;
    case Domain.skin:
      return switch (answers.single(Q.skinKind)) {
        'mole' => _atypicalMole,
        'acne' => _acne,
        'bite' => _bite,
        'bump' => _seborrheicKeratosis,
        _ => _eczema,
      };
  }
}

const _eczema = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like eczema. Home care is a reasonable start.',
  observationSummary:
      'A patch of dry, slightly thickened skin with fine scale and faint '
      'redness. The edges fade gradually into normal skin, and there are a '
      'few scratch marks.',
  observedFeatures: [
    'Dry, rough surface with fine flaking',
    'Faint redness with a blurry edge',
    'Scratch marks',
    'No pus, crusting, or blisters',
  ],
  possibilities: [
    Possibility(
      name: 'Eczema',
      medicalTerm: 'Atopic dermatitis',
      icd10: 'L20.9',
      likelihood: Likelihood.high,
      description:
          'A common condition where the skin barrier is weak, so skin gets '
          'dry, itchy, and inflamed. It tends to come and go.',
      supportingFeatures:
          'Itchy, dry, scaly patch with a soft edge and scratch marks.',
    ),
    Possibility(
      name: 'Contact dermatitis',
      medicalTerm: 'Allergic or irritant contact dermatitis',
      icd10: 'L25.9',
      likelihood: Likelihood.moderate,
      description:
          'A reaction to something that touched the skin, such as a soap, '
          'fragrance, metal, or plant.',
      supportingFeatures:
          'Possible if it started after a new product. A sharp, geometric '
          'edge would make this more likely.',
    ),
    Possibility(
      name: 'Ringworm',
      medicalTerm: 'Tinea corporis',
      icd10: 'B35.4',
      likelihood: Likelihood.low,
      description:
          'A fungal skin infection that makes a ring-shaped, scaly patch. It '
          'needs antifungal cream, not steroid cream.',
      supportingFeatures:
          'Less likely because there is no clear raised ring with a clearer '
          'center, but a photo can\'t rule it out.',
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason:
      'Nothing here suggests infection or anything that needs urgent care, '
      'and eczema usually responds to simple home care.',
  careSetting: CareSetting.selfCare,
  watchFor: [
    'Yellow crusts, pus, or weeping',
    'Rapidly spreading redness, warmth, or pain',
    'Clusters of small punched-out sores',
    'No improvement after 2 weeks of home care',
  ],
  selfCare: [
    'Moisturize with a thick fragrance-free cream at least twice a day',
    'Use a gentle, fragrance-free cleanser and lukewarm water',
    'Try 1% hydrocortisone cream for up to 7 days if it is very itchy',
    'Stop using any new soap, detergent, or cosmetic that could be a trigger',
  ],
  doctorQuestions: [
    'Could this be eczema or a fungal infection?',
    'Would a stronger prescription cream help?',
    'Could an allergy patch test find a trigger?',
  ],
  confidence: Confidence.moderate,
  confidenceNote:
      'The photo is clear, but eczema, contact dermatitis, and fungal rashes '
      'can look alike. A skin scraping can tell fungus apart if it doesn\'t '
      'improve.',
);

const _atypicalMole = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Probably a mole, but one feature is worth a dermatologist check.',
  observationSummary:
      'A flat brown spot about the size of a pencil eraser. It is mostly '
      'even, but one side is a little darker and the edge is slightly '
      'uneven.',
  observedFeatures: [
    'Flat, brown, about 5 to 6 mm',
    'Two shades of brown',
    'Slightly uneven border on one side',
    'No bleeding, crusting, or raised areas',
  ],
  possibilities: [
    Possibility(
      name: 'Common mole',
      medicalTerm: 'Melanocytic nevus',
      icd10: 'D22.5',
      likelihood: Likelihood.high,
      description:
          'A harmless cluster of pigment cells. Most adults have 10 to 40.',
      supportingFeatures: 'Flat, mostly uniform brown color, smooth surface.',
    ),
    Possibility(
      name: 'Atypical mole',
      medicalTerm: 'Dysplastic nevus',
      icd10: 'D22.5',
      likelihood: Likelihood.moderate,
      description:
          'A mole that looks a little irregular. Usually harmless, but worth '
          'monitoring because it shares features with melanoma.',
      supportingFeatures: 'Two shades of brown and a slightly uneven edge.',
    ),
    Possibility(
      name: 'Melanoma',
      medicalTerm: 'Malignant melanoma',
      icd10: 'C43.9',
      likelihood: Likelihood.low,
      description:
          'A skin cancer that starts in pigment cells. Caught early, it is '
          'very treatable.',
      supportingFeatures:
          'Not likely from this photo, but uneven color and border are '
          'warning signs that only an in-person exam can clear.',
      serious: true,
    ),
  ],
  redFlags: ['Two shades of brown', 'Slightly uneven border'],
  urgency: Urgency.routine,
  urgencyReason:
      'Uneven color and border are two of the ABCDE warning signs, so a '
      'dermatologist should look at it in person, with a dermatoscope.',
  careSetting: CareSetting.dermatologist,
  watchFor: [
    'Any change in size, shape, color, or height',
    'Bleeding, itching, or crusting without an injury',
    'New colors such as black, blue, red, or white',
  ],
  selfCare: [
    'Take a photo every month in the same light to track changes',
    'Protect it from the sun with SPF 30+ or clothing',
  ],
  doctorQuestions: [
    'Does this need a biopsy or should we monitor it?',
    'Should I have a full-body skin check?',
    'How often should I have my moles checked?',
  ],
  confidence: Confidence.moderate,
  confidenceNote:
      'Moles need a dermatoscope to judge well; a phone photo can miss fine '
      'detail.',
);

const _acne = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like mild to moderate acne. Start with home care.',
  observationSummary:
      'Several small red bumps and a few whiteheads on the face, with some '
      'blackheads. No large, deep, painful lumps are visible.',
  observedFeatures: [
    'Small red bumps and whiteheads',
    'Blackheads',
    'No deep cysts or scarring visible',
  ],
  possibilities: [
    Possibility(
      name: 'Acne',
      medicalTerm: 'Acne vulgaris',
      icd10: 'L70.0',
      likelihood: Likelihood.high,
      description:
          'Blocked pores and inflammation in the oil glands of the skin. Very '
          'common and treatable.',
      supportingFeatures: 'Mix of blackheads, whiteheads, and small red bumps.',
    ),
    Possibility(
      name: 'Rosacea',
      medicalTerm: 'Papulopustular rosacea',
      icd10: 'L71.9',
      likelihood: Likelihood.low,
      description:
          'Facial redness with bumps, usually in adults, often with flushing.',
      supportingFeatures: 'Less likely because blackheads are present.',
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason:
      'Mild to moderate acne without deep cysts can be treated at home at '
      'first.',
  careSetting: CareSetting.pharmacist,
  watchFor: [
    'Deep, painful lumps or cysts',
    'Scarring or dark marks that last',
    'No improvement after 8 to 12 weeks of treatment',
  ],
  selfCare: [
    'Wash twice a day with a gentle cleanser',
    'Use an over-the-counter benzoyl peroxide or adapalene gel as directed',
    'Choose non-comedogenic moisturizer and sunscreen',
    "Don't pick or squeeze spots",
  ],
  doctorQuestions: [
    'Would a prescription treatment work better for me?',
    'How long should I try a treatment before switching?',
  ],
  confidence: Confidence.high,
  confidenceNote: 'Acne is usually easy to recognize in a clear photo.',
);

const _bite = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like a bug bite reaction. Watch it for infection.',
  observationSummary:
      'A single raised red bump with a tiny central mark and a small ring of '
      'redness around it. No streaks, pus, or target pattern.',
  observedFeatures: [
    'Raised red bump',
    'Small central puncture mark',
    'Redness about 1 cm around it',
  ],
  possibilities: [
    Possibility(
      name: 'Insect bite reaction',
      medicalTerm: 'Arthropod bite reaction',
      likelihood: Likelihood.high,
      description: 'A local reaction to a bite from a mosquito, flea, or bug.',
      supportingFeatures: 'Central puncture with a small raised red area.',
    ),
    Possibility(
      name: 'Skin infection',
      medicalTerm: 'Cellulitis',
      icd10: 'L03.90',
      likelihood: Likelihood.low,
      description:
          'A bacterial infection of the skin that needs antibiotics. It '
          'causes spreading redness, warmth, and pain.',
      supportingFeatures:
          'Not likely now: the redness is small and not spreading. Mark the '
          'edge with a pen to see if it grows.',
      serious: true,
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason:
      'The reaction is small and there are no signs of infection or an '
      'allergic reaction.',
  careSetting: CareSetting.selfCare,
  watchFor: [
    'Redness spreading past a pen line drawn around it',
    'Warmth, pus, red streaks, or fever',
    'A bullseye rash in the next few weeks (after a tick bite)',
    'Swelling of the lips or tongue, or trouble breathing: emergency',
  ],
  selfCare: [
    'Wash with soap and water',
    'Use a cool compress for 10 minutes to ease swelling',
    'Try an oral antihistamine for itch, as directed on the package',
    'Keep nails short and avoid scratching',
  ],
  doctorQuestions: ['Does this look infected?', 'Do I need a tetanus booster?'],
  confidence: Confidence.moderate,
  confidenceNote: 'Many bites look alike; the history matters most.',
);

const _seborrheicKeratosis = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Likely a harmless skin growth, but have it checked.',
  observationSummary:
      'A raised, light-brown growth with a waxy, slightly rough surface that '
      'looks stuck on to the skin.',
  observedFeatures: [
    'Raised, stuck-on appearance',
    'Waxy, slightly rough surface',
    'Even light-brown color',
  ],
  possibilities: [
    Possibility(
      name: 'Seborrheic keratosis',
      medicalTerm: 'Seborrheic keratosis',
      icd10: 'L82.1',
      likelihood: Likelihood.high,
      description:
          'A very common, harmless growth that appears with age. It is not '
          'contagious and does not become cancer.',
      supportingFeatures: 'Stuck-on look with a waxy, rough surface.',
    ),
    Possibility(
      name: 'Skin cancer',
      medicalTerm: 'Basal cell carcinoma or melanoma',
      icd10: 'C44.91',
      likelihood: Likelihood.low,
      description:
          'Some skin cancers can look like harmless growths in photos.',
      supportingFeatures:
          'Not suggested by this photo, but new or growing spots should be '
          'looked at in person.',
      serious: true,
    ),
  ],
  urgency: Urgency.routine,
  urgencyReason:
      'It looks benign, but a new growth is worth confirming at a routine '
      'visit.',
  careSetting: CareSetting.primaryCare,
  watchFor: ['Bleeding, rapid growth, or a sore that won\'t heal'],
  selfCare: ['Avoid picking or scratching it off', 'Photograph it monthly'],
  doctorQuestions: [
    'Is this a seborrheic keratosis?',
    'Can it be removed if it catches on clothing?',
  ],
  confidence: Confidence.moderate,
  confidenceNote: 'A dermatoscope exam can confirm it.',
);

const _conjunctivitis = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like pink eye. It usually clears on its own.',
  observationSummary:
      'The white of the eye is pink across its whole surface, with some '
      'watery discharge. The colored part of the eye looks clear and the '
      'pupil looks normal.',
  observedFeatures: [
    'Diffuse pinkness of the white of the eye',
    'Watery discharge',
    'Clear cornea and normal pupil',
  ],
  possibilities: [
    Possibility(
      name: 'Pink eye (viral)',
      medicalTerm: 'Viral conjunctivitis',
      icd10: 'B30.9',
      likelihood: Likelihood.high,
      description:
          'A common viral infection of the eye surface. It is contagious and '
          'usually clears in 1 to 2 weeks.',
      supportingFeatures: 'Diffuse redness with watery discharge.',
    ),
    Possibility(
      name: 'Allergic pink eye',
      medicalTerm: 'Allergic conjunctivitis',
      icd10: 'H10.1',
      likelihood: Likelihood.moderate,
      description:
          'Eye irritation caused by allergies. It is very itchy and usually '
          'affects both eyes.',
      supportingFeatures: 'More likely if itching is the main symptom.',
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason:
      'There is no pain, light sensitivity, or change in vision, which are '
      'the signs that need same-day care.',
  careSetting: CareSetting.pharmacist,
  watchFor: [
    'Eye pain, light sensitivity, or blurred vision: get care today',
    'Thick yellow or green discharge',
    'Symptoms lasting more than 7 days',
  ],
  selfCare: [
    'Use a clean, cool compress on closed eyelids',
    'Try lubricating eye drops (artificial tears)',
    "Wash hands often and don't share towels",
    "Don't wear contact lenses until it clears",
  ],
  doctorQuestions: ['Is this viral, bacterial, or allergic?'],
  confidence: Confidence.moderate,
  confidenceNote: 'An eye exam is needed to see the cornea in detail.',
);

const _cankerSore = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like a canker sore. It should heal within 2 weeks.',
  observationSummary:
      'A small, round, shallow sore inside the lip with a yellow-white base '
      'and a red rim.',
  observedFeatures: [
    'Round, shallow ulcer under 1 cm',
    'Yellow-white base with a red border',
  ],
  possibilities: [
    Possibility(
      name: 'Canker sore',
      medicalTerm: 'Aphthous ulcer',
      icd10: 'K12.0',
      likelihood: Likelihood.high,
      description:
          'A common, non-contagious mouth sore that heals by itself in 1 to 2 '
          'weeks.',
      supportingFeatures: 'Small, round, shallow sore with a red rim.',
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason: 'It looks typical and has only been there a few days.',
  careSetting: CareSetting.pharmacist,
  watchFor: [
    'A sore that hasn\'t healed after 3 weeks',
    'A lump, or a white or red patch that doesn\'t wipe off',
  ],
  selfCare: [
    'Rinse with warm salt water',
    'Avoid spicy, acidic, or crunchy foods',
    'Try an over-the-counter mouth gel for pain',
  ],
  doctorQuestions: ['Why do I keep getting these?'],
  confidence: Confidence.high,
  confidenceNote: 'Canker sores are usually easy to recognize.',
);

const _nailFungus = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like a fungal nail infection. Not urgent.',
  observationSummary:
      'The nail is thickened and yellow, with crumbly debris under the free '
      'edge. No dark stripe is visible.',
  observedFeatures: ['Thick, yellow nail', 'Crumbly debris under the nail'],
  possibilities: [
    Possibility(
      name: 'Fungal nail infection',
      medicalTerm: 'Onychomycosis',
      icd10: 'B35.1',
      likelihood: Likelihood.high,
      description:
          'A slow fungal infection of the nail. Common, harmless, but hard to '
          'clear.',
      supportingFeatures: 'Thickening, yellowing, and crumbly debris.',
    ),
    Possibility(
      name: 'Nail psoriasis',
      medicalTerm: 'Nail psoriasis',
      icd10: 'L40.8',
      likelihood: Likelihood.low,
      description: 'Psoriasis affecting the nails, often with pitting.',
      supportingFeatures: 'Less likely without pits or skin psoriasis.',
    ),
  ],
  urgency: Urgency.routine,
  urgencyReason:
      'It isn\'t urgent, but a nail clipping test confirms fungus before '
      'long treatment.',
  careSetting: CareSetting.primaryCare,
  watchFor: ['A dark stripe in the nail', 'Pain, redness, or swelling'],
  selfCare: ['Keep feet dry and wear breathable shoes'],
  doctorQuestions: ['Should we confirm it with a nail clipping test?'],
  confidence: Confidence.moderate,
  confidenceNote: 'Only a lab test can confirm a fungal infection.',
);

const _dandruff = ModelAssessment(
  imageQuality: ImageQuality(usable: true),
  headline: 'Looks like dandruff. A medicated shampoo should help.',
  observationSummary:
      'Fine, greasy, yellow-white flakes on a mildly pink scalp. The hair '
      'looks normal in density.',
  observedFeatures: ['Greasy yellow-white flakes', 'Mild pinkness'],
  possibilities: [
    Possibility(
      name: 'Dandruff',
      medicalTerm: 'Seborrheic dermatitis',
      icd10: 'L21.0',
      likelihood: Likelihood.high,
      description:
          'A common, harmless scalp condition linked to yeast on the skin.',
      supportingFeatures: 'Greasy flakes without thick plaques.',
    ),
    Possibility(
      name: 'Scalp psoriasis',
      medicalTerm: 'Scalp psoriasis',
      icd10: 'L40.8',
      likelihood: Likelihood.low,
      description: 'Thicker, well-defined, silvery plaques on the scalp.',
      supportingFeatures: 'Less likely without thick, sharp-edged plaques.',
    ),
  ],
  urgency: Urgency.selfCare,
  urgencyReason: 'Nothing suggests infection or scarring hair loss.',
  careSetting: CareSetting.pharmacist,
  watchFor: ['Hair loss in patches', 'Pus bumps or a painful swelling'],
  selfCare: [
    'Use a ketoconazole or selenium shampoo 2 to 3 times a week',
    'Leave it on for 5 minutes before rinsing',
  ],
  doctorQuestions: ['Could this be psoriasis?'],
  confidence: Confidence.moderate,
  confidenceNote: 'Scalp photos can hide detail under hair.',
);
