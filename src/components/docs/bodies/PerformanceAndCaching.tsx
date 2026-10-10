// §6.3 section 11 — performance and caching.
//
// The analysis store as a user meets it: a metric belongs to a run, therefore
// to an input hash and a code version, therefore a repeat request is a HIT BY
// DEFINITION rather than a bet on a timestamp. And the honest half: the store
// is empty in practice because nobody has run an analysis since it shipped
// (§4 D88).

import { capacityVerdict, type CapacityState } from "@/lib/sim/labModel";
import { PageTitle, InShort, Section, P, Key, Callout, Defs, DocTable, Term, DocLink, Provenance } from "@/components/docs/prose";

/** An illustrative plan: 5,000 replication-weeks a month, 2 runs at once, 50 replications per run. */
const plan = (o: Partial<CapacityState["pool"]> = {}, share: CapacityState["share"] = null): CapacityState => ({
  org_id: "example", role: "analyst",
  pool: {
    compute_quota_rep_weeks_month: 5000, compute_used_rep_weeks: 1200, storage_quota_bytes: null, storage_used_bytes: 0,
    max_concurrent_runs: 2, active_runs: 0, max_replications_per_run: 50, ...o,
  },
  share,
});
const run = (replications: number, weeks = 52) => ({ replications, repWeeks: replications * weeks, bytes: 0 });
const CAPACITY_CASES: { when: string; v: ReturnType<typeof capacityVerdict> }[] = [
  { when: "10 replications × 52 weeks, room to spare", v: capacityVerdict(plan(), run(10)) },
  { when: "100 replications in one run", v: capacityVerdict(plan(), run(100)) },
  { when: "Two runs already queued or running", v: capacityVerdict(plan({ active_runs: 2 }), run(10)) },
  { when: "Month nearly used up", v: capacityVerdict(plan({ compute_used_rep_weeks: 4900 }), run(10)) },
  { when: "No limits on the plan", v: capacityVerdict(plan({ compute_quota_rep_weeks_month: null, max_concurrent_runs: null, max_replications_per_run: null }), run(10)) },
];

export default function PerformanceAndCaching() {
  return (
    <>
      <PageTitle lead="Why a second run is faster, and when the answer is recomputed instead.">
        Performance &amp; caching
      </PageTitle>
      <InShort items={[
        <>An answer is reused when it was computed from the same data, parameters and code — never just because it is recent.</>,
        <>An identical simulation offers to <strong>reuse</strong> the stored results; you choose, and Re-run always computes again.</>,
        <>Your organization's plan can limit replications per run, runs at once and replication-weeks a month. The Run card says what is left before you click.</>,
      ]} />

      <Section id="the-rule" title="The rule that decides a reuse">
        <Key>
          An answer is reused when it was computed from the same data, with the same parameters, by
          the same version of the code. Not when it is recent.
        </Key>
        <P>
          That is the whole design, and it is the opposite of the usual one. A cache keyed on
          freshness is a bet: <em>probably nothing has changed in the last hour</em>. This is keyed
          on identity — two requests carrying the same three things are asking the same question, so
          answering from the store is not an optimisation with a risk attached, it is the same
          answer.
        </P>
        <P>
          The consequence a user feels: change your data and the next request recomputes, every
          time, without you having to remember to clear anything. Change nothing and it returns
          immediately, however long ago it was computed.
        </P>
      </Section>

      <Callout tone="law" title="A result you are shown always knows what it was computed from">
        <p>
          Because reuse is keyed on identity, every stored answer carries the identity it was keyed
          on — which data, which parameters, which code version. That is what lets{" "}
          <DocLink to="data-trust-report">the Data Trust Report</DocLink> sort a project's computed
          rows into current, out of date, and <em>we cannot tell</em>.
        </p>
      </Callout>

      <Callout tone="limit" title="In practice the store is empty, and that is worth knowing">
        <p>
          The mechanism is shipped and correct. What has not happened is that anybody has run an
          analysis since it shipped — so every computed row that exists predates it and carries no
          identity at all, and none of them can be reused.
        </p>
        <p>
          The first analysis you run fills it in for the rows it writes. Until then, everything
          recomputes, and <DocLink to="reproducibility-record">Reproducibility record</DocLink>{" "}
          explains why the old rows cannot be back-filled rather than being given a plausible stamp.
        </p>
      </Callout>

      <Section id="simulation-reuse" title="Reusing a simulation">
        <P>Every dispatched run gets a <strong>RunKey</strong>: a fingerprint of everything that decides its numbers — the engine build, the policy version, the data the simulation reads, and the scenario's settings, seed and disruptions. Two runs with the same key produce the same results.</P>
        <P>So when you dispatch a scenario whose key matches a completed run, the Lab asks <strong>Reuse the stored results?</strong>, naming when that run finished, its replications and its engine. <strong>Reuse results</strong> shows it instantly; <strong>Re-run</strong> computes it again from scratch. Neither is automatic.</P>
        <Defs items={[
          { term: "Changes the key", def: "A data edit the simulation reads, a new policy version, any scenario setting (horizon, warm-up, replications, seed, disruptions), or a new engine build." },
          { term: "Does not change it", def: "Deep-tier company data, network layouts and centralities — the simulation does not read them, so they cannot make an identical run a new one." },
        ]} />
      </Section>

      <Section id="capacity" title="What your organization's plan allows">
        <P>An organization can have up to five limits: replication-weeks per month (compute), storage, runs queued or running at once, replications per run, and how long a run's weekly series are kept. A role can also be given a share of the organization's compute and storage. A limit left empty is unlimited.</P>
        <P>The Run card states what is left, and forecasts — in the dispatcher's own order — the refusal a run would get, before you click. These are its words for an illustrative plan of 5,000 replication-weeks a month, 2 runs at once and 50 replications per run, with 1,200 replication-weeks already used:</P>
        <DocTable
          caption="The Run card's capacity line and forecast refusal — computed by the Lab's own function."
          head={["Situation", "Capacity line", "Refused because"]}
          rows={CAPACITY_CASES.map(({ when, v }) => [when, v.line, v.refusal ?? "fits"])}
        />
        <P>A replication-week is one replication simulating one week, so a run costs replications × horizon weeks. Halving either halves the cost.</P>
      </Section>

      <Section id="retention" title="How long a run's weekly series are kept">
        <P>A finished run's KPIs are kept. Its <strong>weekly series</strong> — the traces behind the charts — are kept for the organization's retention period, then removed to free storage. The line under a finished run says which of three states it is in:</P>
        <Defs items={[
          { term: "Standard", def: "Kept until a date, then removed. Editors can choose Keep series to pin it." },
          { term: "Pinned", def: "Kept until someone with Edit Policies chooses Release." },
          { term: "Evidence", def: "The runs behind a Validated Model are kept for as long as the model needs them, and cannot be released." },
        ]} />
        <P>A run whose series were removed says so, with its RunKey — dispatching the same key again reproduces the series exactly. The KPIs never go away.</P>
      </Section>

      <Section id="why-a-run-is-slow" title="Why a particular run is slow">
        <P>
          The simulation cost scales with the size of your chain, the length of the window and the
          number of replications — and only the last of those is free to change. Halving
          replications halves the time and widens every interval, which is a trade to make
          deliberately rather than to discover.
        </P>
        <P>
          Replications are independent, so they parallelise; a single replication does not, and is
          deterministic for that reason. A run that is slow because the model is large will not get
          faster on a bigger machine per replication — it gets faster because more of them run at
          once.
        </P>
      </Section>

      <Callout title="Uploading a large network is one recomputation, not one per row">
        <p>
          Loading a deep-tier graph used to trigger a full recomputation of the whole graph{" "}
          <em>for every row inserted</em> — thousands of identical requests, none of which could
          reuse another because each one saw a slightly different graph. That is fixed: a bulk load
          is one statement and triggers one recomputation.
        </p>
      </Callout>

      <Section id="related" title="Related">
        <P>
          <DocLink to="dataset-versions">Dataset Versions</DocLink> ·{" "}
          <DocLink to="network-science-metrics">Network science metrics</DocLink> ·{" "}
          <DocLink to="seeds-replications-confidence">Seeds, replications &amp; confidence</DocLink> ·{" "}
          <DocLink to="data-trust-report">Data Trust Report</DocLink>
        </P>
      </Section>

      <Provenance from="the analysis store's five-part identity, as the contract declares it" />
    </>
  );
}
