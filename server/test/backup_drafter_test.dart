import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

/// Answers with a draft or throws, and counts its calls.
class _Model implements QuoteDrafter {
  _Model(this.name, [this.error]);

  final String name;
  final Object? error;
  int calls = 0;

  @override
  Future<Draft> draft(DraftRequest request, {String? userId}) async {
    calls++;
    if (error != null) throw error!;
    return Draft(SampleJob.fence.draft, DraftStats(), model: name);
  }
}

DraftFailed _failed(int status, {bool dailyQuota = false}) => DraftFailed(
  'The model request failed.',
  cause: GeminiApiException(
    status,
    'STATUS',
    'message',
    dailyQuota: dailyQuota,
  ),
);

void main() {
  late List<Map<String, Object?>> logs;
  setUp(() => logs = []);

  BackupDrafter chain(List<_Model> models) => BackupDrafter([
    for (final m in models) (model: m.name, drafter: m),
  ], log: logs.add);

  test('the main model drafts when it can; backups stay idle', () async {
    final main = _Model('gemini-3.8-flash');
    final backup = _Model('gemini-3.7-flash');
    final d = await chain([main, backup]).draft(draftRequest());
    expect(d.model, 'gemini-3.8-flash');
    expect(backup.calls, 0);
    expect(logs, isEmpty);
  });

  test('a busy, rate limited, or refusing provider hands the job on', () async {
    for (final error in [
      _failed(503),
      _failed(429, dailyQuota: true),
      _failed(401),
      _failed(404),
      DraftFailed(
        'The model request failed.',
        cause: ClaudeApiException(529, 'overloaded_error', 'Overloaded'),
      ),
    ]) {
      logs.clear();
      final backup = _Model('gemini-3.7-flash');
      final d = await chain([
        _Model('gemini-3.8-flash', error),
        backup,
      ]).draft(draftRequest());
      expect(d.model, 'gemini-3.7-flash', reason: '$error');
      expect(logs.single, {
        'event': 'draft_backup',
        'from': 'gemini-3.8-flash',
        'to': 'gemini-3.7-flash',
        'cause': contains('${(error.cause! as ModelApiException).statusCode}'),
      });
    }
  });

  test('an answer the model gave stands', () async {
    for (final error in [
      DraftFailed('The model declined these photos.', refused: true),
      DraftFailed(
        'No valid draft was produced.',
        cause: const FormatException('bad JSON'),
      ),
      _failed(400),
    ]) {
      final backup = _Model('gemini-3.7-flash');
      await expectLater(
        chain([
          _Model('gemini-3.8-flash', error),
          backup,
        ]).draft(draftRequest()),
        throwsA(same(error)),
      );
      expect(backup.calls, 0, reason: '$error');
    }
  });

  test('tries each backup in order and reports the last failure', () async {
    final last = _failed(503);
    final third = _Model('claude-sonnet-5');
    final d = await chain([
      _Model('gemini-3.8-flash', _failed(503)),
      _Model('gemini-3.7-flash', _failed(429)),
      third,
    ]).draft(draftRequest());
    expect(d.model, 'claude-sonnet-5');
    expect(logs.map((l) => l['to']), ['gemini-3.7-flash', 'claude-sonnet-5']);

    await expectLater(
      chain([
        _Model('gemini-3.8-flash', _failed(503)),
        _Model('gemini-3.7-flash', last),
      ]).draft(draftRequest()),
      throwsA(same(last)),
    );
  });

  test('the server config builds the chain', () {
    const base = {'GEMINI_API_KEY': 'g', 'JOBWALK_AI_PROVIDER': 'gemini'};
    final withBackup = drafterFromConfig(ServerConfig.fromEnvironment(base));
    expect(withBackup, isA<BackupDrafter>());
    expect((withBackup as BackupDrafter).models.map((m) => m.model), [
      'gemini-3.8-flash',
      'gemini-3.7-flash',
    ]);
    expect(
      drafterFromConfig(
        ServerConfig.fromEnvironment({
          ...base,
          'JOBWALK_BACKUP_MODELS': 'none',
        }),
      ),
      isA<GeminiDrafter>(),
    );
    expect(
      drafterFromConfig(
        ServerConfig.fromEnvironment({'JOBWALK_FAKE_MODEL': 'true'}),
      ),
      isA<DemoDrafter>(),
    );
    final mixed =
        drafterFromConfig(
              ServerConfig.fromEnvironment({
                ...base,
                'ANTHROPIC_API_KEY': 'a',
                'JOBWALK_BACKUP_MODELS': 'gemini-3.7-flash, claude-sonnet-5',
              }),
            )
            as BackupDrafter;
    expect(mixed.models.map((m) => m.drafter.runtimeType), [
      GeminiDrafter,
      GeminiDrafter,
      Drafter,
    ]);
    final sonnet = mixed.models.last.drafter as Drafter;
    expect(sonnet.config.model, 'claude-sonnet-5');
    expect(sonnet.config.useFallbacks, isFalse);

    final free =
        drafterFromConfig(
              ServerConfig.fromEnvironment({
                ...base,
                'GROQ_API_KEY': 'q',
                'JOBWALK_FREE_TIER': 'true',
              }),
            )
            as BackupDrafter;
    expect(free.models.map((m) => m.model), [
      'gemini-3.8-flash',
      'gemini-3.7-flash',
      'gemini-3.5-flash-lite',
      'qwen/qwen3.8-27b',
    ]);
    expect((free.models.last.drafter as GroqDrafter).config.maxPhotos, 1);
  });
}
