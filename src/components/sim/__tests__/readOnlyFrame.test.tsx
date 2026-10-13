/**
 * The Lab's settings lock must carry its own way out. While a Validated Model is
 * chosen, replications and warm-up are locked to its protocol; the only unlock
 * used to be a small "Advanced" link on the model card, and the lock banner on
 * the Setup pane linked to /policies — a page that cannot unlock them.
 * Rendered to static markup (vitest runs in node).
 */
import { describe, expect, it } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { ReadOnlyFrame } from "../ReadOnlyFrame";

const render = (props: Parameters<typeof ReadOnlyFrame>[0]) =>
  renderToStaticMarkup(createElement(MemoryRouter, null, createElement(ReadOnlyFrame, props)));

describe("ReadOnlyFrame", () => {
  it("renders the editor untouched when there is no lock", () => {
    const html = render({ reason: null, action: { label: "Unlock settings", onClick: () => {} }, children: "form" });
    expect(html).toBe("form");
  });

  it("offers the model lock's unlock in place, without sending the reader to /policies", () => {
    const html = render({
      reason: "Replications, warm-up and the run window follow the Validated Model's protocol.",
      action: { label: "Unlock settings", onClick: () => {} },
      validateLink: false,
      children: "form",
    });
    expect(html).toContain('data-testid="read-only-action"');
    expect(html).toContain("Unlock settings");
    expect(html).not.toContain('href="/policies"');
    expect(html).toContain("<fieldset disabled");
  });

  it("keeps the Run & Validate link for the baseline, beside its action", () => {
    const html = render({
      reason: "The validated baseline is set and run in Policies › Run & Validate.",
      action: { label: "New scenario from it", onClick: () => {} },
      children: "form",
    });
    expect(html).toContain("New scenario from it");
    expect(html).toContain('href="/policies"');
  });

  it("defaults to the link alone, as before", () => {
    const html = render({ reason: "read-only", children: "form" });
    expect(html).not.toContain("read-only-action");
    expect(html).toContain('href="/policies"');
  });
});
