import 'database.dart';

/// Schema changes, applied in order and recorded in `schema_migrations`.
/// Never edit a migration that has shipped; add a new one.
const migrations = <(int, String, String)>[(1, 'initial schema', _v1)];

/// Arbitrary constant for `pg_advisory_lock`, so only one instance migrates
/// at a time when several start together.
const _lockKey = 727274001;

/// Applies pending migrations. Returns the versions applied.
Future<List<int>> migrate(Db db) => db.withConnection((conn) async {
  await conn.execute('SELECT pg_advisory_lock($_lockKey)');
  try {
    await conn.script('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version integer PRIMARY KEY,
        name text NOT NULL,
        applied_at timestamptz NOT NULL DEFAULT now()
      )''');
    final applied = {
      for (final r in await conn.query('SELECT version FROM schema_migrations'))
        r['version'] as int,
    };
    final done = <int>[];
    for (final (version, name, sql) in migrations) {
      if (applied.contains(version)) continue;
      await conn.tx((tx) async {
        await tx.script(sql);
        await tx.execute(
          'INSERT INTO schema_migrations (version, name) VALUES (@v:int4, @n)',
          {'v': version, 'n': name},
        );
      });
      done.add(version);
    }
    return done;
  } finally {
    await conn.execute('SELECT pg_advisory_unlock($_lockKey)');
  }
});

/// The newest schema version this build knows about.
int get latestSchemaVersion => migrations.last.$1;

const _v1 = '''
CREATE TABLE businesses (
  id text PRIMARY KEY,
  profile jsonb NOT NULL DEFAULT '{}',
  rates jsonb NOT NULL DEFAULT '{}',
  next_quote_number integer NOT NULL DEFAULT 1001,
  plan text NOT NULL DEFAULT 'trial' CHECK (plan IN ('trial', 'pro', 'crew')),
  plan_status text NOT NULL DEFAULT 'trialing',
  trial_drafts_used integer NOT NULL DEFAULT 0,
  stripe_customer_id text UNIQUE,
  stripe_subscription_id text UNIQUE,
  stripe_account_id text UNIQUE,
  stripe_account_ready boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id text PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses (id) ON DELETE CASCADE,
  email text NOT NULL,
  name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'owner' CHECK (role IN ('owner', 'member')),
  email_notifications boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz
);
CREATE UNIQUE INDEX users_email_key ON users (lower(email));
CREATE INDEX users_business_idx ON users (business_id);

CREATE TABLE sign_in_codes (
  email text PRIMARY KEY,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sessions (
  token_hash text PRIMARY KEY,
  user_id text NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  device text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX sessions_user_idx ON sessions (user_id);
CREATE INDEX sessions_expiry_idx ON sessions (expires_at);

-- Sync cursor: every quote write takes the next value.
CREATE SEQUENCE sync_seq;

-- Quote ids are made on the phone, so they are unique per business.
CREATE TABLE quotes (
  business_id text NOT NULL REFERENCES businesses (id) ON DELETE CASCADE,
  id text NOT NULL,
  number integer NOT NULL,
  status text NOT NULL,
  data jsonb NOT NULL,
  version integer NOT NULL DEFAULT 1,
  deleted boolean NOT NULL DEFAULT false,
  seq bigint NOT NULL DEFAULT nextval('sync_seq'),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, id)
);
CREATE INDEX quotes_sync_idx ON quotes (business_id, seq);

-- What the customer sees at /q/<public_id>, and what they did with it.
CREATE TABLE publications (
  public_id text PRIMARY KEY,
  business_id text NOT NULL,
  quote_id text NOT NULL,
  published_by text,
  revision integer NOT NULL DEFAULT 1,
  content jsonb NOT NULL,
  content_hash text NOT NULL,
  response jsonb NOT NULL DEFAULT '{}',
  sent_at timestamptz NOT NULL,
  deposit_status text NOT NULL DEFAULT 'none'
    CHECK (deposit_status IN ('none', 'paid')),
  deposit_paid_cents integer,
  deposit_paid_at timestamptz,
  deposit_payment_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_id, quote_id),
  FOREIGN KEY (business_id, quote_id) REFERENCES quotes (business_id, id)
    ON DELETE CASCADE
);

-- Activity feed and e-signature audit trail. Append-only.
CREATE TABLE quote_events (
  id bigserial PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses (id) ON DELETE CASCADE,
  quote_id text NOT NULL,
  public_id text,
  kind text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX quote_events_business_idx ON quote_events (business_id, id);
CREATE INDEX quote_events_quote_idx ON quote_events (business_id, quote_id, id);

-- Photo ids are made on the phone too.
CREATE TABLE photos (
  business_id text NOT NULL REFERENCES businesses (id) ON DELETE CASCADE,
  id text NOT NULL,
  object_key text NOT NULL,
  content_type text NOT NULL,
  bytes integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, id)
);

-- AI drafts: usage metering, cost, and idempotent retries.
CREATE TABLE drafts (
  id bigserial PRIMARY KEY,
  business_id text NOT NULL REFERENCES businesses (id) ON DELETE CASCADE,
  user_id text,
  idempotency_key text,
  state text NOT NULL DEFAULT 'running'
    CHECK (state IN ('running', 'done', 'failed')),
  response jsonb,
  photos integer NOT NULL DEFAULT 0,
  usable boolean,
  model text NOT NULL DEFAULT '',
  input_tokens integer NOT NULL DEFAULT 0,
  output_tokens integer NOT NULL DEFAULT 0,
  cost_micros bigint NOT NULL DEFAULT 0,
  latency_ms integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
CREATE UNIQUE INDEX drafts_idempotency_idx
  ON drafts (business_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX drafts_business_idx ON drafts (business_id, created_at);

-- Background work: emails, reminders, cleanup.
CREATE TABLE jobs (
  id bigserial PRIMARY KEY,
  kind text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}',
  run_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 6,
  locked_until timestamptz,
  last_error text,
  done_at timestamptz,
  failed boolean NOT NULL DEFAULT false,
  dedupe_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX jobs_due_idx ON jobs (run_at) WHERE done_at IS NULL;
CREATE UNIQUE INDEX jobs_dedupe_idx ON jobs (dedupe_key)
  WHERE dedupe_key IS NOT NULL AND done_at IS NULL;

CREATE TABLE waitlist (
  email text PRIMARY KEY,
  trade text NOT NULL DEFAULT '',
  crew text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Token buckets shared by every instance.
CREATE TABLE rate_limits (
  key text PRIMARY KEY,
  tokens double precision NOT NULL,
  updated_at timestamptz NOT NULL
);

-- Stripe webhook deliveries already handled (Stripe retries).
CREATE TABLE stripe_events (
  id text PRIMARY KEY,
  type text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);
''';
