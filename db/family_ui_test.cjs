const fs=require('fs'),vm=require('vm'),assert=require('assert');
const source=fs.readFileSync('family.js','utf8');
new vm.Script(source);
const fixed='2026-09-14T00:00:00Z';
const base={now:fixed,ready_at:fixed,can_marry:true,marriage:null,requests:[],parents:[],history:[]};
async function page(snapshot,signedIn=true,error=null){
 const els=new Map();const element=id=>{if(!els.has(id))els.set(id,{textContent:'',innerHTML:'',className:'',addEventListener(){},querySelectorAll:()=>[]});return els.get(id);};
 const calls=[];
 const client={auth:{getSession:async()=>({data:{session:signedIn?{}:null}})},rpc:(name,args)=>({abortSignal:async()=>{calls.push({name,args});return {data:snapshot,error}}})};
 const ctx={document:{getElementById:element,hidden:false,addEventListener(){}},window:{supabase:{createClient:()=>client},addEventListener(){}},console,AbortSignal,setTimeout:()=>0,setInterval:()=>0,FormData,confirm:()=>true};
 vm.createContext(ctx);vm.runInContext(source,ctx);await new Promise(r=>setImmediate(r));return {ctx,els,calls};
}
(async()=>{
 let p=await page(base);assert(p.els.get('content').innerHTML.includes('propose-form'));assert(!p.els.get('content').innerHTML.includes('id="partner-panel"'));assert(p.els.get('content').innerHTML.includes('privacy-propose'));
 p=await page(base,false);assert(p.els.get('content').innerHTML.includes('Войти через Telegram'));assert.equal(p.calls.length,0);
 p=await page(base,true,{message:'Test RPC failure'});assert(p.els.get('content').innerHTML.includes('Test RPC failure'));assert(!p.els.get('content').innerHTML.includes('Загружаем'));
 const married={...base,can_marry:false,marriage:{id:'fixture',registered_at:fixed,can_divorce:false,divorce_at:fixed,can_invite_child:false,next_child_at:fixed,children:[],partner:{nickname:'<script>alert(1)</script>',number:'123',status:'active',first_name:'Hidden first',surname:'Hidden last',birth_day:1,birth_month:1,birth_year:null,member_since:fixed}}};
 p=await page(married);assert.equal(p.els.get('title').textContent,'Моя семья');let html=p.els.get('content').innerHTML;assert(html.includes('Hidden first'));assert(!html.includes('<script>alert'));assert(html.includes('data-action="divorce" data-id="fixture" disabled'));
 vm.runInContext("tab='children';render()",p.ctx);html=p.els.get('content').innerHTML;assert(html.includes('id="children-panel" role="tabpanel" aria-labelledby="tab-children" >'));
 vm.runInContext('data='+JSON.stringify({...base,can_marry:false,history:[{partner:'Former spouse',registered_at:fixed,divorced_at:fixed,children:['Child']} ]})+';render()',p.ctx);
 html=p.els.get('content').innerHTML;assert(!html.includes('Hidden first'));assert(html.includes('История семей'));assert.equal(p.els.get('title').textContent,'Браки');
 const invitation={...base,requests:[{id:'r1',kind:'marriage',proposer:'P',proposer_number:'1',recipient:'R',recipient_number:'2',can_accept:true,mine:false,expires_at:fixed}]};
 p=await page(invitation);assert(p.els.get('content').innerHTML.includes('consent-r1'));assert(p.els.get('content').innerHTML.includes('Согласиться на брак'));
 console.log('PASS: signed-out, RPC error, marriage/family transition, spouse data, children tab, divorce privacy, consent, HTML escaping.');
})().catch(e=>{console.error(e);process.exitCode=1});
