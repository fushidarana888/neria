-- Run as a database administrator; fixtures and notifications are rolled back.
begin;
do $$
declare
 u uuid[] := array[]::uuid[]; c bigint[] := array[]::bigint[]; nums text[] := array[]::text[];
 uid uuid; cid bigint; num text; r uuid; m uuid; j jsonb; failed boolean; i integer;
begin
 for i in 1..8 loop
   uid=gen_random_uuid();
   insert into auth.users(id) values(uid);
   insert into public.citizens(user_id,nickname,birth_day,birth_month,created_at,first_name,surname,show_first_name,show_surname,show_birth_date)
   values(uid,'family-test-'||uid::text,1,1,now()-interval '100 days','PRIVATE-FIRST','PRIVATE-LAST',false,false,false)
   returning id,citizen_number::text into cid,num;
   u=array_append(u,uid); c=array_append(c,cid); nums=array_append(nums,num);
 end loop;
 perform set_config('request.jwt.claim.sub',u[1]::text,true);
 update public.citizens set created_at=now()-interval '15 days' where id=c[1];
 failed=false; begin perform public.family_action('propose',nums[2]); exception when others then failed=true; end;
 assert failed,'15 days exactly must be rejected';
 update public.citizens set created_at=now()-interval '16 days' where id=c[1];
 update public.citizens set created_at=now()-interval '14 days' where id=c[2];
 failed=false; begin perform public.family_action('propose',nums[2]); exception when others then failed=true; end;
 assert failed,'Both spouses need 15 days';
 update public.citizens set created_at=now()-interval '16 days' where id=c[2];
 perform public.family_action('propose',nums[2]);
 select id into r from neria_family.requests where proposer=c[1] and status='pending';
 -- Only recipient can accept; unrelated users cannot even see requests.
 perform set_config('request.jwt.claim.sub',u[3]::text,true);
 assert jsonb_array_length(public.family_dashboard()->'requests')=0,'Invitation privacy';
 failed=false; begin perform public.family_action('accept',r::text); exception when others then failed=true; end;
 assert failed,'Outsider cannot accept';
 perform set_config('request.jwt.claim.sub',u[1]::text,true);
 failed=false; begin perform public.family_action('accept',r::text); exception when others then failed=true; end;
 assert failed,'Proposer cannot self-accept';
 perform set_config('request.jwt.claim.sub',u[2]::text,true);
 perform public.family_action('accept',r::text);
 j=public.family_dashboard();
 assert j->'marriage'->'partner'->>'first_name'='PRIVATE-FIRST','Spouse sees hidden fields';
 m=(j->'marriage'->>'id')::uuid;
 failed=false; begin perform public.family_action('accept',r::text); exception when others then failed=true; end;
 assert failed,'Double acceptance rejected';
 failed=false; begin perform public.family_action('divorce',m::text); exception when others then failed=true; end;
 assert failed,'Early divorce rejected';
 failed=false; begin perform public.family_action('propose',nums[3]); exception when others then failed=true; end;
 assert failed,'Second concurrent marriage rejected';
 -- First child: both parents plus child must agree. Boundary checks at 30/60/90.
 for i in 1..3 loop
   perform set_config('request.jwt.claim.sub',u[1]::text,true);
   update neria_family.marriages set registered_at=now()-(i*30)*interval '1 day' where id=m;
   failed=false; begin perform public.family_action('invite_child',nums[i+2]); exception when others then failed=true; end;
   assert failed,'Child threshold is strictly more than 30/60/90 days';
   update neria_family.marriages set registered_at=registered_at-interval '1 second' where id=m;
   perform public.family_action('invite_child',nums[i+2]);
   select id into r from neria_family.requests where marriage_id=m and status='pending';
   perform set_config('request.jwt.claim.sub',u[i+2]::text,true);
   perform public.family_action('accept',r::text);
   assert (select count(*) from neria_family.children where marriage_id=m)=i-1,'Wait for second parent consent';
   perform set_config('request.jwt.claim.sub',u[2]::text,true);
   perform public.family_action('accept',r::text);
   assert (select count(*) from neria_family.children where marriage_id=m)=i,'Child accepted with all consents';
 end loop;
 failed=false; begin perform public.family_action('invite_child',nums[6]); exception when others then failed=true; end;
 assert failed,'Maximum three children';
 perform set_config('request.jwt.claim.sub',u[3]::text,true);
 j=public.family_dashboard();
 assert j->'marriage'='null'::jsonb and jsonb_array_length(j->'parents')=1,'Child has parent information but no spouse private data';
 -- Divorce on day 10, archive, no private data, cooldown applies to both.
 update neria_family.marriages set registered_at=now()-interval '10 days' where id=m;
 perform set_config('request.jwt.claim.sub',u[1]::text,true);
 perform public.family_action('divorce',m::text);
 j=public.family_dashboard();
 assert j->'marriage'='null'::jsonb and j::text not like '%PRIVATE-FIRST%','Private fields inaccessible after divorce';
 assert jsonb_array_length(j->'history')=1,'Divorce history retained';
 for i in 1..2 loop
   perform set_config('request.jwt.claim.sub',u[i]::text,true);
   failed=false; begin perform public.family_action('propose',nums[6]); exception when others then failed=true; end;
   assert failed,'Both former spouses must wait one month';
 end loop;
 update neria_family.marriages set divorced_at=now()-interval '32 days' where id=m;
 perform set_config('request.jwt.claim.sub',u[1]::text,true);
 perform public.family_action('propose',nums[6]);
 select id into r from neria_family.requests where proposer=c[1] and status='pending';
 -- Recheck target status on acceptance.
 update public.citizens set citizenship_status='banned' where id=c[1];
 perform set_config('request.jwt.claim.sub',u[6]::text,true);
 failed=false; begin perform public.family_action('accept',r::text); exception when others then failed=true; end;
 assert failed,'Recheck active status before registering';
 update public.citizens set citizenship_status='active' where id=c[1];
 perform public.family_action('accept',r::text);
 m=(public.family_dashboard()->'marriage'->>'id')::uuid;
 update public.citizens set citizenship_status='banned' where id=c[1];
 assert (public.family_dashboard()->'marriage'->>'id')::uuid=m,'Ban does not automatically dissolve marriage';
 perform set_config('request.jwt.claim.sub',u[1]::text,true);
 failed=false; begin perform public.family_dashboard(); exception when others then failed=true; end;
 assert failed,'Banned citizen cannot read family data';
 perform set_config('request.jwt.claim.sub',u[6]::text,true);
 perform public.family_action('divorce',m::text);
 assert public.family_dashboard()->'marriage'='null'::jsonb,'Immediate divorce when spouse banned';
 -- Anonymous and table permissions.
 perform set_config('request.jwt.claim.sub','',true);
 failed=false; begin perform public.family_dashboard(); exception when others then failed=true; end;
 assert failed,'Anonymous access rejected';
 assert not has_function_privilege('anon','public.family_dashboard()','EXECUTE'),'No anon RPC';
 assert not has_function_privilege('authenticated','neria_family.assert_eligible(bigint)','EXECUTE'),'Helpers not callable';
 assert not has_table_privilege('authenticated','neria_family.marriages','SELECT'),'No direct table access';
 assert not has_table_privilege('authenticated','neria_family.marriages','INSERT'),'No client writes';
 assert has_function_privilege('authenticated','public.family_action(text,text)','EXECUTE'),'Authenticated RPC available';
end;
$$;
rollback;
