(()=>{
 'use strict';
 const client=typeof supabaseClient!=='undefined'?supabaseClient:sb;
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const names={economy_minister:'Министр экономики',mvd:'МВД',journalist:'Журналист'};
 const dlg=document.createElement('dialog');dlg.className='role-chat';
 dlg.innerHTML='<div class="role-chat-head"><h2>Переписка по заявке</h2><button type="button" id="roleChatClose" aria-label="Закрыть переписку">Закрыть</button></div><p id="roleChatInfo"></p><details><summary>Текст заявки и решение</summary><p id="roleChatStatement"></p><p id="roleChatReview"></p></details><button type="button" id="roleChatOlder" hidden>Загрузить предыдущие сообщения</button><div id="roleChatMessages" role="log" aria-label="Сообщения по заявке"></div><form id="roleChatForm"><label for="roleChatText">Ваше сообщение</label><textarea id="roleChatText" maxlength="2000" required placeholder="Напишите сообщение…"></textarea><div class="role-chat-head"><button type="submit" id="roleChatSend">Отправить</button><button type="button" id="roleChatRefresh">Обновить</button></div></form><p id="roleChatError" role="status"></p>';
 const style=document.createElement('style');style.textContent='.role-chat{box-sizing:border-box;width:min(740px,calc(100% - 24px));max-height:90vh;border:1px solid #ddd;border-radius:14px;padding:20px;color:#17171c;background:#fff;font:14px Arial,sans-serif}.role-chat::backdrop{background:#17171c88}.role-chat-head{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}.role-chat h2{font-size:22px;margin:0}.role-chat p{line-height:1.6;overflow-wrap:anywhere;white-space:pre-wrap}.role-chat button{border:1px solid #6d3fc0;border-radius:8px;padding:10px 14px;min-height:44px;background:#6d3fc0;color:white;cursor:pointer;font:inherit}.role-chat button:disabled{opacity:.5;cursor:wait}.role-chat textarea{box-sizing:border-box;width:100%;min-height:90px;margin:10px 0;resize:vertical;border:1px solid #ccc;border-radius:8px;padding:12px;font:16px Arial}.role-chat label{display:block;margin-top:14px}.role-chat #roleChatMessages{height:32vh;min-height:160px;overflow-y:auto;padding:10px 0;margin:10px 0;border-block:1px solid #eee}.role-chat .chat-message{max-width:88%;padding:12px 15px;margin:10px 0;border-radius:12px;background:#f3f3f6;overflow-wrap:anywhere;white-space:pre-wrap}.role-chat .chat-message.mine{background:#eee6fc;margin-left:auto}.role-chat .chat-message small{display:block;color:#686872;margin-top:8px}.role-chat #roleChatError{color:#a52940}.role-chat details p{white-space:pre-wrap}.role-chat [hidden]{display:none!important}@media(max-width:500px){.role-chat{padding:14px}.role-chat .chat-message{max-width:95%}}';
 document.head.appendChild(style);document.body.appendChild(dlg);
 const el=id=>dlg.querySelector('#'+id),messages=el('roleChatMessages'),text=el('roleChatText'),error=el('roleChatError');
 let current=null,items=[],oldest=null,nonce=null,nonceText='',busy=false,loading=false,generation=0;
 async function rpc(name,args){const r=await client.rpc(name,args).abortSignal(AbortSignal.timeout(20000));if(r.error)throw Error(r.error.message);return r.data;}
 function draw(){messages.innerHTML=items.map(m=>'<div class="chat-message '+(m.mine?'mine':'')+'"><strong>'+(m.founder?'Основатель':'Заявитель')+'</strong><p>'+esc(m.body)+'</p><small>'+esc(new Date(m.created_at).toLocaleString('ru-RU'))+'</small></div>').join('')||'<p>Переписка ещё не началась. Здесь можно обсудить заявку до принятия решения и после него.</p>';}
 async function load(older=false){if(!current||loading)return;loading=true;const gen=generation,id=current,scrollHeight=messages.scrollHeight;el('roleChatOlder').disabled=true;
  try{const d=await rpc('role_application_chat',{p_application_id:id,p_before:older?oldest:null});if(gen!==generation)return;
   el('roleChatInfo').textContent=(names[d.role]||d.role)+' · '+d.applicant+' · '+({pending:'На рассмотрении',accepted:'Принята',rejected:'Отклонена'}[d.status]||d.status);
   el('roleChatStatement').textContent=d.statement;el('roleChatReview').textContent=d.review_note?'Решение: '+d.review_note:'';
   if(older){items=[...d.messages,...items];oldest=d.oldest;el('roleChatOlder').hidden=!d.has_more;draw();messages.scrollTop=messages.scrollHeight-scrollHeight;}
   else{const bottom=messages.scrollHeight-messages.scrollTop-messages.clientHeight<70;const first=items.length===0;
    const map=new Map(items.map(m=>[m.id,m]));for(const m of d.messages)map.set(m.id,m);items=[...map.values()].sort((a,b)=>BigInt(a.id)<BigInt(b.id)?-1:1);
    if(first){oldest=d.oldest;el('roleChatOlder').hidden=!d.has_more;}const previous=messages.innerHTML;draw();if(first||bottom)messages.scrollTop=messages.scrollHeight;
   }
  }catch(e){if(gen===generation){error.textContent=e.message;items=[];messages.textContent='Переписку не удалось загрузить.';}}
  finally{if(gen===generation){loading=false;el('roleChatOlder').disabled=false;}}
 }
 window.openRoleApplicationChat=async id=>{if(!/^\d{1,18}$/.test(String(id)))return;if(busy)return;generation++;loading=false;current=String(id);items=[];oldest=null;nonce=null;text.value='';error.textContent='';messages.textContent='Загрузка переписки…';el('roleChatInfo').textContent='';el('roleChatStatement').textContent='';el('roleChatReview').textContent='';el('roleChatOlder').hidden=true;if(!dlg.open)dlg.showModal();await load();};
 el('roleChatClose').addEventListener('click',()=>dlg.close());dlg.addEventListener('close',()=>{generation++;current=null;loading=false;items=[];text.value='';messages.textContent='';});
 el('roleChatOlder').addEventListener('click',()=>load(true));el('roleChatRefresh').addEventListener('click',()=>{error.textContent='';load();});
 el('roleChatForm').addEventListener('submit',async e=>{e.preventDefault();if(busy||!current||!text.value.trim())return;busy=true;const id=current,gen=generation,body=text.value.trim();if(!nonce||nonceText!==body){nonce=crypto.randomUUID();nonceText=body;}const attemptNonce=nonce;el('roleChatSend').disabled=true;text.disabled=true;error.textContent='';
  try{await rpc('send_role_application_message',{p_application_id:id,p_body:body,p_nonce:attemptNonce});if(gen!==generation)return;text.value='';nonce=null;await load();messages.scrollTop=messages.scrollHeight;}catch(e){if(gen===generation)error.textContent=e.message;}finally{busy=false;el('roleChatSend').disabled=false;text.disabled=false;}
 });
 setInterval(()=>{if(dlg.open&&!document.hidden&&!busy)load();},10000);
 const requested=new URLSearchParams(location.search).get('application');if(requested)window.openRoleApplicationChat(requested);
})();
