import { Input } from "@/components/ui/input";
import { formatDateForDatabase, parseDateFromDatabase } from "@/utils/dateHelpers";
import { endForWeeks, projectWindow } from "@/lib/sim/projectWindow";
import { HORIZON_WEEKS } from "@/lib/sim/planningTime";
import { formatIsoWeek, isoWeekOf } from "@/lib/sim/calendarWeeks";

/**
 * The project's run length, under its start and end dates (PLAN.md §4 D318).
 *
 * The window is the one authored length of a run: a new scenario takes it, and
 * every week field is bounded by it. So it is stated in weeks — the engine's
 * unit — with the engine's own bounds, and it can be SET in weeks: typing a
 * length moves the end date. A run longer than 100 weeks is a deliberate
 * setting here, not a default hidden in a worker.
 */
export function ProjectWindowLength({
  start,
  end,
  onEndChange,
  idPrefix,
}: {
  start: Date | undefined;
  end: Date | undefined;
  onEndChange: (end: Date | undefined) => void;
  idPrefix: string;
}) {
  const s = formatDateForDatabase(start);
  const e = formatDateForDatabase(end);
  const w = projectWindow(s, e);
  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex flex-wrap items-center gap-2">
        <label htmlFor={`${idPrefix}-weeks`} className="text-xs">
          Run length
        </label>
        <Input
          id={`${idPrefix}-weeks`}
          type="number"
          inputMode="numeric"
          className="h-11 w-24 md:h-8"
          min={HORIZON_WEEKS.min}
          max={HORIZON_WEEKS.max}
          disabled={!s}
          value={w ? w.weeks : ""}
          onChange={(ev) => {
            const n = Math.round(Number(ev.target.value));
            if (s && Number.isFinite(n) && n > 0) onEndChange(parseDateFromDatabase(endForWeeks(s, n)));
          }}
        />
        <span className="text-xs text-muted-foreground">
          weeks{w && s ? ` · week 0 is ${formatIsoWeek(isoWeekOf(s))}` : ""} · the engine runs {HORIZON_WEEKS.min}–
          {HORIZON_WEEKS.max} weeks
        </span>
      </div>
      {w?.boundReason ? <p className="text-xs text-destructive">{w.boundReason}</p> : null}
      {!s ? <p className="text-xs text-muted-foreground">Pick a start date to set the length in weeks.</p> : null}
    </div>
  );
}

