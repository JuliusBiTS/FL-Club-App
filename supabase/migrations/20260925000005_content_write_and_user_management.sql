-- 1. Staff can add/edit/remove media, podcast episodes and articles by hand.
--
--    These tables had public READ policies only, so nothing but the sync
--    Edge Functions (service role) could write — which meant the admin
--    "add a video" button built last round could never have worked. Staff
--    (and admins, who count as staff) may now write. Hand-added rows can't
--    collide with the syncs: podcast rows use guid 'manual:<uuid>' and
--    articles leave wp_post_id null, and neither sync ever deletes.

create policy media_posts_staff_write on media_posts
  for all using (is_staff(auth.uid())) with check (is_staff(auth.uid()));

create policy podcast_episodes_staff_write on podcast_episodes
  for all using (is_staff(auth.uid())) with check (is_staff(auth.uid()));

create policy articles_staff_write on articles
  for all using (is_staff(auth.uid())) with check (is_staff(auth.uid()));

-- 2. Registration details captured at sign-up.
--
--    The app sends these as sign-up metadata, so they're saved even when
--    email confirmation means there's no session yet. Consent TIMES are set
--    here by the database, never trusted from the client.

create or replace function handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  v_terms boolean := coalesce((m ->> 'accepted_terms')::boolean, false);
  v_marketing boolean := coalesce((m ->> 'marketing_opt_in')::boolean, false);
begin
  insert into public.profiles (
    id, email, full_name, phone, marketing_opt_in, marketing_consent_at,
    terms_accepted_at, privacy_accepted_at, registration_source
  )
  values (
    new.id,
    new.email,
    nullif(left(trim(coalesce(m ->> 'full_name', '')), 200), ''),
    nullif(left(trim(coalesce(m ->> 'phone', '')), 30), ''),
    v_marketing,
    case when v_marketing then now() end,
    case when v_terms then now() end,
    case when v_terms then now() end,
    case when m ->> 'registration_source' in ('app', 'web') then m ->> 'registration_source' else 'app' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- 3. User management for admins: change a person's role and membership
--    details in one audited step. Promoting someone to staff/admin is the
--    most powerful thing an admin can do, so it lives in a function that
--    also refuses the two ways to lock the club out.

create or replace function admin_update_user(
  p_user_id uuid,
  p_role user_role,
  p_member_status member_status,
  p_membership_kind membership_kind default null,
  p_membership_number text default null,
  p_membership_expires_at timestamptz default null,
  p_notes text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_before profiles%rowtype;
begin
  if not is_admin(auth.uid()) then
    raise exception 'Admins only.';
  end if;

  select * into v_before from profiles where id = p_user_id for update;
  if not found then
    raise exception 'That person no longer exists.';
  end if;

  if v_before.role = 'admin' and p_role <> 'admin' then
    if p_user_id = auth.uid() then
      raise exception 'You can''t remove your own admin access — ask another admin.';
    end if;
    if (select count(*) from profiles where role = 'admin' and deleted_at is null) <= 1 then
      raise exception 'That would leave the club with no admin.';
    end if;
  end if;

  update profiles set
    role                  = p_role,
    member_status         = p_member_status,
    membership_kind       = p_membership_kind,
    membership_number     = nullif(trim(p_membership_number), ''),
    membership_expires_at = p_membership_expires_at,
    membership_notes      = nullif(trim(p_notes), ''),
    membership_started_at = case
                              when p_member_status = 'active' and membership_started_at is null then now()
                              else membership_started_at
                            end
  where id = p_user_id;

  insert into audit_log (actor_id, action, entity, entity_id, before, after)
  values (
    auth.uid(),
    case when v_before.role is distinct from p_role then 'role.change' else 'membership.update' end,
    'profiles',
    p_user_id,
    jsonb_build_object('role', v_before.role, 'member_status', v_before.member_status,
                       'membership_kind', v_before.membership_kind, 'membership_expires_at', v_before.membership_expires_at),
    jsonb_build_object('role', p_role, 'member_status', p_member_status,
                       'membership_kind', p_membership_kind, 'membership_expires_at', p_membership_expires_at)
  );
end;
$$;

grant execute on function admin_update_user(uuid, user_role, member_status, membership_kind, text, timestamptz, text) to authenticated;
