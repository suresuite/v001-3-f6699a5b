import {writeFileSync} from 'node:fs';
const query = `select jsonb_build_object(
 'fence', (select max(version) from supabase_migrations.schema_migrations),
 'functions', (select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,
   'security_definer',p.prosecdef,'anon_execute',has_function_privilege('anon',p.oid,'EXECUTE'),
   'authenticated_execute',has_function_privilege('authenticated',p.oid,'EXECUTE'),
   'service_execute',has_function_privilege('service_role',p.oid,'EXECUTE'),
   'language',l.lanname) order by p.proname)
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname='public'),
 'policies', (select jsonb_agg(to_jsonb(p)) from pg_policies p where schemaname in ('public','storage','realtime')),
 'grants', (select jsonb_agg(jsonb_build_object('schema',n.nspname,'table',c.relname,'role',r.rolname,
   'select',has_table_privilege(r.rolname,c.oid,'SELECT'),'insert',has_table_privilege(r.rolname,c.oid,'INSERT'),
   'update',has_table_privilege(r.rolname,c.oid,'UPDATE'),'delete',has_table_privilege(r.rolname,c.oid,'DELETE'),
   'rls',c.relrowsecurity)) from pg_class c join pg_namespace n on n.oid=c.relnamespace
   cross join (values ('anon'),('authenticated'),('service_role')) r(rolname)
   where n.nspname in ('public','storage','realtime') and c.relkind in ('r','v'))
) as security_metadata`;
if (!/^select\b/i.test(query.trim()) || query.includes(';')) throw Error('Read-only metadata SELECT required');
const token=process.env.SUPABASE_ACCESS_TOKEN;
if(!token) throw Error('No management credential configured');
const response=await fetch('https://api.supabase.com/v1/projects/wckdrutwkytwcomrlpib/database/query',{
 method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({query})});
if(!response.ok)throw Error(`Metadata request failed (${response.status})`);
const result=await response.json();
const report='# D28 security metadata preflight\n\nMetadata only. No tenant rows, credentials, or negative access probes.\n\n```json\n'+JSON.stringify(result,null,2)+'\n```\n';
writeFileSync(process.argv[process.argv.indexOf('--out')+1]||'verification.md',report);
console.log('Security metadata read completed; no production data or writes requested.');
