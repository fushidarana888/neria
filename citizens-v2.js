(()=>{
if((location.pathname.split('/').pop()||'').toLowerCase()!=='citizens.html')return;
const css=document.createElement('link');css.rel='stylesheet';css.href='cosmetics-v2.css?v=3';document.head.appendChild(css);
const frameClass=v=>['cosmos_v2','sakura_v2','imperial_v2','midnight_v2','sky_v2'].includes(v)?'frame-'+v:'';
const effectClass=v=>['stars_v2','petals_v2','embers_v2','shards_v2','clouds_v2'].includes(v)?'effect-'+v:'';
async function enhance(){let n=0;while(!window.supabase&&n++<60)await new Promise(r=>setTimeout(r,100));if(!window.supabase)return;const client=window.__neriaHeaderSb||window.supabase.createClient('https://rictvznkxkeygbrlcymn.supabase.co','sb_publishable_SVwKto14tbMtsmcDOagvCw_TVqg7he7');const {data,error}=await client.rpc('get_public_citizens');if(error||!data)return;let tries=0;while(!document.querySelector('.registry .citizen:not(.header)')&&tries++<80)await new Promise(r=>setTimeout(r,100));const map=new Map(data.map(c=>[String(c.citizen_id),c]));document.querySelectorAll('.registry .citizen:not(.header)').forEach(row=>{const id=row.querySelector('.id')?.textContent?.trim(),c=map.get(id);if(!c)return;const wrap=row.querySelector('.avatar-wrap');if(!wrap)return;const fc=frameClass(c.profile_frame),ec=effectClass(c.profile_effect);if(fc)wrap.classList.add(fc);if(ec)wrap.classList.add(ec)})}
enhance();
})();