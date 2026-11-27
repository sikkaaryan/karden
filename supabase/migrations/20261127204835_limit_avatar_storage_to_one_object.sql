-- One replaceable avatar object per guest account; no unbounded uploads.
drop policy if exists karden_avatar_upload_own_folder on storage.objects;
create policy karden_avatar_upload_own_folder on storage.objects
for insert to authenticated
with check (
  bucket_id='karden-avatars'
  and name=auth.uid()::text || '/avatar'
);

drop policy if exists karden_avatar_update_own_folder on storage.objects;
create policy karden_avatar_update_own_folder on storage.objects
for update to authenticated
using (
  bucket_id='karden-avatars'
  and name=auth.uid()::text || '/avatar'
)
with check (
  bucket_id='karden-avatars'
  and name=auth.uid()::text || '/avatar'
);
