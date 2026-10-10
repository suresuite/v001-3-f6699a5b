// Experiments — Simulation Lab (guide).
//
// Every number and message a reader would otherwise have to trust this page
// for is computed by the code the Lab runs: the scenario defaults
// (`scenarioDefaults.ts`), the run-window and disruption rules and their
// mapper-computed examples (`registry.generated.json`), the run gate's states
// (`runGateState`) and the Compare refusals (`comparabilityFailures`). The
// page writes the explanation; it does not retype the facts.

import registry from "@/lib/policies/registry.generated.json";
import { SCENARIO_ENGINE_DEFAULTS as D, KPI_OPTIONS } from "@/lib/sim/scenarioDefaults";
import { runGateState, type RunGateInput } from "@/lib/sim/runGate";
import { comparabilityFailures, type ComparableSide } from "@/lib/sim/comparability";
import { formatDuration } from "@/lib/sim/planningTime";
import {
  DocPageTitle, InShort, Section, P, Callout, Check, Steps, Defs, Details, DocTable, Flow, QA,
  DocLink, AppLink, Term,
} from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";

const R = registry.run_window;
const E = (registry as unknown as {
  disruption: {
    start_week_min: number; duration_weeks_min: number; duration_weeks_max: number; event_cap: number;
    full_outage_pct: number; partial_cut_needs_finite_supplier_capacity: boolean;
    supported_target_kinds: string[]; unsupported_target_kinds: string[];
  };
}).disruption;
const list = (xs: string[]) => (xs.length > 1 ? `${xs.slice(0, -1).join(", ")} and ${xs[xs.length - 1]}` : xs[0] ?? "");

/** Situations a reader meets at the Run stage, each answered by the real gate. */
const GATE_CASES: { when: string; input: RunGateInput }[] = [
  { when: "Your project role does not include running simulations", input: { permitted: false, blocks: 0, warns: 0, acknowledged: false, needsSave: false } },
  { when: "The selected scenario is the validated baseline", input: { permitted: true, isBaseline: true, blocks: 0, warns: 0, acknowledged: false, needsSave: false } },
  { when: "Input checks found 2 blocking problems", input: { permitted: true, blocks: 2, warns: 1, acknowledged: false, needsSave: false } },
  { when: "3 warnings, not yet acknowledged", input: { permitted: true, blocks: 0, warns: 3, acknowledged: false, needsSave: false } },
  { when: "3 warnings, acknowledged", input: { permitted: true, blocks: 0, warns: 3, acknowledged: true, needsSave: false } },
  { when: "Policy edits since the last saved version", input: { permitted: true, blocks: 0, warns: 0, acknowledged: false, needsSave: true } },
  { when: "Nothing to fix", input: { permitted: true, blocks: 0, warns: 0, acknowledged: false, needsSave: false } },
];

/** Pairs a reader might try to compare, each judged by the real rule. */
const side = (o: { crn?: boolean; seed?: number; policy?: string; world?: string; events?: unknown[]; engine?: string }): ComparableSide => ({
  scenario: { crn: o.crn ?? true, seed: o.seed ?? 42, disruption_schedule: o.events ?? [] },
  run: {
    policy_version_id: o.policy ?? "policy-v1",
    scenario_hash: o.world ?? "world-a",
    code_version: o.engine ?? null,
    seed: o.seed ?? 42,
    disruption_schedule: o.events ?? [],
  },
});
const EVENT = [{ target: "S-BOARD", target_type: "node", start_day: 112, duration_days: 28, magnitude_pct: 80 }];
const COMPARE_CASES: { pair: string; a: ComparableSide; b: ComparableSide }[] = [
  { pair: "Baseline vs the same model with one disruption", a: side({}), b: side({ events: EVENT }) },
  { pair: "Same disruption under two policy versions", a: side({ events: EVENT }), b: side({ events: EVENT, policy: "policy-v2" }) },
  { pair: "A run against itself", a: side({}), b: side({}) },
  { pair: "Disruption AND new policy at once", a: side({}), b: side({ events: EVENT, policy: "policy-v2" }) },
  { pair: "Different seeds", a: side({}), b: side({ seed: 7, events: EVENT }) },
  { pair: "Common random numbers off on one side", a: side({}), b: side({ crn: false, events: EVENT }) },
];

export default function SimulationLabGuide() {
  return (
    <>
      <DocPageTitle slug="simulation-lab" />
      <InShort items={[
        <>Simulation Lab runs <strong>scenarios</strong> of a Validated Model: the same data and policies, under a different horizon, disruption or response.</>,
        <>Work left to right through five stages — Setup, Recovery playbook, Run, Results, Compare. A stage's tick is a hint, not proof.</>,
        <>Compare only runs that differ in exactly one thing, with the same seed and common random numbers on.</>,
      ]} />

      <Section id="the-rail" title="Before you run">
        <P>You need two things before the Lab is useful: a <strong>Validated Model</strong>, saved from <AppLink to="/policies">Policies</AppLink> › <strong>Run &amp; Validate</strong>, and a project role that allows running simulations. Without a Validated Model the Model selector says “No validated model — create one in Policies › Run &amp; Validate”.</P>
        <Defs items={[
          { term: "Model", def: <>The Validated Model the run follows — its dataset version, policy version and protocol. Its facts and credibility badge show under the selector.</> },
          { term: "Exploratory run", def: <>A checkbox, where your role allows it. The run uses current data without a Validated Model, is badged <Term>exploratory — unvalidated</Term> everywhere, can never be a Compare baseline and is never used as training data.</> },
          { term: "Engine", def: <>Which registered engine build runs the job. With one active engine the selector reads <Term>default engine</Term>. <DocLink to="engine-versions">Engine versions</DocLink> lists what each build changed.</> },
          { term: "Protocol", def: <>Replications, warm-up and horizon inherited from the model, <strong>locked</strong>. <strong>Advanced</strong> unlocks them; anything you change is listed as a deviation and recorded on the run.</> },
        ]} />
        <DocTable
          caption="The five stages across the top of the Lab, and what each one's sub-label tells you."
          head={["Stage", "Sub-label shows", "Ticked when"]}
          rows={[
            ["1 · Setup", "horizon · replications · primary KPI", "a primary KPI is chosen"],
            ["2 · Recovery playbook", "events, then levers (or “no events”)", "at least one event and one recovery lever, with recovery on — a baseline never ticks"],
            ["3 · Run", "the gate: not permitted · N blocking · ack N warnings · ready · running", "a run finished and the gate is open"],
            ["4 · Results", "no run · queued 3/10 · running 7/10 · done · older version", "the latest run is done and matches the current settings"],
            ["5 · Compare", "how many scenarios have results", "two or more scenarios have results"],
          ]}
        />
        <DocFigure id="run-sequence" />
      </Section>

      <Section id="new-scenario" title="Create a scenario">
        <Steps steps={[
          { title: "Choose + beside the scenario list", where: "/simulation-lab", body: <>A dialog asks four things: a name, where to start, how long, and what to watch.</> },
          { title: "Pick where to start", where: "Start from", body: <><strong>Validated baseline</strong> (the default) copies the baseline's world. <strong>Stress test</strong> starts from the baseline with a preset disruption — see <DocLink to="stress-tests">Stress tests</DocLink>. <strong>Engine defaults</strong> starts from the values below. The first two need a validated baseline.</> },
          { title: "Leave the horizon locked unless you mean it", where: "Horizon", body: <>From the baseline the horizon is locked, because it is part of what the validation certified. <strong>change</strong> unlocks it — and the dialog warns that the new scenario will not inherit the validation and its badge will read stale.</> },
          { title: "Choose the KPI to watch, then Create", where: "Primary KPI", body: <>Warm-up and replications are shown, not asked: they come from the validation, or from the engine defaults when you start from defaults.</>, check: "the new scenario selected in the list, on the Setup stage." },
        ]} />
        <DocTable
          caption="What a scenario started from engine defaults contains."
          head={["Setting", "Default"]}
          rows={[
            ["Planning horizon", `${D.horizon_days} days (${formatDuration(D.horizon_days)})`],
            ["Warm-up", D.warmup_mode === "auto" ? "detected automatically at run time" : `${D.warmup_days} days`],
            ["Replications", String(D.replications)],
            ["Seed", String(D.seed)],
            ["Common random numbers", D.crn ? "on" : "off"],
            ["Stopping rule", D.stopping_rule.kind === "fixed_horizon" ? `fixed horizon, at most ${D.stopping_rule.max_wall_seconds} s of compute` : D.stopping_rule.kind],
            ["Primary KPI", KPI_OPTIONS.find((k) => k.value === D.primary_kpi)?.label ?? D.primary_kpi],
            ["Disruptions", D.disruption_schedule.length === 0 ? "none" : `${D.disruption_schedule.length}`],
          ]}
        />
        <P>Copying a scenario copies its settings, not its finished runs. The validated baseline itself is read-only here: it runs in Policies, and the Lab copies it.</P>
      </Section>

      <Section id="setup" title="Setup: horizon, warm-up and precision">
        <Defs items={[
          { term: "Planning horizon", def: <>How long one replication simulates. Entered in your planning unit, run in whole weeks, between {R.horizon_weeks_floor} and {R.horizon_weeks_ceiling} weeks; a value outside is raised or lowered and the card says so.</> },
          { term: "Warm-up detection", def: <><strong>auto</strong> lets the engine find when the chain settles; <strong>manual</strong> uses <strong>Steady state starts at</strong>. Typing a warm-up switches to manual and drops the value inherited from the validation — on purpose, so a divergence is never silent.</> },
          { term: "Replications", def: <>Independent repeats with different random draws, at least 1. More replications narrow the confidence interval; they do not make the model more correct. Editing the number also drops the inherited value.</> },
          { term: "Common random numbers · Seed", def: <>With common random numbers on, two scenarios with the same seed draw the same randomness, so a difference between them comes from what you changed rather than from luck. Keep both identical across anything you mean to compare.</> },
          { term: "Stopping rule", def: <><strong>fixed horizon</strong> runs every replication to the end. <strong>CI half-width</strong> stops once the interval on the primary KPI is narrow enough.</> },
          { term: "Primary KPI", def: <>The objective the run reports first: {KPI_OPTIONS.map((k) => k.label).join(", ")}.</> },
        ]} />
        <P>The Run-window card's footer states what the engine will <em>measure</em>, which is not “horizon minus warm-up”. The engine measures a window of {R.analysis_window_weeks} weeks after warm-up — never fewer than {R.analysis_window_min_weeks} or more than {R.analysis_window_max_weeks}, and leaving the last {R.analysis_window_tail_weeks} weeks of the horizon out of the window's room. Weeks after the window are run but not measured.</P>
        <DocTable
          caption="How the engine reads a horizon and warm-up — computed by the engine's own mapper."
          head={["Horizon", "Warm-up", "Runs as", "Measured"]}
          rows={R.examples.map((x) => [
            `${x.horizon_days} days`,
            x.warmup_mode === "manual" ? `${x.warmup_days} days (manual)` : "auto",
            `${x.horizon_weeks} weeks${x.warmup_weeks != null ? `, ${x.warmup_weeks} warm-up` : ""}`,
            x.measured_weeks != null ? `${x.measured_weeks} weeks` : `${x.analysis_window_weeks} weeks after the detected warm-up`,
          ])}
        />
        <P>The Precision card's footer multiplies it out — replications × horizon = run-weeks — which is the honest measure of how long a run will take.</P>
      </Section>

      <Section id="setup-recovery" title="Recovery playbook: events and responses">
        <P>An empty playbook is a baseline. To test a shock, add an <strong>event</strong>: a target (a supplier or the plant), a type such as a capacity reduction, a magnitude, a start and a duration. A <strong>lever</strong> is a response to it, applied only when recovery is on — leave levers off for the first disrupted run, so you measure the shock before the cure.</P>
        <P>Events are entered in days and run in whole weeks: start week at least {E.start_week_min}, duration between {E.duration_weeks_min} and {E.duration_weeks_max} weeks. The engine runs the first {E.event_cap} events; any beyond that are dropped with a warning. A magnitude of {E.full_outage_pct}% is a full outage and anything below is a capacity cut{E.partial_cut_needs_finite_supplier_capacity ? " — except on a supplier with no finite capacity in your data, where there is nothing to cut a share of, so a partial cut becomes a full outage" : ""}.</P>
        <DocTable
          caption="Days as entered, and the weeks the engine runs — computed by the engine's own mapper."
          head={["Start day", "Duration", "Runs from week", "For"]}
          rows={(R.disruption_examples ?? []).map((x) => [String(x.start_day), `${x.duration_days} days`, String(x.start_week), `${x.duration_weeks} ${x.duration_weeks === 1 ? "week" : "weeks"}`])}
        />
        <Callout tone="warning" title="Not every target reaches the engine">
          <p>The engine can disrupt a {list(E.supported_target_kinds)}. A {list(E.unsupported_target_kinds)} is not a target it can place: the event is dropped with a conversion note, and the run then looks exactly like the baseline. <DocLink to="disruptions">Disruptions</DocLink> lists the event types and <DocLink to="recovery-playbooks">Recovery playbooks</DocLink> the levers.</p>
        </Callout>
      </Section>

      <Section id="the-gate" title="Run: the gate">
        <P>The <strong>Run</strong> stage checks the model before anything is sent. The rail's right-hand readout, stage 3's sub-label, the button and the reason beside it all come from one rule, so they cannot disagree. This is what it says in each situation:</P>
        <DocTable
          caption="The run gate, computed by the Lab's own rule for each situation."
          head={["Situation", "Rail reads", "Button", "Why it won't run"]}
          rows={GATE_CASES.map(({ when, input }) => {
            const g = runGateState(input);
            return [when, g.readout.value, g.button, g.reason ?? "it will run"];
          })}
        />
        <P>Acknowledging warnings records your choice; it does not make the inputs right. A warning can describe a real substitution — a default used where your data was blank — so read each one first. A “not permitted” state needs the project owner, not a different setting.</P>
        <Check>a run with an ID, its version bindings and a status of queued or running. Clicking Run alone is not completion.</Check>
      </Section>

      <Section id="how-a-run-goes" title="While it runs">
        <Flow
          caption="A run's life. Results are preliminary until it is done with the full count."
          highlight={2}
          items={[
            { title: "queued", detail: "waiting for a worker" },
            { title: "running", detail: "replications arrive, 7/10" },
            { title: "done", detail: "every replication finished" },
          ]}
        />
        <QA items={[
          { q: "Can I close the browser?", a: "Yes. The run executes remotely; closing the tab neither pauses nor cancels it." },
          { q: "How do I stop it?", a: <>Use <strong>Cancel</strong>, shown while the run is queued or running, then check that its final status reads cancelled. A cancelled or failed run with some replications is not the experiment you asked for.</> },
          { q: "It said results already exist", a: <>If an identical run already finished, the Lab asks <strong>Reuse the stored results?</strong> with when it ran, how many replications and which engine. <strong>Reuse results</strong> shows that run (nothing is recomputed); <strong>Re-run</strong> computes it again from scratch.</> },
          { q: "It was refused for capacity", a: "Your organization's capacity can refuse a run: a used-up quota, too many replications for one run, or too many runs in flight. The message carries the numbers; wait, or reduce the replications." },
          { q: "It failed", a: "Keep the run ID and the error, read the conversion notes and input findings, and fix the cause. Re-sending the same blocked model will fail the same way." },
        ]} />
        <Callout tone="warning" title="“+10 reps” does not add replications yet">
          <p>A finished run shows a <strong>+10 reps</strong> button, and the request is accepted — but the worker has no step that carries it out, so no replications are added and the interval does not tighten. To get more replications, raise <strong>Replications</strong> in Setup and run again.</p>
        </Callout>
      </Section>

      <Section id="results" title="Results">
        <P>Open <strong>Results</strong> when the run is done. Read in this order: the run record (status, completed count, the dataset, policy and scenario versions), then the engine conversion notes, then the KPI summary, convergence plot, weekly traces and inventory. <DocLink to="reading-your-results">Reading your results</DocLink> walks through each panel and what it can and cannot support.</P>
        <P>If the stage reads <Term>older version</Term>, the latest finished run was made under settings that have since changed — run again before reading it as this scenario's result.</P>
      </Section>

      <Section id="compare" title="Compare">
        <P>Pick a completed, non-exploratory baseline; comparable scenarios appear beside it, and selecting one opens the paired table. Two runs are comparable only if they share the seed with common random numbers on, and differ in <strong>exactly one</strong> of three things: the <strong>policies</strong>, the <strong>world</strong> (horizon, time step, demand model) or the <strong>events</strong> (the disruption schedule). Runs from different engine builds are refused too.</P>
        <DocTable
          caption="Pairs you might try, and what Compare answers — computed by its own rule."
          head={["Pair", "Compare says"]}
          rows={COMPARE_CASES.map(({ pair, a, b }) => {
            const f = comparabilityFailures(a, b);
            return [pair, f.length === 0 ? "comparable" : f.join("; ")];
          })}
        />
        <Details title="How this works: why exactly one difference">
          <p>With the seed and common random numbers held, both runs see the same demand and the same random lead times, so the difference between them is caused by the one thing you changed. Change two things and the difference is real but cannot be split between them.</p>
          <p>The seed and schedule are read from the run as it was dispatched, not from the scenario as it is now, so editing a scenario afterwards cannot make an old pair look comparable.</p>
        </Details>
        <P>Next: <DocLink to="experiments-and-comparison">design a controlled comparison</DocLink>, and <DocLink to="seeds-replications-confidence">how many replications you need</DocLink>.</P>
      </Section>
    </>
  );
}
