\set ON_ERROR_STOP on
-- Real RPC calls, not direct inserts. Synthetic identities, no external I/O.
CREATE OR REPLACE FUNCTION pg_temp.rpc_create(p_num integer,p_day date,p_km integer DEFAULT 100,p_employee uuid DEFAULT '00000000-0000-0000-0000-000000000801',p_private uuid DEFAULT NULL,p_end date DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid:=('00000000-0000-0000-0000-'||lpad(p_num::text,12,'0'))::uuid; v_payload jsonb;
BEGIN
 v_payload:=jsonb_build_object('id',v_id,'motivo','folga_campo','obra_id','00000000-0000-0000-0000-000000000899','data_ida',p_day,'pix_viajante','PIX-FICTICIO','origem','Origem ficticia','destino','Destino ficticio','aprovador_id','00000000-0000-0000-0000-000000000001');
 IF p_employee IS NOT NULL THEN v_payload:=v_payload||jsonb_build_object('funcionario_id',p_employee); END IF;
 IF p_private IS NOT NULL THEN v_payload:=v_payload||jsonb_build_object('colaborador_id',p_private); END IF;
 IF p_end IS NOT NULL THEN v_payload:=v_payload||jsonb_build_object('data_retorno',p_end); END IF;
 RETURN public.ro_criar_folga_campo_com_distancia(v_payload,'[]'::jsonb,p_km,false);
END $$;
CREATE OR REPLACE FUNCTION pg_temp.rpc_expect_error(p_sql text,p_error text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_failed boolean:=false;
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF position(p_error in SQLERRM)=0 THEN RAISE; END IF;
  v_failed:=true;
 END;
 IF NOT v_failed THEN RAISE EXCEPTION 'RPC expected %, but succeeded',p_error; END IF;
END $$;
DO $$ DECLARE d date:=current_date+100; v_id uuid; BEGIN
 PERFORM pg_temp.rpc_create(901,d+21);
 PERFORM pg_temp.rpc_create(902,d);
 PERFORM pg_temp.rpc_create(903,d+14);
 PERFORM pg_temp.rpc_create(904,d+7);
 IF (SELECT count(*) FROM public.ro_passagem_solicitacoes WHERE funcionario_id='00000000-0000-0000-0000-000000000801')<>4 THEN RAISE EXCEPTION 'RPC four weeks failed'; END IF;
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(905,%L::date)',d),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.rpc_create(906,d+40,100,'00000000-0000-0000-0000-000000000801',NULL,d+43);
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(907,%L::date)',d+42),'FOLGA_FUTURA_DUPLICADA');
 RAISE NOTICE 'PASS RPC four weekly requests, out-of-order, duplicate and overlap';
END $$;

-- Linked private identity: same employee is canonical; invalid identity rejected.
INSERT INTO public.ro_funcionarios_enderecos_privados(id,funcionario_id,ativo,nome)
 VALUES ('00000000-0000-0000-0000-000000000881','00000000-0000-0000-0000-000000000801',true,'Privado Vinculado Ficticio');
-- The real private-access predicate must grant an active operator and deny an unprivileged user.
DO $body$ BEGIN
 IF public.ro_can_view_private_addresses(auth.uid()) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Expected authorized private-access operator';
 END IF;
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',false);
 IF public.ro_can_view_private_addresses(auth.uid()) IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Unprivileged user unexpectedly authorized';
 END IF;
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(915,%L::date,100,NULL,%L::uuid)',current_date+150,'00000000-0000-0000-0000-000000000881'),'COLABORADOR_PRIVADO_ACESSO_NEGADO');
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',false);
 RAISE NOTICE 'PASS private-access authorization: operator allowed, unprivileged user denied';
END $body$;
DO $body$ DECLARE d date:=current_date+100; BEGIN
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(911,%L::date,100,NULL,%L::uuid)',d,'00000000-0000-0000-0000-000000000881'),'FOLGA_FUTURA_DUPLICADA');
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(912,%L::date,100,%L::uuid,%L::uuid)',d+35,'00000000-0000-0000-0000-000000000802','00000000-0000-0000-0000-000000000881'),'VINCULO_FUNCIONARIO_INCONSISTENTE');
 PERFORM pg_temp.rpc_expect_error(format('SELECT pg_temp.rpc_create(913,%L::date,100,%L::uuid)',d+35,'00000000-0000-0000-0000-000000000888'),'FUNCIONARIO_INDISPONIVEL');
END $$;

-- Positive RPC path with authorized linked private identity and independent private identity.
INSERT INTO public.ro_funcionarios_enderecos_privados(id,funcionario_id,ativo,nome)
 VALUES ('00000000-0000-0000-0000-000000000882',NULL,true,'Privado Independente Ficticio');
DO $$ DECLARE d date:=current_date+100; v uuid; BEGIN
 v:=pg_temp.rpc_create(916,d+55,100,NULL,'00000000-0000-0000-0000-000000000881');
 IF NOT EXISTS (SELECT 1 FROM public.ro_passagem_solicitacoes WHERE id=v AND funcionario_id='00000000-0000-0000-0000-000000000801') THEN
  RAISE EXCEPTION 'Linked private RPC identity was not normalized';
 END IF;
 v:=pg_temp.rpc_create(917,d+60,100,NULL,'00000000-0000-0000-0000-000000000882');
 IF NOT EXISTS (SELECT 1 FROM public.ro_passagem_solicitacoes WHERE id=v AND colaborador_id='00000000-0000-0000-0000-000000000882') THEN
  RAISE EXCEPTION 'Independent private RPC identity was not preserved';
 END IF;
 RAISE NOTICE 'PASS authorized linked and independent private RPC creation';
END $$;
