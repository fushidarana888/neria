create table neria_family.wait_overrides (
 citizen_id bigint primary key references public.citizens(id),
 marriage_days integer not null check(marriage_days between 0 and 15),
 child_days integer not null check(child_days between 0 and 30),
 divorce_days integer not null check(divorce_days between 0 and 10),
 reason text not null check(length(reason) between 1 and 500),
 changed_by uuid not null, changed_at timestamptz not null default now()
);
create table neria_family.wait_audit (
 id bigint generated always as identity primary key,
 citizen_id bigint not null references public.citizens(id),
 changed_by uuid not null, changed_at timestamptz not null default now(),
 previous jsonb not null, replacement jsonb not null, reason text not null
);
alter table neria_family.wait_overrides enable row level security;
alter table neria_family.wait_audit enable row level security;
revoke all on neria_family.wait_overrides,neria_family.wait_audit from public,anon,authenticated;

create function neria_family.wait_days(p_id bigint,p_kind text) returns integer
language sql stable security definer set search_path='' as $$
 select case p_kind when 'marriage' then coalesce((select marriage_days from neria_family.wait_overrides where citizen_id=p_id),15)
 when 'child' then coalesce((select child_days from neria_family.wait_overrides where citizen_id=p_id),30)
 when 'divorce' then coalesce((select divorce_days from neria_family.wait_overrides where citizen_id=p_id),10) end;
$$;
create function neria_family.child_wait(p_marriage uuid) returns integer
language sql stable security definer set search_path='' as $$
 select least(neria_family.wait_days(spouse_a,'child'),neria_family.wait_days(spouse_b,'child')) from neria_family.marriages where id=p_marriage;
$$;

create function neria_family.founder_settings(p_number text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare person public.citizens; selected jsonb; entries jsonb; history jsonb;
begin
 if auth.uid() is null or not public.is_founder() then raise exception 'Доступ только Основателю.'; end if;
 if p_number is not null then
   if p_number !~ '^[0-9]{1,18}$' then raise exception 'Введите числовой ID гражданина.'; end if;
   select * into person from public.citizens where citizen_number=p_number::bigint;
   if person.id is null then raise exception 'Гражданин не найден.'; end if;
   selected=jsonb_build_object('number',person.citizen_number::text,'nickname',person.nickname,'status',person.citizenship_status,
     'marriage_days',neria_family.wait_days(person.id,'marriage'),'child_days',neria_family.wait_days(person.id,'child'),'divorce_days',neria_family.wait_days(person.id,'divorce'));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('number',c.citizen_number::text,'nickname',c.nickname,'marriage_days',w.marriage_days,'child_days',w.child_days,'divorce_days',w.divorce_days,'reason',w.reason,'changed_at',w.changed_at) order by w.changed_at desc),'[]') into entries from neria_family.wait_overrides w join public.citizens c on c.id=w.citizen_id;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.changed_at desc,a.id desc),'[]') into history from (
 select h.id::text,c.nickname,c.citizen_number::text as number,h.changed_at,h.previous,h.replacement,h.reason from neria_family.wait_audit h join public.citizens c on c.id=h.citizen_id order by h.changed_at desc,h.id desc limit 50) a;
 return jsonb_build_object('selected',selected,'entries',entries,'history',history);
end;
$$;
create function neria_family.founder_set_settings(p_number text,p_marriage_days integer,p_child_days integer,p_divorce_days integer,p_reason text,p_reset boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.citizens; old_values jsonb; new_values jsonb;
begin
 if auth.uid() is null or not public.is_founder() then raise exception 'Доступ только Основателю.'; end if;
 if p_number is null or p_number !~ '^[0-9]{1,18}$' then raise exception 'Введите числовой ID гражданина.'; end if;
 if p_reason is null or length(btrim(p_reason)) not between 1 and 500 then raise exception 'Укажите основание изменения (до 500 символов).'; end if;
 if p_reset is null then raise exception 'Укажите режим изменения.'; end if;
 if not p_reset and (p_marriage_days is null or p_marriage_days not between 0 and 15 or p_child_days is null or p_child_days not between 0 and 30 or p_divorce_days is null or p_divorce_days not between 0 and 10) then raise exception 'Сроки: брак 0–15, дети 0–30, развод 0–10 дней.'; end if;
 perform pg_advisory_xact_lock(724113608);
 select * into c from public.citizens where citizen_number=p_number::bigint for update;
 if c.id is null then raise exception 'Гражданин не найден.'; end if;
 old_values=jsonb_build_object('marriage_days',neria_family.wait_days(c.id,'marriage'),'child_days',neria_family.wait_days(c.id,'child'),'divorce_days',neria_family.wait_days(c.id,'divorce'));
 if p_reset then delete from neria_family.wait_overrides where citizen_id=c.id;
 else
   insert into neria_family.wait_overrides(citizen_id,marriage_days,child_days,divorce_days,reason,changed_by) values(c.id,p_marriage_days,p_child_days,p_divorce_days,btrim(p_reason),auth.uid())
   on conflict(citizen_id) do update set marriage_days=excluded.marriage_days,child_days=excluded.child_days,divorce_days=excluded.divorce_days,reason=excluded.reason,changed_by=excluded.changed_by,changed_at=now();
 end if;
 new_values=jsonb_build_object('marriage_days',neria_family.wait_days(c.id,'marriage'),'child_days',neria_family.wait_days(c.id,'child'),'divorce_days',neria_family.wait_days(c.id,'divorce'));
 insert into neria_family.wait_audit(citizen_id,changed_by,previous,replacement,reason) values(c.id,auth.uid(),old_values,new_values,btrim(p_reason));
 perform neria_family.notify(c.id,case when p_reset then 'Обычные семейные сроки восстановлены' else 'Основатель изменил ваши семейные сроки' end);
 return neria_family.founder_settings(p_number);
end;
$$;

-- Replace only the known duration expressions; preserve all authorization and consent checks.
do $$
declare src text;
begin
 src=pg_get_functiondef('neria_family.assert_eligible(bigint)'::regprocedure);
 if position('c.created_at + interval ''15 days''' in src)=0 then raise exception 'Unexpected eligibility definition'; end if;
 src=replace(src,'c.created_at + interval ''15 days''','c.created_at + neria_family.wait_days(c.id,''marriage'')*interval ''1 day''');
 src=replace(src,'if now() <= c.created_at','if neria_family.wait_days(c.id,''marriage'') > 0 and now() <= c.created_at');
 src=replace(src,'Для брака нужно состоять в Нерии больше 15 дней.','Ещё не прошёл установленный для гражданина срок до брака.');
 execute src;
 src=pg_get_functiondef('neria_family.assert_child(uuid,bigint)'::regprocedure);
 if position('((n+1)*30)' in src)=0 then raise exception 'Unexpected child definition'; end if;
 src=replace(src,'((n+1)*30)','((n+1)*neria_family.child_wait(m.id))');
 src=replace(src,'if now() <= m.registered_at','if neria_family.child_wait(m.id) > 0 and now() <= m.registered_at');
 src=replace(src,'Места для детей открываются после 30, 60 и 90 дней брака.','Ещё не наступил срок открытия следующего места для ребёнка.');
 execute src;
 src=pg_get_functiondef('neria_family.action(text,text)'::regprocedure);
 if position('m.registered_at+interval ''10 days''' in src)=0 then raise exception 'Unexpected action definition'; end if;
 src=replace(src,'m.registered_at+interval ''10 days''','m.registered_at+neria_family.wait_days(me.id,''divorce'')*interval ''1 day''');
 src=replace(src,'Расторгнуть брак можно через 10 дней после регистрации.','Ещё не прошёл установленный для вас срок до расторжения брака.');
 execute src;
 src=pg_get_functiondef('neria_family.dashboard()'::regprocedure);
 if position('me.created_at+interval ''15 days''' in src)=0 then raise exception 'Unexpected dashboard definition'; end if;
 src=replace(src,'me.created_at+interval ''15 days''','me.created_at+neria_family.wait_days(me.id,''marriage'')*interval ''1 day''');
 src=replace(src,'m.registered_at+interval ''10 days''','m.registered_at+neria_family.wait_days(me.id,''divorce'')*interval ''1 day''');
 src=replace(src,'((n+1)*30)','((n+1)*neria_family.child_wait(m.id))');
 src=replace(src,'now()>me.created_at+neria_family.wait_days(me.id,''marriage'')*interval ''1 day''','(neria_family.wait_days(me.id,''marriage'')=0 or now()>me.created_at+neria_family.wait_days(me.id,''marriage'')*interval ''1 day'')');
 src=replace(src,'now()>m.registered_at+((n+1)*neria_family.child_wait(m.id))*interval ''1 day''','(neria_family.child_wait(m.id)=0 or now()>m.registered_at+((n+1)*neria_family.child_wait(m.id))*interval ''1 day'')');
 src=replace(src,'''now'',now(),','''now'',now(),''marriage_days'',neria_family.wait_days(me.id,''marriage''),''divorce_days'',neria_family.wait_days(me.id,''divorce''),''child_days'',coalesce(neria_family.child_wait(m.id),neria_family.wait_days(me.id,''child'')),');
 execute src;
end;
$$;
revoke all on function neria_family.wait_days(bigint,text),neria_family.child_wait(uuid),neria_family.founder_settings(text),neria_family.founder_set_settings(text,integer,integer,integer,text,boolean) from public,anon,authenticated;
grant execute on function neria_family.founder_settings(text),neria_family.founder_set_settings(text,integer,integer,integer,text,boolean) to authenticated;
create function public.founder_family_settings(p_number text default null) returns jsonb language sql security invoker set search_path='' as $$ select neria_family.founder_settings(p_number); $$;
create function public.founder_set_family_settings(p_number text,p_marriage_days integer,p_child_days integer,p_divorce_days integer,p_reason text,p_reset boolean default false) returns jsonb language sql security invoker set search_path='' as $$ select neria_family.founder_set_settings(p_number,p_marriage_days,p_child_days,p_divorce_days,p_reason,p_reset); $$;
revoke all on function public.founder_family_settings(text),public.founder_set_family_settings(text,integer,integer,integer,text,boolean) from public,anon;
grant execute on function public.founder_family_settings(text),public.founder_set_family_settings(text,integer,integer,integer,text,boolean) to authenticated;

create schema neria_government;
revoke all on schema neria_government from public,anon,authenticated;
grant usage on schema neria_government to authenticated;
create table neria_government.application_messages (
 id bigint generated always as identity primary key,
 application_id bigint not null references public.government_role_applications(id),
 sender_id uuid not null,
 founder_message boolean not null,
 body text not null check(length(btrim(body)) between 1 and 2000),
 nonce uuid not null,
 created_at timestamptz not null default now(),
 unique(sender_id,nonce)
);
create index on neria_government.application_messages(application_id,id);
create index on neria_government.application_messages(sender_id,created_at);
alter table neria_government.application_messages enable row level security;
revoke all on neria_government.application_messages from public,anon,authenticated;

create function neria_government.application_chat(p_application_id bigint,p_before bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.government_role_applications; messages jsonb; oldest bigint;
begin
 if auth.uid() is null then raise exception 'Войдите в аккаунт.'; end if;
 select * into a from public.government_role_applications where id=p_application_id;
 if a.id is null or not (public.is_founder() or (a.user_id=auth.uid() and public.is_current_user_active_citizen())) then raise exception 'Переписка доступна только заявителю и Основателю.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id::text,'mine',q.sender_id=auth.uid(),'founder',q.founder_message,'body',q.body,'created_at',q.created_at) order by q.id),'[]'),min(q.id) into messages,oldest from (
 select * from neria_government.application_messages where application_id=a.id and (p_before is null or id<p_before) order by id desc limit 100) q;
 return jsonb_build_object('application_id',a.id::text,'role',a.requested_role,'status',a.status,'statement',a.statement,'review_note',a.review_note,'applicant',(select nickname from public.citizens where id=a.citizen_id),'messages',messages,'has_more',exists(select 1 from neria_government.application_messages where application_id=a.id and id<oldest),'oldest',oldest::text);
end;
$$;
create function neria_government.send_application_message(p_application_id bigint,p_body text,p_nonce uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.government_role_applications; is_founder boolean; mid bigint;
begin
 if auth.uid() is null then raise exception 'Войдите в аккаунт.'; end if;
 is_founder=public.is_founder();
 select * into a from public.government_role_applications where id=p_application_id;
 if a.id is null or not (is_founder or (a.user_id=auth.uid() and public.is_current_user_active_citizen())) then raise exception 'Переписка доступна только заявителю и Основателю.'; end if;
 if p_nonce is null or p_body is null or length(btrim(p_body)) not between 1 and 2000 then raise exception 'Сообщение должно содержать от 1 до 2000 символов.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,80322));
 select id into mid from neria_government.application_messages where sender_id=auth.uid() and nonce=p_nonce and application_id=a.id and body=btrim(p_body);
 if mid is not null then return jsonb_build_object('id',mid::text); end if;
 if exists(select 1 from neria_government.application_messages where sender_id=auth.uid() and created_at>now()-interval '3 seconds') then raise exception 'Подождите 3 секунды перед следующим сообщением.'; end if;
 insert into neria_government.application_messages(application_id,sender_id,founder_message,body,nonce) values(a.id,auth.uid(),is_founder,btrim(p_body),p_nonce) returning id into mid;
 if is_founder then
   insert into public.notifications(user_id,kind,title,body,link) select a.user_id,'role_application_message','Ответ Основателя по вашей заявке','Откройте переписку по заявке на должность.','role-applications.html?application='||a.id::text where a.user_id<>auth.uid();
 else
   insert into public.notifications(user_id,kind,title,body,link) select user_id,'role_application_message','Новое сообщение по заявке на должность','Заявитель написал вам.','admin.html?application='||a.id::text from public.founders where user_id<>auth.uid();
 end if;
 return jsonb_build_object('id',mid::text);
end;
$$;
revoke all on all functions in schema neria_government from public,anon,authenticated;
grant execute on function neria_government.application_chat(bigint,bigint),neria_government.send_application_message(bigint,text,uuid) to authenticated;
create function public.role_application_chat(p_application_id bigint,p_before bigint default null) returns jsonb language sql security invoker set search_path='' as $$ select neria_government.application_chat(p_application_id,p_before); $$;
create function public.send_role_application_message(p_application_id bigint,p_body text,p_nonce uuid) returns jsonb language sql security invoker set search_path='' as $$ select neria_government.send_application_message(p_application_id,p_body,p_nonce); $$;
revoke all on function public.role_application_chat(bigint,bigint),public.send_role_application_message(bigint,text,uuid) from public,anon;
grant execute on function public.role_application_chat(bigint,bigint),public.send_role_application_message(bigint,text,uuid) to authenticated;
