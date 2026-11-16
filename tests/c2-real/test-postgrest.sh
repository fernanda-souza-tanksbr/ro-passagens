#!/usr/bin/env bash
set -euo pipefail
BASE=http://127.0.0.1:3000
# Token ficticio assinado no runner: verifica a validacao JWT do PostgREST real.
TOKEN=$(node - <<'JS'
const crypto=require('crypto');
const secret=process.env.JWT_SECRET;
const enc=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const head=enc({alg:'HS256',typ:'JWT'});
const body=enc({sub:'00000000-0000-0000-0000-000000000001',role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+3600});
console.log(head+'.'+body+'.'+crypto.createHmac('sha256',secret).update(head+'.'+body).digest('base64url'));
JS
)
call() { curl -sS -o /tmp/c2-response.json -w '%{http_code}' -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -X POST "$BASE/rpc/$1" -d "$2"; }
status=$(curl -sS -o /tmp/c2-anon.json -w '%{http_code}' -H 'Content-Type: application/json' -X POST "$BASE/rpc/ro_consultar_contexto_distancia_folga" -d '{"p_funcionario_id":"00000000-0000-0000-0000-000000000101","p_obra_id":"00000000-0000-0000-0000-000000000201"}')
test "$status" = 401 || test "$status" = 403
status=$(call ro_consultar_contexto_distancia_folga '{"p_funcionario_id":"00000000-0000-0000-0000-000000000101","p_obra_id":"00000000-0000-0000-0000-000000000201"}')
test "$status" = 400
grep -q FOLGA_CAMPO_KM_AINDA_DESATIVADO /tmp/c2-response.json
# Ativacao somente na base ficticia, nunca na producao.
psql -X -v ON_ERROR_STOP=1 -c "update ro_private.folga_configuracao set ativo=true where chave='novo_fluxo_distancia'"
status=$(call ro_consultar_contexto_distancia_folga '{"p_funcionario_id":"00000000-0000-0000-0000-000000000101","p_obra_id":"00000000-0000-0000-0000-000000000201"}')
test "$status" = 200
grep -q '"estado":"informar"' /tmp/c2-response.json
status=$(call ro_criar_folga_campo_com_distancia '{"p_solicitacao":{"id":"00000000-0000-0000-0000-000000000951","funcionario_id":"00000000-0000-0000-0000-000000000101","obra_id":"00000000-0000-0000-0000-000000000201","motivo":"folga_campo","data_ida":"2027-12-01"},"p_documentos":[],"p_distancia_km":220,"p_confirmacao_retorno":false}')
test "$status" = 200
grep -q '00000000-0000-0000-0000-000000000951' /tmp/c2-response.json
test "$(psql -X -Atc "select folga_distancia_km from public.ro_passagem_solicitacoes where id='00000000-0000-0000-0000-000000000951'")" = 220
# Aba antiga: endpoint legado autentico deve ser recusado pelo gatilho B.
status=$(call ro_criar_solicitacao_com_aprovador '{"p_solicitacao":{"id":"00000000-0000-0000-0000-000000000952","funcionario_id":"00000000-0000-0000-0000-000000000102","obra_id":"00000000-0000-0000-0000-000000000201","motivo":"folga_campo","data_ida":"2027-12-02"},"p_documentos":[]}')
test "$status" = 400
grep -q FOLGA_CAMPO_DISTANCIA_OBRIGATORIA_NOVO_FLUXO /tmp/c2-response.json
# Outros motivos seguem operacionais no endpoint legado.
status=$(call ro_criar_solicitacao_com_aprovador '{"p_solicitacao":{"id":"00000000-0000-0000-0000-000000000953","funcionario_id":"00000000-0000-0000-0000-000000000102","obra_id":"00000000-0000-0000-0000-000000000201","motivo":"ferias","data_ida":"2027-12-02"},"p_documentos":[]}')
test "$status" = 200
echo 'C2_POSTGREST_REAL_JWT_RLS_RPC_GATE_LEGADO_OK'
