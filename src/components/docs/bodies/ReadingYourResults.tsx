// Results — Reading your results (journey page, WP 5.2a redesign).
//
// The checkpoint order is the page's spine: the run record, then the notes,
// then the numbers, then what they can support. Section ids are unchanged;
// `pageDepth.test.tsx` holds five. The heatmap notice is still read from the
// generated replication facts, so it appears exactly when the engine dropped
// the series and not otherwise (`runKpiVocabulary.test.ts`).

import { REPLICATION_SERIES_FACTS as SERIES } from "@/components/docs/generated/policy.generated";
import {
  DocPageTitle, InShort, Section, P, Callout, Steps, Defs, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

export default function Guide() { return <>
<DocPageTitle slug="reading-your-results" />
<InShort items={[
  <>Before quoting any number, confirm the run finished and which data, policy and scenario versions it used.</>,
  <>Read the conversion notes — they say where the engine used a default, clamped a value or ignored one.</>,
  <>A narrow interval means precise for this model. It doesn't mean the model is right.</>,
]} />

<Section id="the-order" title="Start with the run record">
  <Flow
    caption="Read a result in this order. Each step can stop you before the next."
    items={[
      { kicker: "1", title: "Run record", detail: "status · versions · count" },
      { kicker: "2", title: "Conversion notes", detail: "defaults · clamping" },
      { kicker: "3", title: "KPIs", detail: "mean · interval · range" },
      { kicker: "4", title: "Interpretation", detail: "assumptions stated" },
    ]}
  />
  <Steps steps={[
    { title: "Open the finished run", where: "/simulation-lab › Results", body: <>In <AppLink to="/simulation-lab">Simulation Lab</AppLink> › <strong>Results</strong>, or the shared results panel in <strong>Policies › Run &amp; Validate</strong>.</> },
    { title: "Confirm what it is", where: "Run record", body: "Status, completed replication count, the credibility badge, and the exact dataset, policy and scenario versions. A preliminary estimate can move as replications finish; a failed or cancelled run with some rows is not the experiment you asked for." },
    { title: "Read the notes before the numbers", where: "Engine conversion notes", body: "Notes can describe defaults, clamping, unsupported values or a target that couldn't be used. Write down anything that matters to your question.", check: "a completed run, its versions, and no surprises in the notes." },
  ]} />
  <DocFigure id="kpi-vocabulary-gap" />
</Section>

<Section id="the-panels" title="What each panel answers">
  <Defs items={[
    { term: "KPI summary", def: "Mean, confidence interval, standard deviation, range and count across replications. Rows follow the measures the engine actually returned; labels and directions come from the KPI catalog. A measure the engine didn't return is unavailable — never zero." },
    { term: "Convergence plot", def: "Whether the running estimate has settled — the simulation's precision, not whether your demand, capacity or BOM are right. One replication cannot give an interval between replications." },
    { term: "Replication & seed explorer", def: "The weekly trace. Find when the shock starts, whether stock delays its effect, and whether service recovers within the measured window." },
    { term: "Inventory and capacity", def: "Materials and finished goods, read separately. Average inventory is a level averaged over the window, not a weekly sum. Utilization alone doesn't show whether capacity refused production; check the binding measures too." },
    { term: "Per-item inspection", def: "Product or material detail, from an inspection run. A missing series isn't evidence of zero stock or zero demand." },
  ]} />
  {SERIES.heatmapRemoved ? (
    <Callout title="Utilization heatmap — removed">
      <p>The former panel depended on a per-node <Term>capacity_utilization</Term> series that the engine did not produce. Its removal does not mean capacity is unlimited. Use the returned aggregate capacity measures and binding indicators described above.</p>
    </Callout>
  ) : null}
</Section>

<Section id="worked-reading" title="Reading the tutorial result">
  <P>The tutorial needs 100 boards and 200 housings a week. An 80% capacity cut takes S-BOARD from 150 to 30 a week. Opening stock and replenishment can delay the customer impact, so service won't drop the same week the event starts.</P>
  <P>Compare baseline against disruption to measure the shock. Compare the same disruption under two policy versions to measure the buffer. Read lost sales, service and cost together. The example's demand and lead times are fixed, so identical replications and a zero-width interval are expected here.</P>
  <Callout tone="warning" title="Don't count a loss twice">
    <p>Cost of resilience already includes lost-sales cost, among its engine-defined parts. It isn't just the cash spent on extra stock.</p>
  </Callout>
</Section>

<Section id="window" title="Know what's being measured">
  <P>Fill rate is fulfilled demand value divided by demand value in the measured window — value-weighted, so expensive products count for more. No demand means no fill rate. A missing recovery figure can mean recovery didn't happen inside the window.</P>
  <P>The engine separates the total horizon, the excluded warm-up and the measured window. A longer horizon doesn't always lengthen the measured part by the same amount — read the run-window summary, and check that the disruption and recovery both fall inside it.</P>
  <Flow
    caption="Only the measured window counts toward a KPI. Check that the disruption and recovery fall inside it."
    highlight={1}
    items={[
      { title: "Warm-up", detail: "excluded" },
      { title: "Measured window", detail: "KPIs computed here" },
      { title: "Rest of horizon", detail: "if any" },
    ]}
  />
</Section>

<Section id="trust" title="What a result can support">
  <P>A narrow interval is precision given the model. It says nothing about missing suppliers, wrong BOM quantities, uncertain forecasts or policy mapping errors. For a management conclusion, write down those assumptions, test plausible alternatives, and say where the conclusion changes.</P>
  <Callout title="Resilience Index">
    <p>The engine's stress-battery library defines one; ordinary runs don't produce it. Don't infer a score from an empty field. The <DocLink to="kpis-and-resilience-index">KPI reference</DocLink> has the formula and normalization.</p>
  </Callout>
  <P>Next: <DocLink to="experiments-and-comparison">controlled comparisons</DocLink> and <DocLink to="verifiable-exports">verifiable exports</DocLink>. Keep the inputs and protocol with the result, not just a screenshot of a mean.</P>
</Section>
</>; }
