(()=>{
  const KEY='neria_demo_state_v6';
  const LAUNCH_KEY='neria_demo_launch_v6';
  const STATE_PREFIX='neria_demo_state_';
  const VALID_ROLES=new Set(['journalist','deputy','economy','mvd','external','judge']);
  const roleNames={journalist:'Журналист',deputy:'Депутат',economy:'Министр экономики',mvd:'Министр внутренних дел',external:'Министр внешних связей',judge:'Судья'};
  const defs={
    first_chat:{icon:'💬',title:'Первый голос',desc:'Отправить первое сообщение в демо-чате.'},
    first_deal:{icon:'🤝',title:'Первая сделка',desc:'Завершить первую демо-сделку.'},
    first_vote:{icon:'🗳',title:'Первый голос на выборах',desc:'Принять участие в демо-голосовании.'},
    first_transfer:{icon:'💸',title:'Первый перевод',desc:'Перевести демо-NR другому гражданину.'},
    news_reader:{icon:'📰',title:'Читаю Нерию',desc:'Открыть материал демо-Газеты.'},
    explorer:{icon:'🧭',title:'Исследователь Нерии',desc:'Попробовать минимум четыре части демо-Нерии.'}
  };
  function eachStorage(fn){[localStorage,sessionStorage].forEach(storage=>{try{fn(storage)}catch{}})}
  function removeAllDemoStates(){eachStorage(storage=>{Object.keys(storage).forEach(key=>{if(key.startsWith(STATE_PREFIX)||key==='neria_demo_state'||key.startsWith('neria_demo_launch_'))storage.removeItem(key)})})}
  function removeLegacyStates(){eachStorage(storage=>{Object.keys(storage).forEach(key=>{if((key.startsWith(STATE_PREFIX)||key==='neria_demo_state')&&key!==KEY)storage.removeItem(key);if(key.startsWith('neria_demo_launch_')&&key!==LAUNCH_KEY)storage.removeItem(key)})})}
  function candidateTime(s){let t=Number(s?.startedAt)||0;if(Array.isArray(s?.timeline))for(const x of s.timeline)t=Math.max(t,Number(x?.at)||0);if(Array.isArray(s?.messages))for(const x of s.messages)t=Math.max(t,Number(x?.at)||0);if(Array.isArray(s?.transfers))for(const x of s.transfers)t=Math.max(t,Number(x?.at)||0);return t}
  function readLegacyIdentity(){const candidates=[];eachStorage(storage=>{Object.keys(storage).forEach(key=>{if(!(key.startsWith(STATE_PREFIX)||key==='neria_demo_state'))return;try{const s=JSON.parse(storage.getItem(key)||'null');if(!s||typeof s!=='object')return;const nickname=String(s.nickname||'').trim();const role=VALID_ROLES.has(String(s.role||''))?String(s.role):'';candidates.push({nickname,role,time:candidateTime(s),session:storage===sessionStorage})}catch{}})});candidates.sort((a,b)=>{const usefulA=(a.nickname&&a.nickname!=='Будущий гражданин'?2:0)+(a.role?1:0);const usefulB=(b.nickname&&b.nickname!=='Будущий гражданин'?2:0)+(b.role?1:0);return usefulB-usefulA||b.time-a.time||Number(b.session)-Number(a.session)});const c=candidates[0];return c?{nickname:c.nickname||'Будущий гражданин',role:c.role||''}:null}
  function cameFromLauncher(){try{const here=location.pathname.split('/').pop();if(here!=='demo-path.html')return false;if(!document.referrer)return false;const u=new URL(document.referrer);const refPage=u.pathname.split('/').pop();return refPage===''||refPage==='index.html'}catch{return false}}
  if(cameFromLauncher()){const identity=readLegacyIdentity();removeAllDemoStates();if(identity)sessionStorage.setItem(LAUNCH_KEY,JSON.stringify(identity))}else removeLegacyStates();
  function newRunId(){try{return crypto.randomUUID()}catch{return Date.now()+'-'+Math.random().toString(36).slice(2)}}
  function fresh(seed={}){const now=Date.now();return{version:6,runId:newRunId(),nickname:String(seed.nickname||'Будущий гражданин').slice(0,30),role:VALID_ROLES.has(String(seed.role||''))?String(seed.role):'',balance:100,startedAt:now,timeline:[{id:'start',at:now,icon:'🏛️',title:'Первый день в Нерии',description:'Демо-гражданство получено. Настоящий гражданский ID появится только после регистрации.'}],achievements:[],visited:[],messages:[],transfers:[],vote:null,dealDone:false,articleRead:false}}
  function consumeLaunch(){try{const raw=sessionStorage.getItem(LAUNCH_KEY);sessionStorage.removeItem(LAUNCH_KEY);if(!raw)return null;const x=JSON.parse(raw);return x&&typeof x==='object'?x:null}catch{return null}}
  function normalize(raw){const base=fresh({nickname:raw?.nickname,role:raw?.role});const s=Object.assign(base,raw||{});s.version=6;s.nickname=String(s.nickname||'Будущий гражданин').slice(0,30);s.role=VALID_ROLES.has(String(s.role||''))?String(s.role):'';s.balance=Number.isFinite(Number(s.balance))?Number(s.balance):100;s.timeline=Array.isArray(s.timeline)?s.timeline:base.timeline;s.achievements=Array.isArray(s.achievements)?s.achievements:[];s.visited=Array.isArray(s.visited)?s.visited:[];s.messages=Array.isArray(s.messages)?s.messages:[];s.transfers=Array.isArray(s.transfers)?s.transfers:[];return s}
  function save(s){sessionStorage.setItem(KEY,JSON.stringify(s));return s}
  function load(){try{const raw=sessionStorage.getItem(KEY);if(raw)return normalize(JSON.parse(raw))}catch{}const s=fresh(consumeLaunch()||{});return save(s)}
  function start(nick,role){removeAllDemoStates();const s=fresh({nickname:nick,role});return save(s)}
  function visit(section){const s=load();if(!s.visited.includes(section))s.visited.push(section);if(s.visited.length>=4)unlock('explorer',s);save(s);return s}
  function record(id,icon,title,description,s){s=s||load();if(!s.timeline.some(x=>x.id===id))s.timeline.push({id,at:Date.now(),icon,title,description});return save(s)}
  function unlock(key,s){s=s||load();if(!s.achievements.includes(key)){s.achievements.push(key);const d=defs[key];if(d)record('ach_'+key,d.icon,'Получена демо-ачивка «'+d.title+'»',d.desc,s)}return save(s)}
  function sendMessage(text){const s=load();s.messages.push({at:Date.now(),text:String(text).slice(0,300)});record('chat_message','💬','Первое сообщение в общем чате','Вы начали общение с другими гражданами.',s);unlock('first_chat',s);return save(s)}
  function completeDeal(){const s=load();if(!s.dealDone){s.dealDone=true;record('deal','🤝','Первая завершённая сделка','Демо-сделка успешно завершена через систему удержания NR.',s);unlock('first_deal',s)}return save(s)}
  function vote(choice){const s=load();s.vote=choice;record('vote','🗳','Первое участие в голосовании','Вы проголосовали «'+choice+'» по демонстрационному вопросу.',s);unlock('first_vote',s);return save(s)}
  function transfer(to,amount){const s=load();amount=Math.max(1,Math.floor(Number(amount)||0));if(amount>s.balance)return{error:'Недостаточно демо-NR',state:s};s.balance-=amount;s.transfers.push({to,amount,at:Date.now()});record('transfer','💸','Первый перевод NR','Вы перевели '+amount+' демо-NR гражданину '+to+'.',s);unlock('first_transfer',s);save(s);return{state:s}}
  function readArticle(title){const s=load();s.articleRead=true;record('article','📰','Открыт материал Газеты','Вы прочитали демонстрационную статью «'+title+'».',s);unlock('news_reader',s);return save(s)}
  function reset(){removeAllDemoStates();return fresh()}
  function roleName(role){return roleNames[role]||role||''}
  window.NeriaDemo={load,save,start,visit,record,unlock,sendMessage,completeDeal,vote,transfer,readArticle,reset,defs,roleName,clear:removeAllDemoStates};
})();