-- Auto-creates a profiles row the moment someone signs up. Without this,
-- a new auth.users row would have no matching profiles row and every
-- signed-in feature (role checks, member_status, the You tab) would
-- silently see nothing for that user — found by testing sign-up
-- end-to-end against a real project, not by inspection, which is exactly
-- the kind of gap that's easy to miss reading the schema alone.
--
-- full_name is seeded from OAuth provider metadata when available (Google
-- sign-in populates raw_user_meta_data.full_name); email/password sign-up
-- leaves it null for the user to fill in later.
create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();
