import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/photo_pipeline.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../data/models.dart';

class DraftPhoto {
  const DraftPhoto({
    required this.jpeg,
    required this.kind,
    required this.quality,
    this.sample = false,
  });

  /// Prepared (resized, re-encoded) JPEG, exactly what gets uploaded.
  final Uint8List jpeg;
  final PhotoKind kind;
  final PhotoQuality quality;
  final bool sample;
}

/// Everything collected during a check, before it is analyzed.
class CheckDraft {
  CheckDraft({
    this.site,
    this.forSelf,
    this.photos = const [],
    IntakeAnswers? answers,
    this.prefilled = const {},
    this.note = '',
    this.followUpOf,
  }) : answers = answers ?? IntakeAnswers.empty;

  final BodySite? site;
  final bool? forSelf;
  final List<DraftPhoto> photos;
  final IntakeAnswers answers;

  /// Questions answered from the saved profile, so they aren't asked again.
  final Set<String> prefilled;
  final String note;
  final String? followUpOf;

  /// Questions to ask now, in order. Recomputed as answers change because
  /// follow-up questions depend on earlier answers.
  List<IntakeQuestion> get questions {
    final s = site;
    if (s == null) return const [];
    return [
      for (final q in IntakeCatalog.visibleQuestions(s.domain, answers))
        if (!prefilled.contains(q.id)) q,
    ];
  }

  DraftPhoto? photoOfKind(PhotoKind kind) {
    for (final p in photos) {
      if (p.kind == kind) return p;
    }
    return null;
  }

  CheckRequest toRequest() => CheckRequest(
    site: site!,
    answers: answers.prunedFor(site!.domain),
    note: note.trim(),
    photos: [
      for (final p in photos)
        CheckPhoto(bytes: p.jpeg, mediaType: 'image/jpeg', kind: p.kind),
    ],
  );

  CheckDraft copyWith({
    BodySite? site,
    bool? forSelf,
    List<DraftPhoto>? photos,
    IntakeAnswers? answers,
    Set<String>? prefilled,
    String? note,
  }) => CheckDraft(
    site: site ?? this.site,
    forSelf: forSelf ?? this.forSelf,
    photos: photos ?? this.photos,
    answers: answers ?? this.answers,
    prefilled: prefilled ?? this.prefilled,
    note: note ?? this.note,
    followUpOf: followUpOf,
  );
}

class CheckFlowNotifier extends Notifier<CheckDraft> {
  static const _personQuestions = {
    Q.ageBand,
    Q.sex,
    Q.skinTone,
    Q.healthContext,
  };

  @override
  CheckDraft build() => CheckDraft();

  /// Starts a new check, optionally as a recheck of an earlier one.
  void start({CheckRecord? recheckOf}) {
    state = recheckOf == null
        ? CheckDraft()
        : CheckDraft(
            site: recheckOf.site,
            answers: recheckOf.answers,
            followUpOf: recheckOf.id,
          );
  }

  void selectSite(BodySite site) {
    state = state.copyWith(
      site: site,
      answers: state.answers.prunedFor(site.domain),
    );
  }

  /// When checking yourself, answers from the saved profile are used and
  /// those questions are skipped.
  void setForSelf(bool forSelf, IntakeAnswers profile) {
    var answers = state.answers;
    for (final q in _personQuestions) {
      answers = answers.without(q);
    }
    final prefilled = <String>{};
    if (forSelf) {
      for (final q in _personQuestions) {
        if (profile.isAnswered(q)) {
          answers = answers.withAnswer(q, profile[q]);
          prefilled.add(q);
        }
      }
    }
    state = state.copyWith(
      forSelf: forSelf,
      answers: answers,
      prefilled: prefilled,
    );
  }

  void setPhoto(DraftPhoto photo) {
    state = state.copyWith(
      photos: [
        for (final p in state.photos)
          if (p.kind != photo.kind) p,
        photo,
      ]..sort((a, b) => a.kind.index.compareTo(b.kind.index)),
    );
  }

  void removePhoto(PhotoKind kind) {
    state = state.copyWith(
      photos: [
        for (final p in state.photos)
          if (p.kind != kind) p,
      ],
    );
  }

  void toggle(IntakeQuestion question, String optionId) {
    final site = state.site;
    var answers = state.answers.toggle(question, optionId);
    if (site != null) answers = answers.prunedFor(site.domain);
    state = state.copyWith(answers: answers);
  }

  void setNote(String note) => state = state.copyWith(note: note);
}

final checkFlowProvider = NotifierProvider<CheckFlowNotifier, CheckDraft>(
  CheckFlowNotifier.new,
);
