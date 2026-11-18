import test from "node:test";
import assert from "node:assert/strict";
import { fimEfetivoFolga, periodosFolgaConflitam, podePlanejarOutraFolgaSemanal } from "../src/folgaCampoPlanejamento.ts";
const folga=(data_ida:string,data_retorno:string|null=null,retorno_indefinido=false)=>({data_ida,data_retorno,retorno_indefinido});
test("quatro semanas independentes e fora da ordem cronologica",()=>{const semanas=["2026-12-22","2026-12-01","2026-12-15","2026-12-08"].map(d=>folga(d));for(let i=0;i<semanas.length;i++)for(let j=i+1;j<semanas.length;j++)assert.equal(periodosFolgaConflitam(semanas[i],semanas[j]),false);});
test("mesma data e sobreposicao parcial ou total bloqueiam",()=>{assert.equal(periodosFolgaConflitam(folga("2026-12-01"),folga("2026-12-01")),true);assert.equal(periodosFolgaConflitam(folga("2026-12-01","2026-12-05"),folga("2026-12-05","2026-12-08")),true);assert.equal(periodosFolgaConflitam(folga("2026-12-01","2026-12-10"),folga("2026-12-03","2026-12-04")),true);assert.equal(periodosFolgaConflitam(folga("2026-12-01","2026-12-05"),folga("2026-12-06")),false);});
test("retorno indefinido considera apenas ida mesmo quando retorno preenchido",()=>{const p=folga("2026-12-01","2027-01-01",true);assert.equal(fimEfetivoFolga(p),"2026-12-01");assert.equal(periodosFolgaConflitam(p,folga("2026-12-08")),false);assert.equal(fimEfetivoFolga(folga("2026-12-01",null)),"2026-12-01");});
test("somente regime semanal pode passar pelo bloqueio generico",()=>{assert.equal(podePlanejarOutraFolgaSemanal(null),false);assert.equal(podePlanejarOutraFolgaSemanal(-1),false);});
