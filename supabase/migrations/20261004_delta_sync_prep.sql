-- Delta-sync groundwork, step 1: indexes and change timestamps.
--
-- The app reads `select('*, history_entries(*)')` — every document joined to
-- every history row — which is what depleted the project's Disk IO budget.
-- This migration makes two things possible:
--
--   1. The join stops scanning. Without an index on history_entries
--      (document_code) Postgres scans the whole history table for each of the
--      ~291 documents on every read. This is the change most likely to fix the
--      IO problem on its own.
--
--   2. A later release can ask "what changed since I last looked" instead of
--      reading everything. Nothing reads updated_at yet; adding it now means
--      the column is already populated and accurate when that ships.
--
-- Safe to run on a live database: it adds columns with defaults, adds indexes,
-- and changes no existing values. No application change is required, and the
-- current app keeps working unchanged whether or not this has been applied.

-- ---------------------------------------------------------------- indexes --

-- The join behind every document fetch.
create index if not exists history_entries_document_code_idx
  on history_entries (document_code);

-- Used by the delete-history screen, and by delta sync later, to find
-- tombstones newer than a given moment.
create index if not exists deleted_records_deleted_at_idx
  on deleted_records (deleted_at desc);

-- ------------------------------------------------------- change timestamps --

alter table documents
  add column if not exists updated_at timestamptz not null default now();

alter table history_entries
  add column if not exists updated_at timestamptz not null default now();

-- The DATABASE stamps the time, never the client. A device with a wrong clock
-- would otherwise write a timestamp in the past, and its edit would be invisible
-- to every other device's delta query — permanently, and silently.
create or replace function touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists documents_touch_updated_at on documents;
create trigger documents_touch_updated_at
  before insert or update on documents
  for each row execute function touch_updated_at();

drop trigger if exists history_entries_touch_updated_at on history_entries;
create trigger history_entries_touch_updated_at
  before insert or update on history_entries
  for each row execute function touch_updated_at();

-- Range scans over the watermark, once delta sync is reading these.
create index if not exists documents_updated_at_idx
  on documents (updated_at);

create index if not exists history_entries_updated_at_idx
  on history_entries (updated_at);
