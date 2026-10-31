// §6.3 section 7 — disruptions.
//
// ── THE PAGE THAT CANNOT PICK A SIDE ──────────────────────────────────────
//
// TWO disruption models are live at once and neither reads the other: the
// original one-row-per-node shape, and the profile/target/effect/setting split
// that redesigned it a day later. Nothing migrated the rows and nothing
// deprecates either, so a project can hold disruptions in both and a reader of
// one sees half the picture (§16 · WP 6.4 slice 13).
//
// WP 9.4 made the product-side half of that decision (a §16 decision entry): the
// network pages' dialog, the only writer the product had for the profile split,
// now writes the scenario's own schedule instead, so NO screen writes either
// table any more. Deprecating the tables themselves is still a migration with a
// §15 reading either side; this page documents both, as history, and says which
// one the product now writes.

import { PageTitle, Section, P, Key, Callout, Prose, Term, DocLink, Provenance } from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { refTable } from "@/components/docs/tableFacts";
import { SuppliedAndComputed, DatabaseRules } from "@/components/docs/tableRef";

const PROFILE_TABLES = [
  ["disruption_scenario_profiles", "the header — what the disruption is called, when it starts and ends"],
  ["disruption_scenario_targets", "what it hits"],
  ["disruption_scenario_effects", "what it does"],
  ["disruption_scenario_settings", "how it is simulated"],
] as const;

export default function Disruptions() {
  const inline = refTable("disruption_scenarios");
  const parts = PROFILE_TABLES.map(([name, role]) => ({ t: refTable(name), role }));

  return (
    <>
      <PageTitle lead="What fails, when, for how long — and the two different ways this system records that.">
        Disruptions
      </PageTitle>

      <Callout tone="limit" title="Read this first: the simulation reads the scenario's own schedule, and the two tables below are history">
        <p>
          <strong>The simulation runs off a disruption schedule stored on the scenario itself</strong>
          — the list you edit on stage 2 of{" "}
          <DocLink to="simulation-lab">Simulation Lab</DocLink>, and the one a{" "}
          <DocLink to="stress-tests">stress preset</DocLink> fills in for you. That schedule is sent
          with the run and is the only disruption the engine ever sees.
        </p>
        <p>
          The two <em>tables</em> described below are a different thing. One is a single row per
          affected node; the other splits a disruption into a profile, its targets, its effects and
          its settings. Neither reads the other, nothing migrated the rows from the first into the
          second, and nothing marks either as retired. <strong>And no run reads either of
          them</strong>: the worker loads the item masters, the logistics, the BOM, the customers
          and the scenario, and no disruption table is in that list.
        </p>
        <p>
          Until September 2026 a disruption added from a network map's dialog was written to the
          second table set <em>and</em> to a new scenario — and the table half never changed a
          simulation. <strong>The dialog now writes only the scenario's schedule</strong>, to a new
          scenario started from the validated baseline or to one you already have, and it checks
          the target first: the engine disrupts a supplier of the project or the plant, and says
          so before anything is saved.
        </p>
        <p>
          <strong>So the product writes one model, the scenario's schedule.</strong> The two tables
          below keep the rows written before that change; no screen writes them now, and retiring
          them is a migration that has not been made. They are described here so the rows that
          exist can still be read.
        </p>
      </Callout>

      <Section id="the-live-one" title="The one the engine reads: a scenario's own schedule">
        <P>
          A list of events on the scenario, each naming what is hit, the day it starts, how many
          days it lasts and how hard it is. It travels with the run and is the only disruption the
          engine acts on.
        </P>
        <P>
          Everything about how those four numbers are interpreted — which targets resolve, how days
          become weeks, what a magnitude at or above 100% does, and the five-event cap — is on{" "}
          <DocLink to="stress-tests">Stress tests</DocLink>, because that is the page a reader
          arrives at with a schedule already written for them. Read it before you write one by hand.
        </P>
        <P>
          <strong>A start can be entered three ways</strong> — a run week, an ISO 8601 calendar
          week (weeks start Monday; some years have a week 53) or a date — and all three go through
          the project&apos;s simulation start, which is run week 0: run week <em>t</em> is the seven
          days from the start plus 7·<em>t</em>. The engine runs whole weeks, so a date lands in the
          run week that contains it, and the line under the field always states all three readings.
          What you typed is kept beside the run week; if the project start later changes, the event
          says so and offers to keep its run week or move to what you entered — it never moves by
          itself. Without a simulation start only the run week can be entered. The engine has a
          second calendar for demand — the earliest forecast period — and the editor says when the
          two differ.
        </P>
        <P>
          A run records the date of its week 0 when it is dispatched, so later edits to the project
          start never re-date it. Runs made before that record existed were given the project start
          as it stood on 31 Oct 2026, and every place that shows it says it was filled in afterwards.
          Those starts had been saved a day early (31 December instead of 1 January) and were then
          corrected on the projects; the runs keep the 31 December they recorded, so a past run&apos;s
          week 0 can read one day before its project&apos;s start.
        </P>
        <P>
          It is a column on the scenario rather than a table of its own, which is why it has no
          reference block here.
        </P>
      </Section>

      <Section id="the-original" title="The first table — one row per affected node">
        <P>
          <Prose text={inline.grain} />
        </P>
        <P>
          Everything about one disruption lives on one row: which node, how much capacity is lost,
          how much delay is added. It is the simpler thing to write and the harder thing to extend —
          a disruption that hits an edge rather than a node has nowhere to go.
        </P>
        <SuppliedAndComputed table={inline} />
        <DatabaseRules table={inline} />
              <DocFigure id="disruption-models" />
      </Section>

      <Section id="the-split" title="The second table set — a profile, and three tables under it">
        <P>
          The same idea, normalised. A profile is the disruption; three tables under it say what it
          hits, what it does, and how it is simulated. A profile deleted takes all three with it, so
          one action by a person removes rows from four tables.
        </P>
        <div className="space-y-4">
          {parts.map(({ t, role }) => (
            <div key={t.table}>
              <div className="mb-1 flex flex-wrap items-baseline gap-2">
                <Term>{t.table}</Term>
                <span className="text-[12px] text-muted-foreground">{role}</span>
              </div>
              <SuppliedAndComputed table={t} />
            </div>
          ))}
        </div>
      </Section>

      <Callout tone="limit" title="Two things the split does not check">
        <p>
          <Term>target_type</Term> decides whether the node list or the edge list is the meaningful
          one, and nothing stops a node target carrying an edge list. The effects table has exactly
          this shape <em>and</em> a check that enforces it — so the gap is visible only when the two
          are read side by side, which is what a reference section is for.
        </p>
        <p>
          <Term>settings.key</Term> is free text with no vocabulary. A key is unique within its
          profile, which means a typo creates a new setting rather than failing.
        </p>
      </Callout>

      <Callout title="One disruption column carries its unit in its name">
        <p>
          The original shape's delay column names its unit in the column itself, where the tier-2
          convention is a value column beside a unit column — the pattern{" "}
          <DocLink to="units-and-time-periods">Units and time periods</DocLink> describes. It is
          defensible for a decision rather than a measurement, and worth saying, because a reader
          who has learned the tier-2 rule will go looking for a companion column that does not
          exist.
        </p>
      </Callout>

      <Section id="related" title="Related">
        <P>
          <DocLink to="scenarios">Scenarios</DocLink> ·{" "}
          <DocLink to="recovery-playbooks">Recovery playbooks</DocLink> ·{" "}
          <DocLink to="stress-tests">Stress tests</DocLink> ·{" "}
          <DocLink to="policy-catalog">The policy catalog</DocLink>
        </P>
      </Section>

      <Provenance from="the five disruption sidecars for the two table models, and the worker's own table list for what a run loads — which is where the third model, and the fact that it is the only live one, comes from" />
    </>
  );
}
