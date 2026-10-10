// §6.3 section 5 — How planning works (PLAN.md §24, Phase 14). The flow the
// owner decided on 2026-10-02 (ADR 0002): future finished-good demand → planned
// production → material orders → fulfillment, one rule from end to end. Every
// setting it names is a cell documented on its own stage page.
//
// The worked example and the FG-policy examples are the design's
// (`docs/design/mrp-multi-stage-planning.md` §2, §3.2) and each is pinned by an
// engine test — golden #7 in `scsim/tests/test_mrp.py` and the examples in
// `scsim/tests/test_planned_production.py` — so the numbers below are the
// numbers the engine produces. The allocation rules' names are read from the
// policy schema and labelled as /policies labels them.

import { AllocationRule } from "@/lib/policies/schemas";
import { ALLOCATION_FIELD } from "@/lib/policies/projectRules";
import {
  PageTitle, InShort, Section, P, Key, Callout, Defs, Details, DocTable, Flow, Term, DocLink, AppLink, Provenance,
} from "@/components/docs/prose";

/** What each allocation rule does — the engine's own definitions (`scsim/core/allocation.py`). */
const RULE_MEANING: Record<string, string> = {
  priority: "The row with the highest priority is filled completely, then the next.",
  fair_share: "Every row gets the same fill rate — each in proportion to what it wants.",
  proportional: "In proportion to each row's weight (by default, what it wants), never above its want; any excess is re-spread.",
  revenue_max: "The row with the highest price is filled completely, then the next.",
  sla_tier: "Every row first gets its service floor (a share of its want); what remains goes by priority.",
};

export default function HowPlanningWorks() {
  const label = ALLOCATION_FIELD.optionLabel ?? ((t: string) => t);
  return (
    <>
      <PageTitle lead="From the demand your customers state, to what the plant builds, to what it buys, to who gets served.">
        How planning works
      </PageTitle>
      <InShort items={[
        <>The plan starts from each customer row's forecast or mean — never from the demand the run will actually draw.</>,
        <>Planned production is the requirement capped at capacity. MRP materials are ordered from that plan, net of stock and what is on the way.</>,
        <>When there is not enough, one allocation rule decides who is served — in the plan and in fulfillment alike.</>,
      ]} />

      <Section id="the-flow" title="The flow, end to end">
        <Key>The plan always starts from future finished-good demand — and it never reads demand that has not happened.</Key>
        <Flow
          caption="One rule from end to end. Actual demand is drawn around the plan only at fulfillment."
          items={[
            { kicker: "1", title: "Demand per row", detail: "forecast, or mean + variation" },
            { kicker: "2", title: "Planned production", detail: "min(requirement, capacity)" },
            { kicker: "3", title: "Material orders", detail: "MRP from the plan, or reorder point" },
            { kicker: "4", title: "Fulfillment", detail: "allocation rule, backorder per row" },
          ]}
        />
        <P>
          <strong>1 · Demand per customer row.</strong> Each customer × product row states its
          demand: a forecast series (uploaded as a <DocLink to="demand-forecasts">Demand Forecast</DocLink>)
          or a mean, a variation and a distribution. A row that states neither takes its product's
          demand split by volume. The plan uses the forecast or the mean; the run draws actual
          demand around it. See <DocLink to="customer-stage">Customer stage</DocLink>.
        </P>
        <P>
          <strong>2 · Planned production = min(requirement, capacity).</strong> For a make-to-order
          product the requirement is the projected demand plus any backlog; for make-to-stock it is
          what the finished-goods policy asks for — base-stock, min-max or days of cover — plus any
          backlog. The plan looks ahead as far as the longest material lead time planned by MRP. A
          product with a production lead time starts building that many weeks earlier, so it
          finishes when the demand it was planned for arrives.
          See <DocLink to="plant-stage">Plant stage</DocLink> and{" "}
          <DocLink to="products">Products</DocLink>.
        </P>
        <P>
          <strong>3 · Materials.</strong> A material on <Term>MRP</Term> is ordered from the plan:
          the BOM times planned production over its lead time, net of stock and what is on the way,
          rounded up to the MOQ. A material on a reorder-point type is ordered from consumption, as
          before. Both can sit in one project. See <DocLink to="policy-types">Policy types</DocLink>.
        </P>
        <P>
          <strong>4 · Fulfillment per row.</strong> When supply is short, the project's one
          allocation rule splits each product's units across its rows. Each row decides for itself
          whether what it does not get waits (backorder, within its window, at its cost) or is lost.
        </P>
      </Section>

      <Section id="worked-example" title="A worked example, week by week">
        <P>One make-to-order product, P1, with two customer rows that <strong>both allow backorder</strong>, and the allocation rule <Term>fair_share</Term>. Customer C1 forecasts 60, 60, 80, 160, 100, 100 a week; C2 has a mean of 40 a week. P1's capacity is 180 a week and each P1 uses 2 of material M1. M1 has a 2-week lead time and an MOQ of 250; 400 are on hand at the start and 200 more arrive at the start of week 2.</P>
        <DocTable
          caption="The plan. Week 4 asks for more than capacity; the 20 short are carried into week 5."
          head={["Week", "1", "2", "3", "4", "5", "6"]}
          rows={[
            ["Projected demand (C1 + C2)", "100", "100", "120", "200", "140", "140"],
            ["Planned production = min(req, 180)", "100", "100", "120", <strong>180</strong>, <strong>160</strong>, "140"],
            ["M1 need = 2 × planned production", "200", "200", "240", "360", "320", "280"],
          ]}
        />
        <DocTable
          caption="MRP for M1. Each order covers the next 2 weeks (the lead time) and is at least the MOQ."
          head={["Week", "On hand after production", "On the way", "Need, next 2 weeks", "Net", "Order", "Arrives"]}
          rows={[
            ["1", "200", "200", "440", "40", <strong>250</strong>, "week 3"],
            ["2", "200", "250", "600", "150", <strong>250</strong>, "week 4"],
            ["3", "210", "250", "680", "220", <strong>250</strong>, "week 5"],
          ]}
        />
        <Defs items={[
          { term: "The peak is planned for", def: "Week 4 wants 200 but the plant can build 180. The 20 short are split by fair share — 16 to C1 and 4 to C2 — and both carry into week 5, which plans 140 + 20 = 160." },
          { term: "Backorder changes the plan", def: "If C1 did not allow backorder, only C2's 4 would carry: week 5 would plan 144, and C1 would lose its 16 in week 4." },
          { term: "Orders follow the plan", def: "M1 is bought for the production the plan expects, not for last week's consumption, and an MOQ leftover is absorbed by the next week's netting." },
        ]} />
        <P>The engine reproduces both tables week by week in its own test suite, so they are what a run does, not an approximation of it.</P>
      </Section>

      <Section id="the-settings" title="What each setting means">
        <DocTable
          caption="Finished-goods policies for make-to-stock products. Every level is an end-of-week stock target."
          head={["Policy", "You set", "Builds", "Example"]}
          rows={[
            ["Base-stock", "S, in units", "S + this week's projected demand − opening stock, if positive", "S 300, demand 100, opening 250 → builds 150"],
            ["Min-max", "s and S, s below S", "Up to S, but only if opening stock − demand falls below s", "s 100, S 400, demand 100, opening 180 → 80 < 100, builds 320; opening 250 → builds nothing"],
            ["Days of cover", "D, in days", "As base-stock, with S = D/7 × the forecast — so the target moves with the forecast", "D 14, forecast 70 a week → target 140; forecast 140 → target 280"],
          ]}
        />
        <P>A typed S (or s and S, or D) <em>is</em> the target: the finished-goods safety buffer is never added on top of it. Make-to-order products don't use these controls.</P>
        <DocTable
          caption="Allocation rules — how short supply is shared between a product's customer rows."
          head={["Rule", "On /policies", "What it does"]}
          rows={AllocationRule.options.map((r) => [<Term>{r}</Term>, label(r), RULE_MEANING[r] ?? "—"])}
        />
        <P>Within a row, the oldest backlog is served first, then younger backlog, then this week's new demand. Ties go to the earlier row, so a result is repeatable. The rule only matters when two or more customers want the same product — with one customer, /policies shows no allocation line.</P>
        <Details title="How this works: the MRP order, as a formula">
          <p><Term>need(m, τ)</Term> = Σ over products of BOM(product, m) × planned production(product, τ).</p>
          <p><Term>order(m, t)</Term> = need over weeks t+1 … t+L + safety stock − on hand after this week's production − on the way; if positive, at least the MOQ. L is the primary supplier's lead time.</p>
          <p>The plan's horizon is automatic: the longest MRP lead time plus one week. Safety stock reuses the material's safety-stock days: days/7 × the average weekly need over the horizon. A supplier with finite capacity, or a disruption, delays delivery; the order still counts as on the way, and the run reports late receipts.</p>
        </Details>
      </Section>

      <Section id="one-rule" title="One rule for the plan and for fulfillment">
        <P>
          When the plan sees a week it cannot build in full, it splits the shortfall with the same
          allocation rule fulfillment uses, and carries forward only the share of rows that allow
          backorder. A lost-sales row's shortfall leaves the plan the week it leaves the order book,
          so the plant never builds — and MRP never buys — for an order a customer has already
          cancelled.
        </P>
      </Section>

      <Callout tone="note" title="What the plan cannot know">
        <p>
          The plan reads the forecast, not the future. A change that is in your forecast is planned
          for before it arrives; a change nobody forecast is met only by what is on hand and your
          safety stock. The validation study measures both, with the same demand and disruption on
          both sides: <Term>docs/research/mrp-vs-reorder-point.md</Term>.
        </p>
      </Callout>

      <Section id="where-to-set-it" title="Where each setting lives">
        <DocTable
          caption="Every planning setting is a cell on /policies; your uploads are the base each cell overrides."
          head={["Setting", "Where"]}
          rows={[
            ["Demand and fulfillment per customer row (forecast or mean, backorder, priority, price, service floor)", "Customer stage"],
            ["The allocation rule", "Customer stage, the Allocation line above the grid"],
            ["FG policy, levels and opening stock per product", "Plant stage"],
            ["The FG safety buffer", "Plant stage, the line above the grid"],
            ["MRP or a reorder-point type, per material", "Supplier stage, Policy type"],
          ]}
        />
        <P>All on <AppLink to="/policies">/policies</AppLink>.</P>
      </Section>

      <Section id="related" title="Related">
        <P>
          <DocLink to="how-policies-work">How policies work</DocLink> ·{" "}
          <DocLink to="customer-stage">Customer stage</DocLink> ·{" "}
          <DocLink to="plant-stage">Plant stage</DocLink> ·{" "}
          <DocLink to="policy-types">Policy types</DocLink> ·{" "}
          <DocLink to="demand-forecasts">Demand Forecast</DocLink>
        </P>
      </Section>

      <Provenance from="ADR 0002 and the design doc docs/design/mrp-multi-stage-planning.md" />
    </>
  );
}
