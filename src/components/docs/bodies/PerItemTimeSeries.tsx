// §6.3 section 11 — per-item time series. Deepened in WP 5.2j; the inventory
// explorer (G17 / §9.5.1: ranked tables, multi-select charts, the workbook, and
// per-product finished-goods stock from the engine) added in place.
//
// ── WHAT THE PAGE OMITTED, AND WHAT IT GOT WRONG ──────────────────────────
//
// The explorer draws eight named measures and the page named none of them —
// `run_item_series` was deferred in the contract, so there was no generated fact
// to render, which is exactly the correlation WP 5.2i's gap check predicted. WP
// 10.4 describes the table; the measure vocabulary stays the engine's.
// They are declared in two places and `deriveItemSeries` joins them: the engine
// says which item kind each belongs to, the explorer's legend says what the
// reader sees.
//
// It also said series are "kept per replication … so a week that looks
// catastrophic can be checked against the other seeds". That is not true and it
// is the kind of untrue that costs a reader an afternoon: the engine writes item
// series ONLY when the run has exactly one replication, so there are no other
// seeds to check against. Corrected here, and the correction is the reason the
// page now says where the toggle is — a claim about a feature nobody had opened.

import { PageTitle, Section, P, Key, Callout, Steps, Term, DocLink, AppLink, Provenance } from "@/components/docs/prose";
import { DocFigure } from "@/components/docs/DocFigure";
import { UNDESCRIBED } from "@/components/docs/generated/dataModel.generated";
import { ITEM_SERIES } from "@/components/docs/generated/policy.generated";

export default function PerItemTimeSeries() {
  const owing = UNDESCRIBED.find((g) => g.tables.some((t) => t.table === "run_item_series"));
  const materials = ITEM_SERIES.filter((s) => s.kind === "material");
  const products = ITEM_SERIES.filter((s) => s.kind === "product");

  return (
    <>
      <PageTitle lead="Every material's and every finished good's stock, week by week, ranked by risk and downloadable to Excel — and the switch you have to throw before the run to get it.">
        Per-item time series
      </PageTitle>

      <Callout tone="limit" title="You have to ask for this before the run, and only a single-replication run can give it">
        <p>
          Per-item series are <strong>off by default</strong> and cannot be produced afterwards. A
          run that did not keep them has to be run again to get them — which costs time and nothing
          else, because the same seed reproduces the same world exactly.
        </p>
        <p>
          The switch is <strong>Inspection mode</strong>, on{" "}
          <AppLink to="/policies">Policies</AppLink> → Run &amp; validate → the{" "}
          <strong>Single</strong> tab. It is not in Simulation Lab, and it is not on the multi-run
          tab, because <strong>the engine only writes item series for a run with exactly one
          replication</strong>. Ask for it on a run with more and the request is dropped with a
          warning rather than honoured. Simulation Lab shows the explorer for such a run and,
          for any other, links to where one is started: a Lab scenario carries its own
          replication count, so the Lab cannot start one without writing a scenario.
        </p>
      </Callout>

      <Section id="why" title="Why the weekly view is usually the finding">
        <Key>
          An average tells you the level. A series tells you the shape, and the shape is what a
          decision is made about.
        </Key>
        <P>
          A 94% fill rate can be 94% every week, or perfect for forty weeks and 40% for ten. The
          first is a chain running slightly short; the second is a chain that failed and recovered.
          They need different responses and the aggregate cannot distinguish them.
        </P>
        <DocFigure id="series-vs-mean" />
      </Section>

      <Section id="the-measures" title={`The ${ITEM_SERIES.length} measures, and what each one is a count of`}>
        <P>
          Every value is <strong>one week's worth</strong>, in the item's own units — pieces,
          kilograms, whatever the quantities in your files are in. Nothing here is a rate or a
          percentage, so a number is directly comparable with the volumes you uploaded.
        </P>
        <P>
          A material and a product carry different measures, because they are different halves of
          the chain: a material is something you hold and replenish, a product is something you
          promise and deliver.
        </P>

        <div className="space-y-4">
          <div>
            <h4 className="mb-2 text-[12px] font-semibold uppercase tracking-wider text-muted-foreground">
              A material — {materials.length} lines
            </h4>
            <div className="divide-y divide-border rounded-sm border border-border bg-card shadow-xs">
              {materials.map((s) => (
                <div key={s.key} className="p-3">
                  <div className="flex flex-wrap items-baseline gap-2">
                    <span className="text-[13px] font-semibold text-foreground">{s.label}</span>
                    <span className="font-mono text-[11px] text-muted-foreground">{s.key}</span>
                  </div>
                  <p className="mt-1 text-[13px] leading-relaxed text-muted-foreground">
                    {s.key === "on_hand" &&
                      "How much you were holding at the end of that week. The line that hits zero is the stockout, and it is the last event rather than the first."}
                    {s.key === "in_transit" &&
                      "How much was ordered and not yet arrived. Read beside on hand: inventory falling while this stays flat means replenishment stopped, and inventory falling while this rises means it did not stop, it is just too slow."}
                    {s.key === "orders" &&
                      "How much you ordered that week. This is the policy speaking — it is the only one of the three that is a decision rather than a consequence, so it is where a policy change shows up first."}
                  </p>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h4 className="mb-2 text-[12px] font-semibold uppercase tracking-wider text-muted-foreground">
              A product — {products.length} lines
            </h4>
            <div className="divide-y divide-border rounded-sm border border-border bg-card shadow-xs">
              {products.map((s) => (
                <div key={s.key} className="p-3">
                  <div className="flex flex-wrap items-baseline gap-2">
                    <span className="text-[13px] font-semibold text-foreground">{s.label}</span>
                    <span className="font-mono text-[11px] text-muted-foreground">{s.key}</span>
                  </div>
                  <p className="mt-1 text-[13px] leading-relaxed text-muted-foreground">
                    {s.key === "demand" &&
                      "How much was asked for that week. This is the draw the rest of the chain is answering, and on a stochastic demand model it is different on every seed."}
                    {s.key === "production" &&
                      "How much you made. Below demand and flat is a capacity ceiling; below demand and ragged is a material you could not get."}
                    {s.key === "fulfillment" &&
                      "How much you actually delivered. The gap between this and demand is the whole of the service story, and every service KPI is a summary of it."}
                    {s.key === "backlog" &&
                      "What was owed and not yet delivered, carried forward. A backlog that grows week on week is a chain that is not catching up — the level matters less than whether the line is climbing."}
                    {s.key === "fg_on_hand" &&
                      "Finished goods you were holding at the end of that week, after the week's completions — the engine's own stock, summed across products it is the finished-goods inventory on the run's inventory chart. A make-to-order product holds none by design and reads 0."}
                    {s.key === "fg_target" &&
                      "The finished-goods stock the plan aimed for next week (S): a base-stock or min–max S you typed, days of cover times projected demand, or this week's forecast, plus any FG safety stock. 0 for a make-to-order product."}
                    {s.key === "make_to_stock" &&
                      "Not a count: 1 when the engine ran this product make-to-stock, 0 when make-to-order, the same every week. It is the mode the engine resolved — the Plant row, else the product, else the project — so the explorer shows it rather than re-deciding it."}
                    {s.key === "projected_demand" &&
                      "The demand the plan projected for that week, before the week's draw — the plan never reads the realized future."}
                    {s.key === "requirement" &&
                      "What the plan required production to cover that week: projected demand, the finished-goods gap and the backlog."}
                    {s.key === "planned" &&
                      "The production the plan asked the line for that week. Production is what was actually started."}
                    {s.key.startsWith("mrp_") &&
                      "The MRP record for a material planned by MRP: need over the lead time, stock after production, what is on the way, and the net. Present only for a run with MRP materials."}
                    {s.key === "lost_units" && (
                      <>
                        Demand that went away rather than waiting. Read it first: a backlog is a
                        delay, this is a sale you did not make. <strong>Which of the two an unmet
                        order becomes is a policy, not a consequence</strong> — it is set by{" "}
                        <Term>unmet_demand_handling</Term>, whose default is lost sales, so a
                        project nobody has configured produces this line and an empty backlog.
                        Under a backorder rule the same shortfall appears in Backlog instead, and
                        moves here only once it has waited longer than the backorder horizon.
                      </>
                    )}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </Section>

      <Section id="the-tables" title="The two tables, and how they are ranked">
        <P>
          The explorer opens on <strong>Materials</strong>; the switch beside it shows{" "}
          <strong>Finished goods</strong>. Each table has every item of the run, riskiest first, and
          leaves out the weeks before the warm-up ends.
        </P>
        <P>
          <strong>Materials</strong>: suppliers, average and minimum on hand, weeks at zero, the
          first week it ran out, average in transit, average use per week, minimum cover in weeks
          (minimum on hand over average use) and the total ordered. Ranked by weeks at zero, then by
          the thinnest cover — the order notebook 04 uses.
        </P>
        <P>
          <strong>Finished goods</strong>: fulfillment mode, average and minimum finished-goods
          stock, average target, weeks with no stock while demand was waiting, the first such week,
          weeks of cover, fill rate (everything delivered over everything demanded, so backlog
          served late counts), average backlog and lost units. Ranked by the largest shortfall —
          lost units plus average backlog — then by weeks out of stock, then by the lowest fill
          rate. That puts make-to-stock and make-to-order products on one scale.
        </P>
        <Callout tone="limit" title="What the tables cannot say">
          <p>
            <strong>Use is derived, not measured.</strong> It is each product&apos;s production
            (units started) times its bill of materials, flattened through sub-assemblies. The
            engine consumes materials at production start, so it is the consumption it booked —
            but it is computed for this view, and so is minimum cover.
          </p>
          <p>
            <strong>A sub-assembly has no row.</strong> The engine holds stock per leaf material
            and per finished good; an intermediate component is flattened into the materials
            beneath it.
          </p>
          <p>
            <strong>A make-to-order product says &ldquo;not stocked&rdquo;, never 0.</strong> It
            holds no finished-goods stock by design; its service is its backlog and its lost units.
          </p>
          <p>
            <strong>A run recorded before finished-goods stock was kept per product</strong> shows
            the products table without its stock columns and says so: run a new inspection.
          </p>
        </Callout>
      </Section>

      <Section id="the-explorer" title="Using the explorer">
        <Steps
          steps={[
            {
              title: "Run with Inspection mode on",
              where: "/policies → Run & validate → Single",
              body: (
                <>
                  Set the seed you want — the series you get are that seed's world, and writing the
                  number down is how you come back to the same one. The panel appears under the run
                  once it finishes.
                </>
              ),
            },
            {
              title: "Choose materials or finished goods",
              body: (
                <>
                  Two buttons, and two different tables. The header tells you how many of each this
                  run has. The search box filters by id or name.
                </>
              ),
            },
            {
              title: "Tick the items you want to see",
              body: (
                <>
                  Each ticked row draws its own chart below the table, in the order you ticked them,
                  up to twelve at once. A material shows on hand and in transit with a marker on
                  every week it ran out, and below it orders placed as bars with use as a line (and
                  the MRP record, when it has one). A finished good shows its stock against its
                  target with stockout markers, and below it demand, production and fulfillment
                  with the backlog as an area, plus the plan&apos;s projected demand and planned
                  production.
                </>
              ),
            },
            {
              title: "Download Excel",
              body: (
                <>
                  For the selected items, or for all of them. The workbook opens with the run&apos;s
                  reproducibility <strong>record</strong> — the dataset, policy, scenario, seed and
                  engine that produced these numbers, and their limits — then the{" "}
                  <strong>materials</strong> and <strong>products</strong> tables, one weekly sheet
                  per selected item, and a long <strong>weekly</strong> sheet (week, kind, item,
                  measure, value) for every item in the download. It needs the Export right on the
                  project.
                </>
              ),
            },
            {
              title: "Read the chart against the warm-up line",
              body: (
                <>
                  The dashed vertical line is the end of warm-up. Everything left of it is the model
                  filling its pipes from an empty start and is <strong>not</strong> evidence about
                  your chain. A dramatic first ten weeks is almost always this.
                </>
              ),
            },
          ]}
        />
      </Section>

      <Section id="reading-one" title="Reading one">
        <P>
          Start at the week the aggregate went wrong and read backwards. A stockout is the last
          event in a sequence — on-hand falling, in-transit not arriving, demand unchanged — and the
          useful question is which of those moved first.
        </P>
        <P>
          A material&apos;s two charts share their weeks on purpose. If on-hand is falling while
          orders placed are flat, the policy is not reacting; if orders are rising and in-transit is
          not, the supply is not answering. Those are different problems with different fixes, and
          the charts distinguish them at a glance in a way the KPIs never can. A material the
          disruption did not touch, used less: production stopped for want of another one.
        </P>
      </Section>

      <Callout tone="limit" title="One seed, one world — there is nothing here to average">
        <p>
          An inspection run is <strong>one replication</strong>. The chart is one possible world,
          not the expected one, and a spike in it may be that seed rather than your chain. You
          cannot check it against the other seeds on this screen, because this run has none.
        </p>
        <p>
          The way to tell them apart is to change the seed and run inspection again. If the spike
          moves, it was the seed; if it stays in the same week, it is structural.{" "}
          <DocLink to="seeds-replications-confidence">Seeds, replications &amp; confidence</DocLink>{" "}
          is why one run is never the answer on its own.
        </p>
      </Callout>

      <Callout title="An inspection run that could not store its series fails rather than reporting green">
        <p>
          The series are the entire point of asking for one, so a run whose item rows fail to
          persist is marked <strong>failed</strong> — not completed with the panel quietly absent.
          If you asked for inspection and the run says done, the evidence is there.
        </p>
      </Callout>

      {owing && (
        <Callout tone="limit" title="This table is not yet described in the contract">
          <p>
            <Term>run_item_series</Term> has no per-column description and is deferred to WP{" "}
            {owing.wp}. The measures above are read from the engine that writes them and the legend
            that names them, joined — which is a weaker source than a sidecar, and it is what
            exists. There is no column reference to link you to, and this page will not write one by
            hand.
          </p>
        </Callout>
      )}

      <Section id="related" title="Related">
        <P>
          <DocLink to="reading-your-results">Reading your results</DocLink> is the layer above this
          one · <DocLink to="kpis-and-resilience-index">KPIs &amp; the Resilience Index</DocLink> is
          what these series are summarised into ·{" "}
          <DocLink to="seeds-replications-confidence">Seeds, replications &amp; confidence</DocLink>{" "}
          is why one seed is not an answer ·{" "}
          <DocLink to="verifiable-exports">Verifiable exports</DocLink> ships the series as a
          weeks-by-seeds sheet ·{" "}
          <DocLink to="model-validation">Model validation</DocLink> is how the warm-up line got
          where it is.
        </P>
      </Section>

      <Provenance from="scsim/scsim/core/engine.py's item_series dict for which measures each item kind carries, joined to ItemSeriesExplorer's own legend for the names — the table itself is described by the contract since WP 10.4, which deliberately does not restate this vocabulary" />
    </>
  );
}
