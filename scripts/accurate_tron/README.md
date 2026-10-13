# ACCURATE_Tron — anonymized Tronico dataset

The Tronico electronics supply chain from the *syn_effect_Dec25* resilience study,
**de-identified**, for the **ACCURATE_Tron** organization.

- **Identifiers** are pseudonyms: `PRD-nnn` products, `MAT-nnnn` materials, `SUP-nnn` suppliers, `CUST-001` the aggregate customer.
- **Supplier names, addresses and exact coordinates** are not in this folder.
- **Quantities, prices, costs, MOQs, lead times and BOM rates** are the study's own values, unchanged, so results reproduce.

| File | What |
|---|---|
| `csv/*.csv` | Upload files, one per Upload Wizard template. Headers are exactly the wizard's, and every file passes the ingest contract (`src/lib/policies/__tests__/accurateTronCsv.test.ts`) |
| `dataset.json` | The same tables plus policy defaults, policy overrides and scenarios, for the seeder |
| `parameters.md` / `.csv` | Data dictionary: every column's source in the workbook and its rule, the study → SuReSuite policy map (exact vs. similar), and the scenarios |
| `policy_overrides.csv` | Per supplier × material settings. The `abc_xyz_safety_stock` set is the study's ABC-XYZ safety stock as Supplier-stage `safety_stock_days` |
| `audit.json` | Every value floored or clamped to an engine limit (none for this data) |

## Getting it into ACCURATE_Tron

Two ways:

- **Upload.** Open /project-manager in a project owned by an ACCURATE_Tron user and upload the seven CSVs in the order `parameters.md` gives.
- **Seed.** Run the seeder under an ACCURATE_Tron user:

```bash
node scripts/seed_project_accurate_tron.mjs --dry-run      # validate, no writes
USER_ID=<approved_users.id> USER_EMAIL=<ACCURATE_Tron user's email> \
  node scripts/seed_project_accurate_tron.mjs
```

The project's organization is stamped from that user. The seeder fails at the end if the project did not land in `ACCURATE_Tron`.

## Where it comes from (and how to regenerate)

The data is generated in the **syn_effect_Dec25** repository, branch
`claude/amazing-tesla-uhy1j4`, by `supply_chain_simulation/anonymize/tronico_anonymize.ipynb`:

1. It cleans the raw workbook and pseudonymizes it.
2. It runs a leak check.
3. It exports these files by reading the study's own model classes.

The **map back to real IDs is private**. It lives only in that repository's git-ignored
`data/private/` folder, and nothing here can re-identify the data.

To refresh this folder, run the notebook and copy `data/anonymized/suresuite/` here.
