// The sessions' actors run in the MoonBit program (station/mb's reader `--sessions`, mb/src/reader/actors.mbt and
// actor_run.mbt): each session's state and its serial queue are there. This is what the hub holds of each (`MbActor`):
// what it is asked it says to the program (`call`, answered `returned`), with its runtime session's events as they come
// (`event`); what the program asks of the station it answers (`rpc`): the store, the hub's deps, its runtime sessions
// (kept here by a number, `handle`), its chats, and the words and formats of what agents are told (actor.ts's
// functions). What the hub reads of an actor at once (where it stands, its queue run out) is what the program last
// told of it (`mirror`). Its time is the hub's clock: said with every line (`now`), its waits that clock's (`after`,
// told `due`), so a test's TestClock moves them as the rest.
import { Clock, Effect, Fiber } from "effect";
import { log } from "../ops/log.ts";
import { Said, stationLang } from "../ops/i18n.ts";
import { SessionsProgram, type ProgramUser } from "../agents/mb-program.ts";
import type { HostedProcess, Router } from "../agents/mb-agents.ts";
import { mbReaderBinary } from "../read/mb-reader.ts";
import { CommandMissing } from "../agents/runner.ts";
import { RenewRefused } from "../accounts/console.ts";
import { modelLimitOf, runtimeLabel, type AgentSession, type RuntimeEvent, type RuntimeKind } from "../agents/runtime.ts";
import { chars } from "../agents/live.ts";
import * as instructions from "../agents/instructions.ts";
import { handedOf, type MessageRow, type PendingMessage, type RunChange } from "../store/rows.ts";
import { runChangeWords } from "./run-change.ts";
import {
  FALLBACK_MOST, SPENT_BEFORE, cannotStartWords, codexTooOld, compactFailed, compactFailedNotice, failureNotice, formatDelivery,
  OpenAborted, handedWithChoices, lastStationSaid, limitShownNotice, openAgent, personRef, postNotice, promptFor, retuneAgent, shownLimitOf,
  t, timed, withSaid, type DeclaredState, type SessionDeps, type Snapshot,
} from "./actor.ts";

type Json = any;

/// Every line between the station and the program, written to stderr (looking at what a session did).
const TRACE = process.env.STILLFAIL_ACTORS_TRACE === "1";

/// What the program last told of an actor (actors.mbt `mirror`).
type Mirror = {
  queued: number;
  seen: number;
  turn: string | null;
  warm: boolean;
  deferredEnd: boolean;
  codexUpdate: boolean;
  agent: number | null;
  idleSince: number;
  notices: number;
  waiting: boolean;
  refill: boolean;
  toolsRetry: boolean;
  startFailed: boolean;
  unread: [number, number, string][];
  identity: { model: string | null; effort: string | null; runtime: RuntimeKind } | null;
  runtime: RuntimeKind;
  closed: boolean;
};

/// What the program asks of the station that is no session's, and tells it, under a key of its own (`shell`).
export type ProgramShell = {
  readonly key: string;
  readonly runtime: RuntimeKind;
  asked(f: string, args: Json[]): Promise<Json>;
  told(f: string, args: Json[]): void;
  /// Its waits' clock (`after` said `on` it), where it is not the hub's: a part of the station's on a clock of its own.
  readonly clock?: Clock.Clock;
  /// What it is asked is not counted as the program's going on (`busy`): it waits on what is not the program's (where a
  /// transcript is, found by a worker), and says itself when it is done (the live view's `idle`).
  readonly uncounted?: boolean;
};

/// The program, one a hub (`ActorsProgram.open`).
export class ActorsProgram {
  readonly #proc: SessionsProgram;
  /// What it is to the program (agents/mb-program.ts): the actors' part.
  readonly #user: ProgramUser = {
    actors: true,
    said: (said) => this.#said(said),
    exited: (code) => this.#lost(code),
  };
  readonly #clock: Clock.Clock;
  readonly #actors = new Map<string, MbActor | ProgramShell>();
  readonly #timers = new Map<number, Fiber.Fiber<void>>();
  /// Lines said to it, those it said it took in, and whether something of it runs (`active`): `busy`.
  #sent = 0;
  #seen = 0;
  #active = 0;
  #closed = false;
  /// What actors asked of it, waiting for its answer (`returned`).
  #next = 0;
  readonly #calls = new Map<number, { resolve: (value: Json) => void; reject: (error: Error) => void }>();

  readonly #store: { told(changes: any[]): void } | null;

  private constructor(data: string, clock: Clock.Clock, store: { told(changes: any[]): void; db: any } | null, maxConcurrentTurns = 0) {
    this.#clock = clock;
    this.#store = store;
    // (it ends with its hub, which closes it: the process waits on it only while it has something going)
    this.#proc = SessionsProgram.of(data, true)!;
    this.#proc.use(this.#user);
    programs.add(this);
    endAll();
    // Where the station's database is, for what of the store an actor reads and writes itself (actor_store.mbt); one in
    // memory (a test's) is this process's alone, asked as the rest is. Said first: the program's actors begin here.
    const main = store === null ? undefined : (store.db.prepare("PRAGMA database_list").all() as { name: string; file: string }[]).find((d) => d.name === "main");
    this.post({ db: main !== undefined && main.file !== "" ? main.file : null });
    if (maxConcurrentTurns > 0) this.setMaxConcurrentTurns(maxConcurrentTurns);
  }

  #lost(code: number) {
    const lost = !this.#closed;
    this.#ended();
    if (!lost) return;
    // Its sessions' state went with it: the station ends as in a crash, and the next takes up their runners and resumes
    // their turns (hub.ts `takeUp`, `recover`), as it would have of this one's.
    log.error("session", "the program running the sessions ended; the station ends with it, as in a crash", { code });
    process.exit(70);
  }

  /// Ends it at once (the station's process ends).
  kill() {
    this.#proc.kill();
  }

  /// The program it is: where a runtime session's process read there gives its events its actor (`MbActor` `route`).
  get program(): SessionsProgram {
    return this.#proc;
  }

  /// The program for a hub on `data`, where it is built (none: a checkout that did not build it runs no session).
  static open(data: string, clock: Clock.Clock, store: { told(changes: any[]): void; db: any } | null = null, maxConcurrentTurns = 0): ActorsProgram | null {
    if (mbReaderBinary() === null) return null;
    return new ActorsProgram(data, clock, store, maxConcurrentTurns);
  }

  /// Updates the maximum concurrent running turns in the sessions program without restarting.
  setMaxConcurrentTurns(n: number) {
    const limit = typeof n === "number" && Number.isFinite(n) && n > 0 ? Math.trunc(n) : 0;
    this.post({ maxConcurrentTurns: limit });
  }

  /// Wakes queued sessions waiting on per-account concurrency caps (e.g. after config or quota changes).
  drainCapQueue() {
    this.post({ drainCapQueue: true });
  }

  now() {
    return this.#clock.currentTimeMillisUnsafe();
  }

  /// Whether what was said to it is not all taken in yet, or something of it runs (not counting what waits on an answer
  /// of the station's): what a test's `settle` waits for.
  busy() {
    return this.#sent > this.#seen || this.#active > 0 || this.#answering > 0;
  }

  /// What it asked that is being answered here: its actor waits on it.
  #answering = 0;

  /// What answers for `shell.key` that is no session's (the jobs, jobs/jobs.ts: `#jobs`): what the program asks of it
  /// and tells it.
  shell(shell: ProgramShell) {
    this.#actors.set(shell.key, shell);
  }

  actor(key: string, runtime: RuntimeKind, deps: SessionDeps): MbActor {
    const actor = new MbActor(this, key, runtime, deps);
    this.#actors.set(key, actor);
    return actor;
  }

  /// Says `message` to it: whether it is there to be told.
  /// How many lines of each kind (their first key) were said to it: what a test counts of what goes through Node.
  readonly posted = new Map<string, number>();

  post(message: Json): boolean {
    if (this.#closed) return false;
    this.#sent++;
    const kind = Object.keys(message)[0] ?? "";
    this.posted.set(kind, (this.posted.get(kind) ?? 0) + 1);
    if (TRACE) process.stderr.write(`actors < ${JSON.stringify(message).slice(0, 400)}\n`);
    this.#proc.post({ ...message, now: this.now() });
    this.#held();
    return true;
  }

  #refd = false;
  /// Held on to (`MbProcess.ref`) while something of it goes.
  #held() {
    const on = this.busy() || this.#calls.size > 0;
    if (on === this.#refd || this.#closed) return;
    this.#refd = on;
    this.#proc.hold(this.#user, on);
  }

  /// Asks it `method` of actor `key`: what it answers (null where it is gone).
  call(key: string, method: string, args: Json[]): Promise<Json> {
    const id = ++this.#next;
    return new Promise((resolve, reject) => {
      this.#calls.set(id, { resolve, reject });
      if (!this.post({ call: id, actor: key, method, args })) {
        this.#calls.delete(id);
        resolve(null);
      }
    });
  }

  /// It is gone: nothing it was asked is answered by it any more.
  #ended() {
    this.#closed = true;
    programs.delete(this);
    for (const fiber of this.#timers.values()) Effect.runFork(Fiber.interrupt(fiber));
    this.#timers.clear();
    const calls = [...this.#calls.values()];
    this.#calls.clear();
    for (const call of calls) call.resolve(null);
  }

  #said(said: Json) {
    if (TRACE) process.stderr.write(`actors > ${JSON.stringify(said).slice(0, 400)}\n`);
    if (said?.ready === true) return;
    if (typeof said?.seen === "number") this.#seen = said.seen;
    if (typeof said?.active === "number") this.#active = said.active;
    this.#hear(said);
    this.#held();
  }

  #hear(said: Json) {
    if (Array.isArray(said?.changes)) {
      this.#store?.told(said.changes);
      return;
    }
    if (typeof said?.after === "number") {
      const id = said.after;
      const on = typeof said.on === "string" ? this.#actors.get(said.on) : undefined;
      const clock = on !== undefined && !(on instanceof MbActor) && on.clock !== undefined ? on.clock : this.#clock;
      // timer: a wait of an actor's (its wait, a refill), on the hub's clock (or its shell's own)
      const fiber = Effect.runFork(Effect.sleep(said.ms).pipe(
        Effect.andThen(Effect.sync(() => {
          this.#timers.delete(id);
          this.post({ due: id });
        })),
        Effect.provideService(Clock.Clock, clock),
      ));
      this.#timers.set(id, fiber);
      return;
    }
    if (typeof said?.cancel === "number") {
      const fiber = this.#timers.get(said.cancel);
      this.#timers.delete(said.cancel);
      if (fiber) Effect.runFork(Fiber.interrupt(fiber));
      return;
    }
    const actor = typeof said?.actor === "string" ? this.#actors.get(said.actor) : typeof said?.mirror === "string" ? this.#actors.get(said.mirror) : undefined;
    if (typeof said?.returned === "number") {
      const call = this.#calls.get(said.returned);
      this.#calls.delete(said.returned);
      if (typeof said.error === "string") {
        const first = typeof said.cause?.id === "number" ? errors.get(said.cause.id) : undefined;
        if (first !== undefined) errors.delete(said.cause.id);
        call?.reject(first instanceof Error ? first : new Error(said.error));
      } else call?.resolve(said.value ?? null);
      return;
    }
    if (actor === undefined) return;
    if (said.mirror !== undefined) (actor as MbActor).mirrored?.(said.state);
    else if (typeof said.rpc === "number") {
      const id = said.rpc;
      const counted = !(actor instanceof MbActor) && actor.uncounted === true ? 0 : 1;
      this.#answering += counted;
      actor.asked(said.fn, Array.isArray(said.args) ? said.args : []).then(
        (value) => { this.#answering -= counted; this.post({ answer: id, value: value === undefined ? null : value }); },
        (error) => { this.#answering -= counted; this.post({ answer: id, error: errorOf(error, actor.runtime) }); },
      );
    } else if (typeof said.tell === "string") {
      try {
        actor.told(said.tell, Array.isArray(said.args) ? said.args : []);
      } catch (error) {
        log.warn("session", "what a session told the station failed", { session: actor.key, tell: said.tell, error: (error as Error).message });
      }
    }
  }

  forget(key: string, actor: MbActor | ProgramShell) {
    if (this.#actors.get(key) === actor) this.#actors.delete(key);
  }

  async close() {
    if (this.#closed) return;
    this.#ended();
    await this.#proc.release(this.#user);
  }
}

const programs = new Set<ActorsProgram>();
// (one left open as the station's process ends, a hub never stopped, ends with it: before anything else looks)
let ending = false;
const endAll = () => {
  if (ending) return;
  ending = true;
  process.prependListener("exit", () => {
    for (const p of programs) p.kill();
  });
};

/// Whether a program running sessions has something going (test/hub-fakes.ts `settle`).
export const actorsBusy = () => [...programs].some((p) => p.busy());

/// An error of the station's as the program is told it: its words, whether they are the station's own (`Said`), and
/// whether its runtime is not installed (CommandMissing).
function errorOf(error: unknown, runtime: RuntimeKind): Json {
  const message = (error as Error)?.message ?? String(error);
  const id = ++errorsNext;
  errors.set(id, error);
  // (those never given back: the oldest let go)
  if (errors.size > 256) errors.delete(errors.keys().next().value!);
  const cap = (error as any)?.sessionCap === true
    ? {
        sessionCap: true,
        profile: (error as any).profile,
        profileId: (error as any).profileId,
        active: (error as any).active,
        cap: (error as any).cap,
        protection: Boolean((error as any).protection),
      }
    : {};
  return {
    id,
    message,
    said: error instanceof Said,
    missing: error instanceof CommandMissing && error.command === runtime,
    runtime,
    // (what it is, for the program to tell apart a peer's refusal from a request that did not get through: bus.ts)
    kind: (error as Error)?.constructor?.name ?? "Error",
    // (given up, and why: the program's own `openAbort`, actor_run.mbt `open_abort_reason`)
    ...(error instanceof OpenAborted ? { openAbort: error.why } : {}),
    // (a login over, and on which profile where known: the program goes on on another profile, as after a turn
    // refused, actor_run.mbt `open_over`)
    ...(error instanceof RenewRefused ? { auth: true, ...(error.profileId ? { authProfile: error.profileId } : {}) } : {}),
    ...cap,
  };
}

/// The station's errors the program was told, by their number: one it gives back as its call's failure is thrown as
/// it was (its class, what a caller tells apart by it: conversations.ts `StateWriteBusy`).
const errors = new Map<number, unknown>();
let errorsNext = 0;

/// An error the program was told, as it was here.
function errorBack(error: Json): Error {
  const message = typeof error?.message === "string" ? error.message : String(error);
  return error?.said === true ? new Said(message) : new Error(message);
}

/// A session's actor as the hub holds it, run by the program.
export class MbActor {
  readonly key: string;
  runtime: RuntimeKind;
  readonly #program: ActorsProgram;
  readonly #deps: SessionDeps;
  #mirror: Mirror;
  /// Lines said of it to the program (`seen` in its mirror: how many of them it took in).
  #sent = 0;
  #next = 0;
  /// Its runtime sessions, by the number the program knows each by.
  /// `heard`: how many requests its token had made of the station's tools as it was opened (none for one taken up).
  /// `nudgeHeard`: how many requests its token had made when the previous undeclared turn ended (checked after a nudge).
  readonly #agents = new Map<number, { generation: number; session: AgentSession; heard?: number; nudgeHeard?: number }>();
  #generation = 0;
  #closed = false;
  /// What is being read and formatted for it (`pendingAndFormat`): given up at once on a stop or a suspension.
  #formatAbort: AbortController | null = null;
  /// Its runtime sessions being opened (`open`), by the program's number for the ask: each given up as the program gives
  /// it up (`node.cancelOpen`: a stop, a suspension, a close, its deadline), never here before it has (a stop's failure
  /// read there before its stop, as a start that failed), but for its close (`#closing`).
  readonly #openAborts = new Map<number, AbortController>();
  /// What marks what people chose told, once what it was handed with is (`withChoices`); a state's write, by its turn's
  /// tool (`stateForTurn`); what its live view reads as a turn ends (`turnEnded`); a Codex update's, as it began.
  readonly #told = new Map<number, () => void>();
  readonly #records = new Map<number, { words: string | null; about: [number, number, string] | null; watch: boolean; record?: (write: (about: [number, number, string] | null) => void) => void }>();
  readonly #reads = new Map<number, Promise<void> | void>();
  /// What it decided of the batch of routed events it is taking (`#event`): a turn's outcome, its unread cleared.
  #routing: { outcome?: Json; cleared?: boolean } = {};
  #adopting: { generation: number; pending: Array<() => void> } | null = null;
  readonly #codex = new Map<number, { version: string | null; matches: (() => Promise<boolean>) | undefined }>();

  constructor(program: ActorsProgram, key: string, runtime: RuntimeKind, deps: SessionDeps) {
    this.#program = program;
    this.key = key;
    this.runtime = runtime;
    this.#deps = deps;
    this.#mirror = { queued: 0, seen: 0, turn: null, warm: false, deferredEnd: false, codexUpdate: false, agent: null, idleSince: program.now(), notices: 0, waiting: false, refill: false, toolsRetry: false, startFailed: false, unread: [], identity: null, runtime, closed: false };
    this.#post({ runtime });
  }

  #post(message: Json) {
    this.#sent++;
    this.#program.post({ ...message, actor: this.key });
  }

  #call(method: string, args: Json[] = []): Promise<Json> {
    if (this.#closed) return Promise.resolve(null);
    this.#sent++;
    return this.#program.call(this.key, method, args);
  }

  /// What it had been given that its model had not read, read as its model is asked (`requesting`): so at once here,
  /// its tools asking next; a mirror said before the program took that in does not say it again.
  #readAt = 0;

  mirrored(state: Mirror) {
    if (state.seen < this.#readAt) state = { ...state, unread: [] };
    this.#mirror = state;
    this.runtime = state.runtime;
  }

  #session(): AgentSession | null {
    return this.#mirror.agent === null ? null : this.#agents.get(this.#mirror.agent)?.session ?? null;
  }

  // ── what the hub reads at once ───────────────────────────────────────────────────────────────────────────────

  messageIdentity() {
    return this.#mirror.agent !== null ? this.#mirror.identity : null;
  }

  settled(): boolean {
    return this.#sent === this.#mirror.seen && this.#mirror.queued === 0;
  }

  processState(): "running" | "warm" | "cold" {
    if (this.#mirror.turn || this.#mirror.warm || this.#mirror.deferredEnd || this.#mirror.codexUpdate || this.#session()?.busy()) return "running";
    return this.#mirror.agent !== null ? "warm" : "cold";
  }

  startFailed(): boolean {
    return this.#mirror.startFailed && this.processState() !== "running";
  }

  idleMs(now: number): number | null {
    const session = this.#session();
    return session && !session.busy() && !this.#mirror.turn && !this.#mirror.warm && !this.#mirror.deferredEnd ? now - this.#mirror.idleSince : null;
  }

  holdsState(): boolean {
    return this.#mirror.codexUpdate || this.#mirror.notices > 0 || this.#mirror.waiting || this.#mirror.refill || this.#mirror.toolsRetry || this.#mirror.warm || this.#mirror.deferredEnd;
  }

  unreadIn(thread: number, before: number): PendingMessage[] {
    return this.#mirror.unread.filter(([t, n]) => t === thread && n < before).map(([t, n, ts]) => ({ message: { thread: t, n, ts } }) as unknown as PendingMessage);
  }

  currentTurnId(): string | null {
    return this.#mirror.turn;
  }

  listener(generation: number): (event: RuntimeEvent) => void {
    return (event) => this.#event(generation, event);
  }

  nextGeneration(): number {
    return ++this.#generation;
  }

  // ── what the hub asks ────────────────────────────────────────────────────────────────────────────────────────

  flushed() { return this.#call("flushed").then(() => undefined); }
  cleanArchive() { return this.#call("cleanArchive").then(() => undefined); }
  kick() { return this.#call("kick").then(() => undefined); }
  notify(text: string): Promise<void> {
    if ((this.#deps.store.getSession(this.key)?.archivedAt ?? null) !== null) return Promise.resolve();
    return this.#call("notify", [text]).then(() => undefined);
  }
  putAway() { return this.#call("putAway").then(() => undefined); }
  postedNow() { return this.#call("postedNow").then(() => undefined); }
  postedForTurn(id: string) { return this.#call("postedForTurn", [id]).then(() => undefined); }
  goesOn() { return this.#call("goesOn").then(() => undefined); }
  async stateForTurn(id: string, state: DeclaredState, words: string | null, about: [number, number, string] | null,
    watch = false, record?: (write: (about: [number, number, string] | null) => void) => void): Promise<boolean> {
    const token = ++this.#next;
    this.#records.set(token, { words, about, watch, record });
    try { return (await this.#call("stateForTurn", [id, state, token])) === true; }
    finally { this.#records.delete(token); }
  }
  toolsAt(url: string) { return this.#call("toolsAt", [url]).then(() => undefined); }
  declare(state: DeclaredState): Promise<boolean> { return this.#call("declare", [state]).then((v) => v === true); }
  waitFor(what: string, watch: boolean) { return this.#call("waitFor", [what, watch]).then(() => undefined); }
  need(what: string) { return this.#call("need", [what]).then(() => undefined); }
  about(about: [number, number, string] | null) { return this.#call("about", [about]).then(() => undefined); }
  stop() {
    this.#formatAbort?.abort();
    return this.#call("stop").then(() => undefined);
  }
  cancelRetry(thread: number, seq: number) { return this.#call("cancelRetry", [thread, seq]).then(() => undefined); }
  retryFailed(thread: number, seq: number) { return this.#call("retryFailed", [thread, seq]).then(() => undefined); }
  reassign(thread: number, seq: number) { return this.#call("reassign", [thread, seq]).then(() => undefined); }
  async stopFromSlack(connect: string, channel: string, threadTs: string, ts: string, localAt?: number | null): Promise<void> {
    await this.#call("stopFromSlack", localAt === undefined ? [connect, channel, threadTs, ts] : [connect, channel, threadTs, ts, localAt]);
  }
  goOn() { return this.#call("goOn").then(() => undefined); }
  allowanceReset() { return this.#call("allowanceReset").then(() => undefined); }
  recover() { return this.#call("recover").then(() => undefined); }
  cutOffByRestart(): Promise<boolean> { return this.#call("cutOffByRestart").then((v) => v === true); }
  takeWait() { return this.#call("takeWait").then(() => undefined); }
  takeRefill() { return this.#call("takeRefill").then(() => undefined); }
  release() { return this.#call("release").then(() => undefined); }
  warm() { return this.#call("warm").then(() => undefined); }
  changed(restart = false) { return this.#call("changed", [restart]).then(() => undefined); }
  /// Ends its process if idle; `force` (its session archived) even with work left in its background (`holding`).
  evict(force = false) { return this.#call("evict", [force]).then(() => undefined); }
  compact(say = false): Promise<string | null> { return this.#call("compact", [say]); }
  compactToCap() { return this.#call("compactToCap").then(() => undefined); }
  clear(say = false, readBack = false): Promise<string | null> { return this.#call("clear", [say, readBack]); }
  /// `why`: what is said of it (actor.ts `suspend`).
  suspend(why = "the station is in no workspace") {
    this.#formatAbort?.abort();
    return this.#call("suspend", [why]).then(() => undefined);
  }
  async runChanged(change: RunChange): Promise<void> {
    await this.#call("runChanged", [runChangeWords(change, stationLang()), change]);
  }

  /// Where it stands, for the next station: its runtime session's own snapshot said in it, that session let go of.
  async snapshot(): Promise<Snapshot> {
    const snap = await this.#call("snapshot");
    const entry = typeof snap.agent === "number" ? this.#agents.get(snap.agent) : undefined;
    const held = entry?.session ?? null;
    const deps = this.#deps;
    const toolsUnheard = entry?.heard !== undefined && this.runtime !== "codex" && deps.toolsHeard !== undefined && deps.toolsHeard(this.key) === entry.heard;
    const nudgeUnheard = entry?.nudgeHeard !== undefined && deps.toolsHeard !== undefined && deps.toolsHeard(this.key) === entry.nudgeHeard;
    this.#closing();
    const agent = held?.snapshot() ?? null;
    held?.detach();
    return { ...snap, agent, ...(toolsUnheard ? { toolsUnheard: true } : {}), ...(nudgeUnheard ? { nudgeUnheard: true } : {}) } as Snapshot;
  }

  /// Takes up `snap` with its runtime session `agent`; done once the program has. What the hub reads at once (its
  /// idle time, `idleMs`) is so from here: the hub looks at it as it takes up (hub.ts `idleNow`, `evictIdle`), and read
  /// as a session's with no process, every handover started its idle time again (2026-11-15).
  beginAdopt(generation: number): Router {
    this.#adopting = { generation, pending: [] };
    return { program: this.#program.program, took: (batch, proc) => this.#took(batch, null, generation, proc) };
  }

  cancelAdopt(generation: number): void {
    if (this.#adopting?.generation === generation) this.#adopting = null;
  }

  adopt(snap: Snapshot, agent: AgentSession | null, profile: string): Promise<void> {
    const pending = this.#adopting?.pending ?? [];
    this.#adopting = null;
    let taken: Json = null;
    const hasDeferred = snap.deferredEnd != null;
    if (agent) {
      this.runtime = snap.runtime;
      const deps = this.#deps;
      const heard = snap?.toolsUnheard === true && this.runtime !== "codex" && deps.toolsHeard !== undefined ? deps.toolsHeard(this.key) : undefined;
      const nudgeHeard = snap?.nudgeUnheard === true && deps.toolsHeard !== undefined ? deps.toolsHeard(this.key) : undefined;
      const handle = ++this.#next;
      this.#agents.set(handle, {
        generation: this.#generation,
        session: agent,
        ...(heard === undefined ? {} : { heard }),
        ...(nudgeHeard === undefined ? {} : { nudgeHeard }),
      });
      taken = { handle, generation: this.#generation };
      this.#mirror = {
        ...this.#mirror,
        agent: handle,
        turn: snap.turn?.id ?? null,
        warm: snap.turn == null && hasDeferred,
        deferredEnd: hasDeferred,
        idleSince: this.#program.now() - (snap.idleMs ?? 0),
        runtime: snap.runtime,
      };
    } else if (hasDeferred) {
      this.#mirror = {
        ...this.#mirror,
        turn: snap.turn?.id ?? null,
        warm: snap.turn == null,
        deferredEnd: true,
      };
    }
    const adopted = this.#call("adopt", [{ ...snap, agent: null }, taken, profile, this.#deps.store.getSession(this.key)]);
    if (agent) {
      for (const deliver of pending) deliver();
      this.#route(agent, this.#generation);
    }
    return adopted.then(() => undefined);
  }

  close() {
    void this.#call("close");
    this.#closing();
  }

  #closing() {
    this.#closed = true;
    this.#formatAbort?.abort();
    this.#abortOpens();
    this.#program.forget(this.key, this);
  }

  /// Gives up every runtime session being opened for it (`open`), as `why` (the program's `openAbort`).
  #abortOpens(why = "closed") {
    const opening = [...this.#openAborts.values()];
    this.#openAborts.clear();
    for (const abort of opening) abort.abort(why);
  }

  async dispose() {
    await this.#call("dispose");
    this.#closing();
    // (what the program did not end, gone before it could: ended here)
    const left = [...this.#agents.values()];
    this.#agents.clear();
    await Promise.all(left.map((a) => a.session.dispose()));
  }

  // ── its runtime sessions' events ─────────────────────────────────────────────────────────────────────────────

  /// Its runtime session's process, read in this program, gives the actor its events there (agents.mbt `tell`,
  /// actors.mbt `routed`): each batch of them is had here first (`#event`), then said taken.
  #route(session: AgentSession, generation: number) {
    const s = session as AgentSession & { route?: (router: Router | null) => void };
    s.route?.({ program: this.#program.program, took: (batch) => this.#took(batch, s, generation) });
  }

  #unroute(session: AgentSession) {
    (session as AgentSession & { route?: (router: Router | null) => void }).route?.(null);
  }

  #took(batch: number, session: AgentSession | null, generation: number, proc?: number): boolean {
    const n = proc ?? (session as (AgentSession & { hostedProc?: () => HostedProcess | null }) | null)?.hostedProc?.()?.n;
    if (this.#closed || n === undefined) return false;
    if (this.#adopting?.generation === generation) {
      this.#adopting.pending.push(() => { this.#took(batch, session, generation, n); });
      return true;
    }
    const routing = this.#routing;
    this.#routing = {};
    // (what it read clears the unread as the program takes the batch: a mirror from before that is not taken)
    if (routing.cleared === true) this.#readAt = this.#sent + 1;
    this.#post({ routed: n, batch, generation, ...(routing.outcome !== undefined ? { outcome: routing.outcome } : {}) });
    return true;
  }

  #event(generation: number, event: RuntimeEvent) {
    if (this.#closed) return;
    if (this.#adopting?.generation === generation) {
      this.#adopting.pending.push(() => this.#event(generation, event));
      return;
    }
    if ((event as { routed?: boolean }).routed === true) {
      // (the program gives it the actor and the live view once the batch is said taken: here what the station's own parts
      // take of it, its unread cleared and a turn's outcome)
      if (event.type === "live") {
        // (cleared whether or not the program's mirror saying it unread has come yet: one coming later is from before)
        if (event.event.kind === "phase" && event.event.phase === "requesting") {
          this.#mirror = { ...this.#mirror, unread: [] };
          this.#routing.cleared = true;
        }
      } else if (event.type === "turnEnded") this.#routing.outcome = event.outcome;
      return;
    }
    if (event.type === "live") {
      // (the live view takes each at once; the program only what moves its status line and its words)
      this.#deps.live?.event(this.key, event.event);
      const e = event.event;
      if (e.kind === "tasks" || e.kind === "plan" || (e.kind === "delta" && e.field !== "text")) return;
      if (e.kind === "start" && e.step === "thinking") return;
      if (e.kind === "phase" && e.phase === "requesting") {
        this.#mirror = { ...this.#mirror, unread: [] };
        this.#readAt = this.#sent + 1;
      }
      this.#post({ event: { type: "live", event: e.kind === "start" && e.step === "tool" ? { kind: e.kind, step: e.step, id: e.id, tool: e.tool } : e }, generation });
      return;
    }
    if (event.type === "turnEnded") {
      // What it wrote last is read (off the main thread) and told before the turn is said to be over.
      const read = ++this.#next;
      this.#reads.set(read, this.#deps.live?.turnEnded(this.key));
      this.#post({ event, generation, read });
      return;
    }
    this.#post({ event, generation });
  }

  // ── what the program asks of the station ─────────────────────────────────────────────────────────────────────

  /// What is told and not waited for.
  told(f: string, args: Json[]) {
    const deps = this.#deps;
    switch (f) {
      case "log": {
        const [level, message, fields] = args;
        (level === "error" ? log.error : level === "warn" ? log.warn : log.info)("session", message, fields ?? {});
        return;
      }
      case "node.tasks": {
        const session = args[0] === null ? null : this.#agents.get(args[0])?.session ?? null;
        deps.live?.event(this.key, { kind: "tasks", tasks: session?.background?.() ?? [] });
        return;
      }
      case "node.working": {
        const [working, status] = args as [Json[], Json];
        const text = status === "" ? "" : status === "thinking" ? t("station.status.thinking") : deps.toolStatus(status.tool);
        const page = deps.pageOf?.(this.key) ?? null;
        for (const w of working) deps.chat(w.connect)?.working?.({ channel: w.channel, threadTs: w.threadTs }, w.ts, text, page);
        return;
      }
      case "node.cancelOpen": {
        // (given up by the program: its stop, suspension, close or deadline; `open` ends what comes of it)
        const id = args[0];
        if (typeof id !== "number") return this.#abortOpens("cancelled");
        this.#openAborts.get(id)?.abort("cancelled");
        this.#openAborts.delete(id);
        return;
      }
      case "chat.standsAt": {
        const [connect, channel, threadTs, stands] = args;
        deps.chat(connect)?.standsAt?.({ channel, threadTs }, stands);
        return;
      }
    }
    log.warn("session", "a session told the station what it does not know", { session: this.key, tell: f });
  }

  /// What is asked and answered.
  async asked(f: string, args: Json[]): Promise<Json> {
    const deps = this.#deps;
    const store = deps.store as Json;
    const dot = f.indexOf(".");
    const [part, name] = dot < 0 ? [f, ""] : [f.slice(0, dot), f.slice(dot + 1)];
    if (part === "store") {
      if (typeof store[name] !== "function") return null;
      return store[name](...args);
    }
    if (part === "deps") {
      const d = deps as Json;
      if (typeof d[name] !== "function") return name === "canAuthRetry" ? true : null;
      return await d[name](...args);
    }
    if (part === "agent") {
      const [handle, ...rest] = args;
      const session = this.#agents.get(handle)?.session as Json;
      if (session === undefined) throw new Error(`no runtime session ${handle}`);
      switch (name) {
        case "busy": return session.busy();
        case "holding": return (session.background?.().length ?? 0) > 0;
        case "background": return session.background?.() ?? [];
        case "mcpUrl": return session.mcpUrl?.() ?? null;
        case "canCompact": return typeof session.compact === "function";
        case "dispose":
          this.#agents.delete(handle);
          this.#unroute(session);
          await session.dispose();
          return null;
        default:
          if (typeof session[name] !== "function") return null;
          return (await session[name](...rest)) ?? null;
      }
    }
    if (f === "t") return t(args[0], args[1] ?? undefined);
    switch (name) {
      case "words": return this.#words(args[0], args.slice(1));
      case "uuid": return crypto.randomUUID();
      // A turn that ended with no state on a card it posted (since `started`), still waiting: it ends need_human on it
      // (store/card-kinds.ts; actor_run.mbt `on_turn_ended`). Whether it does.
      case "cardAsks": {
        const [id, started] = args as [string, number | null];
        let found: MessageRow | null = null;
        for (const t of deps.store.recentSessionThreads(this.key).threads) {
          const card = deps.store.pendingCard(t.thread.id)?.[0] ?? null;
          if (card === null || card.authorKind !== "agent" || card.author !== this.key) continue;
          if (typeof started === "number" && card.createdAt < started) continue;
          if (found === null || card.createdAt >= found.createdAt) found = card;
        }
        if (found === null) return false;
        deps.store.setAbout(id, [found.thread, found.n, found.ts]);
        deps.store.declareTurn(id, "need_help", null);
        return true;
      }
      // A turn its background work woke, that waits on: what the turn before it (`before`, its summary) asked is asked
      // still, unless a card of the session's chats was closed since (a person decided). Whether it is.
      case "keepAsk": {
        const [id, before] = args as [string, Json];
        const since = typeof before?.endedAt === "number" ? before.endedAt : null;
        if (since === null) return false;
        const threads = deps.store.recentSessionThreads(this.key).threads.map((t) => t.thread.id);
        if (threads.some((thread) => deps.store.cardClosedSince(thread, since))) return false;
        const about = before.about;
        let asked: [number, number, string] | null = about !== null && typeof about === "object" && Number.isInteger(about.seq)
          ? [about.thread, about.seq, about.ts] : null;
        if (asked === null) {
          const during: [number, number] = [typeof before.startedAt === "number" ? before.startedAt : 0, since];
          for (const thread of threads) {
            const m = deps.store.askingMessage(thread, null, during)?.[0];
            if (m !== undefined) {
              asked = [m.thread, m.n, m.ts];
              break;
            }
          }
        }
        if (typeof before.need === "string" && before.need !== "") deps.store.setNeed(id, before.need);
        deps.store.setAbout(id, asked);
        deps.store.declareTurn(id, "need_help", null);
        return true;
      }
      case "timed": return timed(args[0], this.#program.now());
      case "withChoices": {
        const [text, told] = await handedWithChoices(deps, this.key, this.#program.now(), args[0]);
        const id = ++this.#next;
        this.#told.set(id, told);
        return { text, told: id };
      }
      case "told": {
        const told = this.#told.get(args[0]);
        this.#told.delete(args[0]);
        told?.();
        return null;
      }
      case "prompt": {
        const [handed, lost, stopped, afresh, compacted] = args;
        return promptFor(deps, this.key, this.#program.now(), handed, lost, stopped, afresh, compacted);
      }
      case "pendingAndFormat": return this.#pendingAndFormat(args[0] === true);
      case "open": {
        const [stopped, readBack, profile, forceCap, asked] = args;
        let generation = 0;
        const heard = deps.toolsHeard?.(this.key);
        // (the program's number for this ask: what it gives it up by, `node.cancelOpen`)
        const id = typeof asked === "number" ? asked : -(++this.#next);
        const abort = new AbortController();
        if (this.#closed) abort.abort("closed");
        this.#openAborts.set(id, abort);
        let opened: Awaited<ReturnType<typeof openAgent>>;
        try {
          opened = await openAgent(deps, this.key, {
            stopped,
            readBack,
            profile: profile ?? null,
            forceCap: forceCap === true,
            signal: abort.signal,
            runtime: (runtime) => { this.runtime = runtime; },
            generation: () => (generation = this.nextGeneration()),
            listener: (g) => this.listener(g),
          });
        } finally {
          if (this.#openAborts.get(id) === abort) this.#openAborts.delete(id);
        }
        // (given up as it came: never its actor's, ended at once)
        if (abort.signal.aborted || this.#closed) {
          await opened.session.dispose().catch(() => {});
          throw new OpenAborted(typeof abort.signal.reason === "string" ? abort.signal.reason : "closed");
        }
        const handle = ++this.#next;
        this.#agents.set(handle, { generation, session: opened.session, ...(heard === undefined ? {} : { heard }) });
        this.#route(opened.session, generation);
        const { session: _, ...rest } = opened;
        return { ...rest, handle, runtime: this.runtime };
      }
      case "retune": {
        const [handle, profile, restart, holding] = args;
        const session = this.#agents.get(handle)?.session;
        if (!session) return null;
        return retuneAgent(deps, this.key, session, this.runtime, profile, restart, holding);
      }
      case "profileId": return deps.runOn(this.key, args[0] === true, true, args[1] === true).id;
      // A process this station opened whose turn ended saying nothing, that never once reached the station's tools
      // (not even to list them: its MCP connection failed as it opened, 2026-11-19 with the station out of file
      // handles), is one that lost them: why, else null. Not a Codex app-server's, shared by sessions and opened before.
      case "toolsUnheard": {
        if (deps.toolsHeard === undefined) return null;
        const [handle, nudged] = args;
        const entry = this.#agents.get(handle);
        if (!entry) return null;
        const cur = deps.toolsHeard(this.key);
        if (entry.heard !== undefined && this.runtime !== "codex" && cur === entry.heard) {
          return "its process never reached the station's tools";
        }
        if (nudged === true && entry.nudgeHeard !== undefined && cur === entry.nudgeHeard) {
          entry.nudgeHeard = undefined;
          return "its process made no tool requests even after being nudged";
        }
        entry.nudgeHeard = cur;
        return null;
      }
      case "outlived": {
        const session = this.#agents.get(args[0])?.session;
        return session?.outlived?.() === true;
      }
      case "notice": {
        const [text, profile, runtime, change, about, quiet] = args;
        const recorded = typeof about === "string" ? (where: [number, number, string]) => { deps.store.setAbout(about, where); if (!quiet) deps.store.notify(this.key); } : undefined;
        await postNotice(deps, this.key, text, profile ?? null, runtime ?? null, recorded, change ?? undefined);
        return null;
      }
      case "saidLast": return lastStationSaid(deps, this.key);
      case "read": {
        const read = this.#reads.get(args[0]);
        this.#reads.delete(args[0]);
        await read;
        return null;
      }
      case "stateWrite": {
        const [id, state, token] = args as [string, DeclaredState, number];
        const r = this.#records.get(token);
        if (r === undefined) return null;
        const write = (current: [number, number, string] | null) => {
          if (r.words !== null) {
            if (state.kind === "waiting") deps.store.setWaitFor(id, r.words, r.watch);
            else deps.store.setNeed(id, r.words);
          }
          deps.store.setAbout(id, current);
          deps.store.declareTurn(id, state.kind, state.kind === "waiting" ? state.seconds : null);
        };
        if (r.record) r.record(write);
        else write(r.about);
        return null;
      }
      case "limitAfter": {
        if (!deps.limitAfter) return null;
        const limit = await deps.limitAfter(args[0], deps.store.getSession(this.key)?.model ?? null).catch(() => undefined);
        return limit === undefined ? null : { limit };
      }
      case "canUpdateCodex": return deps.updateOldCodex !== undefined;
      case "codexBefore": {
        const [handle, id] = args;
        const session = handle === null ? undefined : this.#agents.get(handle)?.session;
        this.#codex.set(id, { version: session?.runtimeVersion?.() ?? null, matches: session?.runtimeUpdateMatchesStation?.bind(session) });
        return null;
      }
      case "updateCodex": {
        const id = args[0];
        const before = this.#codex.get(id);
        this.#codex.delete(id);
        // (not holding its queue during the install: its end is told it)
        void Promise.resolve().then(async () => {
          if (before?.matches && !(await before.matches())) throw new Error(t("station.notice.codexDifferentPath"));
          await deps.updateOldCodex!(before?.version ?? null);
        }).then(
          () => { if (!this.#closed) this.#post({ codexUpdated: id }); },
          (error) => { if (!this.#closed) this.#post({ codexUpdated: id, why: (error as Error)?.message || String(error) }); },
        );
        return null;
      }
    }
    throw new Error(`a session asked the station for ${f}, which it does not know`);
  }

  /// What instructions.ts and actor.ts say, by name.
  #words(name: string, args: Json[]): Json {
    switch (name) {
      case "GO_ON_AFTER_AUTH": case "GO_ON_AFTER_CODEX_UPDATE": case "GO_ON_AFTER_FAILED": case "GO_ON_AFTER_OVERLOADED":
      case "GO_ON_AFTER_UNANSWERED": case "GO_ON_AFTER_REFILL": case "GO_ON_AFTER_SPENT": case "NUDGE": case "RESUME_AFTER_RESTART":
      case "TOOLS_LOST": case "BACKGROUND_STOPPED_WAITING":
        return (instructions as Json)[name];
      case "nameUntitled": return instructions.nameUntitled(args[0]);
      case "waitOver": return instructions.waitOver(args[0]);
      case "shownLimitOf": {
        const model = shownLimitOf(args[0] ?? null);
        return model === undefined ? null : { model };
      }
      case "runtimeLabel": return runtimeLabel(args[0]);
      case "compactFailed": return compactFailed(errorBack(args[0]));
      case "cannotStartWords": return cannotStartWords(errorBack(args[0]));
      case "compactFailedNotice": return compactFailedNotice(args[0]);
      case "failureNotice": return failureNotice(args[0]);
      case "limitShownNotice": return limitShownNotice(args[0], args[1]);
      case "codexStillOld": return `⚠️ ${withSaid(t("station.notice.codexStillOld"), args[0])}`;
      case "codexTooOld": return codexTooOld(args[0]);
      case "modelLimitOf": return modelLimitOf(args[0]);
      case "spentBefore": return SPENT_BEFORE;
      case "quoted": return chars(args[0], FALLBACK_MOST).split("\n").map((line) => `> ${line}`).join("\n");
    }
    throw new Error(`no words named ${name}`);
  }

  /// actor.ts `pendingAndFormat`, what each message is said to the program as it needs it.
  async #pendingAndFormat(allowEmpty: boolean): Promise<Json> {
    const abort = new AbortController();
    this.#formatAbort = abort;
    try {
      const pending = await this.#deps.pendingDeliveries(this.key, abort.signal);
      if (abort.signal.aborted) throw new Error("delivery cancelled");
      if (!allowEmpty && pending.length === 0) return null;
      const [text, widgets] = await formatDelivery(this.#deps, this.key, pending, abort.signal);
      if (abort.signal.aborted) throw new Error("delivery cancelled");
      const light = pending.map((m: Json) => ({
        connect: m.connect, channel: m.channel, threadTs: m.threadTs, surface: m.surface,
        ts: m.message.ts, thread: m.message.thread, n: m.message.n, apart: m.message.apart === true,
        authorKind: m.message.authorKind, person: m.message.authorKind === "person" ? personRef(m) : null, handed: handedOf(m),
      }));
      return { pending: light, text, widgets };
    } finally { if (this.#formatAbort === abort) this.#formatAbort = null; }
  }
}
