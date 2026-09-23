# WR Locações — Sistema de controle de locação

Controle de saída e retorno de equipamentos (ferramentas por **tag**, andaimes por **número de peças**), taxa de locação em % nas modalidades diária, semanal, quinzenal, mensal e anual (taxa própria por equipamento) e emissão de contrato com **numeração sequencial**.

- **Frontend:** `index.html` (arquivo único, GitHub Pages)
- **Banco e login:** Supabase (`supabase/migrations/001_estrutura.sql` e `002_modalidades.sql`, já aplicadas)
- **Versão:** 1.5.0 · modelo de contrato `CT-LOC v1` (histórico na página *Atualizações* do sistema)

---

## Situação atual
- **Banco no Supabase:** já criado (projeto `wr-locacoes`, região São Paulo), com dados de exemplo.
- **Chaves:** já estão dentro do `index.html`.
- **Acesso:** usuário `vinicius.ornelas1@gmail.com` criado e liberado na equipe.

## Publicação e atualizações
- Hospedado no **GitHub Pages** a partir da branch `main` deste repositório (raiz). Cada commit na `main` atualiza o site em ~1 minuto.
- A cada nova versão: atualizar `APP_VERSION` e `VERSOES` no `index.html` **e** o `version.json`, no mesmo commit. Quem estiver com o sistema aberto vê o aviso "Nova versão disponível".
- `.github/workflows/keepalive.yml` consulta o banco uma vez por dia para o Supabase gratuito não pausar.

## Instalar como aplicativo no computador
No Chrome ou Edge, abra o sistema e clique em **⤓ Instalar aplicativo** no menu lateral (ou no ícone de instalar na barra de endereço). Ele ganha ícone na área de trabalho/barra de tarefas e abre em janela própria. Continua precisando de internet e recebe as atualizações sozinho.
Arquivos envolvidos: `manifest.webmanifest`, `sw.js`, `offline.html` e a pasta `icons/` (ícones provisórios, a trocar quando a identidade visual for definida).

## Liberar outra pessoa
1. Supabase → **Authentication → Users → Add user → Create new user** (marque *Auto Confirm User*).
2. Supabase → **SQL Editor**: `insert into equipe (email, nome) values ('email@da.pessoa', 'Nome');`

Quem não estiver na tabela `equipe` não vê nem altera nada, mesmo que consiga criar uma conta.

## Como o sistema funciona
| Regra | Onde é garantida |
|---|---|
| Número do contrato sequencial e sem buracos (`0001/2026`, `0002/2026`…) | Função `registrar_locacao` no banco, com trava contra registros simultâneos |
| Ferramenta (tag) só pode estar em um contrato ativo | Banco |
| Não sai mais peça de andaime do que há em estoque | Banco |
| Taxa e valor base ficam congelados no contrato | Banco (cópia no item do contrato) |
| Retorno parcial ou total; contrato encerra sozinho quando tudo volta | Função `registrar_devolucao` |
| Quem alterou o quê e quando | Tabela `auditoria` |
| Só usuários logados veem ou alteram dados | RLS (Row Level Security) |

Valor por período = valor base × quantidade × taxa da modalidade (diária, semanal, quinzenal, mensal ou anual). O acumulado é calculado pró-rata por dia (semana = 7, quinzena = 15, mês = 30, ano = 365 dias), descontando devoluções parciais.

## Plano gratuito do Supabase (decisão de 23/09/2026)
O sistema roda no plano **Free**. Cuidados obrigatórios:
- **Sem backup automático:** baixar a **cópia de segurança semanal** em *Configurações → Cópia de segurança* e guardar no Drive/OneDrive.
- **Pausa após 7 dias sem uso:** o workflow `keepalive.yml` consulta o banco todo dia. Como o GitHub desliga agendamentos de repositórios sem commits há 60 dias, configure também um **monitor externo** (cron-job.org, gratuito):
  - URL `https://gxpvvlfmaadiiqktirlj.supabase.co/rest/v1/rpc/ping`, método **POST**;
  - cabeçalhos `apikey: sb_publishable_a7Q-3VPi6AE38vpKtCNMyg_Zwtxivzr` e `Content-Type: application/json`, corpo `{}`;
  - execução diária.
- **Limites:** 500 MB de banco (sobra para anos de contratos) e **2 projetos ativos por organização**. A conta já usa os 2 (Tracker Obra + WR Locações).
- Próximas melhorias planejadas: perfis administrador × operacional, aditivos/prorrogação de contrato e faturamento mensal.
