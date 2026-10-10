// Experiments — Seeds, replications & confidence (concept).
//
// The replication rule's worked numbers are computed with the same t-quantile
// Run & Validate uses (`studentTQuantile`) and capped by the same ceiling
// (`MAX_REPLICATIONS`); the run-window clamp is the engine's exported rule.
// The two example pilots are illustrative inputs, labelled as such.

import registry from "@/lib/policies/registry.generated.json";
import { studentTQuantile } from "@/lib/sim/validationStats";
import { MAX_REPLICATIONS } from "@/lib/sim/validatedModel";
import {
  DocPageTitle, InShort, Section, P, Callout, Defs, Details, DocTable, Flow, DocLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

const R = registry.run_window;

/** n* = (t·s / (ε·x̄))², t at n − 1 degrees of freedom — Run & Validate's rule. */
function nStar(mean: number, sd: number, n: number, eps: number, confidence = 0.95) {
  const t = studentTQuantile(1 - (1 - confidence) / 2, Math.max(1, n - 1));
  return Math.max(1, Math.ceil(((t * sd) / (eps * Math.abs(mean))) ** 2));
}
const PILOTS = [
  { kpi: "Fill rate", mean: 0.95, sd: 0.03, fmt: (x: number) => `${(x * 100).toFixed(0)}%`, sdFmt: (x: number) => `${(x * 100).toFixed(0)} pp` },
  { kpi: "Lost-sales value", mean: 12600, sd: 4000, fmt: (x: number) => x.toLocaleString("en"), sdFmt: (x: number) => x.toLocaleString("en") },
];
const EPS = 0.05;

export default function SeedsReplicationsConfidence() {
  const rows = PILOTS.map((p) => {
    const n = nStar(p.mean, p.sd, 10, EPS);
    return [p.kpi, p.fmt(p.mean), p.sdFmt(p.sd), String(n), n > MAX_REPLICATIONS ? `${MAX_REPLICATIONS} (clamped)` : String(n)];
  });
  return (
    <>
      <DocPageTitle slug="seeds-replications-confidence" />
      <InShort items={[
        <>A <strong>seed</strong> fixes the random draws; <strong>common random numbers</strong> make two scenarios share them, so a difference comes from what you changed.</>,
        <><strong>Replications</strong> buy precision, not truth. Run &amp; Validate recommends a count from a pilot, per KPI, and the Lab inherits it.</>,
        <>A confidence interval is about the model's average, from finite runs. It is not a forecast range for your real chain.</>,
      ]} />

      <Section id="seeds" title="Seeds and common random numbers">
        <P>Demand, lead times and disruptions are drawn at random. The <strong>seed</strong> fixes those draws, so the same model, engine build and seed give the same result. Keep all three: a seed alone does not promise identical output on another engine version.</P>
        <P>With <strong>common random numbers</strong> on, replication 1 of scenario A and replication 1 of scenario B draw the same demand and the same lead times. That is what lets <DocLink to="experiments-and-comparison">Compare</DocLink> subtract them replication by replication. The seed and schedule are stamped on each run when it is dispatched, and Compare reads them from there.</P>
        <DocFigure id="replications" />
      </Section>

      <Section id="replications" title="How many replications?">
        <P>A replication is one simulated history. Each one gives a value for every KPI; the spread of those values across replications is what the confidence interval measures. More replications narrow it in proportion to 1/√n — four times the replications for half the width.</P>
        <P>Run &amp; Validate turns that into a recommendation. From a pilot of <Term>n</Term> replications it takes each focal KPI's mean <Term>x̄</Term> and standard deviation <Term>s</Term>, and your target precision <Term>ε</Term> (a half-width as a share of the mean), and computes</P>
        <div data-b="text" className="max-w-[68ch] rounded-md border border-border bg-muted px-4 py-3 text-center font-mono text-[14px] text-foreground">
          n* = ( t · s / (ε · x̄) )²
        </div>
        <P>with <Term>t</Term> the Student-t quantile at <Term>n − 1</Term> degrees of freedom. The recommendation is the largest <Term>n*</Term> across the focal KPIs, capped at {MAX_REPLICATIONS}; a capped value is recorded as clamped. Scenarios created from that Validated Model start with it.</P>
        <DocTable
          caption={`Illustrative pilots of 10 replications at ε = ${EPS * 100}% and 95% confidence, computed with the same rule.`}
          head={["KPI", "Pilot mean", "Pilot s.d.", "n*", "Recommended"]}
          rows={rows}
        />
        <P>The same target is far cheaper on a high, stable measure like fill rate than on a small, noisy one like lost sales. If the recommendation is clamped, the cap — not your precision target — decides the width; say so when you report.</P>
        <Callout tone="tip" title="The tutorial's three replications">
          <p>The <DocLink to="your-first-project">control-unit tutorial</DocLink> has fixed demand and lead times, so all its replications are identical and the interval has zero width. Three exercise the workflow; they are no evidence about variability in a real chain.</p>
        </Callout>
      </Section>

      <Section id="warmup" title="Warm-up and the measured window">
        <P>A run starts from your opening stock and an empty pipeline, so the first weeks are not typical. Warm-up is the stretch the engine excludes before it starts measuring.</P>
        <Defs items={[
          { term: "auto", def: <>The engine runs two detectors on the weekly fill rate, averaged across clean (undisrupted) replications, and adopts the <strong>later</strong> of the two: <strong>MSER-5</strong>, which batches the series into 5-week means and cuts where the remaining batches are most stable, and <strong>Conway's rule</strong>, the first week that is neither the highest nor the lowest of what follows. Both are reported; an adopted warm-up of 0 is possible.</> },
          { term: "manual", def: <>Your <strong>Steady state starts at</strong> value, in whole weeks, never more than half the horizon.</> },
        ]} />
        <Flow
          caption={`What a run measures: a ${R.analysis_window_weeks}-week window after warm-up (between ${R.analysis_window_min_weeks} and ${R.analysis_window_max_weeks} weeks). Weeks after it are run but not measured.`}
          highlight={1}
          items={[
            { title: "Warm-up", detail: "detected or set; excluded" },
            { title: "Measured window", detail: "every KPI comes from here" },
            { title: "Rest of horizon", detail: "run, not measured" },
          ]}
        />
        <P>Keep the same warm-up and window across scenarios you compare, unless the window is the thing you are testing. And if your question <em>is</em> the start-up — how a new chain fills from empty — excluding warm-up removes exactly what you wanted to study.</P>
      </Section>

      <Section id="confidence" title="What the interval means">
        <DocTable
          caption="The columns of the KPI summary in Results."
          head={["Column", "What it is", "What it is not"]}
          rows={[
            ["Mean", "The average across completed replications", "The value your real chain will see"],
            ["± 95% CI", "t · s / √n either side of the mean — where the model's true average plausibly lies, given n replications", "A range for next year's outcome"],
            ["σ", "The standard deviation: how much one replication differs from another", "Measurement error"],
            ["Min · Max", "The lowest and highest replication actually seen", "A worst case — more replications can widen it"],
            ["n", "Replications that finished and returned the measure", "The number you requested"],
          ]}
        />
        <Callout tone="warning" title="Precision is not validity">
          <p>A narrow interval can sit on a wrong demand mean, a missing common supplier, a wrong BOM quantity or an impossible capacity. Check the inputs and conversion notes, compare with what you have observed, and test the alternatives you are unsure of. <DocLink to="model-validation">Model validation</DocLink> is where that evidence is recorded.</p>
        </Callout>
        <Details title="How this works: missing values are not zeros">
          <p>If recovery was not seen before the window ended, time to recover is censored: report that it exceeded the window, never zero. If there was no demand in the window, fill rate has no value.</p>
          <p>A measure the engine returned on no replication is shown as not measured, with the reason, rather than disappearing from the table.</p>
        </Details>
        <P>Next: <DocLink to="model-validation">model validation</DocLink> and <DocLink to="experiments-and-comparison">controlled comparison</DocLink>.</P>
      </Section>
    </>
  );
}
