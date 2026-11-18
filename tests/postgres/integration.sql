\set ON_ERROR_STOP on
-- Every assertion executes against the actual migrated trigger, not a substitute.
CREATE OR REPLACE FUNCTION pg_temp.add_folga(p_id integer,p_day date,p_regime integer,p_func uuid DEFAULT '00000000-0000-0000-0000-000000000011',p_private uuid DEFAULT NULL,p_end date DEFAULT NULL,p_indef boolean DEFAULT false,p_status text DEFAULT 'solicitada') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid := ('00000000-0000-0000-0000-'||lpad(p_id::text,12,'0'))::uuid;
BEGIN
 INSERT INTO ro_private.folga_criacao_contexto(solicitacao_id,funcionario_id,colaborador_id,obra_id,criado_por,alocacao_id,distancia_km,regime_faixa,intervalo_dias)
 VALUES(v_id,p_func,p_private,'00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000088',100,p_regime::text,p_regime);
 INSERT INTO public.ro_passagem_solicitacoes(id,funcionario_id,colaborador_id,obra_id,data_ida,data_retorno,retorno_indefinido,status)
 VALUES(v_id,p_func,p_private,'00000000-0000-0000-0000-000000000099',p_day,p_end,p_indef,p_status);
 RETURN v_id;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_sql text,p_expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE p_sql;
 RAISE EXCEPTION 'Expected error %, statement succeeded',p_expected;
EXCEPTION WHEN OTHERS THEN
 IF position(p_expected in SQLERRM)=0 THEN RAISE; END IF;
END $$;
DO $$ DECLARE d date:=current_date+40; BEGIN
 PERFORM pg_temp.add_folga(101,d+21,7);
 PERFORM pg_temp.add_folga(102,d,7);
 PERFORM pg_temp.add_folga(103,d+14,7);
 PERFORM pg_temp.add_folga(104,d+7,7);
 IF (SELECT count(*) FROM ro_passagem_solicitacoes WHERE funcionario_id='00000000-0000-0000-0000-000000000011')<>4 THEN RAISE EXCEPTION 'four weeks failed'; END IF;
 PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(105,%L::date,7)',d),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.add_folga(106,d+30,7,'00000000-0000-0000-0000-000000000011',NULL,d+33);
 PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(107,%L::date,7)',d+32),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.add_folga(108,d+40,7,'00000000-0000-0000-0000-000000000011',NULL,d+100,true);
 PERFORM pg_temp.add_folga(109,d+41,7);
 PERFORM pg_temp.expect_error('UPDATE ro_passagem_solicitacoes SET retorno_indefinido=false WHERE id=''00000000-0000-0000-0000-000000000108''','FOLGA_FUTURA_DUPLICADA');
 RAISE NOTICE 'PASS four weeks, out-of-order, same-day, overlaps, indefinite return, UPDATE';
END $$;
-- Independent identities and linked identities.
INSERT INTO ro_funcionarios_enderecos_privados(id,funcionario_id) VALUES
 ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000011'),
 ('00000000-0000-0000-0000-000000000202',NULL),
 ('00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000012');
DO $$ DECLARE d date:=current_date+40; BEGIN
 PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(210,%L::date,7,NULL,%L::uuid)',d,'00000000-0000-0000-0000-000000000201'),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.add_folga(211,d,7,NULL,'00000000-0000-0000-0000-000000000202');
 PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(212,%L::date,7,NULL,%L::uuid)',d,'00000000-0000-0000-0000-000000000202'),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(213,%L::date,7,%L::uuid,%L::uuid)',d,'00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000203'),'FOLGA_IDENTIDADE_INCONSISTENTE');
 RAISE NOTICE 'PASS canonical linked, independent private, inconsistent identity';
END $$;
DO $$ DECLARE d date:=current_date+40; r integer; BEGIN
 FOREACH r IN ARRAY ARRAY[14,45,90] LOOP
  PERFORM pg_temp.add_folga(300+r,d,r,('00000000-0000-0000-0000-'||lpad((300+r)::text,12,'0'))::uuid);
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.add_folga(%s,%L::date,%s,%L::uuid)',500+r,d+7,r,('00000000-0000-0000-0000-'||lpad((300+r)::text,12,'0'))::uuid),'FOLGA_FUTURA_DUPLICADA');
 END LOOP;
 RAISE NOTICE 'PASS 14,45,90 legacy generic future block';
END $$;
DO $$ DECLARE d date:=current_date+40; BEGIN
 PERFORM pg_temp.add_folga(601,d,7,'00000000-0000-0000-0000-000000000061');
 UPDATE ro_passagem_solicitacoes SET status='cancelada' WHERE id='00000000-0000-0000-0000-000000000601';
 PERFORM pg_temp.add_folga(602,d,7,'00000000-0000-0000-0000-000000000061');
 PERFORM pg_temp.expect_error('UPDATE ro_passagem_solicitacoes SET status=''solicitada'' WHERE id=''00000000-0000-0000-0000-000000000601''','FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.add_folga(603,d,7,'00000000-0000-0000-0000-000000000063');
 UPDATE ro_passagem_solicitacoes SET status='recusada' WHERE id='00000000-0000-0000-0000-000000000603';
 PERFORM pg_temp.expect_error('UPDATE ro_passagem_solicitacoes SET status=''solicitada'' WHERE id=''00000000-0000-0000-0000-000000000603''','SOLICITACAO_RECUSADA_IMUTAVEL');
 RAISE NOTICE 'PASS cancelled/reactivation and refused terminal';
END $$;
