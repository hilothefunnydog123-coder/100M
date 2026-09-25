import 'dart:convert';
import 'dart:io';

import 'package:spotcheck_core/spotcheck_core.dart';

class EvalImage {
  const EvalImage({this.url, this.path, this.kind = PhotoKind.closeUp});

  final String? url;

  /// Local path, relative to the manifest file.
  final String? path;
  final PhotoKind kind;

  factory EvalImage.fromJson(Object? json) {
    if (json is String) {
      return json.startsWith('http')
          ? EvalImage(url: json)
          : EvalImage(path: json);
    }
    final map = json as Map<String, Object?>;
    return EvalImage(
      url: map['url'] as String?,
      path: map['path'] as String?,
      kind: PhotoKind.fromId(map['kind']),
    );
  }
}

class EvalLabel {
  const EvalLabel(this.name, this.weight);

  final String name;
  final double weight;
}

/// One labeled case from a JSONL manifest.
///
/// ```json
/// {"id": "case_1", "site": "arm", "images": [{"url": "https://..."}],
///  "answers": {"skin_kind": ["rash"]}, "note": "",
///  "labels": [{"name": "Eczema", "weight": 0.7}],
///  "fitzpatrick": "fst4", "serious": false,
///  "min_urgency": "routine", "expected_urgency": "routine"}
/// ```
class EvalCase {
  const EvalCase({
    required this.id,
    required this.site,
    required this.answers,
    required this.images,
    required this.labels,
    this.note = '',
    this.source = '',
    this.fitzpatrick,
    this.serious = false,
    this.minUrgency,
    this.expectedUrgency,
  });

  final String id;
  final String source;
  final BodySite site;
  final IntakeAnswers answers;
  final String note;
  final List<EvalImage> images;

  /// Reference differential, highest weight first.
  final List<EvalLabel> labels;

  /// Self-reported Fitzpatrick type (`fst1`..`fst6`), for fairness slices.
  final String? fitzpatrick;

  /// The reference includes a condition that needs medical care.
  final bool serious;

  /// The least urgent advice that is acceptable for this case.
  final Urgency? minUrgency;

  /// Clinician-assigned urgency, when the dataset has one.
  final Urgency? expectedUrgency;

  EvalLabel? get primaryLabel => labels.isEmpty ? null : labels.first;

  factory EvalCase.fromJson(Map<String, Object?> json) {
    final site = BodySite.fromId(json['site'] as String?);
    if (site == null) throw FormatException('Unknown site in ${json['id']}');
    final labels = [
      for (final l in (json['labels'] as List? ?? const []))
        if (l is String)
          EvalLabel(l, 1)
        else if (l is Map<String, Object?>)
          EvalLabel(l['name'] as String, (l['weight'] as num? ?? 1).toDouble()),
    ]..sort((a, b) => b.weight.compareTo(a.weight));
    return EvalCase(
      id: json['id'] as String,
      source: json['source'] as String? ?? '',
      site: site,
      answers: IntakeAnswers.fromJson(json['answers']).prunedFor(site.domain),
      note: json['note'] as String? ?? '',
      images: [
        for (final i in (json['images'] as List? ?? const []))
          EvalImage.fromJson(i),
      ].take(CheckRequest.maxPhotos).toList(),
      labels: labels,
      fitzpatrick: json['fitzpatrick'] as String?,
      serious: json['serious'] == true,
      minUrgency: Urgency.fromId(json['min_urgency'] as String?),
      expectedUrgency: Urgency.fromId(json['expected_urgency'] as String?),
    );
  }
}

List<EvalCase> loadManifest(File file) => [
  for (final line in file.readAsLinesSync())
    if (line.trim().isNotEmpty)
      EvalCase.fromJson(jsonDecode(line) as Map<String, Object?>),
];
