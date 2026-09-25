import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

EvalResult result(String id, int actual, int? predicted, {Trade? trade}) =>
    EvalResult(
      id: id,
      trade: trade ?? Trade.painting,
      actualTotalCents: actual,
      predictedTotalCents: predicted,
      usable: predicted != null,
      costUsd: 0.2,
      latencyMs: int.parse(id),
    );

void main() {
  test('summary metrics', () {
    final s = EvalSummary([
      result('10', 10000, 11000), // +10%
      result('20', 10000, 8000), // -20%
      result('30', 10000, 10500), // +5%
      result('40', 10000, 13000, trade: Trade.fencing), // +30%
      result('50', 10000, null), // unusable
    ]);
    expect(s.cases, 5);
    expect(s.priced, 4);
    expect(s.unusable, 1);
    expect(s.medianAbsErrorPct, 15);
    expect(s.medianBiasPct, 7.5);
    expect(s.withinPct(10), 50);
    expect(s.withinPct(20), 75);
    expect(s.meanCostUsd, closeTo(0.2, 1e-9));
    expect(s.latencyPercentile(0.5), 30);
    final byTrade = s.toJson()['by_trade'] as Map;
    expect((byTrade['fencing'] as Map)['cases'], 1);
    expect(s.toMarkdown(), contains('| Within 20% | 75.0% |'));
  });

  test('empty runs do not divide by zero', () {
    final s = EvalSummary(const []);
    expect(s.medianAbsErrorPct, isNull);
    expect(s.withinPct(10), isNull);
    expect(s.toMarkdown(), contains('n/a'));
  });

  test('runs a case end to end with the sample drafter', () async {
    final dir = await Directory.systemTemp.createTemp('jobwalk_eval');
    addTearDown(() => dir.delete(recursive: true));
    final photo = img.Image(width: 800, height: 600);
    img.fill(photo, color: img.ColorRgb8(150, 140, 120));
    File('${dir.path}/fence.png').writeAsBytesSync(img.encodePng(photo));
    final manifest = File('${dir.path}/jobs.jsonl')
      ..writeAsStringSync(
        '// comments are allowed\n'
        '${jsonEncode({
          'id': 'fence-1',
          'trade': 'fencing',
          'photos': ['fence.png'],
          'actual_total': 4655.00,
          'option': 'cedar',
        })}\n'
        '${jsonEncode({
          'id': 'missing-photo',
          'trade': 'fencing',
          'photos': ['nope.png'],
          'actual_total': 100,
        })}\n',
      );
    final cases = EvalCase.readManifest(manifest);
    expect(cases, hasLength(2));
    final drafter = DemoDrafter(delay: Duration.zero);
    final ok = await runCase(cases[0], drafter, root: dir);
    expect(ok.usable, isTrue);
    expect(ok.option, 'Cedar');
    expect(ok.predictedTotalCents, 465500);
    expect(ok.errorPct, 0);
    final missing = await runCase(cases[1], drafter, root: dir);
    expect(missing.error, isNotNull);
  });

  test('bad manifest lines are reported', () {
    expect(
      () => EvalCase.fromJson({'id': 'x', 'photos': <Object?>[]}),
      throwsFormatException,
    );
  });
}
