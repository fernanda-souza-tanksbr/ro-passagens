\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid primary key, active boolean not null);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE public.ro_responsaveis(user_id uuid, ativo boolean);
CREATE TABLE public.ro_passagem_solicitacoes(id uuid primary key, motivo text, solicitante_id uuid, excluida_em timestamptz);
ALTER TABLE public.ro_passagem_solicitacoes ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public,auth TO authenticated;
GRANT SELECT ON public.ro_passagem_solicitacoes TO authenticated;
CREATE FUNCTION public.ro_can_operate() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.ro_responsaveis WHERE user_id=auth.uid() AND ativo)
$$;
CREATE FUNCTION public.ro_is_active_internal_user() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM auth.users WHERE id=auth.uid() AND active)
$$;
CREATE POLICY existing_all ON public.ro_passagem_solicitacoes FOR ALL TO authenticated USING (true) WITH CHECK(true);
CREATE POLICY confidential_read ON public.ro_passagem_solicitacoes AS RESTRICTIVE FOR SELECT TO authenticated
 USING (motivo IS DISTINCT FROM 'desligamento' OR
 (public.ro_is_active_internal_user() AND (solicitante_id=auth.uid() OR public.ro_can_operate())));
INSERT INTO auth.users VALUES
 ('00000000-0000-0000-0000-000000000001',true),
 ('00000000-0000-0000-0000-000000000002',true),
 ('00000000-0000-0000-0000-000000000003',true),
 ('00000000-0000-0000-0000-000000000004',true);
INSERT INTO public.ro_responsaveis VALUES ('00000000-0000-0000-0000-000000000002',true);
INSERT INTO public.ro_passagem_solicitacoes VALUES
 ('10000000-0000-0000-0000-000000000001','desligamento','00000000-0000-0000-0000-000000000001',null),
 ('10000000-0000-0000-0000-000000000002','desligamento','00000000-0000-0000-0000-000000000001',now()),
 ('10000000-0000-0000-0000-000000000003','ferias','00000000-0000-0000-0000-000000000001',null);
CREATE FUNCTION pg_temp.assert_visible(p_user uuid,p_expected int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p_user::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 SELECT count(*) INTO n FROM public.ro_passagem_solicitacoes;
 EXECUTE 'RESET ROLE';
 IF n<>p_expected THEN RAISE EXCEPTION 'User %, expected %, got %',p_user,p_expected,n; END IF;
 RAISE NOTICE 'PASS user %, visible %',p_user,n;
END $$;
SELECT pg_temp.assert_visible('00000000-0000-0000-0000-000000000001',3);
SELECT pg_temp.assert_visible('00000000-0000-0000-0000-000000000002',3);
SELECT pg_temp.assert_visible('00000000-0000-0000-0000-000000000003',1);
SELECT pg_temp.assert_visible('00000000-0000-0000-0000-000000000004',1);
ROLLBACK;
