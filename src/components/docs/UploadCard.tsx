// The summary card an input-table reference page opens with (WP 5.2a redesign).
//
// Left: how to get the file in. Right: what the database will make of it.
// Every value on the right is read from the contract through `tableFacts` —
// the table name, its grain, its row key, the role that may write it and
// whether that key is enforced — and the template is the wizard's own file.
// The card adds no fact a body could contradict; it moves the generated ones
// to the top of the page, where "how do I upload my BOM?" is asked.

import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { Download } from "lucide-react";
import { cn } from "@/lib/utils";
import { TEMPLATE_BTN } from "@/components/admin/adminUi";
import { Prose } from "@/components/docs/prose";
import { refTable, rowKey, uploadAssetFor } from "@/components/docs/tableFacts";

export function UploadCard({ table: name }: { table: string }) {
  const t = refTable(name);
  const asset = uploadAssetFor(t);
  if (!asset) return null;
  const { key, enforced } = rowKey(t);
  const reviewed = Boolean(t.ingestDataset);
  const serverSet = t.ingestDataset?.serverSet ?? [];

  const steps = [
    <>
      Open{" "}
      <Link to="/project-manager" className="docs-link">Project Manager</Link>{" "}
      {"›"} <strong className="font-semibold">Upload Data</strong> and select your project.
    </>,
    <>
      Pick the <strong className="font-semibold">{asset.name}</strong> tab.
    </>,
    reviewed ? (
      <>
        Review the rows, then choose <strong className="font-semibold">Promote N rows</strong> to
        accept them.
      </>
    ) : (
      <>The rows are written straight away — this file has no review step. Export a copy first.</>
    ),
  ];

  const facts: [string, ReactNode][] = [
    ["Database table", <span className="font-mono text-[12.5px]">{t.table}</span>],
    ["One row is", <Prose text={t.grain} />],
    [
      "Identified by",
      key.length ? (
        <>
          <span className="font-mono text-[12.5px]">{key.filter((k) => !serverSet.includes(k)).join(" + ")}</span>
          {key.some((k) => serverSet.includes(k)) && (
            <span className="text-gray-600">
              , within <span className="font-mono text-[12px]">{key.filter((k) => serverSet.includes(k)).join(", ")}</span>{" "}
              (set by the server)
            </span>
          )}
        </>
      ) : (
        "No row key declared"
      ),
    ],
    [
      "Who may write",
      t.governance?.minProjectRole ? `Project role ${t.governance.minProjectRole} or above` : "Not declared",
    ],
    [
      "Uploading again",
      !reviewed
        ? "Uses a separate upload path; check this page before replacing data"
        : enforced
          ? "Updates rows with matching IDs and adds new ones"
          : "Adds the rows again — the database does not enforce the key yet",
    ],
  ];

  return (
    <section
      aria-label="Upload this file"
      className="grid grid-cols-1 overflow-hidden rounded-lg border border-border md:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]"
    >
      <div className="space-y-3.5 p-4 md:p-5">
        <div className="text-[14px] font-semibold text-foreground">Upload this file</div>
        <ol className="space-y-2">
          {steps.map((s, i) => (
            <li key={i} className="grid grid-cols-[18px_minmax(0,1fr)] gap-2 text-[13.5px] leading-[1.55] text-foreground">
              <span className="font-mono text-[12px] font-semibold tabular-nums text-gray-600">{i + 1}</span>
              <span>{s}</span>
            </li>
          ))}
        </ol>
        {asset.templateFile ? (
          <a
            href={asset.templateFile}
            download
            className={cn(
              "inline-flex h-11 items-center gap-2 rounded-md px-3.5 text-[13px] font-medium text-[#171717] md:h-9",
              TEMPLATE_BTN,
            )}
          >
            <Download className="h-4 w-4" aria-hidden />
            Download template
          </a>
        ) : (
          <p className="text-[13px] text-gray-600">
            No template: start from an export of your project's own rows.
          </p>
        )}
      </div>
      <dl className="divide-y divide-border border-t border-border bg-muted/50 md:border-l md:border-t-0">
        {facts.map(([k, v]) => (
          <div key={k} className="px-4 py-2.5">
            <dt className="docs-kicker">{k}</dt>
            <dd className="mt-0.5 text-[13px] leading-[1.5] text-foreground">{v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}
