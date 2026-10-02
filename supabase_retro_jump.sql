-- ═══════════════════════════════════════════════════════════════════════════
-- Rétro Jump — classement en ligne (Supabase)
-- À coller dans Supabase → SQL Editor → New query → Run.
-- Relançable sans risque : met à jour une installation existante sans perdre
-- les scores (v2 : pseudos uniques).
-- ═══════════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.jump_scores (
  device     text        not null,                 -- identifiant secret du téléphone
  pid        text        not null,                 -- identifiant public (sha256 tronqué)
  mode       text        not null check (mode in ('daily', 'all')),
  day        date        not null,                 -- jour de la partie (2000-01-01 pour « all »)
  name       text        not null,
  score      int         not null check (score >= 0),
  hero       int         not null default 0,
  updated_at timestamptz not null default now(),
  primary key (device, mode, day)
);
create index if not exists jump_scores_board on public.jump_scores (mode, day, score desc);

-- Joueurs : un pseudo unique par téléphone (majuscules / espaces ignorés)
create table if not exists public.jump_players (
  device     text        primary key,
  name       text        not null,
  name_key   text        not null unique,          -- lower(btrim(name))
  created_at timestamptz not null default now()
);

-- Lecture publique de quelques colonnes seulement (jamais « device »),
-- aucune écriture directe : tout passe par les fonctions ci-dessous.
alter table public.jump_scores enable row level security;
drop policy if exists "lecture publique" on public.jump_scores;
create policy "lecture publique" on public.jump_scores for select using (true);
revoke all on public.jump_scores from anon, authenticated;
grant select (pid, name, score, hero, mode, day, updated_at) on public.jump_scores to anon;

alter table public.jump_players enable row level security;
revoke all on public.jump_players from anon, authenticated;

-- ── Outils pseudo ───────────────────────────────────────────────────────────
create or replace function public.jump_clean_name(p_name text)
returns text language sql immutable set search_path = '' as $$
  select btrim(left(regexp_replace(coalesce(p_name, ''), '[[:cntrl:]]', '', 'g'), 16))
$$;

-- Réserve un pseudo pour un téléphone. p_force_suffix : si le pseudo est pris,
-- ajoute un chiffre (Mario2, Mario3…) ; sinon renvoie null.
-- Renvoie le pseudo effectivement attribué.
create or replace function public.jump_claim_name(p_device text, p_name text, p_force_suffix boolean)
returns text
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_name text := public.jump_clean_name(p_name);
  v_try  text;
  v_n    int := 1;
  v_owner text;
begin
  if v_name = '' then v_name := 'Joueur'; end if;
  v_try := v_name;
  loop
    select device into v_owner from public.jump_players where name_key = lower(v_try);
    if v_owner is null or v_owner = p_device then
      insert into public.jump_players (device, name, name_key) values (p_device, v_try, lower(v_try))
      on conflict (device) do update set name = excluded.name, name_key = excluded.name_key;
      update public.jump_scores set name = v_try where device = p_device and name <> v_try;
      return v_try;
    end if;
    if not p_force_suffix then return null; end if;
    v_n := v_n + 1;
    v_try := left(v_name, 16 - length(v_n::text)) || v_n;
  end loop;
end $$;

-- Migration v1 → v2 : enregistre les joueurs déjà présents (doublons suffixés)
do $$
declare r record;
begin
  for r in
    select distinct on (device) device, name from public.jump_scores
     where device not in (select device from public.jump_players)
     order by device, updated_at desc
  loop
    perform public.jump_claim_name(r.device, r.name, true);
  end loop;
end $$;

-- ── Envoi d'un score (garde le meilleur) ────────────────────────────────────
drop function if exists public.submit_jump_score(text, text, text, text, int, int, int, text);
create function public.submit_jump_score(
  p_device text, p_name text, p_mode text, p_day text,
  p_score int, p_hero int, p_time int, p_sig text)
returns table(rank int, score int, total int, name text)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';   -- identique à l'appli
  v_day  date;
  v_max  int;
  v_name text;
  v_cur  text;
begin
  if p_sig is distinct from encode(extensions.digest(
       v_salt || '|' || p_device || '|' || p_mode || '|' || p_day || '|' ||
       p_score || '|' || p_time || '|' || p_hero, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if p_mode not in ('daily', 'all') then raise exception 'mode invalide'; end if;
  if p_hero < 0 or p_hero > 63 then raise exception 'héros invalide'; end if;
  if p_time <= 0 or p_time > 6 * 3600 then raise exception 'durée invalide'; end if;

  -- Cohérence : ~115 pts/s au maximum (turbo), départ propulsé ≤ 1 500 pts hors partie du jour
  v_max := 150 + p_time * 130 + case when p_mode = 'all' then 1500 else 0 end;
  if p_score <= 0 or p_score > v_max or p_score > 2000000 then raise exception 'score incohérent'; end if;

  if p_mode = 'daily' then
    v_day := p_day::date;
    if v_day < current_date - 1 or v_day > current_date + 1 then raise exception 'jour expiré'; end if;
  else
    v_day := date '2000-01-01';
  end if;

  -- Pseudo : celui du joueur s'il est déjà inscrit (changé seulement s'il est libre),
  -- sinon réservation avec suffixe automatique si déjà pris
  select p.name into v_cur from public.jump_players p where p.device = p_device;
  if v_cur is null then
    v_name := public.jump_claim_name(p_device, p_name, true);
  elsif lower(public.jump_clean_name(p_name)) <> lower(v_cur) and public.jump_clean_name(p_name) <> '' then
    v_name := coalesce(public.jump_claim_name(p_device, p_name, false), v_cur);
  else
    v_name := v_cur;
  end if;

  insert into public.jump_scores as s (device, pid, mode, day, name, score, hero)
  values (p_device, left(encode(extensions.digest(p_device, 'sha256'), 'hex'), 16),
          p_mode, v_day, v_name, p_score, p_hero)
  on conflict (device, mode, day) do update
    set name       = excluded.name,
        hero       = case when excluded.score > s.score then excluded.hero else s.hero end,
        updated_at = case when excluded.score > s.score then now() else s.updated_at end,
        score      = greatest(s.score, excluded.score);

  return query select r.rank, r.score, r.total, v_name from public.jump_rank(p_device, p_mode, p_day) r;
end $$;

-- ── Rang d'un joueur ────────────────────────────────────────────────────────
create or replace function public.jump_rank(p_device text, p_mode text, p_day text)
returns table(rank int, score int, total int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_day   date := case when p_mode = 'daily' then p_day::date else date '2000-01-01' end;
  v_score int;
begin
  select s.score into v_score from public.jump_scores s
   where s.device = p_device and s.mode = p_mode and s.day = v_day;
  return query select
    case when v_score is null then null else (
      select count(*)::int + 1 from public.jump_scores s
       where s.mode = p_mode and s.day = v_day and s.score > v_score) end,
    v_score,
    (select count(*)::int from public.jump_scores s where s.mode = p_mode and s.day = v_day);
end $$;

-- ── Changement de pseudo ────────────────────────────────────────────────────
-- Renvoie 'ok' ou 'taken' (pseudo déjà utilisé par un autre joueur).
drop function if exists public.rename_jump_player(text, text, text);
create function public.rename_jump_player(p_device text, p_name text, p_sig text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' || p_name, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if public.jump_clean_name(p_name) = '' then raise exception 'pseudo vide'; end if;
  if public.jump_claim_name(p_device, p_name, false) is null then return 'taken'; end if;
  return 'ok';
end $$;

revoke all on function public.jump_clean_name(text) from public;
revoke all on function public.jump_claim_name(text, text, boolean) from public, anon, authenticated;
revoke all on function public.submit_jump_score(text, text, text, text, int, int, int, text) from public;
revoke all on function public.jump_rank(text, text, text) from public;
revoke all on function public.rename_jump_player(text, text, text) from public;
revoke all on function public.submit_jump_score(text, text, text, text, int, int, int, text) from authenticated;
grant execute on function public.submit_jump_score(text, text, text, text, int, int, int, text) to anon;
revoke all on function public.jump_rank(text, text, text) from authenticated;
grant execute on function public.jump_rank(text, text, text) to anon;
revoke all on function public.rename_jump_player(text, text, text) from authenticated;
grant execute on function public.rename_jump_player(text, text, text) to anon;

-- Note « Security Advisor » : les 3 avertissements « Public Can Execute SECURITY
-- DEFINER Function » sont VOULUS — l'appli (rôle anon) doit pouvoir appeler ces
-- fonctions ; elles vérifient elles-mêmes la signature et la cohérence.

-- Ménage : parties du jour de plus de 30 jours (à relancer de temps en temps si besoin)
-- delete from public.jump_scores where mode = 'daily' and day < current_date - 30;
