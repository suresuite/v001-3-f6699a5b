<!-- run_id: 39281747390  outcome: success -->
<!-- trigger: push  ref: codex/security-identity-tenancy  sha: 4df190c57852603ce6b770d6b2a8789b5d3dc751 -->
# D28 security metadata preflight

Metadata only. No tenant rows, credentials, or negative access probes.

```json
[
  {
    "security_metadata": {
      "fence": "20261009000003",
      "grants": [
        {
          "rls": true,
          "role": "anon",
          "table": "external_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "external_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "external_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "disruption_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "disruption_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "disruption_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "schema_migrations",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "schema_migrations",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "schema_migrations",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "migrations",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "migrations",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "migrations",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "disruption_scenario_profiles",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "disruption_scenario_profiles",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "disruption_scenario_profiles",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "disruption_scenario_effects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "disruption_scenario_effects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "disruption_scenario_effects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "disruption_scenario_targets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "disruption_scenario_targets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "disruption_scenario_targets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "disruption_scenario_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "disruption_scenario_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "disruption_scenario_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "s3_multipart_uploads_parts",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "s3_multipart_uploads_parts",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "s3_multipart_uploads_parts",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "objects",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "objects",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "objects",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "s3_multipart_uploads",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "s3_multipart_uploads",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "s3_multipart_uploads",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "outbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "outbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "outbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "multi_tier_supply_chain",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "multi_tier_supply_chain",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "multi_tier_supply_chain",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "bom_single_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "bom_single_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "bom_single_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "subscription",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": true,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "subscription",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": true,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "subscription",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "projects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "projects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "projects",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "customers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "customers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "customers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "node_list",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "node_list",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "node_list",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "buckets_analytics",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "buckets_analytics",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "buckets_analytics",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_cache",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_cache",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_cache",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_performance_metrics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_performance_metrics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_performance_metrics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_jobs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_jobs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_jobs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "proposals",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "proposals",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "proposals",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "project_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "project_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "project_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_chat_events",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_chat_events",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_chat_events",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "supply_chain_data_multi_tier",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "supply_chain_data_multi_tier",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "supply_chain_data_multi_tier",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "buckets_vectors",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "buckets_vectors",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "buckets_vectors",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "vector_indexes",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "vector_indexes",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "vector_indexes",
          "delete": false,
          "insert": false,
          "schema": "storage",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "sim_engine_builds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "sim_engine_builds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "sim_engine_builds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "organizations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "organizations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "organizations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "simulation_results_with_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "simulation_results_with_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "simulation_results_with_settings",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "network_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "network_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "network_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "simulation_result_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "simulation_result_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "simulation_result_scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "network_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "network_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "network_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "api_keys",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "api_keys",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "api_keys",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "api_request_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "api_request_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "api_request_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_job_magnitudes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_job_magnitudes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_job_magnitudes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "inbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "inbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "inbound_logistics",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "api_idempotency",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "api_idempotency",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "api_idempotency",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "policy_presets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "policy_presets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "policy_presets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "api_rate_limits",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "api_rate_limits",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "api_rate_limits",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "docs_section_releases",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "docs_section_releases",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "docs_section_releases",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "docs_faq",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "docs_faq",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "docs_faq",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "experiments",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "experiments",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "experiments",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "run_replications",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "run_replications",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "run_replications",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "approved_users",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "approved_users",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "approved_users",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "organization_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "organization_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "organization_members",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "sc_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "sc_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "sc_nodes",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "sc_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "sc_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "sc_edges",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "project_role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "project_role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "project_role_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "scenarios",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_providers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_providers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_providers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_models",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_models",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_models",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "recovery_playbooks",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "recovery_playbooks",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "recovery_playbooks",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "policy_overrides",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "policy_overrides",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "policy_overrides",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "policy_defaults",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "policy_defaults",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "policy_defaults",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "scenario_templates",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "scenario_templates",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "scenario_templates",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "delegation_grants",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "delegation_grants",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "delegation_grants",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "policy_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "policy_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "policy_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "user_ai_permissions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "user_ai_permissions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "user_ai_permissions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_21",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_21",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_21",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_usage_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_usage_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_usage_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "audit_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "audit_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "audit_logs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_budgets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_budgets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_budgets",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "project_graph_state",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "project_graph_state",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "project_graph_state",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "dataset_versions",
          "delete": true,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "dataset_versions",
          "delete": true,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "dataset_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "project_memory",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "project_memory",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "project_memory",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "org_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "org_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "org_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "chat_threads",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "chat_threads",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "chat_threads",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "v_admin_user_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "v_admin_user_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "v_admin_user_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "user_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "user_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "user_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "chat_folders",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "chat_folders",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "chat_folders",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "chat_messages",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "chat_messages",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "chat_messages",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ai_model_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ai_model_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ai_model_capabilities",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "analysis_kinds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "analysis_kinds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "analysis_kinds",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "model_validation_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "model_validation_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "model_validation_evidence",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "run_item_series",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "run_item_series",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "run_item_series",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "user_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "user_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "user_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "model_validations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "model_validations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "model_validations",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "admin_org_file_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": false,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "admin_org_file_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "admin_org_file_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_staged_rows",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_staged_rows",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_staged_rows",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "tier2_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "tier2_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "tier2_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "supply_chain_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "supply_chain_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "supply_chain_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "network_summary",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "network_summary",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "network_summary",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "chat_plans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "chat_plans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "chat_plans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "sim_engines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "sim_engines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "sim_engines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "tier3_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "tier3_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "tier3_suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "simulation_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "simulation_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "simulation_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "materials",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "materials",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "materials",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "admin_audit_logs",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "admin_audit_logs",
          "delete": true,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "admin_audit_logs",
          "delete": true,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "bom_multi_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "bom_multi_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "bom_multi_level",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "suppliers",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "password_reset_requests",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "password_reset_requests",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "password_reset_requests",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_staged_products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_staged_products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_staged_products",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_staged_bom_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_staged_bom_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_staged_bom_versions",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_staged_bom_lines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_staged_bom_lines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_staged_bom_lines",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "risk_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "risk_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "risk_data",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_files",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "ingest_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "ingest_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "ingest_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "analysis_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "analysis_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "analysis_results",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "analysis_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "analysis_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "analysis_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "buckets",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "buckets",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "buckets",
          "delete": true,
          "insert": true,
          "schema": "storage",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "project_erp_links",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "project_erp_links",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "project_erp_links",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_22",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_22",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_22",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "anon",
          "table": "surrogate_training_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "surrogate_training_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "surrogate_training_runs",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "plan_role_allowances",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "plan_role_allowances",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "plan_role_allowances",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_16",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_16",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_16",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "run_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "run_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "run_usage",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "run_series_orphans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "run_series_orphans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "run_series_orphans",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "anon",
          "table": "graph_level_versions",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "graph_level_versions",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": false
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "graph_level_versions",
          "delete": false,
          "insert": false,
          "schema": "public",
          "select": true,
          "update": false
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_17",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_17",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_17",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_18",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_18",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_18",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_19",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_19",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_19",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "anon",
          "table": "messages_2026_10_20",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "authenticated",
          "table": "messages_2026_10_20",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": false,
          "role": "service_role",
          "table": "messages_2026_10_20",
          "delete": false,
          "insert": false,
          "schema": "realtime",
          "select": false,
          "update": false
        },
        {
          "rls": true,
          "role": "anon",
          "table": "demand_forecasts",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "authenticated",
          "table": "demand_forecasts",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        },
        {
          "rls": true,
          "role": "service_role",
          "table": "demand_forecasts",
          "delete": true,
          "insert": true,
          "schema": "public",
          "select": true,
          "update": true
        }
      ],
      "policies": [
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "external_evidence",
          "permissive": "PERMISSIVE",
          "policyname": "external_evidence_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenarios.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenarios",
          "permissive": "PERMISSIVE",
          "policyname": "Disruption scenarios: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenarios.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenarios",
          "permissive": "PERMISSIVE",
          "policyname": "Disruption scenarios: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenarios.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_results.project_id) AND (p.organization = get_current_user_org()))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_results",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation results: organization access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_results.project_id) AND (p.organization = get_current_user_org()))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_results.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_results",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation results: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_results.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_results",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation results: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_results.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenario_profiles.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_profiles",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario profiles: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenario_profiles.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_profiles",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario profiles: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = disruption_scenario_profiles.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_effects.profile_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_effects",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario effects: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_effects.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_effects",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario effects: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_effects.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_targets.profile_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_targets",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario targets: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_targets.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_targets",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario targets: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_targets.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_settings.profile_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_settings",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario settings: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_settings.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "disruption_scenario_settings",
          "permissive": "PERMISSIVE",
          "policyname": "Scenario settings: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM (disruption_scenario_profiles sp\n     JOIN projects p ON ((p.id = sp.project_id)))\n  WHERE ((sp.id = disruption_scenario_settings.profile_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(bucket_id = 'avatars'::text)",
          "roles": [
            "public"
          ],
          "tablename": "objects",
          "permissive": "PERMISSIVE",
          "policyname": "Avatars are publicly readable",
          "schemaname": "storage",
          "with_check": null
        },
        {
          "cmd": "DELETE",
          "qual": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = COALESCE((get_current_user_id())::text, '__none__'::text)))",
          "roles": [
            "public"
          ],
          "tablename": "objects",
          "permissive": "PERMISSIVE",
          "policyname": "Users can delete their own avatar",
          "schemaname": "storage",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = COALESCE((get_current_user_id())::text, '__none__'::text)))",
          "roles": [
            "public"
          ],
          "tablename": "objects",
          "permissive": "PERMISSIVE",
          "policyname": "Users can update their own avatar",
          "schemaname": "storage",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "objects",
          "permissive": "PERMISSIVE",
          "policyname": "Users can upload their own avatar",
          "schemaname": "storage",
          "with_check": "((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = COALESCE((get_current_user_id())::text, '__none__'::text)))"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = outbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "outbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "Outbound: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = outbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = outbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "outbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "Outbound: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "outbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "outbound_logistics_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "outbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "outbound_logistics_auth_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = multi_tier_supply_chain.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "multi_tier_supply_chain",
          "permissive": "PERMISSIVE",
          "policyname": "Multi-tier: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = multi_tier_supply_chain.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = multi_tier_supply_chain.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "multi_tier_supply_chain",
          "permissive": "PERMISSIVE",
          "policyname": "Multi-tier: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_single_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "bom_single_level",
          "permissive": "PERMISSIVE",
          "policyname": "BOM Single: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_single_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_single_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "bom_single_level",
          "permissive": "PERMISSIVE",
          "policyname": "BOM Single: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "bom_single_level",
          "permissive": "PERMISSIVE",
          "policyname": "bom_single_level_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "bom_single_level",
          "permissive": "PERMISSIVE",
          "policyname": "bom_single_level_auth_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "projects",
          "permissive": "PERMISSIVE",
          "policyname": "Projects: org create by modeler or admin",
          "schemaname": "public",
          "with_check": "(org_is_current_user_org(organization_id, organization) AND (((( SELECT get_current_approved_user.user_role\n   FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n LIMIT 1) = 'modeler'::text) AND (modeler_id = get_current_user_id())) OR (( SELECT get_current_approved_user.user_role\n   FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n LIMIT 1) = 'admin'::text)))"
        },
        {
          "cmd": "DELETE",
          "qual": "(org_is_current_user_org(organization_id, organization) AND ((modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n   FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n LIMIT 1) = 'admin'::text)))",
          "roles": [
            "public"
          ],
          "tablename": "projects",
          "permissive": "PERMISSIVE",
          "policyname": "Projects: org delete by owner or admin",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "(org_is_current_user_org(organization_id, organization) AND ((modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n   FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n LIMIT 1) = 'admin'::text)))",
          "roles": [
            "public"
          ],
          "tablename": "projects",
          "permissive": "PERMISSIVE",
          "policyname": "Projects: org update by owner or admin",
          "schemaname": "public",
          "with_check": "(org_is_current_user_org(organization_id, organization) AND ((modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n   FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n LIMIT 1) = 'admin'::text)))"
        },
        {
          "cmd": "SELECT",
          "qual": "org_is_current_user_org(organization_id, organization)",
          "roles": [
            "public"
          ],
          "tablename": "projects",
          "permissive": "PERMISSIVE",
          "policyname": "Projects: org-wide view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = customers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "customers",
          "permissive": "PERMISSIVE",
          "policyname": "Customers: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = customers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = customers.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "customers",
          "permissive": "PERMISSIVE",
          "policyname": "Customers: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "customers",
          "permissive": "PERMISSIVE",
          "policyname": "customers_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "customers",
          "permissive": "PERMISSIVE",
          "policyname": "customers_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = node_list.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "node_list",
          "permissive": "PERMISSIVE",
          "policyname": "Node list: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "node_list",
          "permissive": "PERMISSIVE",
          "policyname": "Node list: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = node_list.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = node_list.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "node_list",
          "permissive": "PERMISSIVE",
          "policyname": "Node list: project access update",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = node_list.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = node_list.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "node_list",
          "permissive": "PERMISSIVE",
          "policyname": "Node list: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_cache.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_cache",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation cache: project access modify",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_cache.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_cache",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation cache: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_performance_metrics.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_performance_metrics",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation metrics: project access modify",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_performance_metrics.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_performance_metrics",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation metrics: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_jobs.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_jobs",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation jobs: project access modify",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_jobs.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_jobs",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation jobs: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "proposals",
          "permissive": "PERMISSIVE",
          "policyname": "proposals_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "((user_id = get_current_user_id()) OR (EXISTS ( SELECT 1\n   FROM project_members m\n  WHERE ((m.project_id = project_members.project_id) AND (m.user_id = get_current_user_id())))) OR current_is_super_admin())",
          "roles": [
            "public"
          ],
          "tablename": "project_members",
          "permissive": "PERMISSIVE",
          "policyname": "project_members: read own and co-members",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "ai_chat_events",
          "permissive": "PERMISSIVE",
          "policyname": "chat_events: super read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "ai_chat_events",
          "permissive": "PERMISSIVE",
          "policyname": "chat_events: user read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data_multi_tier.project_id) AND (p.organization = get_current_user_org()) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data_multi_tier",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data multi-tier: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data_multi_tier",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data multi-tier: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data_multi_tier.project_id) AND (p.organization = get_current_user_org()) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data_multi_tier.project_id) AND (p.organization = get_current_user_org()) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data_multi_tier",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data multi-tier: project access update",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data_multi_tier.project_id) AND (p.organization = get_current_user_org()) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data_multi_tier.project_id) AND (p.organization = get_current_user_org()))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data_multi_tier",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data multi-tier: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "sim_engine_builds",
          "permissive": "PERMISSIVE",
          "policyname": "sim_engine_builds_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(id = get_current_user_org_id(get_current_user_id()))",
          "roles": [
            "public"
          ],
          "tablename": "organizations",
          "permissive": "PERMISSIVE",
          "policyname": "orgs: members read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "organizations",
          "permissive": "PERMISSIVE",
          "policyname": "orgs: super admin full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_edges.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_edges",
          "permissive": "PERMISSIVE",
          "policyname": "Network edges: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "network_edges",
          "permissive": "PERMISSIVE",
          "policyname": "Network edges: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_edges.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_edges.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_edges",
          "permissive": "PERMISSIVE",
          "policyname": "Network edges: project access update",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_edges.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "network_edges",
          "permissive": "PERMISSIVE",
          "policyname": "Network edges: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_nodes.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_nodes",
          "permissive": "PERMISSIVE",
          "policyname": "Network nodes: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "network_nodes",
          "permissive": "PERMISSIVE",
          "policyname": "Network nodes: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_nodes.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_nodes.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_nodes",
          "permissive": "PERMISSIVE",
          "policyname": "Network nodes: project access update",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_nodes.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "network_nodes",
          "permissive": "PERMISSIVE",
          "policyname": "Network nodes: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "api_request_logs",
          "permissive": "PERMISSIVE",
          "policyname": "api_logs: super read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_job_magnitudes.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_job_magnitudes",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation job magnitudes: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_job_magnitudes.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT g.user_role\n           FROM get_current_approved_user() g(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = simulation_job_magnitudes.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "simulation_job_magnitudes",
          "permissive": "PERMISSIVE",
          "policyname": "Simulation job magnitudes: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = inbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "inbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "Inbound: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = inbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = inbound_logistics.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "inbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "Inbound: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "inbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "inbound_logistics_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "inbound_logistics",
          "permissive": "PERMISSIVE",
          "policyname": "inbound_logistics_auth_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_presets",
          "permissive": "PERMISSIVE",
          "policyname": "Anon can read policy presets",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "((is_system = true) OR (owner_id = auth.uid()))",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_presets",
          "permissive": "PERMISSIVE",
          "policyname": "Anyone signed in can read system presets",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_presets",
          "permissive": "PERMISSIVE",
          "policyname": "Users can create their own presets",
          "schemaname": "public",
          "with_check": "((owner_id = auth.uid()) AND (is_system = false))"
        },
        {
          "cmd": "DELETE",
          "qual": "(owner_id = auth.uid())",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_presets",
          "permissive": "PERMISSIVE",
          "policyname": "Users can delete their own presets",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "(owner_id = auth.uid())",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_presets",
          "permissive": "PERMISSIVE",
          "policyname": "Users can update their own presets",
          "schemaname": "public",
          "with_check": "(owner_id = auth.uid())"
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "api_rate_limits",
          "permissive": "PERMISSIVE",
          "policyname": "api_limits: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "docs_section_releases",
          "permissive": "PERMISSIVE",
          "policyname": "docs_section_releases_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "experiments",
          "permissive": "PERMISSIVE",
          "policyname": "experiments_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "capabilities: read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "capabilities: super write",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "run_replications",
          "permissive": "PERMISSIVE",
          "policyname": "rep_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "run_replications",
          "permissive": "PERMISSIVE",
          "policyname": "run_replications_anon_write",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "role_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "role_caps: read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "role_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "role_caps: super write",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "ALL",
          "qual": "false",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "approved_users",
          "permissive": "PERMISSIVE",
          "policyname": "No direct access - use RPCs",
          "schemaname": "public",
          "with_check": "false"
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "organization_members",
          "permissive": "PERMISSIVE",
          "policyname": "org_members: read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "organization_members",
          "permissive": "PERMISSIVE",
          "policyname": "org_members: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "project_role_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "project_role_capabilities: read all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "scenarios",
          "permissive": "PERMISSIVE",
          "policyname": "scenarios_anon_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "scenarios",
          "permissive": "PERMISSIVE",
          "policyname": "scenarios_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "ai_providers",
          "permissive": "PERMISSIVE",
          "policyname": "ai_providers: read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "ai_providers",
          "permissive": "PERMISSIVE",
          "policyname": "ai_providers: super write",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "ai_models",
          "permissive": "PERMISSIVE",
          "policyname": "ai_models: read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "ai_models",
          "permissive": "PERMISSIVE",
          "policyname": "ai_models: super write",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "DELETE",
          "qual": "((is_system = false) AND (created_by = auth.uid()))",
          "roles": [
            "authenticated"
          ],
          "tablename": "recovery_playbooks",
          "permissive": "PERMISSIVE",
          "policyname": "playbooks_delete_own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "authenticated"
          ],
          "tablename": "recovery_playbooks",
          "permissive": "PERMISSIVE",
          "policyname": "playbooks_insert_own",
          "schemaname": "public",
          "with_check": "((is_system = false) AND (project_id IS NOT NULL) AND (created_by = auth.uid()))"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "recovery_playbooks",
          "permissive": "PERMISSIVE",
          "policyname": "playbooks_select_all_auth",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "((is_system = false) AND (created_by = auth.uid()))",
          "roles": [
            "authenticated"
          ],
          "tablename": "recovery_playbooks",
          "permissive": "PERMISSIVE",
          "policyname": "playbooks_update_own",
          "schemaname": "public",
          "with_check": "((is_system = false) AND (created_by = auth.uid()))"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_overrides",
          "permissive": "PERMISSIVE",
          "policyname": "Anon can read policy overrides",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "DELETE",
          "qual": "(auth.uid() IS NOT NULL)",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_overrides",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can delete policy overrides",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_overrides",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can insert policy overrides",
          "schemaname": "public",
          "with_check": "(auth.uid() IS NOT NULL)"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_overrides",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can read policy overrides",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "(auth.uid() IS NOT NULL)",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_overrides",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can update policy overrides",
          "schemaname": "public",
          "with_check": "(auth.uid() IS NOT NULL)"
        },
        {
          "cmd": "DELETE",
          "qual": "(auth.uid() IS NOT NULL)",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_defaults",
          "permissive": "PERMISSIVE",
          "policyname": "Admins can delete policy defaults",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_defaults",
          "permissive": "PERMISSIVE",
          "policyname": "Anon can read policy defaults",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_defaults",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can read policy defaults",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "UPDATE",
          "qual": "(auth.uid() IS NOT NULL)",
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_defaults",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can update policy defaults",
          "schemaname": "public",
          "with_check": "(auth.uid() IS NOT NULL)"
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "authenticated"
          ],
          "tablename": "policy_defaults",
          "permissive": "PERMISSIVE",
          "policyname": "Authenticated users can upsert policy defaults",
          "schemaname": "public",
          "with_check": "(auth.uid() IS NOT NULL)"
        },
        {
          "cmd": "SELECT",
          "qual": "(is_system = true)",
          "roles": [
            "authenticated"
          ],
          "tablename": "scenario_templates",
          "permissive": "PERMISSIVE",
          "policyname": "Anyone authenticated can read system templates",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "((grantor_user_id = get_current_user_id()) OR (grantee_user_id = get_current_user_id()) OR current_is_super_admin())",
          "roles": [
            "public"
          ],
          "tablename": "delegation_grants",
          "permissive": "PERMISSIVE",
          "policyname": "delegation_grants: read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_versions",
          "permissive": "PERMISSIVE",
          "policyname": "policy_versions_anon_insert",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_versions",
          "permissive": "PERMISSIVE",
          "policyname": "policy_versions_insert_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "policy_versions",
          "permissive": "PERMISSIVE",
          "policyname": "policy_versions_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "user_ai_permissions",
          "permissive": "PERMISSIVE",
          "policyname": "uap: read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "user_ai_permissions",
          "permissive": "PERMISSIVE",
          "policyname": "uap: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "ai_usage_logs",
          "permissive": "PERMISSIVE",
          "policyname": "usage: super read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "ai_usage_logs",
          "permissive": "PERMISSIVE",
          "policyname": "usage: user read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "((plane = ANY (ARRAY['data'::text, 'access'::text])) AND (EXISTS ( SELECT 1\n   FROM (approved_users me\n     JOIN approved_users actor ON ((actor.id = audit_logs.actor_user_id)))\n  WHERE ((me.id = get_current_user_id()) AND (me.role = 'admin'::app_role) AND (me.organization_id IS NOT NULL) AND (me.organization_id = actor.organization_id)))))",
          "roles": [
            "public"
          ],
          "tablename": "audit_logs",
          "permissive": "PERMISSIVE",
          "policyname": "audit: org admins read their own org's data and access rows",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "audit_logs",
          "permissive": "PERMISSIVE",
          "policyname": "audit: super read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "ai_budgets",
          "permissive": "PERMISSIVE",
          "policyname": "budgets: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "((scope = 'user'::text) AND (scope_id = get_current_user_id()))",
          "roles": [
            "public"
          ],
          "tablename": "ai_budgets",
          "permissive": "PERMISSIVE",
          "policyname": "budgets: user reads own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "has_project_access(project_id)",
          "roles": [
            "public"
          ],
          "tablename": "project_graph_state",
          "permissive": "PERMISSIVE",
          "policyname": "project_graph_state_select",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "dataset_versions",
          "permissive": "PERMISSIVE",
          "policyname": "dataset_versions_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "project_memory",
          "permissive": "PERMISSIVE",
          "policyname": "project_memory_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM organization_members m\n  WHERE ((m.org_id = org_capabilities.org_id) AND (m.user_id = get_current_user_id()))))",
          "roles": [
            "public"
          ],
          "tablename": "org_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "org_caps: members read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "org_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "org_caps: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "chat_threads",
          "permissive": "PERMISSIVE",
          "policyname": "chat_threads: owner read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "user_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "user_caps: read own",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "user_capabilities",
          "permissive": "PERMISSIVE",
          "policyname": "user_caps: super full",
          "schemaname": "public",
          "with_check": "current_is_super_admin()"
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "public"
          ],
          "tablename": "chat_folders",
          "permissive": "PERMISSIVE",
          "policyname": "chat_folders: owner read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM chat_threads t\n  WHERE ((t.id = chat_messages.thread_id) AND (t.user_id = get_current_user_id()))))",
          "roles": [
            "public"
          ],
          "tablename": "chat_messages",
          "permissive": "PERMISSIVE",
          "policyname": "chat_messages: owner read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "analysis_kinds",
          "permissive": "PERMISSIVE",
          "policyname": "analysis_kinds_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "has_project_access(project_id)",
          "roles": [
            "public"
          ],
          "tablename": "model_validation_evidence",
          "permissive": "PERMISSIVE",
          "policyname": "model_validation_evidence_select",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "run_item_series",
          "permissive": "PERMISSIVE",
          "policyname": "run_item_series_anon_write",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "run_item_series",
          "permissive": "PERMISSIVE",
          "policyname": "run_item_series_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "(user_id = get_current_user_id())",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "user_files",
          "permissive": "PERMISSIVE",
          "policyname": "user_files_owner_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "current_is_super_admin()",
          "roles": [
            "public"
          ],
          "tablename": "user_files",
          "permissive": "PERMISSIVE",
          "policyname": "user_files_super_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "model_validations",
          "permissive": "PERMISSIVE",
          "policyname": "model_validations_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_rows.ingest_run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_staged_rows",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_staged_rows: project access",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_rows.ingest_run_id) AND has_project_access(r.project_id))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier2_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "tier2_suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "Tier2: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier2_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "tier2_suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "Tier2: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier2_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data: project access update",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = supply_chain_data.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "supply_chain_data",
          "permissive": "PERMISSIVE",
          "policyname": "Supply chain data: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "DELETE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_summary.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_summary",
          "permissive": "PERMISSIVE",
          "policyname": "Network summary: project access delete",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "INSERT",
          "qual": null,
          "roles": [
            "public"
          ],
          "tablename": "network_summary",
          "permissive": "PERMISSIVE",
          "policyname": "Network summary: project access insert",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_summary.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "UPDATE",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_summary.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "network_summary",
          "permissive": "PERMISSIVE",
          "policyname": "Network summary: project access update",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = network_summary.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "network_summary",
          "permissive": "PERMISSIVE",
          "policyname": "Network summary: project access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "chat_plans",
          "permissive": "PERMISSIVE",
          "policyname": "chat_plans_read_all",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "sim_engines",
          "permissive": "PERMISSIVE",
          "policyname": "sim_engines_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier3_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "tier3_suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "Tier3: organization access view",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier3_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "tier3_suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "Tier3: project access modify",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = tier3_suppliers.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "simulation_runs",
          "permissive": "PERMISSIVE",
          "policyname": "sim_runs_anon_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "simulation_runs",
          "permissive": "PERMISSIVE",
          "policyname": "sim_runs_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "products",
          "permissive": "PERMISSIVE",
          "policyname": "products_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "products",
          "permissive": "PERMISSIVE",
          "policyname": "products_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "materials",
          "permissive": "PERMISSIVE",
          "policyname": "materials_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "materials",
          "permissive": "PERMISSIVE",
          "policyname": "materials_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_multi_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "bom_multi_level",
          "permissive": "PERMISSIVE",
          "policyname": "BOM Multi: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_multi_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = bom_multi_level.project_id) AND org_is_current_user_org(p.organization_id, p.organization))))",
          "roles": [
            "public"
          ],
          "tablename": "bom_multi_level",
          "permissive": "PERMISSIVE",
          "policyname": "BOM Multi: organization access",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "bom_multi_level",
          "permissive": "PERMISSIVE",
          "policyname": "bom_multi_level_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "bom_multi_level",
          "permissive": "PERMISSIVE",
          "policyname": "bom_multi_level_auth_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "suppliers_anon_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "true",
          "roles": [
            "authenticated"
          ],
          "tablename": "suppliers",
          "permissive": "PERMISSIVE",
          "policyname": "suppliers_auth_all",
          "schemaname": "public",
          "with_check": "true"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_products.ingest_run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_staged_products",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_staged_products: project access",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_products.ingest_run_id) AND has_project_access(r.project_id))))"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_bom_versions.ingest_run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_staged_bom_versions",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_staged_bom_versions: project access",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_bom_versions.ingest_run_id) AND has_project_access(r.project_id))))"
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_bom_lines.ingest_run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_staged_bom_lines",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_staged_bom_lines: project access",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_staged_bom_lines.ingest_run_id) AND has_project_access(r.project_id))))"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "public"
          ],
          "tablename": "risk_data",
          "permissive": "PERMISSIVE",
          "policyname": "Enable read access for all users",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "risk_data",
          "permissive": "PERMISSIVE",
          "policyname": "risk_data_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_files.ingest_run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_files",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_files: project access",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM ingest_runs r\n  WHERE ((r.id = ingest_files.ingest_run_id) AND has_project_access(r.project_id))))"
        },
        {
          "cmd": "ALL",
          "qual": "has_project_access(project_id)",
          "roles": [
            "authenticated"
          ],
          "tablename": "ingest_runs",
          "permissive": "PERMISSIVE",
          "policyname": "ingest_runs: project access",
          "schemaname": "public",
          "with_check": "has_project_access(project_id)"
        },
        {
          "cmd": "SELECT",
          "qual": "(EXISTS ( SELECT 1\n   FROM analysis_runs r\n  WHERE ((r.id = analysis_results.run_id) AND has_project_access(r.project_id))))",
          "roles": [
            "public"
          ],
          "tablename": "analysis_results",
          "permissive": "PERMISSIVE",
          "policyname": "analysis_results_select",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "has_project_access(project_id)",
          "roles": [
            "public"
          ],
          "tablename": "analysis_runs",
          "permissive": "PERMISSIVE",
          "policyname": "analysis_runs_select",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "has_project_access(project_id)",
          "roles": [
            "authenticated"
          ],
          "tablename": "project_erp_links",
          "permissive": "PERMISSIVE",
          "policyname": "erp_links: project access",
          "schemaname": "public",
          "with_check": "has_project_access(project_id)"
        },
        {
          "cmd": "SELECT",
          "qual": "true",
          "roles": [
            "anon",
            "authenticated"
          ],
          "tablename": "plan_role_allowances",
          "permissive": "PERMISSIVE",
          "policyname": "plan_role_allowances_read",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "SELECT",
          "qual": "has_project_access(project_id)",
          "roles": [
            "public"
          ],
          "tablename": "graph_level_versions",
          "permissive": "PERMISSIVE",
          "policyname": "graph_level_versions_select",
          "schemaname": "public",
          "with_check": null
        },
        {
          "cmd": "ALL",
          "qual": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = demand_forecasts.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))",
          "roles": [
            "public"
          ],
          "tablename": "demand_forecasts",
          "permissive": "PERMISSIVE",
          "policyname": "Demand forecasts: modifiers only",
          "schemaname": "public",
          "with_check": "(EXISTS ( SELECT 1\n   FROM projects p\n  WHERE ((p.id = demand_forecasts.project_id) AND org_is_current_user_org(p.organization_id, p.organization) AND ((p.modeler_id = get_current_user_id()) OR (( SELECT get_current_approved_user.user_role\n           FROM get_current_approved_user() get_current_approved_user(user_id, user_email, user_role)\n         LIMIT 1) = 'admin'::text)))))"
        }
      ],
      "functions": [
        {
          "language": "sql",
          "signature": "_active_super_admin_count()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_api_key_audit(uuid,text,uuid,jsonb,jsonb)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_api_key_caller(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_api_key_management_org(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_assert_super_admin(uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_build_dataset_snapshot(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_build_dataset_snapshot_v2(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_build_policy_snapshot(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_build_scenario_fingerprint(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_capacity_admit(uuid,uuid,integer,bigint,bigint,jsonb)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_capacity_state(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_chat_assert_thread_owner(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_chat_plans_touch()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_compute_used(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_dataset_all_hashes(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_dataset_domain_hashes(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_dataset_graph_hash(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_dataset_level_hashes(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_delete_project_rows(uuid,uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_delete_workspace_objects(text[])",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_engine_build_append_only()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_engine_build_record(uuid,text,text,jsonb)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_engine_for_code_version(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_feature_spec_compute(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_level_backfill(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_level_register(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_level_register_snapshot()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_graph_level_state(uuid,text,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_level_versions_immutable()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_level_versions_number()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_graph_state_mark(uuid[])",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_state_store(uuid,jsonb,bigint)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_state_touch_del()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_state_touch_ins()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_state_touch_upd()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_graph_version_after_promotion()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_insert_validated_model(uuid,uuid,uuid,uuid,text,jsonb,text,jsonb,jsonb,jsonb,text,text,text,uuid,jsonb,uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_jsonb_project(jsonb,text[])",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_lock_active_super_admins()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_model_code_for(uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_next_version_code(text,text[])",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_policy_version_hash(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_project_completion_refresh(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_project_completion_touch()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_proposals_touch()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_resolve_policy_family(jsonb,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_run_usage_complete()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_run_usage_expire()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_scope_hash_key(text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_simulation_run_derive()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_simulation_run_drop_series()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_simulation_run_record_build()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_simulation_run_retention()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "_storage_used(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "_validated_model_engine()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_validated_model_evidence_immutable()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_validated_model_evidence_kept()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_validated_model_hash(text,text,text,jsonb,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_validated_model_immutable()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_validated_model_number()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "_version_codes_backfill(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "_version_day_code(timestamp with time zone)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "account_self_resolve(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "active_model_validation(uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "active_model_validation_by_content(uuid,text,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_add_org_member(uuid,text,uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_audit_log_read(uuid,text,timestamp with time zone,text,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_audit_log_verify(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_copy_project(uuid,text,uuid,text,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_create_organization(uuid,text,text,text,text,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_create_user(uuid,text,text,text,text,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_delete_docs_faq(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_delete_organization(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_delete_project(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_delete_user(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_dismiss_password_reset_request(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_get_project_access(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_get_user_memberships(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_account_role_gaps(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_docs_faq(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_organizations(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_password_reset_requests(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_projects(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_users(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_list_users_basic(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_org_capacity_usage(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_platform_overview(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_preview_role_capability(uuid,text,text,text,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_remove_org_member(uuid,text,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_remove_project_member(uuid,text,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_rename_project(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_reset_user_password(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_save_docs_faq(uuid,text,uuid,text,text,text,text[],integer,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_capability(uuid,text,text,text,text,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_default_org(uuid,text,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_docs_section_audience(uuid,text,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_org_access_period(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_org_capacity(uuid,text,uuid,bigint,bigint,integer,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_org_limits(uuid,text,uuid,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_org_status(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_project_member(uuid,text,uuid,uuid,text,timestamp with time zone,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_role_allowance(uuid,text,uuid,text,numeric,numeric,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_user_active(uuid,text,uuid,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_user_budget(uuid,text,uuid,text,numeric,bigint,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_user_models(uuid,text,uuid,uuid[],uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_user_org_role(uuid,text,uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_set_user_role(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_transfer_project(uuid,text,uuid,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_update_organization(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_update_project_meta(uuid,text,uuid,text,text,text,text,date,date,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_update_user(uuid,text,uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "admin_usage_log_read(uuid,text,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "advance_chat_plan_step(uuid,text,text,uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "agent_artifact_project_rights()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "agent_project_right_refusal(uuid,uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "ai_can_access_project(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_apply_critical_nodes(uuid,jsonb,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "analysis_apply_node_metrics(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_complete_run(uuid,jsonb,jsonb,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_current_run(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_fail_run(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_get_or_start(uuid,text,jsonb,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "analysis_latest_run(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_mark_critical_nodes(uuid,jsonb,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "analysis_results_are_immutable()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "analysis_run_is_current(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_runs_actor_is_required()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "analysis_runs_identity_is_immutable()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "analysis_scope_now(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "api_can_access_project(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "api_count_active_runs(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "api_key_caller(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "api_key_self_service_scopes()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "api_key_usage(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "api_personal_key_actor(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "api_personal_key_grant(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "append_chat_message(uuid,uuid,text,text,jsonb,jsonb,uuid,text,timestamp with time zone)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "apply_policy_bundle(uuid,jsonb,jsonb,text,uuid,text,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "apply_validation_to_scenario(uuid,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "approved_users_derive_name_parts()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "approved_users_stamp_organization_id()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "approved_users_sync_org_membership()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "approved_users_track_active_org()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "archive_project_memory(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "assert_may_edit_policies(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "assert_writer_may_act(text,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "assign_bom_line(uuid,text,text,numeric,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "assign_material_supplier(uuid,text,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "assign_outbound_customer(uuid,text,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "audit_log_digest(audit_logs)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "audit_log_seal(boolean)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "audit_logs_guard()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "audit_logs_seal_after_insert()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "audit_tier_write()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "authenticate_approved_user(text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "authenticate_user(text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "auto_calculate_network_metrics_on_completion()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "auto_combine_on_completion()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "auto_rebuild_supply_chain_lanes()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "auto_refresh_node_list_on_lane_change()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "auto_refresh_node_list_on_scd_change()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_delete_chat_threads(uuid[],uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_bom_multi_level(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_bom_single_level(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_inbound_logistics(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_multi_tier_supply_chain(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_network_edges(uuid,text,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_network_nodes(uuid,text,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_network_summary(uuid,text,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_outbound_logistics(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_tier2_suppliers(uuid,jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_insert_tier3_suppliers(uuid,jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_move_chat_threads(uuid[],uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_set_thread_flags(uuid[],boolean,boolean,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_upsert_customers(uuid,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_upsert_materials(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_upsert_policy_overrides(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_upsert_products(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "bulk_upsert_suppliers(uuid,jsonb,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "capabilities_for_user(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "capabilities_for_user(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "capture_graph_version(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "change_own_password(text,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "chat_quick_thread_id(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "classify_node_echelon(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "classify_node_type(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "cleanup_simulation_cache()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "clear_policy_preset(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "combine_project_into_supply_chain(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_agent_proposal(uuid,text,text,text,jsonb,jsonb,text,jsonb,text,text,text,text,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_api_key(uuid,text,text,text[],text,uuid[],timestamp with time zone,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_chat_folder(uuid,text,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_default_policy_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_disruption_scenario(uuid,text,text,text,numeric,numeric,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_disruption_scenario_v2(uuid,text,text,uuid,text,disruption_status,text,text[],jsonb,jsonb,jsonb,date,date)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_project(text,text,text,text,uuid,text,text,date,date,text,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_simulation_result(uuid,uuid,text,text,uuid[],text,timestamp with time zone,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "create_simulation_run(jsonb,boolean,boolean,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "create_user_file(uuid,text,text,text,bigint,uuid,uuid,uuid,timestamp with time zone,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "current_graph_hash(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "current_hash_inputs(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "current_hash_network(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "current_is_super_admin()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "current_level_hash(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "current_policy_hash(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "dataset_version_tuple(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "dataset_versions_assign_number()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_all_disruption_scenarios(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_chat_folder(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_chat_thread(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_disruption_scenario(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_policy_override(uuid,text,text,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_policy_version(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_project(uuid,uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "delete_project_dataset(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_simulation_result(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_simulation_results_batch(uuid[],uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "delete_user_file(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "demand_forecast_spread()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "docs_audience_rank(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "docs_list_faq(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "docs_reader_level(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "docs_section_audience(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "due_erp_sync_links()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "duration_to_weeks(numeric,text,numeric)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "effective_project_role(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ensure_dataset_plant_matches_project()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ensure_item_masters(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "etl_replace_supply_chain(uuid,uuid,jsonb,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "expire_agent_proposals(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "expire_chat_plans(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "find_reusable_runs(uuid,text,text,integer,uuid,jsonb,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "freshness_of(text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "generate_multi_tier_supply_chain_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_baseline_simulation_results(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_chat_plan(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_critical_node_stats(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_current_approved_user()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_current_user_id()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_current_user_org()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_current_user_org_id(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_deep_tier_datasets(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_disruption_scenarios(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_effective_capabilities(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_erp_oauth_token(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_graph_nodes(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_graph_version_state(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_individual_scenario_results(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_integrated_process_network_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_model_capability_matrix()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_multi_tier_network_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_multi_tier_supply_chain_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_my_capabilities(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_my_capacity(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_my_organization_access(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_my_profile(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_my_project_access(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_my_project_rights(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_edges(uuid,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_edges_for_prominence(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_metrics_for_materials(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_nodes(uuid,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_nodes_for_prominence(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_network_summary(uuid,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_node_list(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_org_access(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_policy_version_snapshot(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_prediction_stats(text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_process_level_integrated_network_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_process_level_network_data(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_project_dataset_counts(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_project_dataset_status(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_project_dataset_status(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_project_datasets(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_project_demand_forecasts(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_role_access(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_scenario_simulation_results(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_self_profile()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_simulation_results(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_supply_chain_data(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_supply_chain_data_multi_tier(uuid,uuid,text,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_supply_chain_plants(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_unlinked_products(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "get_user_access(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "get_validated_model_evidence(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "grant_project_delegation(uuid,uuid,uuid,text,timestamp with time zone,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "graph_level_version_no(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "has_project_access(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "import_local_threads(uuid,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "infer_node_list_metadata()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_apply_run(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_dedup_natural_key(text,text[],text[])",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_diff_run(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_files_write_once()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_inbound_logistics_rpc(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_land_file(uuid,uuid,text,text,text,text,text,text,text,bigint,text,jsonb,jsonb,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_legacy_upsert_lane(uuid,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "ingest_normalize_at_promotion(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_outbound_logistics_rpc(jsonb,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_promotion_plan(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_row_provenance(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_run_review(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "ingest_target_is_promotable(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_target_natural_key(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "ingest_value_chain(uuid,uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "is_stale(text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "is_super_admin(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_agent_proposals(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_api_keys(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_approved_users_safe()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "list_chat_folders(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_chat_messages(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_chat_plans(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "list_chat_threads(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "list_dataset_versions(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "list_model_validations(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_my_organizations(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "list_policy_versions(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_projects(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "list_user_files(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "log_admin_action(text,text,text,jsonb,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "log_data_action(uuid,text,text,text,text,jsonb,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "mark_agent_proposal_applied(uuid,jsonb)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "mark_agent_proposal_apply_failed(uuid,text)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "move_chat_thread(uuid,uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "mrp_apply_staged_products(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "node_bom_depth(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "node_list_discover(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "node_supply_tier(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "normalize_node_location_fields()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "org_access_period_interval(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "org_is_current_user_org(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "organization_members_activate_first()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "organization_members_enforce_org_allowance()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "organization_members_repoint_active()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "organizations_derive_access_valid_until()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "password_max_age()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "policy_bundle_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "policy_versions_assign_number()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "process_structure(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "project_access_read(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "project_creation_right(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "project_freshness(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "project_graph_hashes(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "project_org_admin(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "project_owner_membership()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "project_right_decide(boolean,boolean,text,boolean,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "project_right_decisions(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "project_rights_for_user(uuid,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "project_role_holdings()",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "project_role_rank(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "projects_enforce_org_allowance()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "proposal_grounding_state(proposals)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "prune_ai_chat_events(integer)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "rate_to_weekly(numeric,text,numeric)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "rebuild_node_list(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "rebuild_supply_chain_lanes(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "recompute_project_completion(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_chat_ui_event(text,uuid,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_export(uuid,uuid,text,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_external_evidence(uuid,text,text,text,numeric,jsonb,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_model_validation(uuid,uuid,uuid,uuid,integer,text,integer,jsonb,jsonb,jsonb,text,text,uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_proposal_viewed(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "record_validated_model(uuid,uuid,uuid,uuid,text,jsonb,text,jsonb,jsonb,jsonb,text,text,uuid,jsonb,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "refresh_node_list_for_project(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "refresh_node_list_for_project(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "request_password_reset(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "restore_policy_version(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "review_agent_proposal(uuid,text,uuid,text,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "revoke_api_key(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "revoke_model_validation(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "revoke_project_delegation(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "rotate_api_key(uuid,text,uuid,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "run_series_retention(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "save_policy_defaults(uuid,text,jsonb,text,text,timestamp with time zone,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "save_project_memory(uuid,text,text,jsonb,uuid,uuid,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "scenario_fingerprint_hash(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "scenarios_assign_validation_baseline(uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "search_chat_messages(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "seed_synthetic_simulation_data(uuid,uuid,text,integer,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "set_current_user_context(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_disruption_scenario_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_file_retained(uuid,uuid,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_model_planning_period(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_network_data_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_network_tables_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_node_list_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_project_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_run_retention(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_scenario_child_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_scenario_profile_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_simulation_results_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_simulation_tables_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_supply_chain_data_defaults()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_thread_flags(uuid,boolean,boolean,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "set_thread_summary(uuid,uuid,text,integer)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sim_engine_build_withdraw(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sim_engine_for_dispatch(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sim_engine_report(text,text,text,jsonb,jsonb)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "sql",
          "signature": "simulation_run_key(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "simulation_run_spec(uuid,text,text,uuid,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "snapshot_dataset(uuid,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "snapshot_policy(uuid,text,uuid,text,text,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "split_person_name(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "supersede_agent_proposal(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "surrogate_feature_spec(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "surrogate_training_summary(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "surrogate_training_totals(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sweep_expired_files(uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sweep_expired_run_series(integer)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "switch_my_organization(uuid,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "sync_disruption_to_sim_scenario()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "unit_days(text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_own_profile(text,text,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_policy_version_notes(uuid,text,uuid)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_project(uuid,text,text,text,text,uuid,text,date,date,text,boolean)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_project_completion_status(uuid,uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_project_completion_status()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_project_completion_stmt()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_risk_alert_impact(uuid,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_scenario_effect_magnitude_by_profile(uuid,uuid,text,numeric)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_simulation_job_timing()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "update_updated_at_column()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "upload_node_list_data(uuid,uuid,text,jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "upsert_chat_plan(jsonb,uuid)",
          "anon_execute": false,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": false
        },
        {
          "language": "plpgsql",
          "signature": "upsert_chat_thread(uuid,uuid,text,uuid,boolean,text,uuid,boolean,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "validate_disruption_effect()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "validated_model_protocol_problems(jsonb)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        },
        {
          "language": "plpgsql",
          "signature": "verify_user_exists(uuid,text)",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": true,
          "authenticated_execute": true
        },
        {
          "language": "sql",
          "signature": "workspace_retained_cap_bytes()",
          "anon_execute": true,
          "service_execute": true,
          "security_definer": false,
          "authenticated_execute": true
        }
      ]
    }
  }
]
```
