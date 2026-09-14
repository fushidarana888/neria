'use strict';
const content=document.getElementById('content'),message=document.getElementById('message');
let client=null,data=null,busy=false,tab='partner',checking=false,citizens=[];
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const date=v=>v?new Date(v).toLocaleString('ru-RU'):'—';
const status=v=>({active:'Действующий гражданин',banned:'Заблокирован',revoked:'Гражданство отозвано',resigned:'Отказался от гражданства'}[v]||'Не является действующим гражданином');
const number=v=>String(v??'').padStart(6,'0');
const privacy='Заключая брак, вы открываете супругу имя, фамилию и дату рождения из профиля, даже если скрыли их от остальных. Доступ действует до развода. Telegram-данные, переписка и управление кошельком не передаются.';
function consent(id,text){return `<label class="consent"><input type="checkbox" id="${id}" required><span>${esc(text)}</span></label>`;}
function button(action,id,label,cls='secondary',disabled=false){return `<button type="button" class="${cls}" data-action="${action}" data-id="${esc(id)}" ${disabled?'disabled':''}>${label}</button>`;}
function citizenPicker(prefix,label,disabled=false){const options=citizens.map(c=>{const n=String(c.citizen_id??'').replace(/\D/g,'');return n?`<option value="${esc(n)}">${esc(c.nickname||'Без ника')} · #${esc(number(n))}</option>`:'';}).join('');const dis=disabled?'disabled':'';return `<label for="${prefix}-select">${esc(label)}</label><select id="${prefix}-select" ${dis}><option value="">Выберите гражданина из списка</option>${options}</select><div style="margin:8px 0;color:#85858e;font-size:12px">или введите ID вручную</div><input id="${prefix}-number" inputmode="numeric" pattern="[0-9]{1,18}" maxlength="18" placeholder="Например, 000123" ${dis}>`;}
function pickedNumber(prefix){const manual=document.getElementById(prefix+'-number')?.value?.trim();const selected=document.getElementById(prefix+'-select')?.value?.trim();return manual||selected||'';}
async function rpc(name,args){const {data,error}=await client.rpc(name,args).abortSignal(AbortSignal.timeout(20000));if(error)throw new Error(error.message);return data;}
function render(){
 const m=data.marriage,marriageDays=data.marriage_days??15,childDays=data.child_days??30;
 document.getElementById('title').textContent=m?'Моя семья':'Браки';
 document.getElementById('subtitle').textContent=m?'Семейный кабинет: ваш супруг, дети и история семьи.':'Предложите брак, создайте семью и развивайте её вместе.';
 let html='';
 if(!m){
  html=`<section class="card"><h2>Предложить брак</h2><p>Брак регистрируется после согласия второго гражданина. Оба должны быть действующими гражданами и не иметь другого брака. Общий срок стажа — больше 15 дней; Основатель может сократить его персонально. Ваш срок: ${marriageDays===0?'без ожидания':esc(marriageDays)+' дн.'}</p>${!data.can_marry?`<div class="notice">Регистрация брака доступна после ${esc(date(data.ready_at))}. После развода действует ожидание в один календарный месяц.</div>`:''}<form id="propose-form">${citizenPicker('spouse','Будущий супруг',!data.can_marry)}<small>Можно выбрать гражданина из списка или ввести его ID вручную.</small>${consent('privacy-propose',privacy)}<div class="actions"><button ${!data.can_marry?'disabled':''}>Отправить предложение</button></div></form></section>`;
 }else{
  const p=m.partner;
  html=`<div class="notice">Брак зарегистрирован ${esc(date(m.registered_at))}. ${p.status!=='active'?'Супруг сейчас не является действующим гражданином. Брак сохраняется; вы можете расторгнуть его без ожидания.':''}</div><div class="tabs" role="tablist" aria-label="Семейный кабинет"><button role="tab" id="tab-partner" aria-controls="partner-panel" data-tab="partner" aria-selected="${tab==='partner'}">Супруг</button><button role="tab" id="tab-children" aria-controls="children-panel" data-tab="children" aria-selected="${tab==='children'}">Дети · ${m.children.length}/3</button></div>`;
  html+=`<section class="card" id="partner-panel" role="tabpanel" aria-labelledby="tab-partner" ${tab!=='partner'?'hidden':''}><h2>${esc(p.nickname)} <span class="badge">#${esc(number(p.number))}</span></h2><p>${esc(status(p.status))}</p><dl class="details"><dt>Имя</dt><dd>${esc(p.first_name||'Не указано')}</dd><dt>Фамилия</dt><dd>${esc(p.surname||'Не указана')}</dd><dt>Дата рождения</dt><dd>${esc(String(p.birth_day).padStart(2,'0')+'.'+String(p.birth_month).padStart(2,'0')+(p.birth_year?'.'+p.birth_year:''))}</dd><dt>В Нерии с</dt><dd>${esc(date(p.member_since))}</dd></dl><small>Эти данные доступны вам как супругу. После развода доступ к скрытым полям прекращается.</small><details><summary>Расторгнуть брак</summary><p>Для расторжения достаточно решения одного супруга. После развода оба смогут вступить в новый брак только через календарный месяц. Прежняя семья и дети сохранятся в истории; приглашения будут отменены.</p>${!m.can_divorce?`<p>Расторжение доступно с ${esc(date(m.divorce_at))}, либо раньше, если супруг заблокирован или перестал быть гражданином.</p>`:''}<div class="actions">${button('divorce',m.id,'Расторгнуть брак','danger',!m.can_divorce)}</div></details></section>`;
  html+=`<section class="card" id="children-panel" role="tabpanel" aria-labelledby="tab-children" ${tab!=='children'?'hidden':''}><h2>Дети семьи</h2><p>Виртуальное родство по согласию обоих супругов и приглашённого гражданина. Возраст в реальной жизни не определяет эту роль.</p>${m.children.map(c=>`<div class="row"><strong>${esc(c.nickname)}</strong> · #${esc(number(c.number))}<p>${esc(status(c.status))} · В семье с ${esc(date(c.joined_at))}</p></div>`).join('')||'<p>Детей в семье пока нет.</p>'}<div class="notice">${childDays===0?'Для вашей семьи все три места доступны без ожидания.':'Для вашей семьи места открываются после '+esc(childDays)+', '+esc(childDays*2)+' и '+esc(childDays*3)+' дней с регистрации брака.'} Максимум — три ребёнка.${m.next_child_at?` Следующее место: после ${esc(date(m.next_child_at))}.`:' Все три места заняты.'}</div><form id="child-form"><p>${citizenPicker('child','Гражданин, которого хотите пригласить',!m.can_invite_child)}</p><small>Супругу и приглашённому придут отдельные запросы согласия. Дети не получают доступ к скрытым данным супругов.</small><div class="actions"><button ${!m.can_invite_child?'disabled':''}>Пригласить в семью</button></div></form></section>`;
 }
 html+='<section class="card"><h2>Предложения и приглашения</h2><small>Предложение действует 7 дней. Отправленное предложение можно отменить.</small>';
 html+=data.requests.map(r=>`<div class="row"><h3>${r.kind==='marriage'?'Предложение брака':'Приглашение ребёнка'}</h3><p>${esc(r.proposer)} (#${esc(number(r.proposer_number))}) → ${esc(r.recipient)} (#${esc(number(r.recipient_number))})${r.kind==='child'?`<br>Второй супруг: ${esc(r.partner)}<br>Согласие второго супруга: ${r.partner_accepted?'получено':'ожидается'}. Согласие приглашённого: ${r.recipient_accepted?'получено':'ожидается'}.`:''}</p><small>До ${esc(date(r.expires_at))}</small>${r.can_accept&&r.kind==='marriage'?consent('consent-'+r.id,privacy):''}<div class="actions">${r.mine?button('cancel',r.id,'Отменить'):((r.can_accept?button('accept',r.id,r.kind==='marriage'?'Согласиться на брак':'Подтвердить согласие',''): '<span class="muted">Ваше согласие получено. Ожидаем других участников.</span>')+button('decline',r.id,'Отклонить','danger'))}</div></div>`).join('')||'<p>Новых предложений пока нет.</p>';
 html+='</section>';
 if(data.parents.length)html+=`<section class="card"><h2>Моя родительская семья</h2>${data.parents.map(f=>`<div class="row"><strong>${esc(f.parent_a)} и ${esc(f.parent_b)}</strong><p>Принятие в семью: ${esc(date(f.joined_at))}.${f.divorced_at?' Брак родителей расторгнут, запись сохранена в истории.':''}</p></div>`).join('')}</section>`;
 if(data.history.length)html+=`<section class="card"><h2>История семей</h2>${data.history.map(h=>`<div class="row"><strong>${esc(h.partner)}</strong><p>Брак: ${esc(date(h.registered_at))}. Развод: ${esc(date(h.divorced_at))}.</p><small>Дети прежней семьи: ${esc(h.children.join(', ')||'нет')}.</small></div>`).join('')}</section>`;
 html+='<div class="actions">'+button('refresh','','Обновить данные')+'</div>';
 content.innerHTML=html;
}
async function refresh(){const [dashboard,people]=await Promise.all([rpc('family_dashboard'),rpc('get_public_citizens').catch(()=>[])]);data=dashboard;citizens=(people||[]).slice().sort((a,b)=>String(a.nickname||'').localeCompare(String(b.nickname||''),'ru'));render();}
async function syncFamily(){
 if(!client||!data||busy||checking||document.hidden)return;
 checking=true;
 try{const next=await rpc('family_dashboard');
  const prevState=JSON.stringify({...data,now:null}),nextState=JSON.stringify({...next,now:null});
  data=next;if(prevState!==nextState)render();
 }catch(e){data=null;content.innerHTML='<div class="card"><p>'+esc(e.message)+'</p><button onclick="location.reload()">Повторить загрузку</button></div>';}
 finally{checking=false;}
}
async function act(action,target){
 if(busy)return;
 busy=true;message.textContent='';message.className='';
 content.querySelectorAll('button').forEach(b=>b.disabled=true);
 try{await rpc('family_action',{p_action:action,p_target:target});message.className='success';message.textContent='Готово. Изменения сохранены.';await refresh();}
 catch(e){message.className='';message.textContent=e.message||'Не удалось выполнить действие. Обновите данные перед повторной попыткой.';if(data)render();}
 finally{busy=false;}
}
content.addEventListener('submit',e=>{e.preventDefault();if(busy)return;const form=e.target;if(!form.reportValidity())return;const prefix=form.id==='propose-form'?'spouse':'child';const target=pickedNumber(prefix);if(!/^\d{1,18}$/.test(target)){message.textContent='Выберите гражданина из списка или введите корректный ID.';return;}act(form.id==='propose-form'?'propose':'invite_child',target);});
content.addEventListener('click',async e=>{
 const b=e.target.closest('button');if(!b||busy||b.disabled)return;
 if(b.dataset.tab){tab=b.dataset.tab;render();document.getElementById('tab-'+tab).focus();return;}
 const action=b.dataset.action;if(!action)return;
 if(action==='refresh'){busy=true;b.disabled=true;try{await refresh();message.textContent='';}catch(e){message.textContent=e.message;b.disabled=false;}finally{busy=false;}return;}
 if(action==='accept'){const c=document.getElementById('consent-'+b.dataset.id);if(c&&!c.checked){c.reportValidity();return;}}
 if(action==='divorce'&&!confirm('Расторгнуть брак? Скрытые данные супруга станут недоступны. Новый брак — через календарный месяц.'))return;
 await act(action,b.dataset.id);
});
async function init(){try{
 if(!window.supabase)throw new Error('Не удалось загрузить подключение к сайту. Обновите страницу.');
 client=window.supabase.createClient('https://rictvznkxkeygbrlcymn.supabase.co','sb_publishable_SVwKto14tbMtsmcDOagvCw_TVqg7he7');
 const auth=await Promise.race([client.auth.getSession(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Проверка входа заняла слишком много времени. Обновите страницу.')),15000))]);
 if(auth.error)throw auth.error;
 if(!auth.data.session){content.innerHTML='<div class="card"><p>Войдите в аккаунт Нерии, чтобы открыть браки и семью.</p><a class="btn" href="registration.html">Войти через Telegram</a></div>';return;}
 await refresh();
}catch(e){content.innerHTML='<div class="card"><p>'+esc(e.message)+'</p><button onclick="location.reload()">Повторить загрузку</button></div>';}}
init();
window.addEventListener('focus',syncFamily);
document.addEventListener('visibilitychange',syncFamily);
setInterval(syncFamily,30000);
