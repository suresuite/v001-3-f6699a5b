// §6.3 section 12 — the three workbooks (A4), as the app produces them today.
//
// Corrected in the WP 5.2a manual pass. This page described a "policy
// snapshot" with a provenance row under every value; since §4 D289 a policy
// version's Export is the ENGINE-INPUT workbook (`engineInputWorkbook.ts`) —
// what the run actually receives, through the mapper. And the run-results
// workbook has carried the reproducibility record (A5) as its own sheet since
// WP 6.3, which this page said was owed. Sheet names are the builders'
// (`engineInputWorkbook.ts`, `verifiableExports.ts`).

import {
  PageTitle, InShort, Section, P, Key, Callout, Steps, DocTable, Term, DocLink, AppLink, Provenance,
} from "@/components/docs/prose";

export default function VerifiableExports() {
  return (
    <>
      <PageTitle lead="Three workbooks that let someone check your model without access to this software.">
        Verifiable exports
      </PageTitle>
      <InShort items={[
        <>Three files answer three questions: what the engine received, what data it was computed from, and what came out.</>,
        <>Each carries the fingerprint that ties it to the others, so a reviewer can check they belong together.</>,
        <>All three are on <strong>/policies › Version history</strong>, and need the Export right on the project.</>,
      ]} />

      <Section id="the-idea" title="What makes an export verifiable">
        <Key>
          It carries what it was computed from, not only what was computed.
        </Key>
        <P>
          A spreadsheet of results is a claim. A spreadsheet of results, plus the exact inputs, plus
          the fingerprint tying the two together, is something a reviewer can check — by recomputing
          the fingerprint, by reading the inputs, or by rerunning the model elsewhere.
        </P>
      </Section>

      <Section id="where" title="Where to get them">
        <Steps steps={[
          { title: "Open Version history", where: "/policies", body: <>On <AppLink to="/policies">/policies</AppLink>, open <strong>Version history</strong>. Exports work on saved <DocLink to="policy-versions-and-presets">policy versions</DocLink> — an export of unsaved edits would carry a fingerprint over something nobody could return to.</> },
          { title: "Export a version", where: "Version history", body: <>A saved version's <strong>Export</strong> downloads <Term>simulation-input-…xlsx</Term>.</> },
          { title: "Export the dataset and a run", where: "Verifiable exports", body: <>Below the versions: <strong>Export dataset (graph_hash-stamped)</strong> downloads <Term>dataset-…xlsx</Term>; pick a completed run and choose <strong>Export results</strong> for <Term>run-results-…xlsx</Term>.</>, check: "three files whose fingerprints match: the dataset hash in the dataset file is the one the run results and the simulation input name." },
        ]} />
        <P>The buttons are disabled without the project's Export right, with the reason beside them — see <DocLink to="project-access">Project access</DocLink>.</P>
      </Section>

      <Section id="the-three" title="The three workbooks">
        {/* The old per-workbook anchors, kept so existing deep links still land here. */}
        <span id="policy-snapshot" /><span id="dataset" /><span id="run-results" />
        <DocTable
          caption="What each file holds, sheet by sheet."
          head={["File", "Sheets", "Answers"]}
          rows={[
            [
              "Simulation input",
              "Read me (versions, hashes and a hash re-check) · one sheet per network list · Policies · Settings · Disruptions · Where values came from · Mapping notes · Field guide · Policy as saved · Policy JSON (hashed)",
              "What the engine receives from this policy version and its dataset version — through the same mapping a run uses, not the stored settings alone",
            ],
            [
              "Dataset",
              "suppliers · materials · products · inbound_logistics · bom_single_level · outbound_logistics · customers · the deep-tier sheets · _provenance · _meta",
              "The exact accepted rows the dataset fingerprint was computed over, taken from the frozen snapshot rather than as they are now",
            ],
            [
              "Run results",
              "run_meta · aggregate_kpis · replication_kpis · one series_… sheet per weekly measure · reproducibility",
              "What came out: the run's identity, KPIs with intervals, every seed's KPIs, the weekly traces and the reproducibility record",
            ],
          ]}
        />
      </Section>

      <Section id="what-makes-each-checkable" title="What makes each one checkable">
        <DocTable
          caption="The check a reviewer can make, and what each file admits about itself."
          head={["File", "A reviewer can", "It says plainly"]}
          rows={[
            ["Simulation input", "Recompute the policy hash from the Policy JSON sheet, and read every value with its source and every substitution the mapping made", "Where an empty cell has a meaning (no capacity limit, start at the target), in the Field guide"],
            ["Dataset", "Recompute the dataset fingerprint from the sheets, and trace each row to its file, line, uploader and date in _provenance", "Which rows cannot be traced — _provenance lists every row, with a traced column, rather than only the traced ones"],
            ["Run results", "Recompute each KPI's interval from the per-seed rows rather than trusting the summary", "Which bindings are missing, and why, in the reproducibility sheet's verdict"],
          ]}
        />
        <Callout tone="note" title="The reproducibility record is in the run-results file">
          <p>The <Term>reproducibility</Term> sheet binds the run to its dataset, policy, scenario, seed and engine build, plus any analysis behind a network figure and the known limits. If the record could not be assembled, the sheet is still there and says so. <DocLink to="reproducibility-record">Reproducibility record</DocLink> explains every line.</p>
        </Callout>
      </Section>

      <Section id="related" title="Related">
        <P>
          <DocLink to="dataset-versions">Dataset Versions</DocLink> ·{" "}
          <DocLink to="reproducibility-record">Reproducibility record</DocLink> ·{" "}
          <DocLink to="reading-your-results">Reading your results</DocLink> ·{" "}
          <DocLink to="exporting-and-deleting">Exporting and deleting your data</DocLink>
        </P>
      </Section>

      <Provenance from="the three workbook builders and the stamps each one writes" />
    </>
  );
}
