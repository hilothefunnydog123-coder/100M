import 'package:spotcheck_core/spotcheck_core.dart';

/// Decides whether a predicted possibility names the same condition as a
/// reference label.
///
/// Model output ("Eczema (atopic dermatitis)") and dataset labels ("Acute
/// dermatitis, NOS") rarely match verbatim, so both are mapped to concepts
/// through a synonym table. When several aliases match, the longest wins,
/// so "tinea versicolor" maps to its own concept rather than to "tinea".
/// Extend [synonyms] when the report lists frequent unmatched names.
class LabelMatcher {
  LabelMatcher({Map<String, List<String>> synonyms = LabelMatcher.synonyms}) {
    for (final e in synonyms.entries) {
      for (final alias in e.value) {
        _aliases[normalize(alias)] = e.key;
      }
    }
  }

  final _aliases = <String, String>{};

  static String normalize(String s) => s
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\bnos\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Concepts named by [text], longest alias wins.
  Set<String> conceptsOf(String text) {
    final padded = ' ${normalize(text)} ';
    final hits = [
      for (final alias in _aliases.keys)
        if (padded.contains(' $alias ')) alias,
    ];
    return {
      for (final alias in hits)
        if (!hits.any(
          (other) =>
              other != alias &&
              other.length > alias.length &&
              ' $other '.contains(' $alias ') &&
              _aliases[other] != _aliases[alias],
        ))
          _aliases[alias]!,
    };
  }

  bool matches(Possibility prediction, String label) {
    final labelConcepts = conceptsOf(label);
    final names = [prediction.name, prediction.medicalTerm]
      ..removeWhere((n) => n.trim().isEmpty);
    if (labelConcepts.isNotEmpty) {
      return names.any(
        (n) => conceptsOf(n).intersection(labelConcepts).isNotEmpty,
      );
    }
    // Unknown label: fall back to whole-phrase containment either way.
    final l = normalize(label);
    return names.any((n) {
      final p = normalize(n);
      return p.isNotEmpty &&
          (p == l || ' $p '.contains(' $l ') || ' $l '.contains(' $p '));
    });
  }

  /// Whether [label] maps to any known concept.
  bool knows(String label) => conceptsOf(label).isNotEmpty;

  static const synonyms = <String, List<String>>{
    'eczema': [
      'eczema',
      'atopic dermatitis',
      'nummular eczema',
      'discoid eczema',
      'dyshidrotic eczema',
      'dyshidrosis',
      'pompholyx',
      'acute dermatitis',
      'chronic dermatitis',
      'acute and chronic dermatitis',
      'subacute dermatitis',
    ],
    'contact_dermatitis': [
      'contact dermatitis',
      'allergic contact dermatitis',
      'irritant contact dermatitis',
    ],
    'urticaria': ['urticaria', 'hives', 'wheals'],
    'insect_bite': [
      'insect bite',
      'insect bites',
      'bug bite',
      'bug bites',
      'arthropod bite',
      'bite reaction',
      'papular urticaria',
      'mosquito bite',
      'flea bites',
      'bed bug bites',
    ],
    'folliculitis': ['folliculitis', 'pseudofolliculitis'],
    'psoriasis': ['psoriasis', 'plaque psoriasis', 'guttate psoriasis'],
    'tinea': [
      'tinea',
      'ringworm',
      'tinea corporis',
      'tinea cruris',
      'tinea pedis',
      'athletes foot',
      'jock itch',
      'dermatophytosis',
      'fungal skin infection',
    ],
    'tinea_versicolor': ['tinea versicolor', 'pityriasis versicolor'],
    'impetigo': ['impetigo'],
    'herpes_zoster': ['herpes zoster', 'shingles', 'zoster'],
    'herpes_simplex': [
      'herpes simplex',
      'cold sore',
      'fever blister',
      'herpes labialis',
    ],
    'pigmented_purpuric': [
      'pigmented purpuric eruption',
      'pigmented purpuric dermatosis',
      'schamberg',
      'capillaritis',
    ],
    'acne': ['acne', 'acne vulgaris'],
    'drug_rash': [
      'drug rash',
      'drug eruption',
      'drug reaction',
      'morbilliform drug eruption',
    ],
    'pityriasis_rosea': ['pityriasis rosea'],
    'keratosis_pilaris': ['keratosis pilaris'],
    'lichen_simplex': [
      'lichen simplex chronicus',
      'lichen simplex',
      'neurodermatitis',
    ],
    'rosacea': ['rosacea'],
    'viral_exanthem': ['viral exanthem', 'viral exanthema', 'viral rash'],
    'lichen_planus': ['lichen planus', 'lichenoid eruption'],
    'bruise': ['ecchymoses', 'ecchymosis', 'bruise', 'bruising'],
    'granuloma_annulare': ['granuloma annulare'],
    'vasculitis': [
      'vasculitis',
      'leukocytoclastic vasculitis',
      'cutaneous vasculitis',
      'small vessel vasculitis',
    ],
    'hypersensitivity': ['hypersensitivity', 'allergic reaction'],
    'photodermatitis': [
      'photodermatitis',
      'polymorphous light eruption',
      'polymorphic light eruption',
      'sun allergy',
      'phototoxic reaction',
    ],
    'abrasion': ['abrasion', 'scrape', 'scab'],
    'prurigo_nodularis': ['prurigo nodularis', 'prurigo'],
    'purpura': ['purpura', 'petechiae'],
    'stasis_dermatitis': [
      'stasis dermatitis',
      'venous eczema',
      'gravitational eczema',
    ],
    'scabies': ['scabies'],
    'wart': ['verruca vulgaris', 'verruca', 'wart', 'warts', 'plantar wart'],
    'intertrigo': ['intertrigo'],
    'molluscum': ['molluscum contagiosum', 'molluscum'],
    'scar': ['scar', 'scar condition', 'keloid', 'hypertrophic scar'],
    'abscess': ['abscess', 'boil', 'furuncle', 'carbuncle'],
    'cellulitis': ['cellulitis', 'erysipelas'],
    'miliaria': ['miliaria', 'heat rash', 'prickly heat'],
    'perioral_dermatitis': ['perioral dermatitis', 'periorificial dermatitis'],
    'seborrheic_dermatitis': [
      'seborrheic dermatitis',
      'seborrhoeic dermatitis',
      'dandruff',
    ],
    'actinic_keratosis': ['actinic keratosis', 'solar keratosis'],
    'scc': [
      'scc',
      'sccis',
      'squamous cell carcinoma',
      'bowens disease',
      'bowen disease',
    ],
    'bcc': ['basal cell carcinoma', 'bcc'],
    'melanoma': ['melanoma', 'malignant melanoma'],
    'nevus': [
      'melanocytic nevus',
      'nevus',
      'mole',
      'common mole',
      'atypical nevus',
      'dysplastic nevus',
      'atypical mole',
    ],
    'seborrheic_keratosis': ['seborrheic keratosis', 'seborrhoeic keratosis'],
    'vitiligo': ['vitiligo'],
    'melasma': ['melasma'],
    'hyperpigmentation': [
      'post inflammatory hyperpigmentation',
      'postinflammatory hyperpigmentation',
      'hyperpigmentation',
    ],
    'erythema_multiforme': ['erythema multiforme'],
    'hand_foot_mouth': ['hand foot and mouth disease', 'hand foot mouth'],
    'varicella': ['varicella', 'chickenpox', 'chicken pox'],
    'lupus': ['lupus', 'cutaneous lupus', 'discoid lupus'],
    'dermatofibroma': ['dermatofibroma'],
    'cyst': ['epidermoid cyst', 'sebaceous cyst', 'cyst'],
    'skin_tag': ['skin tag', 'acrochordon'],
    'angioma': ['hemangioma', 'cherry angioma', 'angioma'],
    'hidradenitis': ['hidradenitis', 'hidradenitis suppurativa'],
  };
}
