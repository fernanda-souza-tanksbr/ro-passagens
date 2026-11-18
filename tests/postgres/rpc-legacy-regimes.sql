\set ON_ERROR_STOP on
-- Legacy regimes through actual production RPC; separate synthetic employees.
DO $regression$
DECLARE
  d date := current_date + 180;
  r record;
  v_employee uuid;
  v_first uuid;
  v_second uuid;
  v_payload jsonb;
  v_rejected boolean;
BEGIN
  FOR r IN SELECT * FROM (VALUES (14,350,814),(45,700,845),(90,1100,890)) AS x(interval_days,km,employee_num)
  LOOP
    v_employee := ('00000000-0000-0000-0000-'||lpad(r.employee_num::text,12,'0'))::uuid;
    INSERT INTO public.funcionarios(id,nome) VALUES (v_employee,'Funcionario ficticio regime '||r.interval_days);
    IF (SELECT intervalo_dias FROM ro_private.regime_folga_km(r.km)) <> r.interval_days THEN
      RAISE EXCEPTION 'Regime mismatch: %',r.interval_days;
    END IF;
    v_first := ('00000000-0000-0000-0000-'||lpad((1000+r.employee_num)::text,12,'0'))::uuid;
    v_second := ('00000000-0000-0000-0000-'||lpad((2000+r.employee_num)::text,12,'0'))::uuid;
    v_payload := jsonb_build_object('id',v_first,'motivo','folga_campo','funcionario_id',v_employee,
      'obra_id','00000000-0000-0000-0000-000000000899','data_ida',d,
      'pix_viajante','PIX-FICTICIO','origem','Origem ficticia','destino','Destino ficticio',
      'aprovador_id','00000000-0000-0000-0000-000000000001');
    PERFORM public.ro_criar_folga_campo_com_distancia(v_payload,'[]'::jsonb,r.km,false);
    IF NOT EXISTS (SELECT 1 FROM public.ro_passagem_solicitacoes
       WHERE id=v_first AND folga_intervalo_dias=r.interval_days) THEN
      RAISE EXCEPTION 'Regime snapshot incorrect for %',r.interval_days;
    END IF;
    v_rejected := false;
    BEGIN
      PERFORM public.ro_criar_folga_campo_com_distancia(
        jsonb_set(jsonb_set(v_payload,'{id}',to_jsonb(v_second::text)),
          '{data_ida}',to_jsonb((d+30)::text)),'[]'::jsonb,r.km,false);
    EXCEPTION WHEN OTHERS THEN
      IF position('FOLGA_FUTURA_DUPLICADA' in SQLERRM)=0 THEN RAISE; END IF;
      v_rejected := true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'Legacy regime % allowed second future request',r.interval_days; END IF;
    RAISE NOTICE 'PASS RPC legacy regime %: first accepted, second future request rejected',r.interval_days;
  END LOOP;
END $regression$;
