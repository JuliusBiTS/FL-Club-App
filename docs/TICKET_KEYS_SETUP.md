# Setting the ticket/membership signing keys

`get-my-tickets`, `get-scan-pack`, `verify-scan`, `get-member-card` and
`membership-apply` are all deployed, but every one of them derives its
signing keys from two Edge Function secrets that were never set on the
project: `MASTER_TICKET_KEY` and `MASTER_MEMBER_KEY`. Until these exist,
every one of those functions returns a 500 (`requireEnv` throws). Nothing
else needs to change — this is the only remaining step for M4 to work
end to end, the same way `docs/STRIPE_SETUP.md` was the only remaining
step for M3.

These are **not** club credentials — they're random signing keys the app
invents for itself, so unlike Stripe there's nothing to "get" from anyone.
Generating them was attempted automatically during this build but blocked
by the safety classifier (any action that sets a live secret gets flagged,
even a self-generated one) — so this is a manual step by design, not a
missing feature.

## 1. Generate two keys

```bash
openssl rand -base64 32   # MASTER_TICKET_KEY
openssl rand -base64 32   # MASTER_MEMBER_KEY
```

Run it twice — don't reuse one value for both. Each output is a 32-byte
key, base64-encoded (standard alphabet, not base64url — matches what
`supabase/functions/_shared/ticket-crypto.ts`'s `base64Decode` expects).

## 2. Set them as Edge Function secrets

From the `supabase/` directory:

```bash
supabase secrets set MASTER_TICKET_KEY="<first output>" MASTER_MEMBER_KEY="<second output>"
```

## 3. Why this matters if it's ever lost or rotated

Every ticket QR and membership card QR in circulation is signed with a key
derived from these two values (see the HKDF scheme documented at the top
of `ticket-crypto.ts`). Rotating either key invalidates every ticket and
membership card currently displayable offline — anyone with an
already-cached secret can no longer produce a signature the server (or an
offline scanner holding an `event_scan_key` from before the rotation)
still accepts. Set them once, back them up somewhere safe (a password
manager, not git), and treat a rotation as equivalent to reissuing every
ticket and card in the club.

## 4. Test it

Once set, `get-my-tickets` and `get-member-card` stop 500ing. See M4's
verification notes for the exact steps used to confirm the QR wallet
renders and rotates correctly.
