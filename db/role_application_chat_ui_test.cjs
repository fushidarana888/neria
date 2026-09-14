const fs=require('fs'),vm=require('vm'),assert=require('assert');const tick=()=>new Promise(r=>setImmediate(r));
function el(){return {innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,open:false,scrollHeight:100,scrollTop:0,clientHeight:100,events:{},addEventListener(n,f){this.events[n]=f},showModal(){this.open=true},close(){this.open=false;this.events.close?.()}};}
(async()=>{
 const nodes=new Map(),dlg=el();dlg.querySelector=id=>{if(!nodes.has(id))nodes.set(id,el());return nodes.get(id);};const get=id=>nodes.get('#'+id);
 const calls=[];let rows=[],denied=false,failSend=false;
 const client={rpc:(name,args)=>({abortSignal:async()=>{calls.push({name,args});if(denied)return {error:{message:'Access denied'}};if(name==='send_role_application_message'){if(failSend)return {error:{message:'Network failure'}};rows=[{id:'1',mine:true,founder:false,body:args.p_body,created_at:'2026-09-14T00:00:00Z'}];return {data:{id:'1'}};}return {data:{role:'journalist',applicant:'Test',statement:'Private statement',status:'pending',review_note:null,messages:rows,oldest:rows[0]?.id,has_more:false}};}})};
 const context={sb:client,document:{createElement:t=>t==='dialog'?dlg:el(),head:{appendChild(){}},body:{appendChild(){}},hidden:false},window:{},location:{search:''},URLSearchParams,AbortSignal,crypto:require('crypto').webcrypto,setInterval(){}};
 vm.runInNewContext(fs.readFileSync('role-application-chat.js','utf8'),context);
 await context.window.openRoleApplicationChat('123');assert.equal(dlg.open,true);assert.equal(calls[0].args.p_application_id,'123');assert.equal(get('roleChatStatement').textContent,'Private statement');
 get('roleChatText').value='<img src=x onerror=alert(1)>';failSend=true;await get('roleChatForm').events.submit({preventDefault(){}});const first=calls.find(c=>c.name==='send_role_application_message');assert(get('roleChatError').textContent.includes('Network failure'));assert(get('roleChatText').value.length>0);
 failSend=false;await get('roleChatForm').events.submit({preventDefault(){}});const sends=calls.filter(c=>c.name==='send_role_application_message');assert.equal(sends[0].args.p_nonce,sends[1].args.p_nonce);assert.equal(get('roleChatText').value,'');assert(!get('roleChatMessages').innerHTML.includes('<img'));assert(get('roleChatMessages').innerHTML.includes('&lt;img'));
 denied=true;await context.window.openRoleApplicationChat('456');assert.equal(get('roleChatError').textContent,'Access denied');assert(!get('roleChatMessages').innerHTML.includes('Private statement'));
 console.log('PASS: application-specific chat, failed-send draft retention, idempotency nonce reuse, HTML escaping, access errors.');
})().catch(e=>{console.error(e);process.exitCode=1});
