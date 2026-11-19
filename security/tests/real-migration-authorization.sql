\set ON_ERROR_STOP on
\i security/tests/real-schema-fixture.sql
\i security/desligamento_confidencialidade.sql
-- Check no recursive policy evaluation for documents.
DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid
 WHERE p.polname LIKE 'ro_confidential_%';
 IF n<>9 THEN RAISE EXCEPTION 'Expected nine confidentiality policies, got %',n; END IF;
 IF (SELECT count(*) FROM public.test_rpc_snapshot)<>7 THEN RAISE EXCEPTION 'Missing original RPCs'; END IF;
 RAISE NOTICE 'PASS migration: nine policies and seven original RPCs';
END $$;
-- Synthetic user IDs, never production identities.
INSERT INTO public.ro_responsaveis(user_id,ativo) VALUES
 ('00000000-0000-0000-0000-000000000002',true),
 ('00000000-0000-0000-0000-000000000003',true),
 ('00000000-0000-0000-0000-000000000004',false);
INSERT INTO public.ro_passagem_solicitacoes(id,motivo,solicitante_id,status,created_at,excluida_em)
VALUES
 ('10000000-0000-0000-0000-000000000001','desligamento','00000000-0000-0000-0000-000000000001','em_analise',now(),null),
 ('10000000-0000-0000-0000-000000000002','desligamento','00000000-0000-0000-0000-000000000001','cancelada',now(),null),
 ('10000000-0000-0000-0000-000000000003','desligamento','00000000-0000-0000-0000-000000000001','cancelada',now(),now()),
 ('10000000-0000-0000-0000-000000000004','ferias','00000000-0000-0000-0000-000000000001','em_analise',now(),null);
INSERT INTO public.ro_passagem_custos(id,solicitacao_id,tipo,valor,descricao,created_at)
VALUES ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','refeicao',100,'test',now());
INSERT INTO public.ro_passagem_documentos_internos(id,solicitacao_id,storage_path,created_by)
VALUES ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/doc.pdf','00000000-0000-0000-0000-000000000005');
INSERT INTO storage.objects(id,bucket_id,name) VALUES
 ('40000000-0000-0000-0000-000000000001','ro-documentos-internos','10000000-0000-0000-0000-000000000001/doc.pdf'),
 ('40000000-0000-0000-0000-000000000002','ro-passagem-anexos','10000000-0000-0000-0000-000000000001/ticket.pdf');
CREATE FUNCTION pg_temp.assert_case(p_user uuid,p_visible int,p_docs int,p_storage int,p_cost int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE n int; d int; s int; c int; allowed boolean;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT count(*) INTO n FROM public.ro_passagem_solicitacoes;
 SELECT count(*) INTO d FROM public.ro_passagem_documentos_internos;
 SELECT count(*) INTO s FROM storage.objects;
 SELECT count(*) INTO c FROM public.ro_passagem_custos;
 SELECT public.ro_desligamento_autorizado('10000000-0000-0000-0000-000000000001') INTO allowed;
 EXECUTE 'RESET ROLE';
 IF n<>p_visible OR d<>p_docs OR s<>p_storage OR c<>p_cost THEN
  RAISE EXCEPTION 'user %, actual %,%,%,% expected %,%,%,%',p_user,n,d,s,c,p_visible,p_docs,p_storage,p_cost;
 END IF;
 IF allowed IS DISTINCT FROM (p_docs=1) THEN RAISE EXCEPTION 'helper mismatch for %',p_user; END IF;
 RAISE NOTICE 'PASS RLS/Storage user %, request %, doc %, storage %, costs %',p_user,n,d,s,c;
END $$;
BEGIN;
SELECT pg_temp.assert_case('00000000-0000-0000-0000-000000000001',4,1,2,1);
SELECT pg_temp.assert_case('00000000-0000-0000-0000-000000000002',4,1,2,1);
SELECT pg_temp.assert_case('00000000-0000-0000-0000-000000000003',4,1,2,1);
SELECT pg_temp.assert_case('00000000-0000-0000-0000-000000000004',1,0,0,0);
SELECT pg_temp.assert_case('00000000-0000-0000-0000-000000000005',1,0,0,0);
ROLLBACK;
\i security/desligamento_confidencialidade_rollback.sql
DO $$
DECLARE mismatches int;
BEGIN
 SELECT count(*) INTO mismatches FROM public.test_rpc_snapshot t
 JOIN pg_proc p ON p.proname=t.proname
 JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
 WHERE md5(pg_get_functiondef(p.oid))<>t.signature;
 IF mismatches<>0 THEN RAISE EXCEPTION 'Rollback RPC definitions differ: %',mismatches; END IF;
 IF EXISTS(SELECT 1 FROM pg_policy WHERE polname LIKE 'ro_confidential_%')
 THEN RAISE EXCEPTION 'Rollback left policies'; END IF;
 IF to_regprocedure('public.ro_desligamento_autorizado(uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'Rollback left helper'; END IF;
 RAISE NOTICE 'PASS rollback: seven original RPCs restored, nine policies and helper removed';
END $$;
