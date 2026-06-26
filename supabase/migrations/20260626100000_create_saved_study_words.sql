create table if not exists public.saved_study_words (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    word text not null,
    normalized_word text not null,
    lemma text,
    translation text,
    sentence_target text,
    sentence_native text,
    language_code text not null,
    level text,
    part_of_speech text,
    verb_tense text,
    grammar_notes text,
    source_type text not null,
    source_id text not null,
    source_title text not null,
    source_url text,
    block_index integer,
    media_start double precision,
    media_end double precision,
    audio_word_file text,
    audio_sentence_file text,
    deck_folder_name text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create unique index if not exists saved_study_words_user_source_word_idx
on public.saved_study_words (user_id, normalized_word, language_code, source_type, source_id);

alter table public.saved_study_words enable row level security;

create policy "Users can read own saved study words"
on public.saved_study_words
for select
using (auth.uid() = user_id);

create policy "Users can insert own saved study words"
on public.saved_study_words
for insert
with check (auth.uid() = user_id);

create policy "Users can update own saved study words"
on public.saved_study_words
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create policy "Users can delete own saved study words"
on public.saved_study_words
for delete
using (auth.uid() = user_id);
