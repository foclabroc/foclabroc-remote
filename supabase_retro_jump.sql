-- ═══════════════════════════════════════════════════════════════════════════
-- Rétro Jump — classement en ligne (Supabase)
-- À coller dans Supabase → SQL Editor → New query → Run.
-- Relançable sans risque : met à jour une installation existante sans perdre
-- les scores (v2 : pseudos uniques ; v6 : chat ; v7 : fiche joueur ; v8 : niveaux ; v9 : trophées ; v10 : dernière partie ;
-- v11 : « record battu », joueurs prévenus quand on les dépasse au classement général ;
-- v12 : avatars façon Mii).
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

-- v4 : classement de la semaine (mode « week », day = lundi de la semaine, UTC)
alter table public.jump_scores drop constraint if exists jump_scores_mode_check;
alter table public.jump_scores add constraint jump_scores_mode_check check (mode in ('daily', 'all', 'week'));

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
-- v11 : « record battu » — une ligne par (joueur dépassé, joueur qui l'a dépassé)
create table if not exists public.jump_overtakes (
  device     text        not null,                 -- joueur dépassé
  by_device  text        not null,                 -- joueur qui l'a dépassé
  by_name    text        not null,
  score      int         not null,
  created_at timestamptz not null default now(),
  primary key (device, by_device)
);
alter table public.jump_overtakes enable row level security;
revoke all on public.jump_overtakes from anon, authenticated;

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
  v_old  int;
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

  -- v11 : ancien record général, pour prévenir les joueurs dépassés
  if p_mode = 'all' then
    select s.score into v_old from public.jump_scores s
     where s.device = p_device and s.mode = 'all' and s.day = date '2000-01-01';
  end if;

  insert into public.jump_scores as s (device, pid, mode, day, name, score, hero)
  values (p_device, left(encode(extensions.digest(p_device, 'sha256'), 'hex'), 16),
          p_mode, v_day, v_name, p_score, p_hero)
  on conflict (device, mode, day) do update
    set name       = excluded.name,
        hero       = case when excluded.score > s.score then excluded.hero else s.hero end,
        updated_at = case when excluded.score > s.score then now() else s.updated_at end,
        score      = greatest(s.score, excluded.score);

  -- Classement de la semaine : alimenté par chaque partie normale (aussi pour les anciennes versions)
  if p_mode = 'all' then
    insert into public.jump_scores as s (device, pid, mode, day, name, score, hero)
    values (p_device, left(encode(extensions.digest(p_device, 'sha256'), 'hex'), 16),
            'week', date_trunc('week', current_date)::date, v_name, p_score, p_hero)
    on conflict (device, mode, day) do update
      set name       = excluded.name,
          hero       = case when excluded.score > s.score then excluded.hero else s.hero end,
          updated_at = case when excluded.score > s.score then now() else s.updated_at end,
          score      = greatest(s.score, excluded.score);
  end if;
  -- v11 : « record battu » pour les joueurs doublés (30 au plus, les mieux classés)
  if p_mode = 'all' and p_score > coalesce(v_old, 0) then
    insert into public.jump_overtakes as o (device, by_device, by_name, score)
    select s.device, p_device, v_name, p_score from public.jump_scores s
     where s.mode = 'all' and s.day = date '2000-01-01' and s.device <> p_device
       and s.score < p_score and s.score >= coalesce(v_old, 0)
     order by s.score desc limit 30
    on conflict (device, by_device) do update
      set by_name = excluded.by_name, score = excluded.score, created_at = now();
  end if;
  -- Pièces et avancement connus du joueur recopiés sur ses lignes
  update public.jump_scores sc set coins = p.coins, progress = p.progress, level = p.level, avatar = p.avatar
    from public.jump_players p
   where p.device = p_device and sc.device = p_device
     and (sc.coins is distinct from p.coins or sc.progress is distinct from p.progress
          or sc.level is distinct from p.level or sc.avatar is distinct from p.avatar);
  -- v10 : heure de la dernière partie (affichée dans le classement et la fiche)
  update public.jump_players p set last_played = now() where p.device = p_device;
  update public.jump_scores s set last_played = now() where s.device = p_device;

  return query select r.rank, r.score, r.total, v_name from public.jump_rank(p_device, p_mode, p_day) r;
end $$;

-- ── Rang d'un joueur ────────────────────────────────────────────────────────
create or replace function public.jump_rank(p_device text, p_mode text, p_day text)
returns table(rank int, score int, total int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_day   date := case when p_mode in ('daily', 'week') then p_day::date else date '2000-01-01' end;
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

-- ── v3 : pièces du joueur affichées dans le classement ─────────────────────
alter table public.jump_scores  add column if not exists coins int;
alter table public.jump_players add column if not exists coins int;
grant select (pid, name, score, hero, mode, day, updated_at, coins) on public.jump_scores to anon;

create or replace function public.set_jump_coins(p_device text, p_coins int, p_sig text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' || p_coins, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if p_coins < 0 or p_coins > 100000000 then raise exception 'pièces invalides'; end if;
  update public.jump_players set coins = p_coins where device = p_device;
  update public.jump_scores  set coins = p_coins where device = p_device and coins is distinct from p_coins;
end $$;
revoke all on function public.set_jump_coins(text, int, text) from public, authenticated;
grant execute on function public.set_jump_coins(text, int, text) to anon;

-- ── v5 : avancement du joueur (% d'objets et d'albums), affiché dans le classement ──
alter table public.jump_scores  add column if not exists progress int;
alter table public.jump_players add column if not exists progress int;
grant select (pid, name, score, hero, mode, day, updated_at, coins, progress) on public.jump_scores to anon;

create or replace function public.set_jump_profile(p_device text, p_coins int, p_progress int, p_sig text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
begin
  if p_sig is distinct from encode(extensions.digest(
       v_salt || '|' || p_device || '|' || p_coins || '|' || p_progress, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if p_coins < 0 or p_coins > 100000000 then raise exception 'pièces invalides'; end if;
  if p_progress < 0 or p_progress > 100 then raise exception 'avancement invalide'; end if;
  update public.jump_players set coins = p_coins, progress = p_progress where device = p_device;
  update public.jump_scores  set coins = p_coins, progress = p_progress
   where device = p_device and (coins is distinct from p_coins or progress is distinct from p_progress);
end $$;
revoke all on function public.set_jump_profile(text, int, int, text) from public, authenticated;
grant execute on function public.set_jump_profile(text, int, int, text) to anon;

-- ── v4 : fantôme du n°1 (partie du jour) ────────────────────────────────────
-- Trajet du meilleur score du jour de chaque joueur (positions échantillonnées).
create table if not exists public.jump_ghosts (
  device     text        not null,
  day        date        not null,
  score      int         not null,
  data       text        not null,          -- base64 : x (uint16, ‰ largeur) + hauteur (int32, px) tous les 0,1 s
  updated_at timestamptz not null default now(),
  primary key (device, day)
);
alter table public.jump_ghosts enable row level security;
revoke all on public.jump_ghosts from anon, authenticated;

-- Enregistre le fantôme seulement s'il correspond au meilleur score du jour déjà envoyé
create or replace function public.submit_jump_ghost(p_device text, p_day text, p_score int, p_data text, p_sig text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
  v_day  date := p_day::date;
  v_best int;
begin
  if p_sig is distinct from encode(extensions.digest(
       v_salt || '|' || p_device || '|' || p_day || '|' || p_score || '|' ||
       encode(extensions.digest(p_data, 'sha256'), 'hex'), 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_data) > 200000 then raise exception 'fantôme trop gros'; end if;
  select s.score into v_best from public.jump_scores s
   where s.device = p_device and s.mode = 'daily' and s.day = v_day;
  if v_best is null or p_score <> v_best then return; end if;   -- pas (ou plus) le meilleur score
  insert into public.jump_ghosts (device, day, score, data) values (p_device, v_day, p_score, p_data)
  on conflict (device, day) do update
    set score = excluded.score, data = excluded.data, updated_at = now()
    where excluded.score >= jump_ghosts.score;
end $$;

-- Fantôme du meilleur joueur du jour (en excluant le joueur qui demande)
create or replace function public.jump_top_ghost(p_device text, p_day text)
returns table(name text, hero int, score int, data text)
language sql stable security definer set search_path = public as $$
  select s.name, s.hero, g.score, g.data
    from public.jump_ghosts g
    join public.jump_scores s on s.device = g.device and s.mode = 'daily' and s.day = g.day
   where g.day = p_day::date and g.device <> p_device
   order by g.score desc, g.updated_at asc
   limit 1
$$;

revoke all on function public.submit_jump_ghost(text, text, int, text, text) from public, authenticated;
revoke all on function public.jump_top_ghost(text, text) from public, authenticated;
grant execute on function public.submit_jump_ghost(text, text, int, text, text) to anon;
grant execute on function public.jump_top_ghost(text, text) to anon;

-- ── v6 : chat texte (200 derniers messages gardés, ~30 Ko) ─────────────────
create table if not exists public.jump_chat (
  id         bigint generated always as identity primary key,
  device     text        not null,
  pid        text        not null,
  name       text        not null,
  hero       int         not null default 0,
  msg        text        not null check (char_length(msg) between 1 and 120),
  hidden     boolean     not null default false,      -- masqué (signalé ou modéré)
  created_at timestamptz not null default now()
);
create index if not exists jump_chat_device on public.jump_chat (device, created_at desc);
alter table public.jump_chat enable row level security;
drop policy if exists "lecture publique" on public.jump_chat;
create policy "lecture publique" on public.jump_chat for select using (not hidden);
grant select (id, pid, name, hero, msg, created_at) on public.jump_chat to anon;

-- Signalements (3 joueurs différents = message masqué)
create table if not exists public.jump_chat_reports (
  msg_id     bigint      not null references public.jump_chat(id) on delete cascade,
  device     text        not null,
  created_at timestamptz not null default now(),
  primary key (msg_id, device)
);
alter table public.jump_chat_reports enable row level security;

-- Appareils bannis du chat (à remplir à la main, voir en bas)
create table if not exists public.jump_chat_bans (
  device     text        primary key,
  created_at timestamptz not null default now()
);
alter table public.jump_chat_bans enable row level security;

-- Mots filtrés (remplacés par ***). Ajout possible à tout moment :
--   insert into public.jump_chat_words (word) values ('motinterdit');
-- prefix = true : bloque aussi tous les mots qui commencent par celui-ci.
create table if not exists public.jump_chat_words (
  word   text    primary key,
  prefix boolean not null default false
);
alter table public.jump_chat_words enable row level security;
insert into public.jump_chat_words (word, prefix) values
  ('connard', true), ('connasse', true), ('con', false), ('pute', false),
  ('putain', false), ('salope', false), ('salaud', false), ('encule', true), ('enculer', true),
  ('batard', true), ('niquer', true), ('nique', false), ('ntm', false), ('fdp', false),
  ('tg', false), ('ta gueule', false), ('pd', false), ('pede', false), ('tapette', false),
  ('merde', false), ('bite', false), ('couille', false), ('chatte', false), ('bouffon', false),
  ('negre', true), ('bougnoule', true), ('youpin', true), ('gouine', false), ('trisomique', false),
  ('mongol', false), ('abruti', false), ('debile', false), ('cretin', false), ('enfoire', true),
  ('fuck', true), ('shit', false), ('bitch', true), ('ashole', true), ('cunt', true),
  ('dick', false), ('whore', true), ('slut', true), ('bastard', true),
  ('nigga', true), ('niger', false), ('fagot', true), ('stfu', false),
  ('porn', true), ('porno', true), ('sexe', false), ('sex', false), ('nazi', true), ('hitler', true)
on conflict (word) do nothing;

-- Mot normalisé : minuscules, sans accents, chiffres « leet » → lettres, lettres doublées réduites
create or replace function public.jump_chat_norm(p text)
returns text language sql immutable as $$
  select regexp_replace(
           regexp_replace(
             translate(lower(p), 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ013457@$€',
                                 'aaaaaaceeeeiiiinooooouuuuyyoieastase'),
             '[^a-z]', '', 'g'),
           '(.)\1+', '\1', 'g');
$$;

-- Message filtré : mots interdits, liens et numéros de téléphone masqués
create or replace function public.jump_chat_filter(p_msg text)
returns text language plpgsql stable set search_path = public as $$
declare
  v_out  text[] := '{}';
  v_tok  text;
  v_n    text;
  v_bad  boolean;
  v_msg  text;
begin
  v_msg := btrim(regexp_replace(regexp_replace(p_msg, '[[:cntrl:]]', '', 'g'), '\s+', ' ', 'g'));
  -- numéros de téléphone, même espacés (06 12 34 56 78, +33 6…)
  v_msg := regexp_replace(v_msg, '(\+\d|\m0\d)([ .-]?\d){7,}', '********', 'g');
  -- expressions de plusieurs mots (« ta gueule »)
  for v_tok in select w.word from public.jump_chat_words w where w.word like '% %' loop
    v_msg := regexp_replace(v_msg, '\m' || v_tok || '\M', repeat('*', length(v_tok)), 'gi');
  end loop;
  foreach v_tok in array regexp_split_to_array(v_msg, ' ') loop
    v_n := public.jump_chat_norm(v_tok);
    v_bad := v_tok ~* '(https?:|www\.|\.(com|fr|net|org|io|gg|ly|be|ch|ca)\M)'   -- liens
          or regexp_replace(v_tok, '[^0-9]', '', 'g') ~ '[0-9]{8,}'                -- téléphone
          or (v_n <> '' and exists (
                select 1 from public.jump_chat_words w
                 where w.word not like '% %'
                   and (v_n = public.jump_chat_norm(w.word)
                        or (length(public.jump_chat_norm(w.word)) >= 4
                            and v_n ~ ('^' || public.jump_chat_norm(w.word) || '(s|e|es|x|er|ers)$'))
                        or v_n = public.jump_chat_norm(w.word) || 's'
                        or (w.prefix and v_n like public.jump_chat_norm(w.word) || '%'))));
    v_out := v_out || case when v_bad then repeat('*', least(greatest(length(v_tok), 3), 8)) else v_tok end;
  end loop;
  return array_to_string(v_out, ' ');
end $$;

-- Envoi : renvoie 'ok', 'wait' (10 s entre 2 messages), 'noname', 'banned' ou 'empty'
create or replace function public.send_jump_chat(p_device text, p_msg text, p_hero int, p_sig text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
  v_name text;
  v_msg  text;
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' || p_msg, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if exists (select 1 from public.jump_chat_bans b where b.device = p_device) then return 'banned'; end if;
  select p.name into v_name from public.jump_players p where p.device = p_device;
  if v_name is null then return 'noname'; end if;
  if exists (select 1 from public.jump_chat c where c.device = p_device
              and c.created_at > now() - interval '10 seconds') then return 'wait'; end if;
  v_msg := left(public.jump_chat_filter(left(coalesce(p_msg, ''), 200)), 120);
  if v_msg = '' then return 'empty'; end if;
  insert into public.jump_chat (device, pid, name, hero, msg, level, avatar)
  values (p_device, left(encode(extensions.digest(p_device, 'sha256'), 'hex'), 16), v_name,
          least(greatest(coalesce(p_hero, 0), 0), 99), v_msg,
          (select p.level from public.jump_players p where p.device = p_device),
          (select p.avatar from public.jump_players p where p.device = p_device));
  -- Ménage : seuls les 200 derniers messages sont gardés
  delete from public.jump_chat c where c.id <= (select c2.id from public.jump_chat c2 order by c2.id desc offset 200 limit 1);
  return 'ok';
end $$;

-- Signalement : renvoie 'ok' (le message est masqué au 3ᵉ signalement)
create or replace function public.report_jump_chat(p_device text, p_id bigint, p_sig text)
returns text
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' || p_id::text, 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if not exists (select 1 from public.jump_chat c where c.id = p_id and c.device <> p_device) then return 'ok'; end if;
  insert into public.jump_chat_reports (msg_id, device) values (p_id, p_device) on conflict do nothing;
  if (select count(*) from public.jump_chat_reports r where r.msg_id = p_id) >= 3 then
    update public.jump_chat c set hidden = true where c.id = p_id;
  end if;
  return 'ok';
end $$;

revoke all on function public.jump_chat_norm(text) from public, anon, authenticated;
revoke all on function public.jump_chat_filter(text) from public, anon, authenticated;
revoke all on function public.send_jump_chat(text, text, int, text) from public, authenticated;
revoke all on function public.report_jump_chat(text, bigint, text) from public, authenticated;
grant execute on function public.send_jump_chat(text, text, int, text) to anon;
grant execute on function public.report_jump_chat(text, bigint, text) to anon;

-- ── v7 : fiche joueur (toutes ses stats, en touchant son nom) ───────────────
alter table public.jump_players add column if not exists stats    jsonb;
alter table public.jump_players add column if not exists stats_at timestamptz;
create index if not exists jump_scores_pid on public.jump_scores (pid);

-- Statistiques du joueur (clés connues uniquement, entiers 0..2 000 000 000)
create or replace function public.set_jump_stats(p_device text, p_stats text, p_sig text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
  v_in   jsonb;
  v_out  jsonb := '{}';
  v_key  text;
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' ||
       encode(extensions.digest(p_stats, 'sha256'), 'hex'), 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 or length(p_stats) > 2000 then raise exception 'invalide'; end if;
  v_in := p_stats::jsonb;
  if jsonb_typeof(v_in) <> 'object' then raise exception 'invalide'; end if;
  foreach v_key in array array['games','pts','time','jumps','combo','coins','bags','stomps','turbos',
      'logos','cont','falls','bugdeaths','best','album','heroes','themes','musics','trails',
      'heroes_n','themes_n','musics_n','trails_n','xp','level',
      'trophies','trophies_n'] loop  -- v9 : trophées
    if jsonb_typeof(v_in -> v_key) = 'number' then
      v_out := v_out || jsonb_build_object(v_key,
        least(greatest(floor((v_in ->> v_key)::numeric), 0), 2000000000)::bigint);
    end if;
  end loop;
  update public.jump_players p set stats = v_out, stats_at = now() where p.device = p_device;
  -- v8 : niveau du joueur (1 à 99), recopié sur ses scores
  if v_out ? 'level' then
    update public.jump_players p set level = least(greatest((v_out ->> 'level')::int, 1), 99)
     where p.device = p_device;
    update public.jump_scores s set level = least(greatest((v_out ->> 'level')::int, 1), 99)
     where s.device = p_device and s.level is distinct from least(greatest((v_out ->> 'level')::int, 1), 99);
  end if;
end $$;

-- Fiche publique d'un joueur (identifiant public) ; p_day = jour local de la partie du jour
create or replace function public.jump_player_card(p_pid text, p_day text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_dev  text;
  v_day  date := coalesce(nullif(p_day, '')::date, current_date);
  v_week date := date_trunc('week', current_date)::date;
  v_all  int;  v_wk int;  v_td int;
  p      public.jump_players%rowtype;
begin
  select s.device into v_dev from public.jump_scores s where s.pid = p_pid limit 1;
  if v_dev is null then select c.device into v_dev from public.jump_chat c where c.pid = p_pid limit 1; end if;
  if v_dev is null then return null; end if;
  select * into p from public.jump_players pl where pl.device = v_dev;
  select s.score into v_all from public.jump_scores s where s.device = v_dev and s.mode = 'all' and s.day = date '2000-01-01';
  select s.score into v_wk  from public.jump_scores s where s.device = v_dev and s.mode = 'week' and s.day = v_week;
  select s.score into v_td  from public.jump_scores s where s.device = v_dev and s.mode = 'daily' and s.day = v_day;
  return jsonb_build_object(
    'name',      coalesce(p.name, (select s.name from public.jump_scores s where s.device = v_dev limit 1)),
    'since',     p.created_at,
    'coins',     p.coins,
    'progress',  p.progress,
    'avatar',    p.avatar,
    'stats',     coalesce(p.stats, '{}'::jsonb),
    'hero',      (select s.hero from public.jump_scores s where s.device = v_dev order by (s.mode = 'all') desc, s.score desc limit 1),
    'best',      v_all,
    'rank_all',  case when v_all is null then null else (select count(*) + 1 from public.jump_scores s
                   where s.mode = 'all' and s.day = date '2000-01-01' and s.score > v_all) end,
    'total_all', (select count(*) from public.jump_scores s where s.mode = 'all' and s.day = date '2000-01-01'),
    'week',      v_wk,
    'rank_week', case when v_wk is null then null else (select count(*) + 1 from public.jump_scores s
                   where s.mode = 'week' and s.day = v_week and s.score > v_wk) end,
    'today',     v_td,
    'rank_today', case when v_td is null then null else (select count(*) + 1 from public.jump_scores s
                   where s.mode = 'daily' and s.day = v_day and s.score > v_td) end,
    'dailies',   (select count(*) from public.jump_scores s where s.device = v_dev and s.mode = 'daily'),
    'daily_best', (select max(s.score) from public.jump_scores s where s.device = v_dev and s.mode = 'daily'),
    'daily_wins', (select count(*) from public.jump_scores s where s.device = v_dev and s.mode = 'daily'
                     and s.day < current_date
                     and not exists (select 1 from public.jump_scores o where o.mode = 'daily'
                                      and o.day = s.day and o.score > s.score)),
    'chat',      (select count(*) from public.jump_chat c where c.device = v_dev and not c.hidden),
    'level',     p.level,
    'last_played', p.last_played
  );
end $$;

revoke all on function public.set_jump_stats(text, text, text) from public, authenticated;
revoke all on function public.jump_player_card(text, text) from public, authenticated;
grant execute on function public.set_jump_stats(text, text, text) to anon;
grant execute on function public.jump_player_card(text, text) to anon;

-- ── v8 : niveau du joueur (XP), affiché dans le classement, le chat et la fiche ──
alter table public.jump_players add column if not exists level int;
alter table public.jump_scores  add column if not exists level int;
alter table public.jump_chat    add column if not exists level int;
grant select (pid, name, score, hero, mode, day, updated_at, coins, progress, level) on public.jump_scores to anon;
grant select (id, pid, name, hero, msg, created_at, level) on public.jump_chat to anon;

-- ── v10 : heure de la dernière partie du joueur ────────────────────────────
alter table public.jump_players add column if not exists last_played timestamptz;
alter table public.jump_scores  add column if not exists last_played timestamptz;
-- Initialisation : dernière amélioration connue
update public.jump_scores s set last_played = s.updated_at where s.last_played is null;
update public.jump_players p set last_played = (select max(s.updated_at) from public.jump_scores s where s.device = p.device)
 where p.last_played is null;
grant select (pid, name, score, hero, mode, day, updated_at, coins, progress, level, last_played) on public.jump_scores to anon;

-- ── v11 : « record battu » ─────────────────────────────────────────────────
-- Renvoie (et efface) les joueurs qui m'ont dépassé et sont toujours devant moi.
create or replace function public.jump_overtakes_get(p_device text, p_sig text)
returns table(by_name text, score int, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
  v_me   int;
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|overtakes', 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  delete from public.jump_overtakes o where o.created_at < now() - interval '14 days';
  select s.score into v_me from public.jump_scores s
   where s.device = p_device and s.mode = 'all' and s.day = date '2000-01-01';
  return query
    with d as (delete from public.jump_overtakes o where o.device = p_device
               returning o.by_device, o.by_name, o.created_at)
    select coalesce(p.name, d.by_name), s.score, d.created_at
      from d
      join public.jump_scores s on s.device = d.by_device and s.mode = 'all' and s.day = date '2000-01-01'
      left join public.jump_players p on p.device = d.by_device
     where s.score > coalesce(v_me, 0)
     order by s.score desc
     limit 20;
end $$;
revoke all on function public.jump_overtakes_get(text, text) from public, authenticated;
grant execute on function public.jump_overtakes_get(text, text) to anon;

-- ── v12 : avatars façon Mii (8 caractères : peau, visage, coiffure, couleur, yeux, bouche, accessoire, fond) ──
alter table public.jump_players add column if not exists avatar text;
alter table public.jump_scores  add column if not exists avatar text;
alter table public.jump_chat    add column if not exists avatar text;
grant select (pid, name, score, hero, mode, day, updated_at, coins, progress, level, last_played, avatar) on public.jump_scores to anon;
grant select (id, pid, name, hero, msg, created_at, level, avatar) on public.jump_chat to anon;

create or replace function public.set_jump_avatar(p_device text, p_avatar text, p_sig text)
returns void
language plpgsql security definer set search_path = public, extensions as $$
#variable_conflict use_column
declare
  v_salt constant text := 'rj-lb#9d2e-foc';
  v_av   text := nullif(p_avatar, '');
begin
  if p_sig is distinct from encode(extensions.digest(v_salt || '|' || p_device || '|' || coalesce(p_avatar, ''), 'sha256'), 'hex') then
    raise exception 'signature invalide';
  end if;
  if length(p_device) <> 32 then raise exception 'appareil invalide'; end if;
  if v_av is not null and v_av !~ '^[0-9a-z]{8}$' then raise exception 'avatar invalide'; end if;
  update public.jump_players set avatar = v_av where device = p_device;
  update public.jump_scores  set avatar = v_av where device = p_device and avatar is distinct from v_av;
  update public.jump_chat    set avatar = v_av where device = p_device and avatar is distinct from v_av;
end $$;
revoke all on function public.set_jump_avatar(text, text, text) from public, authenticated;
grant execute on function public.set_jump_avatar(text, text, text) to anon;

-- Note « Security Advisor » : les avertissements « Public Can Execute SECURITY
-- DEFINER Function » sont VOULUS — l'appli (rôle anon) doit pouvoir appeler ces
-- fonctions ; elles vérifient elles-mêmes la signature et la cohérence.

-- Ménage : parties du jour de plus de 30 jours (à relancer de temps en temps si besoin)
-- delete from public.jump_scores where mode in ('daily', 'week') and day < current_date - 30;
-- delete from public.jump_ghosts where day < current_date - 7;

-- ── Modération du chat (à lancer à la main dans le SQL Editor) ─────────────
-- Voir les derniers messages (avec signalements) :
--   select c.id, c.name, c.msg, c.hidden, c.created_at,
--          (select count(*) from public.jump_chat_reports r where r.msg_id = c.id) as signalements
--     from public.jump_chat c order by c.id desc limit 50;
-- Masquer un message :           update public.jump_chat set hidden = true where id = 123;
-- Bannir l'auteur d'un message : insert into public.jump_chat_bans (device)
--                                  select device from public.jump_chat where id = 123 on conflict do nothing;
--                                update public.jump_chat set hidden = true
--                                 where device = (select device from public.jump_chat where id = 123);
-- Débannir tout le monde :       delete from public.jump_chat_bans;
-- Vider le chat :                delete from public.jump_chat;

