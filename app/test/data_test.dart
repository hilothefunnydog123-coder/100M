import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotcheck/data/blob_store.dart';
import 'package:spotcheck/data/models.dart';
import 'package:spotcheck/data/repositories.dart';
import 'package:spotcheck/util/format.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

CheckRecord record(String id, DateTime at) => CheckRecord(
  id: id,
  createdAt: at,
  site: BodySite.arm,
  answers: IntakeAnswers.fromJson({
    'skin_kind': ['rash'],
  }),
  note: 'itchy at night',
  photoKeys: ['${id}_0'],
  result: Triage.merge(
    id: id,
    assessment: demoAssessmentFor(BodySite.arm, IntakeAnswers.empty),
    safety: SafetyRules.evaluate(BodySite.arm, IntakeAnswers.empty),
    createdAt: at,
    demo: true,
  ),
);

void main() {
  test('history round-trips and sorts newest first', () async {
    final store = MemoryBlobStore();
    final repo = HistoryRepository(store);
    final older = record('chk_a', DateTime.utc(2026, 9, 1));
    final newer = record('chk_b', DateTime.utc(2026, 9, 20)).copyWith(
      recheckDue: () => DateTime.utc(2026, 10, 4),
      doctorVerdict: 'Contact dermatitis',
    );
    await repo.save([older, newer]);
    final loaded = await repo.load();
    expect(loaded.map((r) => r.id), ['chk_b', 'chk_a']);
    expect(loaded.first.recheckDue, DateTime.utc(2026, 10, 4));
    expect(loaded.first.doctorVerdict, 'Contact dermatitis');
    expect(loaded.first.result.demo, isTrue);
    expect(loaded.last.note, 'itchy at night');
  });

  test('a corrupt record does not lose the rest of history', () async {
    final store = MemoryBlobStore();
    final good = record('chk_ok', DateTime.utc(2026, 9, 1));
    await store.writeText(
      'history.json',
      jsonEncode([
        good.toJson(),
        {'id': 'broken'},
        'nonsense',
      ]),
    );
    final loaded = await HistoryRepository(store).load();
    expect(loaded.map((r) => r.id), ['chk_ok']);
  });

  test('photos are stored and deleted by key', () async {
    final repo = HistoryRepository(MemoryBlobStore());
    await repo.savePhoto('k1', Uint8List.fromList([1, 2, 3]));
    expect(await repo.loadPhoto('k1'), [1, 2, 3]);
    await repo.deletePhotos(['k1']);
    expect(await repo.loadPhoto('k1'), isNull);
  });

  test('settings are created once and keep the install id', () async {
    final store = MemoryBlobStore();
    final repo = SettingsRepository(store);
    final first = await repo.load();
    expect(first.installId, startsWith('inst_'));
    await repo.save(first.copyWith(onboarded: true, checksUsed: 2));
    final second = await repo.load();
    expect(second.installId, first.installId);
    expect(second.onboarded, isTrue);
    expect(second.checksUsed, 2);
  });

  test('formatDate and relativeDays', () {
    final now = DateTime(2026, 9, 25, 15);
    expect(formatDate(DateTime(2026, 9, 25, 9, 5), now: now), 'Today, 9:05 AM');
    expect(formatDate(DateTime(2026, 9, 24, 22), now: now), 'Yesterday');
    expect(formatDate(DateTime(2026, 3, 2), now: now), 'Mar 2, 2026');
    expect(relativeDays(DateTime(2026, 9, 30), now: now), 'in 5 days');
    expect(relativeDays(DateTime(2026, 9, 26), now: now), 'tomorrow');
    expect(relativeDays(DateTime(2026, 9, 22), now: now), '3 days ago');
  });
}
