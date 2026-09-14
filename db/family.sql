-- Neria: virtual marriages and families. All mutations are serialized and authorized.
create schema if not exists neria_family;
revoke all on schema neria_family from public, anon, authenticated;
grant usage on schema neria_family to authenticated;

create table neria_family.marriages (
 id uuid primary key default gen_random_uuid(),
 spouse_a bigint not null references public.citizens(id),
 spouse_b bigint not null references public.citizens(id),
 registered_at timestamptz not null default now(),
 divorced_at timestamptz,
 divorced_by bigint references public.citizens(id),
 check(spouse_a <> spouse_b)
);
create table neria_family.children (
 id uuid primary key default gen_random_uuid(),
 marriage_id uuid not null references neria_family.marriages(id),
 citizen_id bigint not null references public.citizens(id),
 joined_at timestamptz not null default now(),
 unique(marriage_id,citizen_id)
);
create table neria_family.requests (
 id uuid primary key default gen_random_uuid(),
 kind text not null check(kind in ('marriage','child')),
 proposer bigint not null references public.citizens(id),
 recipient bigint not null references public.citizens(id),
 marriage_id uuid references neria_family.marriages(id),
 partner_accepted boolean not null default false,
 recipient_accepted boolean not null default false,
 status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now() + interval '7 days',
 check(proposer <> recipient),
 check((kind='marriage' and marriage_id is null) or (kind='child' and marriage_id is not null))
);
create index on neria_family.marriages(spouse_a);
create index on neria_family.marriages(spouse_b);
create index on neria_family.children(citizen_id);
create index on neria_family.requests(proposer,created_at);
create index on neria_family.requests(recipient,status);
create index on neria_family.requests(marriage_id);
alter table neria_family.marriages enable row level security;
alter table neria_family.children enable row level security;
alter table neria_family.requests enable row level security;
revoke all on all tables in schema neria_family from public,anon,authenticated;

create function neria_family.notify(p_citizen bigint,p_title text) returns void
language sql security definer set search_path='' as $$
 insert into public.notifications(user_id,kind,title,body,link)
 select user_id,'family',p_title,'Откройте раздел «Браки и семья», чтобы посмотреть подробности.','family.html'
 from public.citizens where id=p_citizen and user_id is not null;
$$;

create function neria_family.assert_eligible(p_id bigint) returns void
language plpgsql security definer set search_path='' as $$
declare c public.citizens; last_divorce timestamptz;
begin
 select * into c from public.citizens where id=p_id;
 if c.id is null or c.citizenship_status <> 'active' then raise exception 'Оба участника должны быть действующими гражданами.'; end if;
 if now() <= c.created_at + interval '15 days' then raise exception 'Для брака нужно состоять в Нерии больше 15 дней.'; end if;
 if exists(select 1 from neria_family.marriages where divorced_at is null and p_id in (spouse_a,spouse_b)) then raise exception 'Участник уже состоит в браке.'; end if;
 select max(divorced_at) into last_divorce from neria_family.marriages where p_id in (spouse_a,spouse_b);
 if last_divorce is not null and now() < last_divorce + interval '1 month' then raise exception 'После развода нужно подождать календарный месяц.'; end if;
end;
$$;

create function neria_family.assert_child(p_marriage uuid,p_child bigint) returns void
language plpgsql security definer set search_path='' as $$
declare m neria_family.marriages; n integer;
begin
 select * into m from neria_family.marriages where id=p_marriage;
 if m.id is null or m.divorced_at is not null then raise exception 'Брак уже расторгнут.'; end if;
 if p_child in(m.spouse_a,m.spouse_b) then raise exception 'Нельзя предложить супругу стать ребёнком этой семьи.'; end if;
 if (select count(*) from public.citizens where id in(m.spouse_a,m.spouse_b,p_child) and citizenship_status='active') <> 3 then raise exception 'Оба супруга и приглашённый должны быть действующими гражданами.'; end if;
 select count(*) into n from neria_family.children where marriage_id=m.id;
 if n >= 3 then raise exception 'В семье может быть не больше трёх детей.'; end if;
 if now() <= m.registered_at + ((n+1)*30)*interval '1 day' then raise exception 'Места для детей открываются после 30, 60 и 90 дней брака.'; end if;
 if exists(select 1 from neria_family.children c join neria_family.marriages f on f.id=c.marriage_id where c.citizen_id=p_child and f.divorced_at is null) then raise exception 'Этот гражданин уже является ребёнком действующей семьи.'; end if;
 -- Prevent cycles in active virtual parent/child relationships.
 if exists(with recursive descendants(id) as (
   select p_child union
   select c.citizen_id from descendants d join neria_family.marriages f on d.id in(f.spouse_a,f.spouse_b) and f.divorced_at is null join neria_family.children c on c.marriage_id=f.id
 ) select 1 from descendants where id in(m.spouse_a,m.spouse_b)) then raise exception 'Нельзя создать замкнутое родство.'; end if;
end;
$$;

create function neria_family.action(p_action text,p_target text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare me public.citizens; target public.citizens; m neria_family.marriages; r neria_family.requests; spouse bigint; mid uuid;
begin
 if auth.uid() is null then raise exception 'Войдите через Telegram.'; end if;
 perform pg_advisory_xact_lock(724113608);
 select * into me from public.citizens where user_id=auth.uid() for update;
 if me.id is null or me.citizenship_status <> 'active' then raise exception 'Раздел доступен только действующим гражданам.'; end if;
 select * into m from neria_family.marriages where divorced_at is null and me.id in(spouse_a,spouse_b);

 if p_action in ('propose','invite_child') then
   if p_target is null or p_target !~ '^[0-9]{1,18}$' then raise exception 'Введите числовой ID гражданина.'; end if;
   select * into target from public.citizens where citizen_number=p_target::bigint for update;
   if target.id is null or target.citizenship_status <> 'active' then raise exception 'Действующий гражданин с таким ID не найден.'; end if;
   if target.id=me.id then raise exception 'Нельзя отправить предложение самому себе.'; end if;
   if (select count(*) from neria_family.requests where proposer=me.id and created_at>now()-interval '1 day') >= 10 then raise exception 'Не более 10 предложений в сутки.'; end if;
   if p_action='propose' then
     perform neria_family.assert_eligible(me.id);
     perform neria_family.assert_eligible(target.id);
     if exists(select 1 from neria_family.requests where proposer=me.id and kind='marriage' and status='pending' and expires_at>now()) then raise exception 'Сначала отмените или дождитесь ответа на предыдущее предложение.'; end if;
     insert into neria_family.requests(kind,proposer,recipient) values('marriage',me.id,target.id);
     perform neria_family.notify(target.id,'Вам предложили брак');
   else
     if m.id is null then raise exception 'Сначала зарегистрируйте брак.'; end if;
     perform 1 from public.citizens where id in(m.spouse_a,m.spouse_b) order by id for update;
     perform neria_family.assert_child(m.id,target.id);
     if exists(select 1 from neria_family.requests where marriage_id=m.id and status='pending' and expires_at>now()) then raise exception 'В семье уже есть приглашение, ожидающее согласия.'; end if;
     insert into neria_family.requests(kind,proposer,recipient,marriage_id) values('child',me.id,target.id,m.id);
     spouse=case when me.id=m.spouse_a then m.spouse_b else m.spouse_a end;
     perform neria_family.notify(target.id,'Вас пригласили стать ребёнком семьи');
     perform neria_family.notify(spouse,'Подтвердите приглашение ребёнка в семью');
   end if;

 elsif p_action in ('accept','decline','cancel') then
   select * into r from neria_family.requests where id=p_target::uuid for update;
   if r.id is null or r.status<>'pending' or r.expires_at<=now() then raise exception 'Предложение уже закрыто или истекло.'; end if;
   if r.marriage_id is not null then
     select * into m from neria_family.marriages where id=r.marriage_id;
     spouse=case when r.proposer=m.spouse_a then m.spouse_b else m.spouse_a end;
   end if;
   if me.id<>r.proposer and me.id<>r.recipient and me.id is distinct from spouse then raise exception 'Это предложение вам недоступно.'; end if;
   if p_action='cancel' then
     if me.id<>r.proposer then raise exception 'Отменить предложение может только его автор.'; end if;
     update neria_family.requests set status='cancelled' where id=r.id;
   elsif p_action='decline' then
     if me.id=r.proposer then raise exception 'Используйте отмену предложения.'; end if;
     update neria_family.requests set status='declined' where id=r.id;
     perform neria_family.notify(r.proposer,'Предложение отклонено');
   else
     if me.id=r.proposer then raise exception 'Нужно согласие приглашённого участника.'; end if;
     perform 1 from public.citizens where id in(r.proposer,r.recipient,spouse) order by id for update;
     if r.kind='marriage' then
       perform neria_family.assert_eligible(r.proposer);
       perform neria_family.assert_eligible(r.recipient);
       insert into neria_family.marriages(spouse_a,spouse_b) values(r.proposer,r.recipient) returning id into mid;
       update neria_family.requests set status='accepted',recipient_accepted=true where id=r.id;
       update neria_family.requests set status='cancelled' where kind='marriage' and status='pending' and (proposer in(r.proposer,r.recipient) or recipient in(r.proposer,r.recipient));
       perform neria_family.notify(r.proposer,'Ваш брак зарегистрирован');
       perform neria_family.notify(r.recipient,'Ваш брак зарегистрирован');
     else
       perform neria_family.assert_child(r.marriage_id,r.recipient);
       update neria_family.requests set recipient_accepted=recipient_accepted or me.id=r.recipient,partner_accepted=partner_accepted or me.id=spouse where id=r.id returning * into r;
       if r.recipient_accepted and r.partner_accepted then
         insert into neria_family.children(marriage_id,citizen_id) values(r.marriage_id,r.recipient);
         update neria_family.requests set status='accepted' where id=r.id;
         perform neria_family.notify(r.proposer,'В вашей семье появился ребёнок');
         perform neria_family.notify(spouse,'В вашей семье появился ребёнок');
         perform neria_family.notify(r.recipient,'Вы приняты в семью');
       end if;
     end if;
   end if;

 elsif p_action='divorce' then
   if m.id is null or m.id::text is distinct from p_target then raise exception 'Этот брак уже недоступен. Обновите страницу.'; end if;
   spouse=case when me.id=m.spouse_a then m.spouse_b else m.spouse_a end;
   select * into target from public.citizens where id=spouse for update;
   if target.citizenship_status='active' and now()<m.registered_at+interval '10 days' then raise exception 'Расторгнуть брак можно через 10 дней после регистрации.'; end if;
   update neria_family.marriages set divorced_at=now(),divorced_by=me.id where id=m.id;
   update neria_family.requests set status='cancelled' where marriage_id=m.id and status='pending';
   perform neria_family.notify(spouse,'Ваш брак расторгнут');
   perform neria_family.notify(me.id,'Ваш брак расторгнут');
 else raise exception 'Неизвестное действие.';
 end if;
 return jsonb_build_object('ok',true);
end;
$$;

create function neria_family.dashboard() returns jsonb
language plpgsql security definer set search_path='' as $$
declare me public.citizens; partner public.citizens; m neria_family.marriages; last_divorce timestamptz; ready timestamptz; kids jsonb; requests jsonb; history jsonb; parents jsonb; n integer;
begin
 if auth.uid() is null then raise exception 'Войдите через Telegram.'; end if;
 select * into me from public.citizens where user_id=auth.uid();
 if me.id is null or me.citizenship_status<>'active' then raise exception 'Раздел доступен только действующим гражданам.'; end if;
 select max(divorced_at) into last_divorce from neria_family.marriages where me.id in(spouse_a,spouse_b);
 ready=greatest(me.created_at+interval '15 days',last_divorce+interval '1 month');
 select * into m from neria_family.marriages where divorced_at is null and me.id in(spouse_a,spouse_b);
 if m.id is not null then
   select * into partner from public.citizens where id=case when me.id=m.spouse_a then m.spouse_b else m.spouse_a end;
   select count(*),coalesce(jsonb_agg(jsonb_build_object('nickname',c.nickname,'number',c.citizen_number::text,'status',c.citizenship_status,'joined_at',k.joined_at) order by k.joined_at),'[]') into n,kids from neria_family.children k join public.citizens c on c.id=k.citizen_id where k.marriage_id=m.id;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'kind',r.kind,'proposer',a.nickname,'proposer_number',a.citizen_number::text,'recipient',b.nickname,'recipient_number',b.citizen_number::text,'partner',case when r.proposer=f.spouse_a then pb.nickname else pa.nickname end,'expires_at',r.expires_at,'mine',r.proposer=me.id,'can_accept',case when me.id=r.recipient then not r.recipient_accepted when me.id in(f.spouse_a,f.spouse_b) and me.id<>r.proposer then not r.partner_accepted else false end,'partner_accepted',r.partner_accepted,'recipient_accepted',r.recipient_accepted) order by r.created_at desc),'[]') into requests
 from neria_family.requests r join public.citizens a on a.id=r.proposer join public.citizens b on b.id=r.recipient left join neria_family.marriages f on f.id=r.marriage_id left join public.citizens pa on pa.id=f.spouse_a left join public.citizens pb on pb.id=f.spouse_b
 where r.status='pending' and r.expires_at>now() and (me.id in(r.proposer,r.recipient) or me.id in(f.spouse_a,f.spouse_b));
 select coalesce(jsonb_agg(jsonb_build_object('registered_at',f.registered_at,'divorced_at',f.divorced_at,'partner',c.nickname,'children',(select coalesce(jsonb_agg(kc.nickname),'[]') from neria_family.children k join public.citizens kc on kc.id=k.citizen_id where k.marriage_id=f.id)) order by f.divorced_at desc),'[]') into history
 from neria_family.marriages f join public.citizens c on c.id=case when me.id=f.spouse_a then f.spouse_b else f.spouse_a end where me.id in(f.spouse_a,f.spouse_b) and f.divorced_at is not null;
 select coalesce(jsonb_agg(jsonb_build_object('parent_a',a.nickname,'parent_b',b.nickname,'joined_at',k.joined_at,'divorced_at',f.divorced_at) order by k.joined_at desc),'[]') into parents from neria_family.children k join neria_family.marriages f on f.id=k.marriage_id join public.citizens a on a.id=f.spouse_a join public.citizens b on b.id=f.spouse_b where k.citizen_id=me.id;
 return jsonb_build_object('now',now(),'ready_at',ready,'can_marry',m.id is null and now()>me.created_at+interval '15 days' and (last_divorce is null or now()>=last_divorce+interval '1 month'),'requests',requests,'history',history,'parents',parents,
 'marriage',case when m.id is null then null else jsonb_build_object('id',m.id,'registered_at',m.registered_at,'can_divorce',partner.citizenship_status<>'active' or now()>=m.registered_at+interval '10 days','divorce_at',m.registered_at+interval '10 days','next_child_at',case when n<3 then m.registered_at+((n+1)*30)*interval '1 day' else null end,'can_invite_child',n<3 and partner.citizenship_status='active' and now()>m.registered_at+((n+1)*30)*interval '1 day','children',kids,
 'partner',jsonb_build_object('nickname',partner.nickname,'number',partner.citizen_number::text,'status',partner.citizenship_status,'first_name',partner.first_name,'surname',partner.surname,'birth_day',partner.birth_day,'birth_month',partner.birth_month,'birth_year',partner.birth_year,'member_since',partner.created_at)) end);
end;
$$;

revoke all on all functions in schema neria_family from public,anon,authenticated;
grant execute on function neria_family.action(text,text),neria_family.dashboard() to authenticated;
create function public.family_dashboard() returns jsonb language sql security invoker set search_path='' as $$ select neria_family.dashboard(); $$;
create function public.family_action(p_action text,p_target text default null) returns jsonb language sql security invoker set search_path='' as $$ select neria_family.action(p_action,p_target); $$;
revoke all on function public.family_dashboard(),public.family_action(text,text) from public,anon;
grant execute on function public.family_dashboard(),public.family_action(text,text) to authenticated;
