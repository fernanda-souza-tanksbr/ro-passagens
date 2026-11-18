import assert from "node:assert/strict";
import test from "node:test";
import { montarCsvCentrosCusto } from "../src/relatoriosCsv.ts";
import { defaultReportViewState, hasSpecificReportFilters, namesByReportCenter } from "../src/relatoriosPersistence.ts";
import { resolveSolicitacaoFuncionarioNome } from "../src/solicitacaoColaborador.ts";
const line = { centro_custo_id:"a",compradas:2,abertas:1,imprevistos:3,valor_total:1250.75 };
const labels=()=> 'Centro "A"; Obras';
const rows=(csv:string)=>csv.slice(1).split("\r\n").map(x=>x.match(/"(?:[^"]|"")*"/g)?.map(v=>v.slice(1,-1).replaceAll('""','"')));
test("CSV inclui Funcionários após centro de custo, nomes múltiplos e escape Excel",()=>{
  const csv=montarCsvCentrosCusto([line],labels,new Map([["a",['Ana, Silva','Bia "Teste"; RO']]]),true);
  assert.equal(csv.charCodeAt(0),0xfeff);
  const [head,row]=rows(csv);
  assert.deepEqual(head,["Centro de custo","Funcionários","Compradas","Em aberto","Imprevistos/complementares","Valor total"]);
  assert.deepEqual(row,['Centro "A"; Obras','Ana, Silva, Bia "Teste"; RO',"2","1","3","1250.75"]);
  assert.match(csv,/\r\n/);
  assert.match(csv,/;"Ana, Silva, Bia ""Teste""; RO";/);
});
test("CSV sem filtro específico mantém coluna vazia e preserva ordem e valores",()=>{
  const d=defaultReportViewState().aplicados;
  assert.equal(hasSpecificReportFilters(d),false);
  const csv=montarCsvCentrosCusto([line,{...line,centro_custo_id:null,valor_total:0}],labels,new Map([["a",["Privado"]]]),hasSpecificReportFilters(d));
  const [,a,b]=rows(csv);
  assert.equal(a?.[1],"");assert.equal(b?.[1],"");assert.equal(a?.[5],"1250.75");assert.equal(b?.[5],"0.00");
});
test("CSV usa nomes agrupados e deduplicados respeitando filtros aplicados",()=>{
  const f={...defaultReportViewState().aplicados,status:"em_andamento",motivo:"ferias",responsavel:"11111111-1111-1111-1111-111111111111",centro:"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"};
  const p={id:"p",obra_id:f.centro,status:f.status,motivo:f.motivo,responsavel_ro_id:f.responsavel,colaborador_id:"privado"};
  const m={id:"m",obra_id:f.centro,status:f.status,motivo:f.motivo,responsavel_ro_id:f.responsavel,viajante_nome_informado:"MANUAL"};
  const excluded={...m,id:"x",motivo:"outros"};
  const groups=namesByReportCenter([{centro_custo_id:f.centro,solicitacao:p}],[p,m,excluded],f,{p:"PRIVADO"},resolveSolicitacaoFuncionarioNome);
  assert.deepEqual(groups.get(f.centro),["MANUAL","PRIVADO"]);
  const csv=montarCsvCentrosCusto([{...line,centro_custo_id:f.centro}],labels,groups,hasSpecificReportFilters(f));
  assert.equal(rows(csv)[1]?.[1],"MANUAL, PRIVADO");
});
