(()=>{
  const SB_URL="https://rictvznkxkeygbrlcymn.supabase.co";
  const SB_KEY="sb_publishable_SVwKto14tbMtsmcDOagvCw_TVqg7he7";
  function renderCount(n){const a=document.querySelector('.neria-notifications-link');if(!a)return;a.classList.toggle('has-unread',n>0);const badge=a.querySelector('.neria-notification-badge');if(badge){badge.textContent=n>99?'99+':String(n);badge.style.display=n>0?'inline-flex':'none'}a.title=n>0?'Непрочитанных уведомлений: '+n:'Уведомления'}
  function getSb(){if(!window.supabase)return null;return window.__neriaHeaderSb||(window.__neriaHeaderSb=window.supabase.createClient(SB_URL,SB_KEY))}
  async function setupNotifications(){try{const sb=getSb();if(!sb)return;const {data:{session}}=await sb.auth.getSession();if(!session){renderCount(0);return}const refresh=async()=>{const {data,error}=await sb.rpc('my_unread_notification_count');if(!error)renderCount(Number(data)||0)};await refresh();sb.channel('neria-header-notifications-'+session.user.id).on('postgres_changes',{event:'*',schema:'public',table:'notifications',filter:'user_id=eq.'+session.user.id},refresh).subscribe()}catch{}}
  async function setupLastSeen(){try{const sb=getSb();if(!sb)return;const {data:{session}}=await sb.auth.getSession();if(!session)return;const touch=async()=>{try{await sb.rpc('touch_my_last_seen')}catch{}};await touch();const timer=setInterval(touch,180000);window.addEventListener('pagehide',()=>clearInterval(timer),{once:true})}catch{}}
  async function setupProfileCustomization(){try{const sb=getSb();if(!sb)return;const {data:{session}}=await sb.auth.getSession();if(!session)return;const {data,error}=await sb.rpc('my_store_status');if(error||!data?.citizen_id)return;const apply=()=>{const avatar=document.querySelector('.avatar-editor'),color=document.querySelector('.nickname-color-editor');if(avatar)avatar.style.display=data.avatar_access?'flex':'none';if(color)color.style.display=data.nickname_color_access?'block':'none'};apply();const target=document.getElementById('profileCard')||document.body;const obs=new MutationObserver(apply);obs.observe(target,{childList:true,subtree:true});setTimeout(()=>obs.disconnect(),15000)}catch{}}
  function addScript(src,key){if(document.querySelector('script[data-'+key+']'))return;const s=document.createElement('script');s.src=src;s.defer=true;s.setAttribute('data-'+key,'1');document.head.appendChild(s)}
  function loadCosmetics(path){if(['profile.html','citizen.html'].includes(path))addScript('profile-cosmetics.js?v=4','neria-cosmetics');if(path==='cosmetics.html')addScript('cosmetics-v2-editor.js?v=4','neria-cosmetics-v2');if(path==='shop.html')addScript('shop-v2.js?v=4','neria-shop-v2');if(path==='citizens.html')addScript('citizens-v2.js?v=3','neria-citizens-v2')}
  function init(){
    const path=(location.pathname.split('/').pop()||'index.html').toLowerCase();
    if(path.startsWith('demo-'))return;
    document.querySelectorAll('body > header').forEach(h=>h.remove());

    const familyPages=['family.html','state-family.html'];
    const statePages=['state.html','state-founder.html','state-ministers.html','state-deputies.html','state-elections.html','state-justice.html','state-migration.html','state-economy.html','state-events.html','state-careers.html','state-earn-nr.html','state-alliance.html','constitution.html','government-law.html','economy-law.html'];
    const economyPages=['treasury.html','wallet.html','shop.html','market.html'];
    const communityPages=['communities.html','group.html'];
    const activeFor=href=>href==='family.html'?familyPages.includes(path):href==='state.html'?statePages.includes(path):href==='treasury.html'?economyPages.includes(path):href==='communities.html'?communityPages.includes(path):href===path;

    const primary=[
      ['profile.html','Кабинет','👤'],
      ['square.html','Площадь','🏙️'],
      ['chat.html','Чат','💬'],
      ['state.html','Государство','🏛️'],
      ['treasury.html','Экономика','💰'],
      ['communities.html','Сообщества','🏠']
    ];

    const groups=[
      ['Личное',[
        ['profile.html','Личный кабинет','👤'],
        ['family.html','Семья','💍'],
        ['subscriptions.html','Подписки','👥'],
        ['while-away.html','Пока вас не было','✨']
      ]],
      ['Государство',[
        ['citizens.html','Граждане','🪪'],
        ['laws.html','Законы','📜'],
        ['alliances.html','Союзы','🤝']
      ]],
      ['Экономика',[
        ['shop.html','Маркет','🛍️'],
        ['market.html','Объявления','📌'],
        ['treasury.html','Экономика и казна','💰']
      ]],
      ['Общество',[
        ['newspaper.html','Газета','📰'],
        ['discussions.html','Общественные обсуждения','🗳️'],
        ['calendar.html','Календарь','📅'],
        ['contests.html','Конкурсы','🏆'],
        ['initiatives.html','Инициативы','🛠️'],
        ['projects.html','Дочерние проекты','🧩'],
        ['community.html','Telegram','✈️']
      ]]
    ];

    const secondaryPaths=new Set(groups.flatMap(([,items])=>items.map(([href])=>href)));
    const menuActive=secondaryPaths.has(path)||familyPages.includes(path);
    const menuHtml=groups.map(([title,items])=>'<section class="neria-menu-group"><div class="neria-menu-title">'+title+'</div>'+items.map(([href,label,icon])=>'<a href="'+href+'"'+(activeFor(href)?' class="active" aria-current="page"':'')+'><span>'+icon+'</span><b>'+label+'</b></a>').join('')+'</section>').join('');

    const h=document.createElement('header');
    h.className='neria-site-header';
    h.innerHTML=
      '<a class="neria-site-logo" href="index.html"><span class="neria-site-flag" aria-label="Флаг Нерии"><i></i><i></i><i></i></span><span>НЕРИЯ</span></a>'+
      '<nav class="neria-site-nav">'+
        primary.map(([href,label,icon])=>'<a href="'+href+'"'+(activeFor(href)?' class="active" aria-current="page"':'')+'><span class="neria-nav-icon">'+icon+'</span><span>'+label+'</span></a>').join('')+
        '<button type="button" class="neria-menu-toggle'+(menuActive?' active':'')+'" aria-expanded="false" aria-controls="neria-all-sections"><span>☰</span><span>Разделы</span></button>'+
        '<a href="notifications.html" class="neria-notifications-link'+(path==='notifications.html'?' active':'')+'" aria-label="Уведомления"><span class="neria-bell">🔔</span><span class="neria-notification-text">Уведомления</span><span class="neria-notification-badge" style="display:none">0</span></a>'+
      '</nav>'+
      '<div class="neria-menu-panel" id="neria-all-sections" hidden><div class="neria-menu-grid">'+menuHtml+'</div></div>';

    document.body.prepend(h);

    const toggle=h.querySelector('.neria-menu-toggle');
    const panel=h.querySelector('.neria-menu-panel');
    const setOpen=open=>{panel.hidden=!open;toggle.setAttribute('aria-expanded',open?'true':'false');toggle.classList.toggle('open',open)};
    toggle.addEventListener('click',e=>{e.stopPropagation();setOpen(panel.hidden)});
    panel.addEventListener('click',e=>e.stopPropagation());
    document.addEventListener('click',()=>setOpen(false));
    document.addEventListener('keydown',e=>{if(e.key==='Escape')setOpen(false)});

    loadCosmetics(path);
    let tries=0;
    const wait=()=>{if(window.supabase){setupNotifications();setupLastSeen();if(path==='profile.html')setupProfileCustomization()}else if(tries++<40)setTimeout(wait,100)};
    wait()
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
})();