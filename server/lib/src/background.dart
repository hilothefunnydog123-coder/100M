import 'integrations/email.dart';
import 'integrations/object_store.dart';
import 'jobs.dart';
import 'services/billing.dart';
import 'services/maintenance.dart';
import 'services/quotes.dart';

/// Every kind of background job and what runs it.
Map<String, JobHandler> jobHandlers({
  required EmailSender email,
  required ObjectStore store,
  required QuoteService quotes,
  required BillingService billing,
  required Maintenance maintenance,
}) => {
  'email.send': (payload) async {
    try {
      await email.send(OutgoingEmail.fromJson(payload));
    } on EmailException catch (e) {
      if (!e.retryable) throw PermanentJobError(e.message);
      rethrow;
    }
  },
  'quote.follow_up': quotes.followUp,
  'storage.delete': (payload) async {
    final keys = payload['keys'];
    if (keys is! List) return;
    for (final key in keys) {
      if (key is String) await store.delete(key);
    }
  },
  'stripe.cancel_subscription': billing.cancelSubscription,
  Maintenance.kind: maintenance.run,
};
