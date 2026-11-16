import { expect, test, type Page, type Route } from "@playwright/test";

/**
 * Navegador real + App.tsx/pages.tsx + supabase-js real.
 * Apenas respostas HTTP de Auth/PostgREST sao simuladas.
 * Vite e SDK usam endereco loopback; toda rede externa e bloqueada.
 */
const HOST = "http://127.0.0.1:4174";
const USER = "00000000-0000-0000-0000-000000000001";
const FUNC = "00000000-0000-0000-0000-000000000101";
const PRIVATE = "00000000-0000-0000-0000-000000000701";
const LINKED = "00000000-0000-0000-0000-000000000702";
const CC_A = "00000000-0000-0000-0000-000000000201";
const CC_B = "00000000-0000-0000-0000-000000000202";
const STAFF = [
  { id: FUNC, funcionario_id: FUNC, nome: "Funcionário Fictício", obra_id: CC_A, visivel_obras_control: true },
  { id: PRIVATE, funcionario_id: null, nome: "Colaborador Privado Fictício", obra_id: CC_A },
  { id: LINKED, funcionario_id: FUNC, nome: "Colaborador Vinculado Fictício", obra_id: CC_A }
];
const WORKS = [
  { id:CC_A, nome:"Obra A", codigo:"254", descricao:"Obra fictícia A", visivel_passagens:true },
  { id:CC_B, nome:"Obra B", codigo:"243", descricao:"Obra fictícia B", visivel_passagens:true }
];

function jwt() {
  const b64 = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return [b64({alg:"HS256",typ:"JWT"}), b64({sub:USER,role:"authenticated",aud:"authenticated",exp:4102444800,iat:1790000000}), "ficticio"].join(".");
}
const USER_JSON = {id:USER,aud:"authenticated",role:"authenticated",email:"teste@exemplo.invalid",email_confirmed_at:"2026-01-01T00:00:00Z",app_metadata:{provider:"email",providers:["email"]},user_metadata:{full_name:"Operador Fictício"},identities:[],created_at:"2026-01-01T00:00:00Z"};
type Scenario = "first"|"same"|"move"|"return"|"private"|"linked"|"early"|"duplicate"|"denied";
type MockData = { rpc: Array<{name:string;body:Record<string,unknown>}>; loginCalls:number; data:Scenario; activated:boolean; writes:number };
function contextFor(s: Scenario, body:Record<string,unknown>) {
  const c = (s==="private"||s==="linked") ? s==="private" ? PRIVATE:LINKED : null;
  const funcionarioId = s==="private" ? null:FUNC;
  const km = s==="same" ? 420:s==="return" ? 601:s==="early" ? 650:s==="duplicate"?450:null;
  return {
    funcionario_id:funcionarioId,colaborador_id:c,obra_id:body.p_obra_id,
    distancia_km:km,estado:km===null?"informar":s==="return"?"confirmar":"reutilizar",
    retorno_ao_cc:s==="return",
    ultima_folga_data_ida:["same","return","early","duplicate"].includes(s)?"2026-11-01":null,
    proxima_folga_prevista:null,
    solicitacao_futura_existente_id:s==="duplicate"?"00000000-0000-0000-0000-000000000999":null
  };
}
async function fixture(page:Page, data:MockData) {
  await page.route("**/*",async route => {
    const request=route.request(),u=new URL(request.url());
    if(u.hostname!=="127.0.0.1" && u.hostname!=="localhost") return route.abort("blockedbyclient");
    if(u.pathname.startsWith("/auth/v1/")) {
      if(u.pathname==="/auth/v1/token") {
        data.loginCalls++;
        return route.fulfill({status:200,contentType:"application/json",body:JSON.stringify({
          access_token:jwt(),token_type:"bearer",expires_in:7200,expires_at:4102444800,refresh_token:"ficticio",user:USER_JSON
        })});
      }
      if(u.pathname==="/auth/v1/user")return route.fulfill({status:200,contentType:"application/json",body:JSON.stringify(USER_JSON)});
      if(u.pathname==="/auth/v1/logout")return route.fulfill({status:204,body:""});
      throw new Error("AUTH_NAO_SIMULADO:"+u.pathname);
    }
    if(u.pathname.startsWith("/rest/v1/")) {
      let body:Record<string,unknown>={};
      try{body=(request.postDataJSON() ?? {}) as Record<string,unknown>}catch{}
      const name=u.pathname.split("/").pop()||"";
      const rpc=name.startsWith("ro_") && u.pathname.includes("/rpc/");
      if(rpc)data.rpc.push({name,body});
      const results:Record<string,unknown>={
        user_roles:[{role:"coordenador"}],
        users_profiles:{full_name:"Operador Fictício"},
        ro_responsaveis:null,
        ro_listar_minhas_notificacoes:[],
        ro_calendario_nao_util:[],
        ro_calendario_anos:[{ano:2026,completo:true},{ano:2027,completo:true},{ano:2028,completo:true}],
        obras:WORKS,
        ro_catalogo_colaboradores_viagem:STAFF,
        ro_catalogo_centros_custo:WORKS,
        ro_listar_aprovadores:[{id:"00000000-0000-0000-0000-000000000301",label:"Aprovador Fictício"}],
        ro_is_system_admin:false,ro_is_rh_active:false,ro_can_manage_rh:false,ro_is_approval_candidate:false,ro_is_denise:false,
        ro_obter_destino_residencial_resumido:{possui_endereco:false,cidade:null,uf:null},
        ro_obter_destino_colaborador_resumido:{possui_endereco:false,cidade:null,uf:null},
        ro_ultimo_pix_viajante:null,
        ro_consultar_contexto_distancia_folga:null,
        ro_obter_ciclo_folga_funcionario:{possui_historico:false,solicitacao_futura_existente_id:null},
      };
      if(name==="ro_criar_folga_campo_com_distancia"||name==="ro_criar_solicitacao_com_aprovador"){
        data.writes++;
        if(!data.activated)return route.fulfill({status:400,contentType:"application/json",body:JSON.stringify({code:"P0001",message:"FOLGA_CAMPO_KM_AINDA_DESATIVADO"})});
        return route.fulfill({status:200,contentType:"application/json",body:JSON.stringify("00000000-0000-0000-0000-000000000900")});
      }
      if(!Object.hasOwn(results,name))throw new Error("REST_NAO_SIMULADO:"+name);
      const value=name==="ro_consultar_contexto_distancia_folga" ? contextFor(data.data,body) : results[name];
      return route.fulfill({status:200,headers:{"content-type":"application/json","access-control-allow-origin":"*"},body:JSON.stringify(value)});
    }
    if(u.pathname.startsWith("/storage/v1/")||u.pathname.startsWith("/functions/v1/"))throw new Error("SAIDA_NAO_AUTORIZADA:"+u.pathname);
    return route.continue();
  });
}

async function login(page:Page) {
  await page.goto(HOST+"/nova");
  await expect(page.getByText("Portal Tanks BR")).toBeVisible();
  await page.getByLabel("E-mail").fill("teste@exemplo.invalid");
  await page.getByLabel("Senha").fill("senha-ficticia");
  await page.getByRole("button",{name:"Entrar",exact:true}).last().click();
  await expect(page.getByText("Nova solicitação")).toBeVisible({timeout:10000});
}
test("React real: login pelo SDK, redirecionamento e selecao do formulario",async({page})=>{
  const state:MockData={rpc:[],loginCalls:0,data:"first",activated:false,writes:0};
  await fixture(page,state);await login(page);
  expect(state.loginCalls).toBe(1);
  await expect(page.getByText("Funcionário *")).toBeVisible();
  await expect(page.getByLabel("Funcionário *").locator(`option[value="${FUNC}"]`)).toHaveCount(1);
  await page.getByLabel("Funcionário *").selectOption(FUNC);
  await page.getByLabel("Motivo *").selectOption("folga_campo");
  await expect(page.getByLabel("Quilometragem da Folga de Campo")).toBeVisible();
  expect(state.rpc.some(x=>x.name==="ro_catalogo_colaboradores_viagem")).toBe(true);
  expect(state.rpc.some(x=>x.name==="ro_consultar_contexto_distancia_folga")).toBe(true);
  expect(state.writes).toBe(0);
});
for(const [scenario,expected] of [
  ["first","Distância da residência ao centro de custo atual"],
  ["same","Distância registrada para este centro de custo"],
  ["return","Confirmo que esta distância continua correta"],
  ["duplicate","Já existe uma Folga de Campo futura ativa"]
] as const){
 test("React real: contexto ficticio "+scenario,async({page})=>{
  const state:MockData={rpc:[],loginCalls:0,data:scenario,activated:false,writes:0};
  await fixture(page,state);await login(page);
  await page.getByLabel("Funcionário *").selectOption(FUNC);
  await page.getByLabel("Motivo *").selectOption("folga_campo");
  await expect(page.getByText(expected,{exact:false}).first()).toBeVisible();
  expect(state.writes).toBe(0);
 });
}
test("React real: funcionario privado sem vinculo e vinculado",async({page})=>{
 const state:MockData={rpc:[],loginCalls:0,data:"private",activated:false,writes:0};
 await fixture(page,state);await login(page);
 await expect(page.getByLabel("Funcionário *").locator(`option[value="${PRIVATE}"]`)).toHaveCount(1);
 await page.getByLabel("Funcionário *").selectOption(PRIVATE);
 await page.getByLabel("Motivo *").selectOption("folga_campo");
 await page.getByRole("combobox",{name:"Centro de custo atual *"}).fill("254");
 await page.getByRole("option",{name:/254/}).click();
 await expect(page.getByLabel("Quilometragem da Folga de Campo")).toBeVisible();
 expect(state.rpc.some(x=>x.name==="ro_consultar_contexto_distancia_folga" && x.body.p_colaborador_id===PRIVATE)).toBe(true);
 state.data="linked";
 await expect(page.getByLabel("Funcionário *").locator(`option[value="${LINKED}"]`)).toHaveCount(1);
 await page.getByLabel("Funcionário *").selectOption(LINKED);
 await page.getByRole("combobox",{name:"Centro de custo atual *"}).fill("254");
 await page.getByRole("option",{name:/254/}).click();
 await expect(page.getByLabel("Quilometragem da Folga de Campo")).toBeVisible();
 expect(state.rpc.some(x=>x.name==="ro_consultar_contexto_distancia_folga" && x.body.p_colaborador_id===LINKED)).toBe(true);
});
