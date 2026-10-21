# Nexus Node Guide

A **nexus node** is a supplier or a purchased material whose outage, on its own, costs you the most sales. The **Nexus node prediction** panel on the network pages shows them for the selected project, ranked by **lost sales in €** under one shared disruption scenario.

Nothing runs when you open the panel. The stress test is prepared in advance and the panel reads the stored result.

## What is tested

- **Targets:** every supplier, and every material a supplier delivers. Sub-assemblies (made in-house), products, customers and the plant are not targets.
- **One at a time:** each target is disrupted alone. There are no compound events.
- **The outage:** a full stop. The target delivers nothing while it lasts, and goods already in transit arrive when it ends.
  - A **supplier** outage stops everything that supplier delivers.
  - A **material** outage stops every supplier's deliveries of that material, and nothing else they deliver.
- **When:** the outage starts in **week 26**, or in the first week after the warm-up if the warm-up ends later. Every target is hit in the same week.
- **How long:** each target is tested at **2, 3, 4, 5, 6, 7, 8 and 9 weeks**.
- **Your policies apply:** safety stock, reorder rules, backup suppliers, multi-sourcing, allocation and unmet-demand handling all run as configured. The losses are what remains after your own mitigations.

## How lost sales are measured

For each target and duration, the simulation runs twice on the same random draws: once with the outage, once without. The figure is the **extra** lost sales the outage causes, in €, over the measured window, averaged over the replications.

The **Average** column is the mean of the eight durations. The table opens ranked by it, and you can sort by any duration instead. A target that is harmless at 2 weeks and costly at 9 weeks shows that pattern across its row.

A target that loses nothing says why:

- **Covered** — stock or a policy, such as a backup supplier, absorbed the outage.
- **Backordered** — customers waited instead of being lost, so a backlog built up. €0 lost sales does not mean nothing happened.

## The baseline

Every result is tied to the run it came from. The panel states it before showing a figure:

- the **Validated Model** — the stress test only runs on a validated baseline;
- the **data version** and the **policy version** it used;
- the **engine build** that computed it;
- the scenario, the number of replications, and when it was prepared.

If your project's data changed after the stress test was prepared, the panel says so and still shows the prepared result. It never recomputes on view.

## The first-order estimate

The earlier score, **demand at risk**, is still computed by the network analysis. It is the share of finished-goods demand lost if a node alone fails, with no rerouting, no stock and no recovery. It answers a different, static question and is no longer the panel's ranking.
