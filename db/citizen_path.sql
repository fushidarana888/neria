create schema if not exists neria_path;
revoke all on schema neria_path from public, anon, authenticated;

create or replace function neria_path.build_path(p_citizen_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c public.citizens%rowtype;
  result jsonb;
  timeline jsonb;
  stats jsonb;
  roles jsonb;
  marriage_info jsonb;
begin
  select * into c from public.citizens where id=p_citizen_id;
  if c.id is null then return null; end if;

  select coalesce(jsonb_agg(jsonb_build_object('role',x.role,'assigned_at',x.assigned_at) order by x.assigned_at),'[]'::jsonb)
  into roles from public.government_roles x where x.user_id=c.user_id;

  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'registered_at',m.registered_at,'divorced_at',m.divorced_at,'partner_number',lpad(cp.citizen_number::text,6,'0'),'partner_nickname',cp.nickname) order by m.registered_at desc),'[]'::jsonb)
  into marriage_info
  from neria_family.marriages m
  join public.citizens cp on cp.id=case when m.spouse_a=c.id then m.spouse_b else m.spouse_a end
  where c.id in (m.spouse_a,m.spouse_b);

  select jsonb_build_object(
    'days_in_neria',greatest(0,floor(extract(epoch from (now()-c.created_at))/86400)::int),
    'citizens_at_join',(select count(*) from public.citizens q where q.created_at<=c.created_at),
    'citizens_now',(select count(*) from public.citizens q where q.citizenship_status='active'),
    'citizens_joined_after',(select count(*) from public.citizens q where q.created_at>c.created_at),
    'wallet_balance',coalesce((select w.balance from public.wallets w where w.citizen_id=c.id),0),
    'nr_received',coalesce((select sum(greatest(t.amount,0)) from public.wallet_transactions t where t.citizen_id=c.id),0),
    'messages',(select count(*) from public.public_chat_messages x where x.author_citizen_id=c.id),
    'completed_deals',(select count(*) from public.market_deals d where d.status='completed' and c.id in(d.payer_citizen_id,d.payee_citizen_id)),
    'articles',(select count(*) from public.news_articles a where a.author_citizen_id=c.id),
    'state_jobs',(select count(*) from public.market_listings l where l.author_citizen_id=c.id and l.target='state' and l.state_offer_status in('completed_paid','completed_unpaid')),
    'achievements',(select count(*) from public.citizen_achievements a where a.citizen_id=c.id),
    'special_awards',(select count(*) from public.citizen_special_awards a where a.citizen_id=c.id and a.revoked_at is null),
    'marriages',(select count(*) from neria_family.marriages m where c.id in(m.spouse_a,m.spouse_b)),
    'children',(select count(distinct ch.citizen_id) from neria_family.children ch join neria_family.marriages m on m.id=ch.marriage_id where c.id in(m.spouse_a,m.spouse_b))
  ) into stats;

  with events as (
    select c.created_at as event_at,'citizenship'::text as kind,'🇳🇪'::text as icon,'Получено гражданство Нерии'::text as title,('Гражданин №'||lpad(c.citizen_number::text,6,'0'))::text as description,10 as priority
    union all select ca.earned_at,'achievement',ad.icon,ad.title,ad.description,30 from public.citizen_achievements ca join public.achievement_definitions ad on ad.key=ca.achievement_key where ca.citizen_id=c.id
    union all select sa.granted_at,'special_award',coalesce(sa.icon,'🎖'),sa.title,coalesce(nullif(sa.reason,''),sa.description),20 from public.citizen_special_awards sa where sa.citizen_id=c.id and sa.revoked_at is null
    union all select a.published_at,'article','📰','Опубликована статья',a.title,50 from public.news_articles a where a.author_citizen_id=c.id and a.published_at is not null
    union all select g.assigned_at,'government_role','🏛','Государственная служба',case g.role when 'economy_minister' then 'Назначен министром экономики' when 'mvd' then 'Назначен министром МВД' when 'journalist' then 'Получена роль журналиста' else 'Получена государственная роль: '||g.role end,25 from public.government_roles g where g.user_id=c.user_id
    union all select m.registered_at,'marriage','💍','Зарегистрирован брак','Брак с '||cp.nickname||' · №'||lpad(cp.citizen_number::text,6,'0'),25 from neria_family.marriages m join public.citizens cp on cp.id=case when m.spouse_a=c.id then m.spouse_b else m.spouse_a end where c.id in(m.spouse_a,m.spouse_b)
    union all select m.divorced_at,'divorce','📜','Брак расторгнут','Брак с '||cp.nickname||' · №'||lpad(cp.citizen_number::text,6,'0'),26 from neria_family.marriages m join public.citizens cp on cp.id=case when m.spouse_a=c.id then m.spouse_b else m.spouse_a end where c.id in(m.spouse_a,m.spouse_b) and m.divorced_at is not null
    union all select ch.joined_at,'family','👨‍👩‍👧','Семья стала больше','К семье присоединился гражданин '||cc.nickname||' · №'||lpad(cc.citizen_number::text,6,'0'),40 from neria_family.children ch join neria_family.marriages m on m.id=ch.marriage_id join public.citizens cc on cc.id=ch.citizen_id where c.id in(m.spouse_a,m.spouse_b)
    union all select l.state_completed_at,'state_work','🏛','Выполнена работа для государства',l.title,45 from public.market_listings l where l.author_citizen_id=c.id and l.target='state' and l.state_offer_status in('completed_paid','completed_unpaid') and l.state_completed_at is not null
  )
  select coalesce(jsonb_agg(jsonb_build_object('at',event_at,'kind',kind,'icon',icon,'title',title,'description',description) order by event_at desc,priority asc),'[]'::jsonb)
  into timeline from (select * from events where event_at is not null order by event_at desc,priority asc limit 160) z;

  result:=jsonb_build_object('citizen',jsonb_build_object('number',lpad(c.citizen_number::text,6,'0'),'nickname',c.nickname,'member_since',c.created_at,'status',c.citizenship_status),'stats',stats,'roles',roles,'marriages',marriage_info,'timeline',timeline);
  return result;
end;
$$;

revoke all on function neria_path.build_path(bigint) from public, anon, authenticated;

create or replace function public.my_citizen_path()
returns jsonb language plpgsql security definer set search_path=''
as $$ declare c public.citizens%rowtype; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into c from public.citizens where user_id=auth.uid();
 if c.id is null or c.citizenship_status<>'active' then raise exception 'Active citizenship required'; end if;
 return neria_path.build_path(c.id);
end; $$;

create or replace function public.public_citizen_path(p_citizen_number bigint)
returns jsonb language plpgsql security definer set search_path=''
as $$ declare viewer public.citizens%rowtype; target public.citizens%rowtype; data jsonb; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into viewer from public.citizens where user_id=auth.uid();
 if viewer.id is null or viewer.citizenship_status<>'active' then raise exception 'Active citizenship required'; end if;
 select * into target from public.citizens where citizen_number=p_citizen_number and citizenship_status='active';
 if target.id is null then raise exception 'Citizen not found'; end if;
 data:=neria_path.build_path(target.id);
 data:=jsonb_set(data,'{stats}',(data->'stats')-'wallet_balance'-'nr_received');
 return data;
end; $$;

revoke all on function public.my_citizen_path() from public, anon;
revoke all on function public.public_citizen_path(bigint) from public, anon;
grant execute on function public.my_citizen_path() to authenticated;
grant execute on function public.public_citizen_path(bigint) to authenticated;
