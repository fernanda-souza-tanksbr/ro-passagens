-- Fail closed: full production-compatible authorization and allocation schema not yet reconstructed.
-- Do not introduce permissive stubs. This file must be replaced with faithful dependencies.
DO $$ BEGIN RAISE EXCEPTION 'RPC_FIXTURE_INCOMPLETA: auth.users, alocacoes, centro de custo, aprovadores, storage e triggers operacionais pendentes'; END $$;
