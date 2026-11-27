-- KARDEN player avatar uploads. Public reads are restricted to the dedicated avatar bucket;
-- uploads are authenticated and confined to the uploader's own UUID folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('karden-avatars', 'karden-avatars', true, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists karden_avatar_public_read on storage.objects;
create policy karden_avatar_public_read on storage.objects
for select to public
using (bucket_id = 'karden-avatars');

drop policy if exists karden_avatar_upload_own_folder on storage.objects;
create policy karden_avatar_upload_own_folder on storage.objects
for insert to authenticated
with check (
  bucket_id = 'karden-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);
