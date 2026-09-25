import 'dart:async';

import '../common.dart';
import '../db/database.dart';
import '../integrations/email.dart';
import '../jobs.dart';

/// Queues side effects (emails, cleanups) in the caller's transaction, so
/// they happen exactly when the change that caused them commits.
class Outbox {
  Outbox({
    required this.templates,
    required Clock clock,
    this.queue = const JobQueue(),
    void Function()? onEnqueue,
  }) : _clock = clock,
       _onEnqueue = onEnqueue ?? (() {});

  final EmailTemplates templates;
  final JobQueue queue;
  final Clock _clock;
  final void Function() _onEnqueue;

  Future<void> email(Db db, OutgoingEmail email, {int maxAttempts = 6}) =>
      add(db, 'email.send', email.toJson(), maxAttempts: maxAttempts);

  Future<void> add(
    Db db,
    String kind,
    Map<String, Object?> payload, {
    DateTime? runAt,
    String? dedupeKey,
    int maxAttempts = 6,
  }) async {
    await queue.enqueue(
      db,
      kind,
      payload,
      runAt: runAt ?? _clock(),
      dedupeKey: dedupeKey,
      maxAttempts: maxAttempts,
    );
    if (runAt == null) _onEnqueue();
  }

  /// Emails the people who should hear about a quote: the owners and
  /// whoever sent it, minus anyone who turned notifications off.
  Future<void> notifyBusiness(
    Db db, {
    required String businessId,
    String? sentBy,
    required OutgoingEmail Function(String to) build,
  }) async {
    final rows = await db.query(
      '''
      SELECT email FROM users
      WHERE business_id = @b AND email_notifications
        AND (role = 'owner' OR id = @sender)''',
      {'b': businessId, 'sender': sentBy ?? ''},
    );
    for (final r in rows) {
      await email(db, build(r['email'] as String));
    }
  }
}
