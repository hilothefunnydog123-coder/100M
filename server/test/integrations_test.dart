import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_server/src/integrations/email.dart';
import 'package:jobwalk_server/src/integrations/stripe.dart';
import 'package:test/test.dart';

void main() {
  group('Stripe form encoding', () {
    test('flattens nested maps and lists', () {
      final form = encodeStripeForm({
        'mode': 'payment',
        'line_items': [
          {
            'price_data': {
              'currency': 'usd',
              'unit_amount': 31100,
              'product_data': {'name': 'Deposit for Quote #1042'},
            },
            'quantity': 1,
          },
        ],
        'metadata': {'public_id': 'abc'},
        'skip': null,
      });
      expect(Uri.splitQueryString(form), {
        'mode': 'payment',
        'line_items[0][price_data][currency]': 'usd',
        'line_items[0][price_data][unit_amount]': '31100',
        'line_items[0][price_data][product_data][name]':
            'Deposit for Quote #1042',
        'line_items[0][quantity]': '1',
        'metadata[public_id]': 'abc',
      });
    });
  });

  group('Stripe client', () {
    test('sends auth, version, account, and idempotency headers', () async {
      late http.Request seen;
      final client = StripeClient(
        secretKey: 'sk_test_123',
        client: MockClient((r) async {
          seen = r;
          return http.Response('{"id":"cs_1","url":"https://checkout"}', 200);
        }),
      );
      final r = await client.post(
        '/v1/checkout/sessions',
        {'mode': 'payment'},
        idempotencyKey: 'dep_abc',
        account: 'acct_1',
      );
      expect(r['id'], 'cs_1');
      expect(seen.headers['authorization'], 'Bearer sk_test_123');
      expect(seen.headers['stripe-version'], StripeClient.apiVersion);
      expect(seen.headers['Stripe-Account'], 'acct_1');
      expect(seen.headers['Idempotency-Key'], 'dep_abc');
      expect(seen.body, 'mode=payment');
    });

    test('errors carry the Stripe message and retry hint', () async {
      final client = StripeClient(
        secretKey: 'sk',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'type': 'invalid_request_error',
                'message': 'No such price',
                'code': 'resource_missing',
              },
            }),
            400,
          ),
        ),
      );
      await expectLater(
        client.get('/v1/prices/nope'),
        throwsA(
          isA<StripeException>()
              .having((e) => e.message, 'message', 'No such price')
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
      final busy = StripeClient(
        secretKey: 'sk',
        client: MockClient((_) async => http.Response('oops', 503)),
      );
      await expectLater(
        busy.get('/v1/x'),
        throwsA(isA<StripeException>().having((e) => e.retryable, 'r', isTrue)),
      );
    });
  });

  group('Stripe webhooks', () {
    const secret = 'whsec_test';
    final now = DateTime.utc(2026, 9, 25, 15);
    const payload = '{"id":"evt_1","type":"account.updated"}';

    test('accepts a valid signature', () {
      final header = signStripePayload(payload, secret, now);
      final event = verifyStripeWebhook(payload, header, secret, now: now);
      expect(event['id'], 'evt_1');
    });

    test('rejects tampering, wrong secrets, and replays', () {
      final header = signStripePayload(payload, secret, now);
      expect(
        () => verifyStripeWebhook('$payload ', header, secret, now: now),
        throwsA(isA<WebhookSignatureException>()),
      );
      expect(
        () => verifyStripeWebhook(payload, header, 'whsec_other', now: now),
        throwsA(isA<WebhookSignatureException>()),
      );
      expect(
        () => verifyStripeWebhook(
          payload,
          header,
          secret,
          now: now.add(const Duration(minutes: 6)),
        ),
        throwsA(isA<WebhookSignatureException>()),
      );
      for (final bad in [null, '', 't=abc', 'v1=abc']) {
        expect(
          () => verifyStripeWebhook(payload, bad, secret, now: now),
          throwsA(isA<WebhookSignatureException>()),
        );
      }
    });

    test('accepts any of several v1 signatures (secret rotation)', () {
      final good = signStripePayload(payload, secret, now);
      final t = good.split(',').first;
      final v1 = good.split(',').last;
      final header = '$t,v1=${'0' * 64},$v1';
      expect(
        verifyStripeWebhook(payload, header, secret, now: now)['id'],
        'evt_1',
      );
    });
  });

  group('email', () {
    const templates = EmailTemplates(appUrl: 'https://jobwalk.app');

    test('sign-in code', () {
      final e = templates.signInCode('mike@example.com', '123456');
      expect(e.subject, 'Your Jobwalk code: 123456');
      expect(e.text, contains('expires in 10 minutes'));
      expect(e.html, contains('123456'));
    });

    test('quote events escape customer names in HTML', () {
      final e = templates.quoteEvent(
        'owner@example.com',
        kind: 'approved',
        quoteLabel: 'Quote #1042',
        customer: '<b>Dana</b>',
        url: 'https://jobwalk.app/q/abc',
        detail: r'Full room, $1,410.',
      );
      expect(e.subject, '<b>Dana</b> approved Quote #1042');
      expect(e.text, contains(r'Full room, $1,410.'));
      expect(e.html, isNot(contains('<b>Dana</b>')));
      expect(e.html, contains('&lt;b&gt;Dana&lt;/b&gt;'));
      expect(
        () => templates.quoteEvent(
          'a@b.co',
          kind: 'nope',
          quoteLabel: 'Q',
          customer: '',
          url: '',
        ),
        throwsArgumentError,
      );
    });

    test('Resend sender posts JSON and classifies failures', () async {
      late http.Request seen;
      var status = 200;
      final sender = ResendEmailSender(
        apiKey: 're_123',
        from: 'Jobwalk <quotes@jobwalk.app>',
        client: MockClient((r) async {
          seen = r;
          return http.Response('{"id":"e_1"}', status);
        }),
      );
      await sender.send(
        const OutgoingEmail(to: 'a@b.co', subject: 'Hi', text: 'Hello'),
      );
      expect(seen.headers['authorization'], 'Bearer re_123');
      final body = jsonDecode(seen.body) as Map;
      expect(body['to'], ['a@b.co']);
      expect(body['from'], 'Jobwalk <quotes@jobwalk.app>');

      status = 422;
      await expectLater(
        sender.send(const OutgoingEmail(to: 'x', subject: 's', text: 't')),
        throwsA(isA<EmailException>().having((e) => e.retryable, 'r', isFalse)),
      );
      status = 503;
      await expectLater(
        sender.send(const OutgoingEmail(to: 'x', subject: 's', text: 't')),
        throwsA(isA<EmailException>().having((e) => e.retryable, 'r', isTrue)),
      );
    });

    test('emails survive a job payload round trip', () {
      final e = templates.signInCode('a@b.co', '000111');
      final back = OutgoingEmail.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>,
      );
      expect(back.toJson(), e.toJson());
    });
  });
}
