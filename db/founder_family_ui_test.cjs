const fs=require('fs'),vm=require('vm'),assert=require('assert');
const tick=()=>new Promise(r=>setImmediate(r));
function element(){return {innerHTML:'',textContent:'',value:'',hidden:false,disabled:false,dataset:{},events:{},addEventListener(n,f){this.events[n]=f},reportValidity(){return true},querySelectorAll(){return []}};}
(async()=>{
 const nodes=new Map();const root=element();const get=id=>{if(!nodes.has(id))nodes.set(id,element());return nodes.get(id);};root.querySelector=get;
 const form=get('#familyOverrideForm');form.elements={marriage:{value:15},child:{value:30},divorce:{value:10},reason:{value:'Testing'}};
 const calls=[];const selected={number:'123',nickname:'Chosen citizen',marriage_days:15,child_days:30,divorce_days:10};
 const reply={selected:null,entries:[],history:[]};
 const client={rpc:(name,args)=>({abortSignal:async()=>{calls.push({name,args});return {data:{...reply,selected:args?.p_number?selected:null}}}})};
 const context={supabaseClient:client,document:{getElementById:()=>root},MutationObserver:class{observe(){}disconnect(){}},AbortSignal,confirm:()=>true};
 vm.runInNewContext(fs.readFileSync('founder-family.js','utf8'),context);await tick();
 assert.equal(calls[0].name,'founder_family_settings');get('#familyCitizenNumber').value='123';
 const lookup=get('#familyLookup');lookup.events.submit({preventDefault(){},target:lookup});await tick();assert.equal(form.hidden,false);
 // Editing the lookup box alone must not silently change the saved recipient.
 get('#familyCitizenNumber').value='999';form.elements.marriage.value=0;form.elements.child.value=0;form.elements.divorce.value=0;
 form.events.submit({preventDefault(){}});await tick();const save=calls.find(c=>c.name==='founder_set_family_settings');assert.equal(save.args.p_number,'123');assert.equal(save.args.p_marriage_days,0);assert.equal(save.args.p_child_days,0);assert.equal(save.args.p_divorce_days,0);
 assert(get('#familySettingsMessage').textContent.includes('Chosen citizen'));
 console.log('PASS: founder lookup, explicit selected citizen binding, 0-day settings submitted and confirmation displayed.');
})().catch(e=>{console.error(e);process.exitCode=1});
