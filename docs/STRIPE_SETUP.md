# Connecting Stripe

Everything checkout needs is already built and deployed — `create-order`,
`stripe-webhook`, `refund-order` are live on the Supabase project, and the
Flutter app's full 4-step checkout flow (review → account → payment →
confirmation) is wired up and waiting on two secrets and one webhook
registration. Nothing here requires touching code again.

## 1. Get Stripe API keys

1. Sign in to (or create) the club's Stripe account at
   [dashboard.stripe.com](https://dashboard.stripe.com).
2. [CONFIRM] first whether the club's existing WooCommerce/Stripe account
   (already installed on the website) can be reused — see
   `docs/OPEN_QUESTIONS.md`. Reusing it means one less set of keys to
   manage and keeps the club's payment history in one place.
3. While in test mode (toggle top-right), go to **Developers → API keys**
   and copy:
   - **Publishable key** (`pk_test_...`)
   - **Secret key** (`sk_test_...`) — keep this one out of chat, git, and
     anywhere else it could leak.
4. Apply for **Stripe's nonprofit/charity pricing** while you're in
   there (Settings → search "nonprofit") — the club qualifies and it
   lowers the per-transaction fee further (briefing §3).

## 2. Set the two Edge Function secrets

From the `supabase/` directory:

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_test_...
```

(The webhook secret comes from step 3 below — set it after creating the
endpoint, since Stripe only reveals it once the endpoint exists.)

## 3. Register the webhook endpoint

1. Stripe dashboard → **Developers → Webhooks → Add endpoint**.
2. Endpoint URL:
   `https://rpkvvkqonjrjugjpgdtn.supabase.co/functions/v1/stripe-webhook`
3. Select these events (exactly what `stripe-webhook`'s code handles —
   see `supabase/functions/stripe-webhook/index.ts`):
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `payment_intent.canceled`
   - `charge.refunded`
4. Save, then click into the new endpoint and reveal its **Signing
   secret** (`whsec_...`).
5. Set it:
   ```bash
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
   ```

## 4. Run the app with the publishable key

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://rpkvvkqonjrjugjpgdtn.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...
```

Without `STRIPE_PUBLISHABLE_KEY`, the payment step shows a plain "Payments
aren't configured yet" message instead of crashing (`lib/features/checkout/presentation/payment_step.dart`)
— that's what you'll see until this step.

## 5. Test it

Use Stripe's test card `4242 4242 4242 4242`, any future expiry, any CVC.
Buy a ticket to one of the seeded demo events end to end and confirm:

- The order appears in the admin console's **Orders** section as `paid`
- A ticket row exists (`select * from tickets where order_id = ...`)
- The **Refund** button in the admin console actually refunds it via
  Stripe and flips the order to `refunded`

## 6. (Optional but recommended) Let the pg_cron jobs run

`expire-pending-orders` and the other scheduled Edge Functions
(`eventbrite-sync`, `podcast-sync`, `wordpress-sync`, `purge-deleted-accounts`)
are already scheduled via `pg_cron`, but need two secrets in **Supabase
Vault** (not the same as the Edge Function secrets above) before they can
actually call themselves. In the Supabase SQL Editor, run:

```sql
select vault.create_secret('https://rpkvvkqonjrjugjpgdtn.supabase.co', 'project_url');
select vault.create_secret('<service_role_key>', 'service_role_key');
```

Find the service role key at **Project Settings → API Keys → Secret
keys**. This step was deliberately left for you to do by hand — an
automated attempt to fetch and store it was (correctly) blocked as
handling of a live secret credential.

Until this is done, abandoned checkouts won't automatically release their
15-minute inventory hold — harmless at low volume, but do this before
real events go on sale.
