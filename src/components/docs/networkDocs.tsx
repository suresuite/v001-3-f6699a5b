// What the three network lenses share, documented once.
//
// The Firm-, Product- and Process-level pages render one graph card
// (`components/network/lens/GraphCard.tsx`) and one selection/focus/search
// model (`useLensGraph.ts`). Writing their controls into each of three pages
// would be three authors of one behaviour; each page renders this block and
// adds only the header buttons it alone has.

import type { ReactNode } from "react";
import { DocTable, Steps } from "@/components/docs/prose";

export function LensControls({ extra = [] }: { extra?: [ReactNode, ReactNode][] }) {
  return (
    <DocTable
      caption="The controls every network lens shares, plus this page's own."
      head={["Control", "What it does"]}
      rows={[
        ["Click a node", "Selects it: the details panel on the right fills in, and its edges are highlighted. Clicking empty canvas clears the selection."],
        ["Double-click a node", "Focuses it: everything outside its focus is removed from the canvas, not greyed. What the focus keeps differs by lens — this page says which, below. Double-click it again, or choose Show all in the details panel, to bring the rest back."],
        ["Search (magnifier)", "Opens “find a node”. Typing lists up to eight matching IDs from what is on screen; pick one to centre on it. An exact ID highlights straight away."],
        ["Drag a node · drag the canvas", "Moves a node (it stays where you put it) or pans the view. The wheel zooms."],
        ["Zoom in · Zoom out · Fit view", "The stack at the bottom left. 100% means “fits the canvas”, not 1:1; the wheel zoom is held between 0.3× and 4× of that."],
        ["Reset layout", "Puts every node you dragged back in its column, then fits."],
        ["Minimap", "Bottom right: where the visible area sits in the whole graph."],
        ["Resize handle", "Drag the bottom edge to make the canvas 360–1200px tall. The height is remembered."],
        ["Refresh", "Reloads the project's data and refits the graph."],
        ["Analytics", "Shows or hides the charts and tables under the graph."],
        ...extra,
      ]}
    />
  );
}

/**
 * "Add disruption event" — one dialog on all three lenses
 * (`components/network/NetworkDisruptionDialog.tsx`), checked by the same rule
 * as the Lab's editor and the run gate.
 */
export function AddDisruptionSteps() {
  return (
    <Steps steps={[
      { title: "Select the node, then Add disruption event", where: "graph header", body: <>The dialog names what you picked as the engine would: <strong>Supplier</strong>, <strong>Plant</strong>, or <strong>Cannot be disrupted</strong> with the reason. For a material, product or customer it offers the suppliers connected to it instead.</> },
      { title: "Choose what fails, how hard, when and for how long", where: "Add disruption event", body: <>The same fields, limits and words as the Simulation Lab's Recovery playbook. A problem is shown before anything is saved, not after a run.</> },
      { title: "Send it to a scenario", where: "New scenario · existing", body: <><strong>New scenario</strong> creates one from the validated baseline, so it can inherit the validation. Choosing an existing scenario adds the event to its schedule — refused if that would pass the event cap.</>, check: <>a confirmation naming the scenario and the event, with <strong>Open in Simulation Lab</strong>, which lands on its Recovery playbook.</> },
    ]} />
  );
}
