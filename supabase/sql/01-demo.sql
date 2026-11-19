-- Datos de demostración del prototipo: un "muro" de mensajes cortos.
-- Se ejecuta una vez, como postgres, desde el SQL Editor de Studio o con psql:
--   psql "postgres://postgres.labredes:<POSTGRES_PASSWORD>@supabase.lab.internal:5432/postgres" -f 01-demo.sql

-- 1. Tabla
create table if not exists public.mensajes (
    id         bigint generated always as identity primary key,
    autor      uuid not null default auth.uid() references auth.users (id) on delete cascade,
    texto      text not null check (char_length(texto) between 1 and 280),
    creado_en  timestamptz not null default now()
);

-- 2. Permisos de tabla (GRANT): qué operaciones puede intentar cada rol
grant select on public.mensajes to anon, authenticated;
grant insert, delete on public.mensajes to authenticated;

-- 3. Row Level Security: qué filas alcanza cada operación
alter table public.mensajes enable row level security;

drop policy if exists "leer todos" on public.mensajes;
create policy "leer todos" on public.mensajes
    for select to anon, authenticated
    using (true);

drop policy if exists "insertar propios" on public.mensajes;
create policy "insertar propios" on public.mensajes
    for insert to authenticated
    with check (autor = (select auth.uid()));

drop policy if exists "borrar propios" on public.mensajes;
create policy "borrar propios" on public.mensajes
    for delete to authenticated
    using (autor = (select auth.uid()));

-- 4. Realtime: publicar los cambios de la tabla (replicación lógica)
do $$
begin
    if not exists (
        select 1 from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'mensajes'
    ) then
        alter publication supabase_realtime add table public.mensajes;
    end if;
end $$;

-- 5. Storage: bucket privado para adjuntos
insert into storage.buckets (id, name, public)
values ('adjuntos', 'adjuntos', false)
on conflict (id) do nothing;

drop policy if exists "adjuntos: subir autenticados" on storage.objects;
create policy "adjuntos: subir autenticados" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'adjuntos');

drop policy if exists "adjuntos: leer autenticados" on storage.objects;
create policy "adjuntos: leer autenticados" on storage.objects
    for select to authenticated
    using (bucket_id = 'adjuntos');
