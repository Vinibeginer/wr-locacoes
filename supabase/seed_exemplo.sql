-- Dados de exemplo para a apresentação (opcional). Rode DEPOIS do 001_estrutura.sql.
-- Para apagar depois: delete from andaimes where descricao like '%(exemplo)%'; etc.
insert into public.clientes (nome, doc, endereco, contato, telefone) values
  ('Construtora Exemplo Ltda (exemplo)', '00.000.000/0001-00', 'Rua Exemplo, 100 — Centro', 'Eng. Responsável', '(22) 99999-0000');

insert into public.ferramentas (tag, descricao, categoria, valor_base, taxa_mensal, taxa_anual) values
  ('FER-0001', 'Martelete rompedor 10 kg (exemplo)', 'Demolição',   6500, 8, 72),
  ('FER-0002', 'Gerador a diesel 6 kVA (exemplo)',   'Energia',     14800, 7, 65),
  ('FER-0003', 'Betoneira 400 L (exemplo)',          'Concretagem', 5200, 8, 72);

insert into public.andaimes (codigo, descricao, valor_unitario, qtd_total, taxa_mensal, taxa_anual) values
  ('TUB-2M',   'Tubo galvanizado 2,00 m (exemplo)', 95,  400, 8, 72),
  ('BRAC-FIX', 'Braçadeira fixa (exemplo)',         18,  800, 8, 72),
  ('PISO-1M',  'Piso metálico 1,00 m (exemplo)',    160, 120, 8, 72);
