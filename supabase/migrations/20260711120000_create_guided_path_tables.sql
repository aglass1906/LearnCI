-- Guided Story Learning Path: next-day plans + resume progress.
-- Client sync (SyncManager) no-ops gracefully until these tables exist.

create table if not exists public.next_session_plans (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    scheduled_for timestamptz not null,
    source_type text not null,
    source_id text not null,
    source_title text not null,
    chapter_number integer,
    scene_index integer,
    target_minutes integer not null default 10,
    word_review_count integer not null default 5,
    focus_note text,
    notification_time timestamptz,
    notification_id text,
    status text not null default 'pending'
);

create index if not exists next_session_plans_user_scheduled_idx
on public.next_session_plans (user_id, scheduled_for);

alter table public.next_session_plans enable row level security;

create policy "Users can read own next session plans"
on public.next_session_plans for select using (auth.uid() = user_id);

create policy "Users can insert own next session plans"
on public.next_session_plans for insert with check (auth.uid() = user_id);

create policy "Users can update own next session plans"
on public.next_session_plans for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can delete own next session plans"
on public.next_session_plans for delete using (auth.uid() = user_id);


create table if not exists public.story_path_progress (
    id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    story_id text not null,
    story_title text not null,
    chapter_number integer not null,
    scene_index integer,
    current_stage integer not null default 1,
    stage_completion jsonb not null default '[false,false,false,false,false]'::jsonb,
    read_minutes_accumulated integer not null default 0,
    loops_completed integer not null default 0,
    words_marked jsonb not null default '[]'::jsonb,
    shadow_lines jsonb not null default '[]'::jsonb,
    started_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    completed_at timestamptz
);

create index if not exists story_path_progress_user_story_chapter_idx
on public.story_path_progress (user_id, story_id, chapter_number);

alter table public.story_path_progress enable row level security;

create policy "Users can read own story path progress"
on public.story_path_progress for select using (auth.uid() = user_id);

create policy "Users can insert own story path progress"
on public.story_path_progress for insert with check (auth.uid() = user_id);

create policy "Users can update own story path progress"
on public.story_path_progress for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users can delete own story path progress"
on public.story_path_progress for delete using (auth.uid() = user_id);
