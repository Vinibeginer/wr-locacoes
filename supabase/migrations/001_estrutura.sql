-- =====================================================================
-- WR Locações — estrutura inicial do banco (Supabase / Postgres)
-- Migração 001 · rodar uma única vez no SQL Editor do Supabase
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Configuração da locadora (linha única)
-- ---------------------------------------------------------------------
create table public.config (
  id                 int primary key default 1 check (id = 1),
  razao              text not null default 'WR LOCAÇÕES',
  cnpj               text not null default '',
  endereco           text not null default '',
  cidade             text not null default '',
  foro               text not null default '',
  taxa_mensal_padrao numeric(7,2) not null default 8,
  taxa_anual_padrao  numeric(7,2) not null default 72,
  multa_atraso       numeric(7,2) not null default 2,
  alerta_dias        int not null default 7 check (alerta_dias >= 0),
  updated_at         timestamptz not null default now()
);
insert into public.config (id) values (1) on conflict do nothing;

-- Contador de contratos: número só é consumido se a locação for gravada
-- (sem buracos na sequência, ao contrário de uma SEQUENCE do Postgres).
create table public.contador_contrato (
  id     int primary key default 1 check (id = 1),
  ultimo int not null default 0
);
insert into public.contador_contrato (id) values (1) on conflict do nothing;

-- ---------------------------------------------------------------------
-- Cadastros
-- ---------------------------------------------------------------------
create table public.clientes (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null check (length(trim(nome)) > 0),
  doc        text not null default '',
  endereco   text not null default '',
  contato    text not null default '',
  telefone   text not null default '',
  email      text not null default '',
  created_at timestamptz not null default now()
);

create table public.ferramentas (
  id          uuid primary key default gen_random_uuid(),
  tag         text not null unique check (tag = upper(trim(tag)) and length(tag) > 0),
  descricao   text not null,
  categoria   text not null default '',
  valor_base  numeric(12,2) not null check (valor_base >= 0),
  taxa_mensal numeric(7,2) not null default 8 check (taxa_mensal >= 0),
  taxa_anual  numeric(7,2) not null default 72 check (taxa_anual >= 0),
  manutencao  boolean not null default false,
  created_at  timestamptz not null default now()
);

create table public.andaimes (
  id             uuid primary key default gen_random_uuid(),
  codigo         text not null default '',
  descricao      text not null,
  valor_unitario numeric(12,2) not null check (valor_unitario >= 0),
  qtd_total      int not null check (qtd_total >= 0),
  taxa_mensal    numeric(7,2) not null default 8 check (taxa_mensal >= 0),
  taxa_anual     numeric(7,2) not null default 72 check (taxa_anual >= 0),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Locações (contratos), itens e devoluções
-- ---------------------------------------------------------------------
create table public.locacoes (
  id                uuid primary key default gen_random_uuid(),
  numero            int  not null unique,
  ano               int  not null,
  numero_fmt        text not null unique,
  status            text not null default 'ativa' check (status in ('ativa','encerrada')),
  modalidade        text not null check (modalidade in ('mensal','anual')),
  cliente_id        uuid not null references public.clientes(id),
  cliente           jsonb not null,           -- dados do cliente congelados no contrato
  local             text not null default '',
  responsavel       text not null default '',
  data_saida        date not null,
  previsao_retorno  date not null,
  data_encerramento date,
  empresa           jsonb not null,           -- dados da locadora congelados no contrato
  multa_atraso      numeric(7,2) not null,
  template_versao   text not null,
  app_versao        text,
  criado_por        uuid default auth.uid(),
  created_at        timestamptz not null default now(),
  check (previsao_retorno >= data_saida)
);

create table public.locacao_itens (
  id            uuid primary key default gen_random_uuid(),
  locacao_id    uuid not null references public.locacoes(id) on delete cascade,
  idx           int  not null,
  tipo          text not null check (tipo in ('ferramenta','andaime')),
  ref_id        uuid not null,
  tag           text not null default '',
  descricao     text not null,
  qtd           int  not null check (qtd > 0),
  qtd_devolvida int  not null default 0,
  valor_base    numeric(12,2) not null,       -- congelado na saída
  taxa_mensal   numeric(7,2) not null,        -- congelada na saída
  taxa_anual    numeric(7,2) not null,        -- congelada na saída
  unique (locacao_id, idx),
  check (qtd_devolvida between 0 and qtd)
);
create index on public.locacao_itens (tipo, ref_id);

create table public.devolucoes (
  id             uuid primary key default gen_random_uuid(),
  locacao_id     uuid not null references public.locacoes(id) on delete cascade,
  data           date not null,
  cond           text not null default 'Em ordem',
  obs            text not null default '',
  itens          jsonb not null,              -- [{ "idx": 0, "qtd": 10 }, ...]
  registrado_por uuid default auth.uid(),
  created_at     timestamptz not null default now()
);
create index on public.devolucoes (locacao_id);

-- ---------------------------------------------------------------------
-- Trilha de auditoria: quem alterou o quê e quando
-- ---------------------------------------------------------------------
create table public.auditoria (
  id            bigserial primary key,
  tabela        text not null,
  registro_id   text,
  acao          text not null,
  antes         jsonb,
  depois        jsonb,
  usuario       uuid default auth.uid(),
  usuario_email text default (auth.jwt() ->> 'email'),
  em            timestamptz not null default now()
);

create or replace function public.fn_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.auditoria (tabela, registro_id, acao, antes, depois)
  values (
    tg_table_name,
    coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id'),
    tg_op,
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['config','clientes','ferramentas','andaimes','locacoes','locacao_itens','devolucoes'] loop
    execute format('create trigger trg_auditoria after insert or update or delete on public.%I
                    for each row execute function public.fn_auditoria()', t);
  end loop;
end $$;

-- Não deixa reduzir o estoque de um tipo de andaime abaixo do que está em campo
create or replace function public.fn_andaime_estoque() returns trigger
language plpgsql set search_path = public as $$
declare v_uso int;
begin
  select coalesce(sum(li.qtd - li.qtd_devolvida), 0) into v_uso
    from public.locacao_itens li join public.locacoes l on l.id = li.locacao_id
   where l.status = 'ativa' and li.tipo = 'andaime' and li.ref_id = new.id;
  if new.qtd_total < v_uso then
    raise exception 'Há % peças de "%" em campo; o estoque total não pode ser menor que isso.', v_uso, new.descricao;
  end if;
  return new;
end $$;
create trigger trg_andaime_estoque before update of qtd_total on public.andaimes
  for each row execute function public.fn_andaime_estoque();

-- ---------------------------------------------------------------------
-- Registrar locação: valida estoque, numera e grava tudo numa transação
-- p = { cliente_id, modalidade, local, responsavel, data_saida, previsao_retorno, app_versao,
--       itens: [{ tipo: 'ferramenta'|'andaime', ref_id, qtd }] }
-- ---------------------------------------------------------------------
create or replace function public.registrar_locacao(p jsonb) returns public.locacoes
language plpgsql security definer set search_path = public as $$
declare
  v_cli  public.clientes;
  v_cfg  public.config;
  v_loc  public.locacoes;
  v_f    public.ferramentas;
  v_a    public.andaimes;
  v_num  int;
  v_ano  int;
  v_uso  int;
  v_qtd  int;
  v_idx  int := 0;
  it     jsonb;
begin
  if auth.uid() is null or not public.eh_equipe() then
    raise exception 'Seu usuário não tem acesso liberado ao sistema.';
  end if;

  -- serializa registros simultâneos (estoque + numeração)
  perform pg_advisory_xact_lock(4242001);

  select * into v_cli from public.clientes where id = (p ->> 'cliente_id')::uuid;
  if not found then raise exception 'Selecione um cliente válido.'; end if;

  if coalesce(jsonb_array_length(p -> 'itens'), 0) = 0 then
    raise exception 'Adicione ao menos um equipamento.';
  end if;
  if (p ->> 'modalidade') not in ('mensal','anual') then
    raise exception 'Modalidade inválida.';
  end if;
  if (p ->> 'previsao_retorno')::date < (p ->> 'data_saida')::date then
    raise exception 'A previsão de retorno deve ser igual ou posterior à data de saída.';
  end if;

  select * into v_cfg from public.config where id = 1;
  update public.contador_contrato set ultimo = ultimo + 1 where id = 1 returning ultimo into v_num;
  v_ano := extract(year from (p ->> 'data_saida')::date);

  insert into public.locacoes (numero, ano, numero_fmt, modalidade, cliente_id, cliente, local, responsavel,
                               data_saida, previsao_retorno, empresa, multa_atraso, template_versao, app_versao)
  values (
    v_num, v_ano, lpad(v_num::text, 4, '0') || '/' || v_ano,
    p ->> 'modalidade', v_cli.id,
    jsonb_build_object('nome', v_cli.nome, 'doc', v_cli.doc, 'endereco', v_cli.endereco,
                       'contato', v_cli.contato, 'telefone', v_cli.telefone, 'email', v_cli.email),
    coalesce(p ->> 'local', ''), coalesce(p ->> 'responsavel', ''),
    (p ->> 'data_saida')::date, (p ->> 'previsao_retorno')::date,
    jsonb_build_object('razao', v_cfg.razao, 'cnpj', v_cfg.cnpj, 'endereco', v_cfg.endereco,
                       'cidade', v_cfg.cidade, 'foro', v_cfg.foro),
    v_cfg.multa_atraso, 'CT-LOC v1', p ->> 'app_versao'
  ) returning * into v_loc;

  for it in select * from jsonb_array_elements(p -> 'itens') loop
    if it ->> 'tipo' = 'ferramenta' then
      select * into v_f from public.ferramentas where id = (it ->> 'ref_id')::uuid;
      if not found then raise exception 'Ferramenta não encontrada.'; end if;
      if v_f.manutencao then raise exception 'A ferramenta % está em manutenção.', v_f.tag; end if;
      if exists (select 1 from public.locacao_itens li join public.locacoes l on l.id = li.locacao_id
                  where l.status = 'ativa' and li.tipo = 'ferramenta' and li.ref_id = v_f.id
                    and li.qtd > li.qtd_devolvida) then
        raise exception 'A ferramenta % já está locada em outro contrato.', v_f.tag;
      end if;
      insert into public.locacao_itens (locacao_id, idx, tipo, ref_id, tag, descricao, qtd, valor_base, taxa_mensal, taxa_anual)
      values (v_loc.id, v_idx, 'ferramenta', v_f.id, v_f.tag, v_f.descricao, 1, v_f.valor_base, v_f.taxa_mensal, v_f.taxa_anual);

    elsif it ->> 'tipo' = 'andaime' then
      v_qtd := (it ->> 'qtd')::int;
      if v_qtd is null or v_qtd <= 0 then raise exception 'Quantidade de peças inválida.'; end if;
      select * into v_a from public.andaimes where id = (it ->> 'ref_id')::uuid;
      if not found then raise exception 'Tipo de peça não encontrado.'; end if;
      select coalesce(sum(li.qtd - li.qtd_devolvida), 0) into v_uso
        from public.locacao_itens li join public.locacoes l on l.id = li.locacao_id
       where l.status = 'ativa' and li.tipo = 'andaime' and li.ref_id = v_a.id;
      if v_uso + v_qtd > v_a.qtd_total then
        raise exception 'Estoque insuficiente de "%": há % peça(s) disponível(is).', v_a.descricao, v_a.qtd_total - v_uso;
      end if;
      insert into public.locacao_itens (locacao_id, idx, tipo, ref_id, tag, descricao, qtd, valor_base, taxa_mensal, taxa_anual)
      values (v_loc.id, v_idx, 'andaime', v_a.id, v_a.codigo, v_a.descricao, v_qtd, v_a.valor_unitario, v_a.taxa_mensal, v_a.taxa_anual);
    else
      raise exception 'Tipo de item inválido.';
    end if;
    v_idx := v_idx + 1;
  end loop;

  return v_loc;
end $$;

-- ---------------------------------------------------------------------
-- Registrar retorno (parcial ou total)
-- p_itens = [{ idx, qtd }]
-- ---------------------------------------------------------------------
create or replace function public.registrar_devolucao(
  p_locacao uuid, p_data date, p_cond text, p_obs text, p_itens jsonb
) returns public.locacoes
language plpgsql security definer set search_path = public as $$
declare
  v_loc public.locacoes;
  it    jsonb;
  v_q   int;
  v_n   int := 0;
begin
  if auth.uid() is null or not public.eh_equipe() then raise exception 'Seu usuário não tem acesso liberado ao sistema.'; end if;

  select * into v_loc from public.locacoes where id = p_locacao for update;
  if not found then raise exception 'Locação não encontrada.'; end if;
  if v_loc.status <> 'ativa' then raise exception 'Esta locação já está encerrada.'; end if;
  if p_data is null or p_data < v_loc.data_saida then
    raise exception 'A data de retorno não pode ser anterior à saída (%).', to_char(v_loc.data_saida, 'DD/MM/YYYY');
  end if;

  for it in select * from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) loop
    v_q := (it ->> 'qtd')::int;
    continue when v_q is null or v_q <= 0;
    update public.locacao_itens
       set qtd_devolvida = qtd_devolvida + v_q
     where locacao_id = p_locacao and idx = (it ->> 'idx')::int and qtd_devolvida + v_q <= qtd;
    if not found then raise exception 'Quantidade de retorno maior que a quantidade em campo.'; end if;
    v_n := v_n + 1;
  end loop;
  if v_n = 0 then raise exception 'Informe ao menos um item retornando.'; end if;

  insert into public.devolucoes (locacao_id, data, cond, obs, itens)
  values (p_locacao, p_data, coalesce(p_cond, 'Em ordem'), coalesce(p_obs, ''),
          (select jsonb_agg(x) from jsonb_array_elements(p_itens) x where (x ->> 'qtd')::int > 0));

  if not exists (select 1 from public.locacao_itens where locacao_id = p_locacao and qtd_devolvida < qtd) then
    update public.locacoes
       set status = 'encerrada',
           data_encerramento = (select max(data) from public.devolucoes where locacao_id = p_locacao)
     where id = p_locacao;
  end if;

  select * into v_loc from public.locacoes where id = p_locacao;
  return v_loc;
end $$;

-- Chamada leve usada pelo keep-alive (plano gratuito pausa após ~7 dias sem uso)
create or replace function public.ping() returns text
language sql security definer set search_path = public as $$ select 'ok'::text $$;

-- ---------------------------------------------------------------------
-- Equipe autorizada: só esses e-mails acessam o sistema, mesmo que alguém crie conta
-- ---------------------------------------------------------------------
create table public.equipe (
  email      text primary key check (email = lower(trim(email))),
  nome       text not null default '',
  papel      text not null default 'admin' check (papel in ('admin','operacional')),
  ativo      boolean not null default true,
  created_at timestamptz not null default now()
);

create or replace function public.eh_equipe() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.equipe
                  where ativo and email = lower(coalesce(auth.jwt() ->> 'email', '')))
$$;

-- ---------------------------------------------------------------------
-- Segurança (RLS): só a equipe autorizada acessa; contratos só mudam pelas funções
-- ---------------------------------------------------------------------
alter table public.config            enable row level security;
alter table public.contador_contrato enable row level security;
alter table public.clientes          enable row level security;
alter table public.ferramentas       enable row level security;
alter table public.andaimes          enable row level security;
alter table public.locacoes          enable row level security;
alter table public.locacao_itens     enable row level security;
alter table public.devolucoes        enable row level security;
alter table public.auditoria         enable row level security;
alter table public.equipe            enable row level security;

create policy leitura on public.config            for select to authenticated using (public.eh_equipe());
create policy edicao  on public.config            for update to authenticated using (public.eh_equipe()) with check (public.eh_equipe());
create policy leitura on public.contador_contrato for select to authenticated using (public.eh_equipe());

create policy leitura  on public.clientes for select to authenticated using (public.eh_equipe());
create policy inclusao on public.clientes for insert to authenticated with check (public.eh_equipe());
create policy edicao   on public.clientes for update to authenticated using (public.eh_equipe()) with check (public.eh_equipe());

create policy leitura  on public.ferramentas for select to authenticated using (public.eh_equipe());
create policy inclusao on public.ferramentas for insert to authenticated with check (public.eh_equipe());
create policy edicao   on public.ferramentas for update to authenticated using (public.eh_equipe()) with check (public.eh_equipe());

create policy leitura  on public.andaimes for select to authenticated using (public.eh_equipe());
create policy inclusao on public.andaimes for insert to authenticated with check (public.eh_equipe());
create policy edicao   on public.andaimes for update to authenticated using (public.eh_equipe()) with check (public.eh_equipe());

create policy leitura on public.locacoes      for select to authenticated using (public.eh_equipe());
create policy leitura on public.locacao_itens for select to authenticated using (public.eh_equipe());
create policy leitura on public.devolucoes    for select to authenticated using (public.eh_equipe());
create policy leitura on public.auditoria     for select to authenticated using (public.eh_equipe());
create policy leitura on public.equipe        for select to authenticated using (public.eh_equipe());

revoke all on function public.registrar_locacao(jsonb) from public, anon;
revoke all on function public.registrar_devolucao(uuid, date, text, text, jsonb) from public, anon;
grant execute on function public.registrar_locacao(jsonb) to authenticated;
grant execute on function public.registrar_devolucao(uuid, date, text, text, jsonb) to authenticated;
grant execute on function public.ping() to anon, authenticated;
revoke all on function public.eh_equipe() from public, anon;
grant execute on function public.eh_equipe() to authenticated;

-- ---------------------------------------------------------------------
-- Atualização em tempo real entre usuários
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.config, public.contador_contrato, public.clientes, public.ferramentas,
      public.andaimes, public.locacoes, public.locacao_itens, public.devolucoes;
  end if;
end $$;

-- Funções de trigger não devem ser chamáveis pela API
revoke all on function public.fn_auditoria() from public, anon, authenticated;
revoke all on function public.fn_andaime_estoque() from public, anon, authenticated;
