import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'quotes_test.dart' show approve;
import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    late SignIn dana;
    setUp(() async {
      h = Harness(testDb());
      dana = await h.owner('dana@example.com');
    });

    Future<Map<String, Object?>> business() async =>
        (await h.accounts.me(dana.account))['business']!
            as Map<String, Object?>;

    group('subscriptions', () {
      test('checkout creates the customer once and opens Stripe', () async {
        final first = await h.app.billing.checkout(dana.account, 'pro');
        expect(first['url'], startsWith('https://checkout.stripe.com/'));
        await h.app.billing.checkout(dana.account, 'crew');
        expect(h.stripe.posted('/v1/customers'), hasLength(1));
        final customer = h.stripe.posted('/v1/customers').single;
        expect(customer['email'], 'dana@example.com');
        expect(customer['name'], 'Brightline Painting');

        final sessions = h.stripe.posted('/v1/checkout/sessions');
        expect(sessions.first['mode'], 'subscription');
        expect(sessions.first['line_items[0][price]'], 'price_pro');
        expect(sessions.last['line_items[0][price]'], 'price_crew');
        expect(sessions.first['client_reference_id'], dana.account.businessId);
        expect(
          sessions.first['success_url'],
          'https://jobwalk.test/billing/done?session_id={CHECKOUT_SESSION_ID}',
        );
        final idempotency = h.stripe.requests.first;
        expect(idempotency.path, '/v1/customers');
      });

      test('only owners pay, for real plans', () async {
        await h.accounts.addMember(dana.account, {'email': 'lee@example.com'});
        final lee = await h.signIn('lee@example.com');
        expect(
          (await apiError(
            () => h.app.billing.checkout(lee.account, 'pro'),
          )).status,
          403,
        );
        expect(
          (await apiError(
            () => h.app.billing.checkout(dana.account, 'gold'),
          )).code,
          'invalid_plan',
        );
      });

      test('webhooks apply the subscription as Stripe reports it', () async {
        await h.app.billing.checkout(dana.account, 'pro');
        final customer =
            (await h.db.one(
                  'SELECT stripe_customer_id FROM businesses',
                ))!['stripe_customer_id']
                as String;
        h.stripe.addSubscription('sub_1', customer: customer);

        final r = await h.stripeEvent('checkout.session.completed', {
          'id': 'cs_1',
          'mode': 'subscription',
          'subscription': 'sub_1',
          'client_reference_id': dana.account.businessId,
        });
        expect(r.statusCode, 200);
        var plan = (await business())['plan']! as Map;
        expect(plan['id'], 'pro');
        expect(plan['status'], 'active');
        expect(plan['paid'], isTrue);
        expect(plan['trial_drafts_left'], isNull);

        // Upgrading to Crew in the portal.
        h.stripe.addSubscription(
          'sub_1',
          customer: customer,
          price: 'price_crew',
        );
        await h.stripeEvent('customer.subscription.updated', {'id': 'sub_1'});
        plan = (await business())['plan']! as Map;
        expect(plan['id'], 'crew');
        expect(plan['max_users'], 15);

        // A second checkout is refused while subscribed.
        expect(
          (await apiError(
            () => h.app.billing.checkout(dana.account, 'pro'),
          )).code,
          'already_subscribed',
        );
        expect(
          (await h.app.billing.portal(dana.account))['url'],
          startsWith('https://billing.stripe.com/'),
        );

        // Canceling drops back to the trial's limits.
        h.stripe.addSubscription(
          'sub_1',
          customer: customer,
          status: 'canceled',
        );
        await h.stripeEvent('customer.subscription.deleted', {'id': 'sub_1'});
        plan = (await business())['plan']! as Map;
        expect(plan['paid'], isFalse);
        expect(plan['max_users'], 3);
      });

      test('a late event about an old subscription is ignored', () async {
        await h.app.billing.checkout(dana.account, 'pro');
        final customer =
            (await h.db.one(
                  'SELECT stripe_customer_id FROM businesses',
                ))!['stripe_customer_id']
                as String;
        h.stripe
          ..addSubscription('sub_old', customer: customer, status: 'canceled')
          ..addSubscription('sub_new', customer: customer);
        await h.stripeEvent('customer.subscription.created', {'id': 'sub_new'});
        await h.stripeEvent('customer.subscription.deleted', {'id': 'sub_old'});
        final plan = (await business())['plan']! as Map;
        expect(plan['status'], 'active');
      });

      test('bad signatures are refused; repeats are ignored', () async {
        final bad = await h.stripeEvent('customer.subscription.updated', {
          'id': 'sub_x',
        }, secret: 'whsec_wrong');
        expect(bad.statusCode, 400);
        expect(
          (await jsonOf(bad))['error'],
          containsPair('code', 'invalid_signature'),
        );

        final one = await h.stripeEvent('invoice.paid', {}, id: 'evt_same');
        final two = await h.stripeEvent('invoice.paid', {}, id: 'evt_same');
        expect(await jsonOf(one), {'received': true});
        expect(await jsonOf(two), {'received': true, 'duplicate': true});
      });

      test('Stripe outages become retryable errors', () async {
        final e = await apiError(
          () => h.app.billing.syncSubscription('sub_missing'),
        );
        expect(e.status, 502);
      });

      test('deleting the account cancels the subscription', () async {
        h.stripe.addSubscription('sub_9', customer: 'cus_9');
        await h.db.execute(
          "UPDATE businesses SET stripe_subscription_id = 'sub_9'",
        );
        await h.accounts.deleteAccount(dana.account, confirm: 'DELETE');
        await h.runJobs();
        expect(h.stripe.subscriptions['sub_9']!['status'], 'canceled');
        expect(
          h.stripe.requests.any(
            (r) => r.method == 'DELETE' && r.path == '/v1/subscriptions/sub_9',
          ),
          isTrue,
        );
      });

      test('billing is off without Stripe', () async {
        final off = Harness(testDb(), config: testConfig(stripe: false));
        final owner = await off.owner('kim@example.com');
        final e = await apiError(
          () => off.app.billing.checkout(owner.account, 'pro'),
        );
        expect(e.status, 503);
        expect(e.code, 'billing_unavailable');
        expect(
          (await off.app.billing.payments(owner.account))['enabled'],
          isFalse,
        );
      });
    });

    group('payouts and deposits', () {
      Future<String> onboard() async {
        final link = await h.app.billing.connect(dana.account);
        expect(link['url'], startsWith('https://connect.stripe.com/setup/'));
        final account =
            (await h.db.one(
                  'SELECT stripe_account_id FROM businesses',
                ))!['stripe_account_id']
                as String;
        h.stripe.accounts[account]!
          ..['charges_enabled'] = true
          ..['details_submitted'] = true;
        await h.stripeEvent('account.updated', {'id': account});
        return account;
      }

      test('onboarding creates one Express account', () async {
        await h.app.billing.connect(dana.account);
        await h.app.billing.connect(dana.account);
        final created = h.stripe.posted('/v1/accounts');
        expect(created, hasLength(1));
        expect(created.single['type'], 'express');
        expect(created.single['capabilities[transfers][requested]'], 'true');
        final link = h.stripe.posted('/v1/account_links').last;
        expect(link['return_url'], 'https://jobwalk.test/payments/done');
        expect(
          link['refresh_url'],
          startsWith('https://jobwalk.test/payments/refresh?account=acct_'),
        );
        var payments = await h.app.billing.payments(dana.account);
        expect(payments['connected'], isTrue);
        expect(payments['ready'], isFalse);
        expect(
          (payments['fee']! as Map)['description'],
          '3.9% + 30¢ per deposit',
        );

        final account = created.isEmpty
            ? ''
            : (await h.db.one(
                    'SELECT stripe_account_id FROM businesses',
                  ))!['stripe_account_id']
                  as String;
        h.stripe.accounts[account]!
          ..['charges_enabled'] = true
          ..['details_submitted'] = true;
        // Opening payments settings refreshes a pending account.
        payments = await h.app.billing.payments(dana.account);
        expect(payments['ready'], isTrue);
        expect(
          (await h.app.billing.dashboard(dana.account))['url'],
          'https://connect.stripe.com/express/$account',
        );
      });

      test(
        'expired onboarding links refresh only with our signature',
        () async {
          await h.app.billing.connect(dana.account);
          final refresh = Uri.parse(
            h.stripe.posted('/v1/account_links').last['refresh_url']!,
          );
          final ok = await h.send('GET', '${refresh.path}?${refresh.query}');
          expect(ok.statusCode, 303);
          expect(
            ok.headers['location'],
            startsWith('https://connect.stripe.com'),
          );
          final account = refresh.queryParameters['account']!;
          final forged = await h.send(
            'GET',
            '/payments/refresh?account=$account&sig=${'0' * 32}',
          );
          expect(forged.statusCode, 404);
        },
      );

      test('customers pay the approved deposit by card', () async {
        final account = await onboard();
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);

        var view = await h.quotes.open(publicId, countView: false);
        expect(view!.onlineDeposit, isTrue);
        expect(view.canPayDeposit, isFalse, reason: 'approve first');
        await approve(h, publicId, option: 'walls_trim');
        view = await h.quotes.open(publicId, countView: false);
        expect(view!.canPayDeposit, isTrue);

        final url = await h.app.billing.depositCheckout(publicId);
        expect(url.host, 'checkout.stripe.com');
        final session = h.stripe.posted('/v1/checkout/sessions').last;
        // Walls + trim: $1,245 total, 25% deposit = $311.25 -> $311.
        final deposit = view.approvedOption!.depositCents;
        expect(session['mode'], 'payment');
        expect(session['line_items[0][price_data][unit_amount]'], '$deposit');
        expect(
          session['payment_intent_data[transfer_data][destination]'],
          account,
        );
        expect(session['payment_intent_data[on_behalf_of]'], account);
        expect(
          session['payment_intent_data[application_fee_amount]'],
          '${(deposit * 0.039).round() + 30}',
        );
        expect(session['metadata[public_id]'], publicId);

        await h.runJobs();
        h.emails.sent.clear();
        await h.stripeEvent('checkout.session.completed', {
          'id': 'cs_dep',
          'mode': 'payment',
          'payment_status': 'paid',
          'amount_total': deposit,
          'payment_intent': 'pi_1',
          'metadata': {'kind': 'deposit', 'public_id': publicId},
        });
        view = await h.quotes.open(publicId, countView: false);
        expect(view!.depositPaid, isTrue);
        expect(view.depositPaidCents, deposit);
        expect(view.canPayDeposit, isFalse);
        final synced = await h.quotes.get(dana.account, q.id);
        expect(synced['deposit'], containsPair('status', 'paid'));
        await h.runJobs();
        expect(
          h.emails.sent.single.subject,
          'Deposit received for Quote #1042',
        );

        // The page now says so.
        final page = await (await h.send(
          'GET',
          '/q/$publicId?preview=1',
        )).readAsString();
        expect(page, contains('paid'));
        expect(page, isNot(contains('deposit by card')));

        // The same payment again changes nothing; a second payment warns.
        await h.stripeEvent('checkout.session.completed', {
          'id': 'cs_dep',
          'mode': 'payment',
          'payment_status': 'paid',
          'amount_total': deposit,
          'payment_intent': 'pi_1',
          'metadata': {'kind': 'deposit', 'public_id': publicId},
        });
        await h.stripeEvent('checkout.session.completed', {
          'id': 'cs_dep2',
          'mode': 'payment',
          'payment_status': 'paid',
          'amount_total': deposit,
          'payment_intent': 'pi_2',
          'metadata': {'kind': 'deposit', 'public_id': publicId},
        });
        final kinds = [
          for (final e in await h.db.query(
            "SELECT kind FROM quote_events WHERE kind LIKE 'deposit%' "
            'ORDER BY id',
          ))
            e['kind'],
        ];
        expect(kinds, ['deposit_paid', 'deposit_duplicate']);
        expect(
          (await apiError(() => h.app.billing.depositCheckout(publicId))).code,
          'deposit_unavailable',
        );
      });

      test('no card deposits until payouts are ready', () async {
        await h.app.billing.connect(dana.account);
        final publicId = await h.sendQuote(dana.account, h.sampleQuote());
        await approve(h, publicId, option: 'walls');
        final view = await h.quotes.open(publicId, countView: false);
        expect(view!.canPayDeposit, isFalse);
        final page = await (await h.send(
          'GET',
          '/q/$publicId?preview=1',
        )).readAsString();
        expect(page, isNot(contains('deposit by card')));
      });
    });

    test('fees', () {
      const s = BillingSettings();
      expect(s.applicationFee(31100), 1243);
      expect(s.applicationFee(10), 10, reason: 'never more than the charge');
      expect(
        const BillingSettings(processingFeeCents: 0).feeDescription,
        '3.9% per deposit',
      );
      expect(
        const BillingSettings(platformFeeBps: 110).feeDescription,
        '4% + 30¢ per deposit',
      );
    });
  });
}
