import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const sql = (name: string) => readFileSync(`docs/sql/folga-campo-${name}-RASCUNHO.sql`,"utf8");
const episodio=sql("04-episodio-transacional");
const contexto=sql("08-contexto-privado-transacional");
const criacao=sql("09-rpc-criacao-coordenada");
const ciclo=sql("10-trigger-ciclo-coordenado");
const protecao=sql("11-auditoria-guard-status");

test("sequencia transacional: episodio, contexto, criacao legada, conferência e limpeza",()=>{
  const indices=[
    criacao.indexOf("ro_private.preparar_episodio_folga("),
    criacao.indexOf("insert into ro_private.folga_criacao_contexto("),
    criacao.indexOf("public.ro_criar_solicitacao_com_aprovador("),
    criacao.indexOf("SNAPSHOT_FOLGA_NAO_APLICADO"),
    criacao.indexOf("delete from ro_private.folga_criacao_contexto")
  ];
  assert.ok(indices.every(x=>x>=0),`Etapa ausente: ${indices}`);
  assert.deepEqual(indices,[...indices].sort((a,b)=>a-b));
  assert.match(criacao,/if v_criado is distinct from v_id then[\s\S]*ID_CRIACAO_DIVERGENTE/);
});

test("episodio compartilha advisory lock e so troca CC dentro da mesma transacao",()=>{
  assert.match(episodio,/pg_advisory_xact_lock\([\s\S]*hashtextextended\(p_funcionario_id::text, 904\)/);
  assert.match(ciclo,/pg_advisory_xact_lock\([\s\S]*hashtextextended\(new.funcionario_id::text,904\)/);
  assert.match(episodio,/for update/);
  assert.match(episodio,/CONFIRMACAO_RETORNO_OBRIGATORIA/);
  assert.match(episodio,/CORRECAO_SOMENTE_POR_RPC_AUTORIZADA/);
});

test("contexto privado nao confia em configuracao local de sessao para autorizacao",()=>{
  assert.match(contexto,/revoke all on ro_private\.folga_criacao_contexto from public, anon, authenticated/);
  assert.doesNotMatch(criacao,/set_config\s*\(\s*'ro\.folga/i);
  assert.match(ciclo,/solicitacao_id=new\.id[\s\S]*funcionario_id=new\.funcionario_id[\s\S]*obra_id=new\.obra_id[\s\S]*criado_por=auth\.uid\(\)/);
});

test("a auditoria faz branch de INSERT antes de usar OLD",()=>{
  const fn=protecao.split("create or replace function public.ro_auditar_ciclo_folga_campo()")[1]?.split("$$;")[0];
  assert.ok(fn);
  assert.match(fn,/if tg_op='INSERT' then[\s\S]*elsif tg_op='UPDATE' then[\s\S]*old\.status/);
  const insert=fn.split("elsif tg_op='UPDATE' then")[0];
  assert.doesNotMatch(insert,/old\./i);
});

test("guarda de snapshot cobre qualquer UPDATE e previne alteracao historica",()=>{
  assert.match(protecao,/create trigger ro_guardar_snapshot_folga\s+before update on public\.ro_passagem_solicitacoes/);
  for(const campo of ["folga_alocacao_id","folga_distancia_km","folga_regime_faixa","folga_intervalo_dias","funcionario_id","obra_id"]){
    assert.match(protecao,new RegExp(`new\\.${campo} is distinct from old\\.${campo}`));
  }
  assert.match(protecao,/SNAPSHOT_FOLGA_IMUTAVEL/);
});

test("atualizacao isolada de status preserva previsao, aprovacao e snapshot",()=>{
  assert.match(ciclo,/if tg_op='UPDATE'[\s\S]*new\.folga_data_prevista_ciclo:=old\.folga_data_prevista_ciclo/);
  assert.match(ciclo,/new\.folga_ciclo_anterior_id:=old\.folga_ciclo_anterior_id/);
  assert.match(ciclo,/new\.folga_antecipada:=old\.folga_antecipada/);
  assert.match(ciclo,/old\.status is distinct from 'recusada'[\s\S]*new\.folga_antecipacao_status:='recusada'/);
});

test("novo ciclo exige historico aprovado e finalizado; legado permanece",()=>{
  assert.match(ciclo,/s\.status='finalizada'[\s\S]*s\.aprovacao_status in \('aprovada','dispensada'\)/);
  assert.match(ciclo,/public\.ro_obter_ciclo_folga_funcionario\(new\.funcionario_id\)/);
  assert.match(criacao,/revoke all on function public\.ro_criar_folga_campo_com_distancia/);
});
