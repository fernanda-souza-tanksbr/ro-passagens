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
