"use client";

import { useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { ListChecks, Loader2, Plus, Sparkles, X } from "lucide-react";
import { toast } from "sonner";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { ApiError, PARSER_URL, parseAgenda, saveAgenda } from "@/lib/api";
import type {
  ActionItem,
  Agenda,
  AgendaItem,
  Meeting,
  ParseResult,
} from "@/lib/types";

const MAX_CHARS = 10_000;

type Mode = "view" | "paste" | "edit";

/** Message for every way a parse can fail; the user can always type the agenda instead. */
function parseErrorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    if (error.status === 413)
      return "The text is too long (10,000 characters at most).";
    if (error.status === 422)
      return "Could not find an agenda in this text. Type it in below.";
    if (error.status === 429 || error.status === 503)
      return "The AI service is busy. Try again in a minute, or type the agenda in.";
    if (error.status === 401) return "Your session has expired. Sign in again.";
    if (error.status === 0)
      return "Network error: the parser could not be reached.";
    return error.message;
  }
  return "Something went wrong while parsing.";
}

const emptyItem = (): AgendaItem => ({ topic: "", owner: null, minutes: null });
const emptyAction = (): ActionItem => ({ task: "", owner: null, due: null });

/** Keys of every field the model filled, e.g. "items.0.owner". */
function suggestedKeys(agenda: Agenda): Set<string> {
  const keys = new Set<string>();
  agenda.items.forEach((item, i) =>
    (Object.keys(item) as (keyof AgendaItem)[]).forEach((field) => {
      if (item[field] !== null && item[field] !== "")
        keys.add(`items.${i}.${field}`);
    }),
  );
  agenda.action_items.forEach((item, i) =>
    (Object.keys(item) as (keyof ActionItem)[]).forEach((field) => {
      if (item[field] !== null && item[field] !== "")
        keys.add(`action_items.${i}.${field}`);
    }),
  );
  return keys;
}

function Suggested({ show }: { show: boolean }) {
  return show ? (
    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">
      <Sparkles aria-hidden />
      suggested
    </Badge>
  ) : null;
}

export function AgendaSection({ meeting }: { meeting: Meeting }) {
  const queryClient = useQueryClient();
  const [mode, setMode] = useState<Mode>("view");
  const [text, setText] = useState("");
  const [parsing, setParsing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState<Agenda>({ items: [], action_items: [] });
  const [suggested, setSuggested] = useState<Set<string>>(new Set());
  const [suggestion, setSuggestion] = useState<ParseResult | null>(null);
  const [saving, setSaving] = useState(false);
  const abortRef = useRef<AbortController | null>(null);

  const touch = (key: string) =>
    setSuggested((prev) => {
      if (!prev.has(key)) return prev;
      const next = new Set(prev);
      next.delete(key);
      return next;
    });

  const setItem = (i: number, patch: Partial<AgendaItem>) => {
    Object.keys(patch).forEach((field) => touch(`items.${i}.${field}`));
    setDraft((d) => ({
      ...d,
      items: d.items.map((it, j) => (j === i ? { ...it, ...patch } : it)),
    }));
  };
  const setAction = (i: number, patch: Partial<ActionItem>) => {
    Object.keys(patch).forEach((field) => touch(`action_items.${i}.${field}`));
    setDraft((d) => ({
      ...d,
      action_items: d.action_items.map((it, j) =>
        j === i ? { ...it, ...patch } : it,
      ),
    }));
  };

  const startManual = () => {
    setDraft(meeting.agenda ?? { items: [emptyItem()], action_items: [] });
    setSuggested(new Set());
    setSuggestion(null);
    setError(null);
    setMode("edit");
  };

  const onParse = async () => {
    const controller = new AbortController();
    abortRef.current = controller;
    setParsing(true);
    setError(null);
    try {
      const result = await parseAgenda(text, controller.signal);
      if (
        result.agenda.items.length === 0 &&
        result.agenda.action_items.length === 0
      ) {
        setError("Could not find an agenda in this text. Type it in below.");
        return;
      }
      setDraft({
        items: result.agenda.items,
        action_items: result.agenda.action_items,
      });
      setSuggested(suggestedKeys(result.agenda));
      setSuggestion(result);
      setMode("edit");
    } catch (caught) {
      if (!controller.signal.aborted) setError(parseErrorMessage(caught));
    } finally {
      setParsing(false);
      abortRef.current = null;
    }
  };

  const onSave = async () => {
    const clean: Agenda = {
      items: draft.items
        .filter((it) => it.topic.trim())
        .map((it) => ({ ...it, owner: it.owner?.trim() || null })),
      action_items: draft.action_items
        .filter((it) => it.task.trim())
        .map((it) => ({
          ...it,
          owner: it.owner?.trim() || null,
          due: it.due || null,
        })),
    };
    setSaving(true);
    try {
      // The normal API, with its validation, writes. The suggestion travels
      // along so the API can keep it next to what the user saved.
      await saveAgenda(meeting.id, {
        ...clean,
        ai_suggestion: suggestion?.agenda ?? null,
        ai_model: suggestion?.model ?? null,
        prompt_version: suggestion?.prompt_version ?? null,
      });
      await queryClient.invalidateQueries({ queryKey: ["meetings"] });
      toast.success("Agenda saved");
      setMode("view");
      setText("");
    } catch (caught) {
      toast.error(
        caught instanceof Error ? caught.message : "Could not save the agenda.",
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <section className="space-y-3">
      <h3 className="flex items-center gap-2 text-sm font-semibold">
        <ListChecks className="size-4" aria-hidden />
        Agenda
      </h3>

      {mode === "view" ? (
        <>
          {meeting.agenda &&
          meeting.agenda.items.length + meeting.agenda.action_items.length >
            0 ? (
            <div className="space-y-2 text-sm">
              <ol className="list-decimal space-y-1 pl-5">
                {meeting.agenda.items.map((item, i) => (
                  <li key={i}>
                    {item.topic}
                    {item.owner ? (
                      <span className="text-muted-foreground">
                        {" "}
                        — {item.owner}
                      </span>
                    ) : null}
                    {item.minutes ? (
                      <span className="text-muted-foreground">
                        {" "}
                        · {item.minutes} min
                      </span>
                    ) : null}
                  </li>
                ))}
              </ol>
              {meeting.agenda.action_items.length > 0 ? (
                <ul className="text-muted-foreground list-disc space-y-1 pl-5">
                  {meeting.agenda.action_items.map((a, i) => (
                    <li key={i}>
                      {a.task}
                      {a.owner ? ` — ${a.owner}` : ""}
                      {a.due ? ` (by ${a.due})` : ""}
                    </li>
                  ))}
                </ul>
              ) : null}
            </div>
          ) : (
            <p className="text-muted-foreground text-sm">No agenda yet.</p>
          )}
          <div className="flex flex-wrap gap-2">
            {PARSER_URL ? (
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setMode("paste")}
              >
                <Sparkles aria-hidden />
                Paste an agenda
              </Button>
            ) : null}
            <Button variant="outline" size="sm" onClick={startManual}>
              {meeting.agenda ? "Edit agenda" : "Add agenda"}
            </Button>
          </div>
        </>
      ) : null}

      {mode === "paste" ? (
        <div className="space-y-2">
          <Textarea
            value={text}
            onChange={(e) => setText(e.target.value)}
            placeholder="Paste an email, a chat message or notes with the agenda…"
            rows={5}
            disabled={parsing}
            aria-label="Pasted agenda text"
          />
          <p className="text-muted-foreground text-xs tabular-nums">
            {text.length.toLocaleString()} / {MAX_CHARS.toLocaleString()}{" "}
            characters
          </p>
          {parsing ? (
            <p className="flex items-center gap-2 text-sm" role="status">
              <Loader2 className="size-4 animate-spin" aria-hidden />
              Reading your text… this takes a few seconds.
            </p>
          ) : null}
          {error ? <p className="text-destructive text-sm">{error}</p> : null}
          <div className="flex flex-wrap gap-2">
            {parsing ? (
              <Button
                variant="outline"
                size="sm"
                onClick={() => abortRef.current?.abort()}
              >
                Cancel
              </Button>
            ) : (
              <>
                <Button
                  size="sm"
                  onClick={onParse}
                  disabled={!text.trim() || text.length > MAX_CHARS}
                >
                  <Sparkles aria-hidden />
                  Parse
                </Button>
                <Button variant="outline" size="sm" onClick={startManual}>
                  Type it in instead
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setMode("view")}
                >
                  Close
                </Button>
              </>
            )}
          </div>
        </div>
      ) : null}

      {mode === "edit" ? (
        <div className="space-y-3">
          {suggestion ? (
            <p className="text-muted-foreground text-xs">
              Suggested by {suggestion.model} ({suggestion.prompt_version}).
              Check every field before saving.
            </p>
          ) : null}

          <div className="space-y-2">
            {draft.items.map((item, i) => (
              <div
                key={i}
                className="grid grid-cols-[1fr_auto] gap-2 rounded-xl border p-2"
              >
                <div className="grid gap-1.5">
                  <label className="flex items-center gap-1.5 text-xs font-medium">
                    Topic <Suggested show={suggested.has(`items.${i}.topic`)} />
                  </label>
                  <Input
                    value={item.topic}
                    onChange={(e) => setItem(i, { topic: e.target.value })}
                  />
                  <div className="grid grid-cols-2 gap-2">
                    <label className="grid gap-1 text-xs font-medium">
                      <span className="flex items-center gap-1.5">
                        Owner{" "}
                        <Suggested show={suggested.has(`items.${i}.owner`)} />
                      </span>
                      <Input
                        value={item.owner ?? ""}
                        onChange={(e) =>
                          setItem(i, { owner: e.target.value || null })
                        }
                      />
                    </label>
                    <label className="grid gap-1 text-xs font-medium">
                      <span className="flex items-center gap-1.5">
                        Minutes{" "}
                        <Suggested show={suggested.has(`items.${i}.minutes`)} />
                      </span>
                      <Input
                        type="number"
                        min={1}
                        max={480}
                        value={item.minutes ?? ""}
                        onChange={(e) =>
                          setItem(i, {
                            minutes: e.target.value
                              ? Number(e.target.value)
                              : null,
                          })
                        }
                      />
                    </label>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Remove item"
                  onClick={() =>
                    setDraft((d) => ({
                      ...d,
                      items: d.items.filter((_, j) => j !== i),
                    }))
                  }
                >
                  <X aria-hidden />
                </Button>
              </div>
            ))}
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                setDraft((d) => ({ ...d, items: [...d.items, emptyItem()] }))
              }
            >
              <Plus aria-hidden />
              Add item
            </Button>
          </div>

          <div className="space-y-2">
            <p className="text-xs font-semibold">Action items</p>
            {draft.action_items.map((item, i) => (
              <div
                key={i}
                className="grid grid-cols-[1fr_auto] gap-2 rounded-xl border p-2"
              >
                <div className="grid gap-1.5">
                  <label className="flex items-center gap-1.5 text-xs font-medium">
                    Task{" "}
                    <Suggested show={suggested.has(`action_items.${i}.task`)} />
                  </label>
                  <Input
                    value={item.task}
                    onChange={(e) => setAction(i, { task: e.target.value })}
                  />
                  <div className="grid grid-cols-2 gap-2">
                    <label className="grid gap-1 text-xs font-medium">
                      <span className="flex items-center gap-1.5">
                        Owner{" "}
                        <Suggested
                          show={suggested.has(`action_items.${i}.owner`)}
                        />
                      </span>
                      <Input
                        value={item.owner ?? ""}
                        onChange={(e) =>
                          setAction(i, { owner: e.target.value || null })
                        }
                      />
                    </label>
                    <label className="grid gap-1 text-xs font-medium">
                      <span className="flex items-center gap-1.5">
                        Due{" "}
                        <Suggested
                          show={suggested.has(`action_items.${i}.due`)}
                        />
                      </span>
                      <Input
                        type="date"
                        value={item.due ?? ""}
                        onChange={(e) =>
                          setAction(i, { due: e.target.value || null })
                        }
                      />
                    </label>
                  </div>
                </div>
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Remove action item"
                  onClick={() =>
                    setDraft((d) => ({
                      ...d,
                      action_items: d.action_items.filter((_, j) => j !== i),
                    }))
                  }
                >
                  <X aria-hidden />
                </Button>
              </div>
            ))}
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                setDraft((d) => ({
                  ...d,
                  action_items: [...d.action_items, emptyAction()],
                }))
              }
            >
              <Plus aria-hidden />
              Add action item
            </Button>
          </div>

          <div className="flex gap-2">
            <Button size="sm" onClick={onSave} disabled={saving}>
              {saving ? <Loader2 className="animate-spin" aria-hidden /> : null}
              Save agenda
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setMode("view")}
              disabled={saving}
            >
              Cancel
            </Button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
