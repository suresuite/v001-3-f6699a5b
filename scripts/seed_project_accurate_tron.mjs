#!/usr/bin/env node
// Seed the anonymized Tronico dataset into the ACCURATE_Tron organization.
//
// The data is scripts/accurate_tron/dataset.json (generated in syn_effect_Dec25 —
// see scripts/accurate_tron/README.md). The lifecycle is
// seed_project_tron_ver2.mjs's, unchanged; this entry point only sets its
// DATASET and EXPECT_ORG defaults, so there is one seeder to keep correct.
//
// Usage:
//   node scripts/seed_project_accurate_tron.mjs --dry-run
//   USER_ID=<uuid> USER_EMAIL=<email of an ACCURATE_Tron user> \
//     node scripts/seed_project_accurate_tron.mjs
//
// The project's organization is stamped from USER_EMAIL's approved_users row, so
// that user must belong to ACCURATE_Tron. The run fails at the end if the
// project did not land there.

process.env.DATASET ??= "scripts/accurate_tron/dataset.json";
process.env.EXPECT_ORG ??= "ACCURATE_Tron";
await import("./seed_project_tron_ver2.mjs");
