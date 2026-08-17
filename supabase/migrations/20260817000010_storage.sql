-- Storage buckets. Member photos are the most sensitive data in the system
-- (§13.6): private bucket, no public URLs ever, no direct client read
-- policy at all — every read goes through a 15-minute signed URL minted by
-- an Edge Function that checks the caller is either the photo's owner or
-- staff performing an active scan.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('event-images',       'event-images',       true,  10485760, array['image/jpeg', 'image/png', 'image/webp']),
  ('membership-photos',  'membership-photos',  false,  5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- storage.objects already has RLS enabled by the platform on hosted
-- Supabase (the migration role doesn't own the table to re-enable it
-- itself, which is why there's no `alter table ... enable row level
-- security` here) — we only ever need to add policies to it.

-- event-images: hero images, speaker photos, gallery — public content, admin-managed.
create policy event_images_public_read on storage.objects
  for select using (bucket_id = 'event-images');

create policy event_images_admin_insert on storage.objects
  for insert with check (bucket_id = 'event-images' and is_admin(auth.uid()));

create policy event_images_admin_update on storage.objects
  for update using (bucket_id = 'event-images' and is_admin(auth.uid()));

create policy event_images_admin_delete on storage.objects
  for delete using (bucket_id = 'event-images' and is_admin(auth.uid()));

-- membership-photos: deliberately NO select policy for any client role.
-- Owners and staff read via signed URL from an Edge Function, never
-- directly. Uploads/replacements go through an Edge Function too (so EXIF
-- can be stripped and the image re-encoded to a fixed 512x512 JPEG
-- server-side), but admin-direct is left available for the console.
create policy membership_photos_admin_insert on storage.objects
  for insert with check (bucket_id = 'membership-photos' and is_admin(auth.uid()));

create policy membership_photos_admin_update on storage.objects
  for update using (bucket_id = 'membership-photos' and is_admin(auth.uid()));

create policy membership_photos_admin_delete on storage.objects
  for delete using (bucket_id = 'membership-photos' and is_admin(auth.uid()));
