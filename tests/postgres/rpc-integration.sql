\set ON_ERROR_STOP on
-- This test must call the actual production RPC. Never claim a pass without its execution.
DO $$ BEGIN RAISE EXCEPTION 'RPC_INTEGRATION_NOT_IMPLEMENTED: full-chain assertions and concurrency pending'; END $$;
