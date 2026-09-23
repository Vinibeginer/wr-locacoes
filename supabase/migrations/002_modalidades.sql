-- =====================================================================
-- WR Locações — Migração 002 · modalidades diária, semanal e quinzenal
-- Só acrescenta colunas e amplia regras; não apaga nem altera contratos.
-- Cada equipamento passa a ter taxa própria para cada modalidade.
-- =====================================================================

-- Taxas padrão (usadas quando o cadastro deixa o campo em branco)
alter table public.config
  add column taxa_diaria_padrao    numeric(7,3) not null default 0.3,
  add column taxa_semanal_padrao   numeric(7,2) not null default 2,
  add column taxa_quinzenal_padrao numeric(7,2) not null default 4;

-- Taxas por equipamento
alter table public.ferramentas
  add column taxa_diaria    numeric(7,3) not null default 0.3 check (taxa_diaria >= 0),
  add column taxa_semanal   numeric(7,2) not null default 2   check (taxa_semanal >= 0),
  add column taxa_quinzenal numeric(7,2) not null default 4   check (taxa_quinzenal >= 0);

alter table public.andaimes
  add column taxa_diaria    numeric(7,3) not null default 0.3 check (taxa_diaria >= 0),
  add column taxa_semanal   numeric(7,2) not null default 2   check (taxa_semanal >= 0),
  add column taxa_quinzenal numeric(7,2) not null default 4   check (taxa_quinzenal >= 0);

-- Taxas congeladas no item do contrato (contratos antigos ficam com 0: eram mensais/anuais)
alter table public.locacao_itens
  add column taxa_diaria    numeric(7,3) not null default 0,
  add column taxa_semanal   numeric(7,2) not null default 0,
  add column taxa_quinzenal numeric(7,2) not null default 0;

-- Novas modalidades
alter table public.locacoes drop constraint locacoes_modalidade_check;
alter table public.locacoes add constraint locacoes_modalidade_check
  check (modalidade in ('diaria','semanal','quinzenal','mensal','anual'));

-- Registrar locação: aceita as novas modalidades e congela todas as taxas do item
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
  if (p ->> 'modalidade') is null or (p ->> 'modalidade') not in ('diaria','semanal','quinzenal','mensal','anual') then
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
      insert into public.locacao_itens (locacao_id, idx, tipo, ref_id, tag, descricao, qtd, valor_base,
                                        taxa_mensal, taxa_anual, taxa_diaria, taxa_semanal, taxa_quinzenal)
      values (v_loc.id, v_idx, 'ferramenta', v_f.id, v_f.tag, v_f.descricao, 1, v_f.valor_base,
              v_f.taxa_mensal, v_f.taxa_anual, v_f.taxa_diaria, v_f.taxa_semanal, v_f.taxa_quinzenal);

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
      insert into public.locacao_itens (locacao_id, idx, tipo, ref_id, tag, descricao, qtd, valor_base,
                                        taxa_mensal, taxa_anual, taxa_diaria, taxa_semanal, taxa_quinzenal)
      values (v_loc.id, v_idx, 'andaime', v_a.id, v_a.codigo, v_a.descricao, v_qtd, v_a.valor_unitario,
              v_a.taxa_mensal, v_a.taxa_anual, v_a.taxa_diaria, v_a.taxa_semanal, v_a.taxa_quinzenal);
    else
      raise exception 'Tipo de item inválido.';
    end if;
    v_idx := v_idx + 1;
  end loop;

  return v_loc;
end $$;
