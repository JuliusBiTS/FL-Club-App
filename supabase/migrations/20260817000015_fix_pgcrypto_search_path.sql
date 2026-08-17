-- Fix: found live, not by inspection — create-order failed with "function
-- gen_random_bytes(integer) does not exist" the first time it actually
-- ran against a real project. Hosted Supabase installs pgcrypto into an
-- `extensions` schema, not `public` (verified via pg_extension), so the
-- SECURITY DEFINER functions that generate order references and ticket
-- codes couldn't see gen_random_bytes() under their pinned
-- `search_path = public, pg_temp`. Adding `extensions` to the path is the
-- fix — pinning a search_path at all (rather than leaving it default) is
-- still the right call for SECURITY DEFINER functions, this just needed
-- one more schema in it.
alter function reserve_order_inventory(uuid, uuid, uuid, integer, boolean, text[], integer)
  set search_path = public, extensions, pg_temp;

alter function mark_order_paid(uuid, text, text, text)
  set search_path = public, extensions, pg_temp;
