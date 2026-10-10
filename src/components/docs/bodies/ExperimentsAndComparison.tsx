// Experiments — Experiments & comparison (guide).
//
// The worked paired example is computed by `pairedDifference`, the function
// the Compare table calls, and the "which KPIs can have a winner" list is read
// from the KPI catalog's `higherIsBetter`. Neither is restated by hand.

import { pairedDifference } from "@/lib/sim/pairedCompare";
import { KPI_DISPLAY } from "@/lib/sim/kpiDisplay";
import {
  DocPageTitle, InShort, Section, P, Callout, Steps, Bullets, Details, DocTable, Flow, DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

// Illustrative fill rates for five CRN-paired replications. Not results.
const A = [0.952, 0.968, 0.941, 0.975, 0.960];
const B = [0.961, 0.979, 0.947, 0.982, 0.969];
const reps = (xs: number[]) => xs.map((v, i) => ({ rep_index: i, status: "done", kpis: { fill_rate: v } }));
const PAIRED = pairedDifference(reps(A), reps(B), "fill_rate");
const mean = (xs: number[]) => xs.reduce((s, x) => s + x, 0) / xs.length;
const pct = (x: number, d = 1) => `${(x * 100).toFixed(d)}%`;
const pp = (x: number) => `${x >= 0 ? "+" : "−"}${(Math.abs(x) * 100).toFixed(2)} pp`;

export default function ExperimentsGuide() {
  const directional = KPI_DISPLAY.filter((k) => k.higherIsBetter !== null);
  const descriptive = KPI_DISPLAY.filter((k) => k.higherIsBetter === null);
  return (
    <>
      <DocPageTitle slug="experiments-and-comparison" />
      <InShort items={[
        <>Ask one question per comparison. Change one thing — the policies, the world or the disruptions — and hold everything else.</>,
        <>Compare reads the <strong>paired</strong> difference between matching replications, and names a winner only when its interval excludes zero.</>,
        <>A winner on one KPI is not a decision. Report service, loss and cost together, with the assumptions behind them.</>,
      ]} />

      <Section id="what-an-experiment-is" title="Choose the question first">
        <P>Every comparison answers exactly one question. Write it down before you build anything, and name each scenario for the one thing that differs.</P>
        <DocTable
          caption="Three questions, and the pair of runs that answers each."
          head={["Question", "Run A", "Run B", "What differs"]}
          rows={[
            ["What does the disruption cost?", "Baseline", "Baseline + disruption", "events"],
            ["Does the buffer pay for itself under that disruption?", "Disruption, policy v1", "Disruption, policy v2 (buffer)", "policies"],
            ["Does a longer horizon change the answer?", "Baseline, 52 weeks", "Baseline, 104 weeks", "world"],
          ]}
        />
        <Callout tone="warning" title="Two changes cannot be split">
          <p>Baseline against <em>disruption plus a new policy</em> changes two causes at once. The difference is real, but you cannot say how much came from the shock and how much from the response — Compare refuses the pair for that reason.</p>
        </Callout>
        <DocFigure id="controlled-comparison" />
        <P>The <DocLink to="your-first-project">control-unit tutorial</DocLink> follows the first two rows: baseline, board disruption, and the same disruption with a 28-day buffer.</P>
      </Section>

      <Section id="build-it" title="Build the pair">
        <Steps steps={[
          { title: "Start from the same model", where: "/simulation-lab", body: <>Create every scenario from the same Validated Model, so the dataset and protocol match. See <DocLink to="simulation-lab">Simulation Lab</DocLink>.</> },
          { title: "Change one thing, and name it", where: "Setup · Recovery playbook", body: <>Add the event, or select the other policy version — nothing else. Name the scenario for the change: <Term>Board disruption</Term>, <Term>Board disruption + 28d buffer</Term>.</> },
          { title: "Keep seed and common random numbers", where: "Setup", body: "Same seed on both, common random numbers on for both, same replications, warm-up and horizon." },
          { title: "Run both to done", where: "Run", body: "Wait for the full replication count on both sides. The paired difference only uses replications that finished on both.", check: "both scenarios showing results, and the second appearing as a column beside the first in Compare." },
        ]} />
      </Section>

      <Section id="the-four-conditions" title="What Compare checks">
        <P>Open <AppLink to="/simulation-lab">Simulation Lab</AppLink> › <strong>Compare</strong> and pick a baseline from the scenarios with completed, non-exploratory results. Every other scenario is checked against it separately, and the comparable ones become columns. Chips let you include scenarios and rank by a KPI; select a column to open its paired table. On a phone, the same comparison is a ranked list.</P>
        <DocTable
          caption="The four conditions a pair must meet."
          head={["Condition", "Why"]}
          rows={[
            ["Common random numbers on, on both runs", "Without them the two runs saw different randomness and the difference is partly luck"],
            ["The same seed", "The same seed is what makes replication i of A and replication i of B the same world"],
            ["Exactly one of policies, world or events differs", "Zero differences is nothing to compare; two cannot be separated"],
            ["The same engine build", "A different engine is another difference — re-run one side"],
          ]}
        />
        <P>Read a refusal literally; <DocLink to="simulation-lab#compare">Simulation Lab › Compare</DocLink> shows the exact message for each case. For runs older than the seed and schedule being stamped at dispatch, those two fall back to the scenario record — so a pass on an old run is weaker evidence than a pass on a new one.</P>
      </Section>

      <Section id="reading-the-table" title="Read the difference and its interval">
        <P>Under common random numbers, replication 3 of A and replication 3 of B saw the same demand and the same random lead times. So Compare subtracts them replication by replication, then puts a 95% t-interval on the <strong>mean of those differences</strong>. The common swing cancels, which is why a paired test can separate two policies whose own intervals overlap.</P>
        {PAIRED && (
          <DocTable
            caption="A worked example with five illustrative replications, computed by the same function Compare uses."
            head={["", "Rep 1", "Rep 2", "Rep 3", "Rep 4", "Rep 5", "Mean"]}
            rows={[
              ["A · fill rate", ...A.map((v) => pct(v)), pct(mean(A), 2)],
              ["B · fill rate", ...B.map((v) => pct(v)), pct(mean(B), 2)],
              ["B − A", ...B.map((v, i) => pp(v - A[i])), pp(PAIRED.mean)],
            ]}
          />
        )}
        {PAIRED && (
          <P>The paired difference is {pp(PAIRED.mean)} ± {(PAIRED.halfWidth * 100).toFixed(2)} pp over {PAIRED.n} pairs. The interval {PAIRED.separated ? "excludes" : "includes"} zero, so Compare {PAIRED.separated ? "marks B as better on fill rate" : "draws no direction"}. B won every single replication; the two runs' own intervals would still overlap, which is exactly the case a paired test exists for.</P>
        )}
        <P>A row with no matching replications on both sides reads <Term>unpaired</Term> and draws no direction at all. A winner is only ever drawn for a measure with a defined direction:</P>
        <DocTable
          caption="Which measures can have a winner — read from the KPI catalog."
          head={["Measure", "Better when"]}
          rows={[
            ...directional.map((k) => [k.label, k.higherIsBetter ? "higher" : "lower"]),
            [<em>{descriptive.length} descriptive measures</em>, <>no direction — {descriptive.map((k) => k.label.toLowerCase()).join(", ")}</>],
          ]}
        />
        <Details title="How this works: many cells, one decision">
          <p>Each scenario–KPI cell is its own test. Scanning thirty cells for something significant will find one by chance; decide the primary measure before you run, and confirm a surprising result with a fresh experiment.</p>
          <p>The matrix compares each challenger with the baseline, not challengers with each other. To rank two challengers, make one of them the baseline.</p>
          <p>Inventory and utilization are trade-offs, not scores: more is neither better nor worse until you say what it costs and what it buys.</p>
        </Details>
      </Section>

      <Section id="review-protocol" title="Check what the screen cannot decide for you">
        <Bullets items={[
          <>Confirm the dataset version behind each run. A changed price, BOM or capacity is a model change even when the label looks familiar.</>,
          <>Use the same warm-up and measured window on both sides, and check that the event and its recovery fall inside the window.</>,
          <>Read the actual paired count, not the requested one — a cancelled or failed replication drops out of the pairing.</>,
          <>Read the conversion notes on both runs. A new fallback or a clamped value is another changed factor.</>,
          <>Decide the difference that matters before choosing more replications, and don't keep adding them until a preferred answer turns significant.</>,
        ]} />
        <P>A worked trade-off: B serves five more units a week than A and lifts fill rate, but if the buffer behind it adds holding cost worth more than the lost sales it saves, the commercial answer is still no. Report <DocLink to="kpis-and-resilience-index">fill rate, lost-sales value and cost of resilience</DocLink> side by side.</P>
      </Section>

      <Section id="scope" title="What the app does, and what only the engine library does">
        <Flow
          caption="The comparison the app supports today: one baseline against many challengers, each tested in pairs."
          highlight={0}
          items={[
            { kicker: "baseline", title: "Run A", detail: "validated, completed" },
            { kicker: "challenger", title: "Run B", detail: "one change from A" },
            { kicker: "challenger", title: "Run C", detail: "one other change from A" },
          ]}
        />
        <P>The repository also contains an experiment-designer component and the engine library's stress and synergy functions. Their presence does not make them app features: use the controls documented here, or the Python interfaces documented with the engine.</P>
        <P>Next: <DocLink to="seeds-replications-confidence">seeds, replications and confidence</DocLink>, then <DocLink to="verifiable-exports">exporting the evidence</DocLink>.</P>
      </Section>
    </>
  );
}
