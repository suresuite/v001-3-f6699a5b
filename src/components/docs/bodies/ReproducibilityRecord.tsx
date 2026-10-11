// §6.3 section 12 — the reproducibility record (A5).
//
// What ships, read from the code that builds it. The record is
// `lib/trust/reproducibilityRecord.ts` (WP 6.3) and reaches a user as the
// `reproducibility` sheet of the run-results workbook; since WP 10.4 a new run
// row carries its own binding (`result-binding`, I8, MET for every run
// dispatched since). The bindings list and the verdicts below are produced by
// `bindingsOf` and `buildReproducibilityRecord` from illustrative inputs.
//
// What is still NOT met is history (§4 D88): derived rows written before
// provenance existed carry no input hash and cannot be back-filled. The page
// says that as plainly as it says what works.
//
// (Corrected in the WP 5.2a manual pass: this page used to say the record was
// owed and did not exist. It had shipped two phases earlier.)

import { bindingsOf, buildReproducibilityRecord, type ReproducibilityRecordInput } from "@/lib/trust/reproducibilityRecord";
import {
  PageTitle, InShort, Section, P, Key, Callout, Steps, DocTable, Term, DocLink, AppLink, Provenance, Prose,
} from "@/components/docs/prose";
import { refTable, computedColumns } from "@/components/docs/tableFacts";

const CARRIES_PROVENANCE = ["network_nodes", "node_list", "network_summary", "supply_chain_data"];

/** A run dispatched today: every binding present. Illustrative values. */
const BOUND: ReproducibilityRecordInput = {
  projectId: "example", projectName: "Control-unit tutorial",
  graphHash: "3f9a…c210", datasetVersionId: "dv-…", hashSchemaVersion: 3,
  policyVersionId: "pv-…", policyHash: "a17e…09bb",
  scenarioId: "sc-…", scenarioSeed: 42, disruptionSchedule: "[S-BOARD, 80%, week 16, 4 weeks]",
  engineCodeVersion: "scsim-0.8.0+1a2b3c4d5e6f", browserEngineVersion: "scsim-0.8.0+1a2b3c4d5e6f",
  scenarioHash: "77c0…1e2d", validatedModelId: "vm-…", engineId: "eng-…", runKey: "rk-…",
  protocolOverrides: {}, exploratory: false,
  simulationHash: "5be1…aa30", simulationVersionNo: 4,
  levelVersions: { product: 4, process: 4, firm: 2 }, runKeyVersion: 2,
  analyses: [], limits: [], measuredAt: "illustrative",
};
/** An older run: no seed or schedule stamped, no run binding. */
const OLDER: ReproducibilityRecordInput = {
  ...BOUND, scenarioSeed: null, scenarioSeedReason: "the scenario was edited after dispatch",
  disruptionSchedule: null, scenarioHash: null, validatedModelId: null, engineId: null, runKey: null,
  simulationHash: null, simulationVersionNo: null, levelVersions: null, runKeyVersion: null,
};
const STALE: ReproducibilityRecordInput = {
  ...BOUND,
  analyses: [{ kind: "centrality", runId: "ar-…", codeVersion: "x", inputHash: "old…", paramsHash: "p", finishedAt: null, inputHashIsCurrent: false }],
};
const UNHASHED: ReproducibilityRecordInput = {
  ...BOUND,
  analyses: [{ kind: "centrality", runId: null, codeVersion: null, inputHash: null, paramsHash: null, finishedAt: null, inputHashIsCurrent: null }],
};

export default function ReproducibilityRecord() {
  // Which tables carry the provenance columns is read from the contract's
  // `computed_by` declarations, not asserted.
  const withStamp = CARRIES_PROVENANCE.map((name) => {
    const t = refTable(name);
    return { table: name, stamped: computedColumns(t).some((c) => c.name === "computed_from_hash") };
  }).filter((x) => x.stamped);
  const bindings = bindingsOf(BOUND);
  const verdicts: [string, string][] = [
    ["A run dispatched today, no network figures", buildReproducibilityRecord(BOUND).headline],
    ["The same, with a centrality computed on an earlier dataset", buildReproducibilityRecord(STALE).headline],
    ["The same, with a centrality that predates provenance", buildReproducibilityRecord(UNHASHED).headline],
    ["An older run, dispatched before runs were stamped", buildReproducibilityRecord(OLDER).headline],
  ];

  return (
    <>
      <PageTitle lead="The stamp that lets someone else rerun exactly what you ran — what it binds, how to get it, and where it falls short.">
        Reproducibility record
      </PageTitle>
      <InShort items={[
        <>The record binds a result to its data, policies, scenario and engine build, so someone else can put the system back in that state.</>,
        <>It ships as the <Term>reproducibility</Term> sheet of the run-results workbook, and every run dispatched today carries it.</>,
        <>A binding that is missing is listed with the reason, and the verdict says <em>NOT reproducible</em> rather than staying quiet.</>,
      ]} />

      <Section id="what-it-would-be" title="What a reproducibility record is">
        <Key>
          Four things, bound to one result: the data it ran on, the decisions it ran under, the
          scenario it ran in, and the version of the engine that ran it.
        </Key>
        <P>
          With all four, a figure can be handed to somebody else and recreated. With any one
          missing, it cannot — a number reproduced against different data is a different number that
          happens to look the same. The record adds two more: every analysis run behind a network
          figure, and the known limits of all of it.
        </P>
      </Section>

      <Section id="get-it" title="Get the record for a run">
        <Steps steps={[
          { title: "Export the run's results", where: "/policies › Version history", body: <>On <AppLink to="/policies">/policies</AppLink>, open <strong>Version history</strong>. Under <strong>Verifiable exports</strong>, pick the completed run and choose <strong>Export results</strong> — the <DocLink to="verifiable-exports">run-results workbook</DocLink>. It needs the Export right on the project.</> },
          { title: "Open the reproducibility sheet", where: "run results workbook", body: <>It opens with a verdict, then one line per binding — its value, where it was read from, and, if it is missing, why.</>, check: "a verdict line, and no MISSING (required) binding." },
          { title: "Keep it with the figure", where: "your report", body: "Send the workbook with the figure it supports. The record is what lets a reviewer check, and what lets you rerun it in two years." },
        ]} />
      </Section>

      <Section id="bindings" title="What the record binds">
        <DocTable
          caption="Every binding in the record, as the record's own code lists them for a run dispatched today."
          head={["Binds", "Level", "Read from"]}
          rows={bindings.map((b) => [<Prose text={b.label} />, b.level, <Prose text={b.source} />])}
        />
        <P>A <strong>required</strong> binding missing makes the verdict <em>NOT reproducible</em>. A <strong>recommended</strong> one missing is listed but does not, so a run from before a binding existed is not made unreproducible by a column it could not have had.</P>
      </Section>

      <Section id="verdicts" title="The verdict line">
        <DocTable
          caption="What the record's first line says in four situations — produced by the record's own code."
          head={["Situation", "Verdict"]}
          rows={verdicts.map(([w, v]) => [w, <Prose text={v} />])}
        />
        <P>An analysis computed on an earlier dataset reproduces <em>itself</em> perfectly; it just doesn't describe the data loaded now. Re-run it on the current data if the figure should.</P>
      </Section>

      <Section id="the-stamps-that-do-exist" title="Computed rows and their stamp">
        <P>
          Computed rows can also say which version of your data they came from. The columns exist on{" "}
          {withStamp.length} tables, and the analyses that write them fill them in from the run rather
          than from a parameter — so a row cannot name a world its run never saw.
        </P>
        <ul className="flex flex-wrap gap-1.5">
          {withStamp.map((x) => (
            <li key={x.table}>
              <code className="docs-code">{x.table}</code>
            </li>
          ))}
        </ul>
        <P>
          The deep-tier edges deliberately have no such column, because every column of them is
          uploaded: a stamp no writer could fill would be a promise rather than a fact.
        </P>
        <Callout tone="warning" title="Rows written before provenance carry no stamp">
          <p>
            Derived rows written before the stamp existed have an empty <Term>computed_from_hash</Term>,
            and <strong>they cannot be back-filled</strong>: inventing a hash would be fabricated
            provenance, worse than an empty column, because empty is legible as “we do not know”.
          </p>
          <p>
            Such a number is reported as <em>unknown</em> — neither current nor stale — and the{" "}
            <DocLink to="data-trust-report">Data Trust Report</DocLink> counts them. Running the
            analysis again is what stamps them.
          </p>
        </Callout>
      </Section>

      <Section id="what-to-do" title="What to do for a defensible figure">
        <P>
          Run from a <DocLink to="model-validation">Validated Model</DocLink>: it fixes the{" "}
          <DocLink to="dataset-versions">dataset version</DocLink> and{" "}
          <DocLink to="policy-versions-and-presets">policy version</DocLink> the run reads, and the
          run binds both. Avoid exploratory runs for anything you will quote — they are badged as
          unvalidated in the record too.
        </P>
        <P>
          If the figure is a network measure, re-run its analysis on the current data first, so the
          verdict does not carry an unstamped or earlier-dataset result. Then export the workbook and
          keep it with the figure.
        </P>
      </Section>

      <Section id="related" title="Related">
        <P>
          <DocLink to="verifiable-exports">Verifiable exports</DocLink> ·{" "}
          <DocLink to="dataset-versions">Dataset Versions</DocLink> ·{" "}
          <DocLink to="data-trust-report">Data Trust Report</DocLink> ·{" "}
          <DocLink to="known-limits">Known limits</DocLink> ·{" "}
          <DocLink to="model-validation">Model validation</DocLink>
        </P>
      </Section>

      <Provenance from="lib/trust/reproducibilityRecord.ts and the provenance columns the contract declares on each derived table" />
    </>
  );
}
