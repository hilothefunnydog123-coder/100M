import 'package:jobwalk_core/jobwalk_core.dart';

import '../common.dart';
import '../db/database.dart';
import '../integrations/stripe.dart';
import 'accounts.dart';
import 'quotes.dart';

class BillingSettings {
  const BillingSettings({
    this.webhookSecrets = const [],
    this.proPriceId,
    this.crewPriceId,
    this.platformFeeBps = 100,
    this.processingFeeBps = 290,
    this.processingFeeCents = 30,
    this.country = 'US',
    this.currency = 'usd',
  });

  /// Signing secrets of the webhook endpoints (platform and Connect).
  final List<String> webhookSecrets;
  final String? proPriceId;
  final String? crewPriceId;

  /// Jobwalk's cut of each deposit, in basis points (100 = 1%).
  final int platformFeeBps;

  /// Card processing, passed through: with destination charges the
  /// platform pays Stripe's fee, so the application fee covers it.
  final int processingFeeBps;
  final int processingFeeCents;
  final String country;
  final String currency;

  /// What Jobwalk keeps from a deposit of [amountCents].
  int applicationFee(int amountCents) {
    final fee =
        (amountCents * (platformFeeBps + processingFeeBps) / 10000).round() +
        processingFeeCents;
    return fee.clamp(0, amountCents);
  }

  String get feeDescription {
    final pct = (platformFeeBps + processingFeeBps) / 100;
    final pctText = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    return processingFeeCents > 0
        ? '$pctText% + $processingFeeCents¢ per deposit'
        : '$pctText% per deposit';
  }
}

/// Subscriptions (Stripe Billing), payouts to contractors (Stripe Connect
/// Express), and card deposits from their customers.
class BillingService {
  BillingService({
    required Db db,
    required StripeClient? stripe,
    required this.settings,
    required this.publicUrl,
    required QuoteService quotes,
    required String linkSecret,
    Clock clock = systemClock,
    LogSink? log,
  }) : _db = db,
       _stripe = stripe,
       _quotes = quotes,
       _linkSecret = linkSecret,
       _clock = clock,
       _log = log ?? ((_) {});

  final BillingSettings settings;
  final Uri publicUrl;
  final Db _db;
  final StripeClient? _stripe;
  final QuoteService _quotes;
  final String _linkSecret;
  final Clock _clock;
  final LogSink _log;

  bool get enabled => _stripe != null;

  StripeClient get _api =>
      _stripe ??
      (throw ApiError.unavailable(
        'billing_unavailable',
        "Payments aren't set up on this server yet.",
      ));

  String _url(String path, [Map<String, String>? query]) =>
      publicUrl.replace(path: path, queryParameters: query).toString();

  // ---------------------------------------------------------------------------
  // Subscription
  // ---------------------------------------------------------------------------

  /// A Stripe Checkout page for [plan] (`pro` or `crew`).
  Future<Map<String, Object?>> checkout(Account a, Object? plan) async {
    a.requireOwner();
    final api = _api;
    final price = switch (plan) {
      'pro' => settings.proPriceId,
      'crew' => settings.crewPriceId,
      _ => throw ApiError.badRequest('invalid_plan', 'Choose pro or crew.'),
    };
    if (price == null) {
      throw ApiError.unavailable(
        'billing_unavailable',
        "That plan isn't available yet.",
      );
    }
    final b = (await _db.one(
      'SELECT plan, plan_status FROM businesses WHERE id = @b',
      {'b': a.businessId},
    ))!;
    if (b['plan'] != 'trial' &&
        const {'active', 'trialing', 'past_due'}.contains(b['plan_status'])) {
      throw ApiError(
        409,
        'already_subscribed',
        'You already have a plan. Change it from Manage billing.',
      );
    }
    final customer = await _customer(a);
    final session = await _call(
      () => api.post('/v1/checkout/sessions', {
        'mode': 'subscription',
        'customer': customer,
        'client_reference_id': a.businessId,
        'line_items': [
          {'price': price, 'quantity': 1},
        ],
        'allow_promotion_codes': true,
        'subscription_data': {
          'metadata': {'business_id': a.businessId},
        },
        'metadata': {'business_id': a.businessId, 'kind': 'subscription'},
        'success_url':
            '${_url('/billing/done')}?session_id={CHECKOUT_SESSION_ID}',
        'cancel_url': _url('/billing/cancelled'),
      }),
    );
    _log({'event': 'checkout_started', 'business': a.businessId, 'plan': plan});
    return {'url': session['url']};
  }

  /// Stripe's billing portal: change plan, update the card, cancel.
  Future<Map<String, Object?>> portal(Account a) async {
    a.requireOwner();
    final api = _api;
    final row = (await _db.one(
      'SELECT stripe_customer_id FROM businesses WHERE id = @b',
      {'b': a.businessId},
    ))!;
    final customer = row['stripe_customer_id'] as String?;
    if (customer == null) {
      throw ApiError(409, 'no_subscription', 'Choose a plan first.');
    }
    final session = await _call(
      () => api.post('/v1/billing_portal/sessions', {
        'customer': customer,
        'return_url': _url('/billing/done'),
      }),
    );
    return {'url': session['url']};
  }

  Future<String> _customer(Account a) async {
    final row = (await _db.one(
      'SELECT stripe_customer_id, profile FROM businesses WHERE id = @b',
      {'b': a.businessId},
    ))!;
    final existing = row['stripe_customer_id'] as String?;
    if (existing != null) return existing;
    final name = BusinessProfile.fromJson(row['profile']).name;
    final customer = await _call(
      () => _api.post('/v1/customers', {
        'email': a.email,
        if (name.isNotEmpty) 'name': name,
        'metadata': {'business_id': a.businessId},
      }, idempotencyKey: 'customer-${a.businessId}'),
    );
    final stored = await _db.one(
      '''
      UPDATE businesses SET stripe_customer_id = COALESCE(stripe_customer_id, @c)
      WHERE id = @b RETURNING stripe_customer_id''',
      {'c': customer['id'], 'b': a.businessId},
    );
    return stored!['stripe_customer_id'] as String;
  }

  /// Applies a subscription's current state from Stripe. Fetching instead
  /// of trusting the event makes out-of-order webhooks harmless.
  Future<void> syncSubscription(
    String subscriptionId, {
    String? businessId,
  }) async {
    final sub = await _call(
      () => _api.get('/v1/subscriptions/$subscriptionId'),
    );
    final status = asString(sub['status']) ?? 'incomplete';
    final customer = asString(sub['customer']);
    final items = asMap(sub['items'])['data'];
    final price = items is List && items.isNotEmpty
        ? asString(asMap(asMap(items.first)['price'])['id'])
        : null;
    final plan = price != null && price == settings.crewPriceId
        ? 'crew'
        : 'pro';
    final business =
        businessId ??
        asString(asMap(sub['metadata'])['business_id']) ??
        (await _db.one(
              'SELECT id FROM businesses WHERE stripe_customer_id = @c',
              {'c': customer},
            ))?['id']
            as String?;
    if (business == null) {
      _log({'event': 'stripe_unmatched', 'subscription': subscriptionId});
      return;
    }
    const live = {'active', 'trialing', 'past_due'};
    // A stale event about an old subscription must not override a newer
    // live one.
    final n = await _db.execute(
      '''
      UPDATE businesses SET plan = @plan, plan_status = @status,
        stripe_subscription_id = @sub,
        stripe_customer_id = COALESCE(stripe_customer_id, @cus),
        updated_at = @now:timestamptz
      WHERE id = @b AND (stripe_subscription_id IS NULL
        OR stripe_subscription_id = @sub OR @live)''',
      {
        'plan': plan,
        'status': status,
        'sub': subscriptionId,
        'cus': customer,
        'now': _clock(),
        'b': business,
        'live': live.contains(status),
      },
    );
    _log({
      'event': 'subscription_synced',
      'business': business,
      'plan': plan,
      'status': status,
      'applied': n == 1,
    });
  }

  /// Cancels at once; used when an account is deleted.
  Future<void> cancelSubscription(Map<String, Object?> payload) async {
    final id = asString(payload['subscription_id']);
    if (id == null) return;
    try {
      await _api.delete('/v1/subscriptions/$id');
    } on StripeException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Getting paid (Connect)
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> payments(Account a) async {
    var row = (await _db.one(
      'SELECT stripe_account_id, stripe_account_ready FROM businesses '
      'WHERE id = @b',
      {'b': a.businessId},
    ))!;
    final account = row['stripe_account_id'] as String?;
    if (enabled && account != null && row['stripe_account_ready'] != true) {
      await syncAccount(account);
      row = (await _db.one(
        'SELECT stripe_account_id, stripe_account_ready FROM businesses '
        'WHERE id = @b',
        {'b': a.businessId},
      ))!;
    }
    return {
      'enabled': enabled,
      'connected': account != null,
      'ready': row['stripe_account_ready'],
      'fee': {
        'platform_bps': settings.platformFeeBps,
        'processing_bps': settings.processingFeeBps,
        'processing_cents': settings.processingFeeCents,
        'description': settings.feeDescription,
      },
    };
  }

  /// A Stripe-hosted onboarding link that sets up payouts.
  Future<Map<String, Object?>> connect(Account a) async {
    a.requireOwner();
    final api = _api;
    final row = (await _db.one(
      'SELECT stripe_account_id, profile FROM businesses WHERE id = @b',
      {'b': a.businessId},
    ))!;
    var account = row['stripe_account_id'] as String?;
    if (account == null) {
      final name = BusinessProfile.fromJson(row['profile']).name;
      final created = await _call(
        () => api.post('/v1/accounts', {
          'type': 'express',
          'country': settings.country,
          'email': a.email,
          'capabilities': {
            'card_payments': {'requested': true},
            'transfers': {'requested': true},
          },
          'business_profile': {
            if (name.isNotEmpty) 'name': name,
            'product_description': 'Home improvement and repair services',
          },
          'metadata': {'business_id': a.businessId},
        }, idempotencyKey: 'account-${a.businessId}'),
      );
      final stored = await _db.one(
        '''
        UPDATE businesses SET stripe_account_id = COALESCE(stripe_account_id, @a)
        WHERE id = @b RETURNING stripe_account_id''',
        {'a': created['id'], 'b': a.businessId},
      );
      account = stored!['stripe_account_id'] as String;
      _log({'event': 'connect_account_created', 'business': a.businessId});
    }
    return {'url': await onboardingLink(account)};
  }

  Future<String> onboardingLink(String account) async {
    final link = await _call(
      () => _api.post('/v1/account_links', {
        'account': account,
        'type': 'account_onboarding',
        'refresh_url': _url('/payments/refresh', {
          'account': account,
          'sig': refreshSignature(account),
        }),
        'return_url': _url('/payments/done'),
      }),
    );
    return link['url'] as String;
  }

  /// Onboarding links expire; Stripe then sends the contractor to our
  /// refresh page, which has no session. The signature proves the link
  /// came from us.
  String refreshSignature(String account) =>
      hmacHex(_linkSecret, 'connect-refresh:$account').substring(0, 32);

  bool validRefresh(String account, String sig) =>
      RegExp(r'^acct_[A-Za-z0-9]{6,40}$').hasMatch(account) &&
      constantTimeEquals(refreshSignature(account), sig);

  /// The Express dashboard, for payouts and refunds.
  Future<Map<String, Object?>> dashboard(Account a) async {
    a.requireOwner();
    final api = _api;
    final row = (await _db.one(
      'SELECT stripe_account_id, stripe_account_ready FROM businesses '
      'WHERE id = @b',
      {'b': a.businessId},
    ))!;
    final account = row['stripe_account_id'] as String?;
    if (account == null || row['stripe_account_ready'] != true) {
      throw ApiError(409, 'payments_not_ready', 'Finish payment setup first.');
    }
    final link = await _call(
      () => api.post('/v1/accounts/$account/login_links', const {}),
    );
    return {'url': link['url']};
  }

  Future<void> syncAccount(String account) async {
    final acct = await _call(() => _api.get('/v1/accounts/$account'));
    final ready =
        acct['charges_enabled'] == true && acct['details_submitted'] == true;
    await _db.execute(
      'UPDATE businesses SET stripe_account_ready = @r, '
      'updated_at = @now:timestamptz WHERE stripe_account_id = @a',
      {'r': ready, 'now': _clock(), 'a': account},
    );
  }

  // ---------------------------------------------------------------------------
  // Deposits
  // ---------------------------------------------------------------------------

  /// A Checkout page where the customer pays the approved option's
  /// deposit. The money goes to the contractor's account, minus the fee.
  Future<Uri> depositCheckout(String publicId) async {
    final api = _api;
    final view = await _quotes.open(publicId, countView: false);
    if (view == null) throw ApiError.notFound('No such quote.');
    final option = view.approvedOption;
    if (!view.canPayDeposit || option == null) {
      throw ApiError(
        409,
        'deposit_unavailable',
        view.depositPaid
            ? 'The deposit is already paid.'
            : 'Online payment is not available for this quote.',
      );
    }
    final account =
        (await _db.one(
              'SELECT stripe_account_id FROM businesses WHERE id = @b',
              {'b': view.businessId},
            ))?['stripe_account_id']
            as String?;
    if (account == null) throw ApiError.notFound('No such quote.');
    final amount = option.depositCents;
    final q = view.quote;
    final label = 'Deposit for Quote #${q.number}';
    final session = await _call(
      () => api.post('/v1/checkout/sessions', {
        'mode': 'payment',
        'submit_type': 'pay',
        'line_items': [
          {
            'quantity': 1,
            'price_data': {
              'currency': settings.currency,
              'unit_amount': amount,
              'product_data': {
                'name': label,
                'description': q.options.length > 1
                    ? '${q.business.name} · ${option.name}'
                    : q.business.name,
              },
            },
          },
        ],
        'payment_intent_data': {
          'application_fee_amount': settings.applicationFee(amount),
          'on_behalf_of': account,
          'transfer_data': {'destination': account},
          'description': '$label from ${q.business.name}',
          'metadata': {'public_id': publicId, 'revision': view.revision},
        },
        'metadata': {
          'kind': 'deposit',
          'public_id': publicId,
          'revision': view.revision,
        },
        'success_url': _url('/q/$publicId', {'done': 'deposit'}),
        'cancel_url': _url('/q/$publicId', {'preview': '1'}),
      }),
    );
    _log({'event': 'deposit_checkout', 'quote': publicId, 'cents': amount});
    return Uri.parse(session['url'] as String);
  }

  // ---------------------------------------------------------------------------
  // Webhooks
  // ---------------------------------------------------------------------------

  /// Verifies and applies a Stripe event. Safe to receive twice.
  Future<Map<String, Object?>> webhook(
    String payload,
    String? signature,
  ) async {
    _api;
    Map<String, Object?>? event;
    for (final secret in settings.webhookSecrets) {
      try {
        event = verifyStripeWebhook(payload, signature, secret, now: _clock());
        break;
      } on WebhookSignatureException {
        continue;
      }
    }
    if (event == null) {
      throw ApiError.badRequest('invalid_signature', 'Bad Stripe signature.');
    }
    final id = asString(event['id']) ?? '';
    final type = asString(event['type']) ?? '';
    final seen = await _db.one('SELECT 1 FROM stripe_events WHERE id = @id', {
      'id': id,
    });
    if (seen != null) return {'received': true, 'duplicate': true};

    final object = asMap(asMap(event['data'])['object']);
    switch (type) {
      case 'checkout.session.completed' ||
          'checkout.session.async_payment_succeeded':
        final metadata = asMap(object['metadata']);
        if (metadata['kind'] == 'deposit') {
          if (object['payment_status'] == 'paid') {
            await _quotes.depositPaid(
              asString(metadata['public_id']) ?? '',
              amountCents: asInt(object['amount_total']) ?? 0,
              paymentId:
                  asString(object['payment_intent']) ??
                  asString(object['id']) ??
                  '',
            );
          }
        } else if (object['mode'] == 'subscription') {
          final sub = asString(object['subscription']);
          if (sub != null) {
            await syncSubscription(
              sub,
              businessId: asString(object['client_reference_id']),
            );
          }
        }
      case 'customer.subscription.created' ||
          'customer.subscription.updated' ||
          'customer.subscription.deleted':
        final sub = asString(object['id']);
        if (sub != null) await syncSubscription(sub);
      case 'account.updated':
        final account = asString(object['id']);
        if (account != null) await syncAccount(account);
      default:
        break;
    }
    await _db.execute(
      'INSERT INTO stripe_events (id, type, received_at) '
      'VALUES (@id, @t, @now:timestamptz) ON CONFLICT (id) DO NOTHING',
      {'id': id, 't': type, 'now': _clock()},
    );
    _log({'event': 'stripe_webhook', 'type': type});
    return {'received': true};
  }

  /// Stripe errors become friendly API errors; its outages become 503s.
  Future<T> _call<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on StripeException catch (e) {
      _log({
        'event': 'stripe_error',
        'status': e.statusCode,
        'type': e.type,
        'code': e.code,
        'message': e.message,
      });
      if (e.retryable) {
        throw ApiError.unavailable(
          'payments_unavailable',
          'Payments are temporarily unavailable. Please try again.',
        );
      }
      throw ApiError(502, 'payments_error', e.message);
    }
  }
}
