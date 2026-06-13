alter table public.profiles
    add column if not exists proficiency_level integer,
    add column if not exists onboarding_version integer not null default 0,
    add column if not exists onboarding_completed_at timestamptz;

update public.profiles
set proficiency_level = case current_level
    when 'Super Beginner' then 1
    when 'Beginner' then 2
    when 'Intermediate' then 3
    when 'Advanced' then 5
    else 1
end
where proficiency_level is null;

alter table public.profiles
    alter column proficiency_level set default 1,
    alter column proficiency_level set not null;

alter table public.profiles
    drop constraint if exists profiles_proficiency_level_check;

alter table public.profiles
    add constraint profiles_proficiency_level_check
    check (proficiency_level between 1 and 6);
