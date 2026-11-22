// What a session's actor is and asks of the station: its types (what a turn declares, a snapshot handed to the next
// station, what it needs of the store, a chat surface and the hub), and the station's side of what it does that is not
// the program's yet (formatting what the agent is handed, its prompt, opening its runtime session, the station's
// notices). The actor itself runs in the MoonBit program (mb/src/reader/actor_run.mbt), the hub holding a shell of
// each (mb-actor.ts) that answers it with these.
import { presetCopyOf, presetInstructions } from "./presets.ts";
import { RenewRefused } from "../accounts/console.ts";
import { markNotice } from "./chat.ts";
import { sessionSkills } from "./agent-home.ts";
import { writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { Clock } from "effect";
import type { MbActor } from "./mb-actor.ts";
import type { AgentDriver, AgentSession, BackgroundTask, FailureReason, LiveEvent, OpenOptions, Profile, RuntimeEvent, TurnOutcome } from "../agents/runtime.ts";
import { afresh as afreshNote, backgroundStopped, cleared, continuedHere, formatCardChoices, formatInbound, formatWidgetModels, readMemory, resumeLost, sessionInstructions } from "../agents/instructions.ts";
import { latest as latestNote, untold } from "../agents/migrations.ts";
import { unreadableDirAsync, unreadableDirMessage } from "../ops/files.ts";
import { Places } from "../ops/places.ts";
import { log } from "../ops/log.ts";
import { Said, tr, stationLang } from "../ops/i18n.ts";
import { failureOf, modelLimitOf, runtimeKind, runtimeLabel, type RuntimeKind } from "../agents/runtime.ts";
import { CommandMissing } from "../agents/runner.ts";
import { type CardChoice, type DeliveryCardState, type Handed, type MessageRow, type PendingMessage, type RunChange } from "../store/rows.ts";
import { PostBlocksUnavailable } from "../store/post-blocks.ts";
import { WidgetSourcesUnavailable } from "../store/widget-sources.ts";
import { STATION_AUTHOR, STILLFAIL_SURFACE } from "../store/rows.ts";
import { INTERNAL_CONNECT } from "./internal.ts";

/// How an agent ended its turn (chat_post / chat_state `kind`).
export type DeclaredState = { kind: "all_done" } | { kind: "need_help" } | { kind: "waiting"; seconds: number };

/// A kind as kept or given, the words from before these included: final is all_done, block and need_decision need_help.
export function parseDeclared(kind: string, wait: number): DeclaredState | null {
  if (kind === "all_done" || kind === "final") return { kind: "all_done" };
  if (["need_human", "need_help", "block", "need_decision"].includes(kind)) return { kind: "need_help" };
  if (kind === "waiting") return { kind: "waiting", seconds: wait };
  return null;
}


/// The runtime may keep a session open across long waits: say the time with every turn and every steer.
export const timed = (text: string, now: number) => `[Delivered at ${new Date(now).toISOString()} (UTC)]\n${text}`;



/// The reasons a failed turn can be taken up again by a press of its notice's 重试 (`retryFailed`), as a person's reply
/// would: what failed was the provider's or the connection's, or not said (`other`), and nothing of the person's (an
/// account's sign-in, its allowance, a refusal) has to change first.
const AGAIN = ["network", "model", "other", "exited"];

/// A turn that failed for one of `AGAIN`'s reasons and waits on nothing: its notice offers 重试.
const failedAgain = (turn: { outcome: string | null; declared: string | null; detail: string | null }) =>
  turn.outcome === "failed" && turn.declared === null && AGAIN.some((reason) => (turn.detail ?? "").startsWith(`${reason}:`));

/// A turn that completed in no state after the station stopped asking it again (`giveUp`): its notice (回复即可继续)
/// offers 重试 too, as every notice that says a reply goes on does (the user, 2026-11-14).
const givenUp = (turn: { outcome: string | null; declared: string | null }) => turn.outcome === "completed" && turn.declared === null;

/// A turn cut off by a non-update station restart without a declared final state: its notice offers 重试 to resume.
export const cutOffByRestart = (turn: { outcome: string | null; declared: string | null; detail: string | null }) =>
  turn.outcome === "aborted" && turn.declared === null && turn.detail === "other: cut off by restart";

/// A turn its notice's 重试 takes up again.
export const retryable = (turn: { outcome: string | null; declared: string | null; detail: string | null }) =>
  failedAgain(turn) || givenUp(turn) || cutOffByRestart(turn);


export type TurnFor = { profile: string | null; person: string | null; thread: number | null };

/// A chat thread the running turn works for, with the message that brought it in: it is told what the turn does.
type Working = { connect: string; channel: string; threadTs: string; ts: string | null; firstTs?: string | null; since?: number };

/// What the actor needs of the store: the Rust Store's methods, camelCase (src/store/store.ts).
export type SessionStore = {
  hasPending(key: string): boolean;
  markDelivered(key: string, handed: Handed[]): void;
  markUndelivered(key: string, handed: Handed[]): void;
  untoldWidgetModels(key: string): any[];
  markWidgetModelsTold(key: string, pairs: [string, string][]): void;
  untoldCardChoices(key: string): CardChoice[];
  markCardChoicesTold(key: string, told: readonly CardChoice[]): void;
  /// What it is told once of its chat having moved here from a station retired (store.ts `untoldMovedNote`).
  untoldMovedNote?(key: string): string | null;
  markMovedNoteTold?(key: string): void;
  heardThreads(key: string, threads: number[]): Set<number> | number[];
  postsAfter(key: string, messages: readonly { thread: number; n: number }[]): (string | null)[];
  cardEndedByMessage(thread: number, n: number): [MessageRow, any] | null;
  pendingCard(thread: number): [MessageRow, any] | null;
  /// What a turn that said no state asked (actor_run.mbt `on_turn_ended`, mb-actor.ts `cardAsks`, `keepAsk`): the
  /// session's recent threads, an agent's question there, and whether a card there was closed since (ms).
  recentSessionThreads(session: string): { threads: { thread: { id: number } }[] };
  askingMessage(thread: number, about: number | null, during: [number, number]): [MessageRow, MessageRow[]] | null;
  cardClosedSince(thread: number, since: number): boolean;
  threadSessions(thread: number): { session: string; connect: string }[];
  /// Whether the session left this thread (chat_leave) and was not mentioned there since (optional: never without it).
  leftThread?(session: string, connect: string, channel: string, threadTs: string): boolean;
  getSession(key: string): any | null;
  hasTurns(key: string): boolean;
  toldNotes(key: string): number | null;
  setToldNotes(key: string, n: number): void;
  startTurnFor(id: string, key: string, kind: string, by: TurnFor): void;
  endTurn(id: string, outcome: string, detail: string | null, declared: string | null, wait: number | null): void;
  declareTurn(id: string, declared: string | null, wait: number | null): void;
  /// The turns a restart cut off, ended as aborted (store.ts `endCutOff`; optional: none ended without it).
  endCutOff?(key: string): number;
  setRunning(key: string, running: boolean): void;
  setSessionContextBefore(key: string, before: number | null): void;
  setRuntimeSessionId(key: string, id: string | null): void;
  /// Its runtime session compacted its context once more (optional: a store from before counts none).
  noteCompacted?(key: string): void;
  /// The runtime sessions it ran in, the first first (optional: none known without it).
  runtimeSessions?(key: string): string[];
  runtimeSessionSources?(key: string): { id: string; runtime: string; profile: string | null }[];
  runtimeSessionSource?(key: string, id: string): { id: string; runtime: string; profile: string | null } | null;
  setWaitFor(turn: string, what: string, watch: boolean): void;
  setNeed(turn: string, what: string): void;
  setAbout(turn: string, about: [number, number, string] | null): void;
  lastTurn(key: string): any | null;
  latestTurn?(key: string): { id: string; summary: any } | null;
  slackStop(session: string, connect: string, channel: string, threadTs: string): { ts: string; turn: string | null } | null;
  rememberSlackStop(session: string, connect: string, channel: string, threadTs: string, ts: string, turn: string | null): void;
  stopWait(key: string, refill?: boolean): void;
  forgetWait(key: string): void;
  hasSessionActiveWatch(session: string): boolean;
  latestThread(key: string): any | null;
  entriesBefore(thread: number, n: number | null, limit: number): any[];
  insertMessage(message: any): [number, boolean];
  notify(key: string): void;
};

/// A chat surface, as far as a session uses one (chat/mod.rs `ChatSurface`).
export type Surface = {
  post(thread: { channel: string; threadTs: string }, text: string, files: unknown[]): Promise<string>;
  userName?(user: string): Promise<string | null>;
  working?(thread: { channel: string; threadTs: string }, messageTs: string | null, status: string, page?: string | null): void;
  standsAt?(thread: { channel: string; threadTs: string }, stands: { kind: "done" | "need" | "left"; words: string | null } | null): void;
  mention?(user: string): string;
  botName?(): string;
  botUserId?(): string;
};

/// What a session needs of the station; the hub gives it.
export type SessionDeps = {
  store: SessionStore;
  /// What its process opening needs read first: its workspace's skills linked where it runs, its memory given back
  /// (`linkSkills`).
  linkSkills(row: any): Promise<string>;
  /// Pending messages and letters, merged as they are now, read off the station thread.
  pendingDeliveries(key: string, signal?: AbortSignal): Promise<PendingMessage[]>;
  /// Card state for a person's delivery, read off the station thread.
  deliveryCardState(thread: number, n: number, signal?: AbortSignal): Promise<DeliveryCardState | null>;
  /// An older store brings forward only the message ranges this delivery needs.
  preparePostsAfter?(messages: readonly { thread: number; n: number }[], signal?: AbortSignal): Promise<void>;
  prepareWidgetSources?(threads: readonly number[], signal?: AbortSignal): Promise<void>;
  chat(connect: string): Surface | undefined;
  driver(runtime: RuntimeKind): AgentDriver;
  /// The profile a session's runtime starts on now: its own while usable, else another that can take it on (`holding`:
  /// its process has work going in the background, kept on an account nearly full; `across`: before a turn, so another
  /// runtime's when none of its own can run it, accounts.ts `runOn`; `forceCap`: bypasses account concurrency caps).
  runOn(key: string, holding?: boolean, across?: boolean, forceCap?: boolean): Profile & { spelling?(model: string): string | null };
  /// A turn ran into the allowance of `ranOn`, the profile its process was started on (null: the session's own), or
  /// `model`'s own limit there (that model alone passed over on it): the profile left and the one moved to, when it moved,
  /// or `{ paused: "session_cap", ... }` when only capped accounts remain.
  spend(key: string, ranOn: string | null, model?: string | null): [string, string] | { paused: "session_cap"; profile: string; profileId: string; active: number; cap: number } | null;
  /// When session `key`'s profile, its allowance run out, is expected to run again (absent: in an hour).
  refillsAt?(key: string): number;
  /// A runtime failed to sign in on `profile`: it is checked again (the pool passes over one whose login is over);
  /// `force`: refused on it again in the same turn, its login taken as over.
  recheck?(profile: string, force?: boolean): Promise<void>;
  /// Read-only check whether a turn that failed with `auth` on `failedProfile` should automatically reopen and retry,
  /// `tried` the profiles it was refused on before in the same turn.
  canAuthRetry?(key: string, failedProfile: string, tried?: readonly string[]): boolean;
  /// A turn on `profile` failed with words that name no limit: what its allowance, asked again, says it ran into
  /// (accounts.ts `limitAfter`: a model's own limit by its name, null the account's, undefined none).
  limitAfter?(profile: string, model: string | null): Promise<string | null | undefined>;
  mcpUrl(): string;
  /// How many requests session `key`'s token made of the agents' MCP endpoint (mcp.ts `heard`); absent where unknown.
  toolsHeard?(key: string): number;
  reposDir(): string;
  /// Session `key`'s MEMORY.md: its workspace's (agent-home.ts `workspaceAgentHome`).
  memoryPath(key: string): string;
  /// What the deployment adds to every session's instructions (instructions.ts `readSiteInstructions`); none by default.
  siteInstructions?(): string;
  /// This station's name (what its agents are told they run on); "" where it has none.
  ownName?(): string;
  /// Whether moving to another station is on here (every station's; a test's may say not): its skill named in the instructions.
  moveOn?(): boolean;
  maxNudges(): number;
  /// The chat session `key` last heard from (its address), when it has no title and nobody is at work in it.
  untitled?(key: string): string | null;
  backgroundOnMessage(key: string): boolean;
  /// Where the runtime's live steps go, for whoever watches the session (and that it went on in a new runtime session).
  live?: { event(key: string, event: LiveEvent): void; turnEnded(key: string): Promise<void> | void; moved?(key: string): void };
  /// What it is told when it goes on on `to` in a new runtime session rather than take up `id` (last run on `was`, when
  /// the store does not know); null: it takes it up (sessions/afresh.ts).
  startsAfresh?(key: string, id: string, to: Profile, was: string | null): string | null;
  /// What a session whose context was cleared is told with its next prompt (sessions/afresh.ts `toldCleared`): to read
  /// back what it needs of its work too when `readBack` (cleared to go on afresh, as on another account).
  cleared?(key: string, readBack: boolean): string;
  /// Whether its next message or notice is to start it afresh, at `now` (sessions/afresh.ts `goesAfresh`): its chat or
  /// station set to, and its large context's prompt cache over.
  coldAfresh?(key: string, now: number): boolean;
  /// What a session whose runtime session could not be resumed is told with its next prompt (sessions/afresh.ts
  /// `toldResumeLost`), found off the station's thread.
  resumeLost?(key: string): string | Promise<string>;
  /// What a session compacted or gone on in a new conversation is told when its chats are long (sessions/afresh.ts
  /// `toldLongChat`): to read back what people said in them. Null when they are not.
  longChat?(key: string): string | null;
  /// Its subagents `ids` of runtime session `from`, stopped with its process, taken to runtime session `to` begun on
  /// `on`, so that they are taken up there (sessions/afresh.ts): the ids taken.
  carrySubagents?(from: string, to: string, on: Profile, ids: string[]): Promise<string[]>;
  /// The runtime session it runs in, on `profile` (null: not known).
  ranIn?(key: string, id: string, profile: string | null): void;
  idle(key: string): void;
  archiveIsCold(key: string): Promise<boolean>;
  restoreArchive(key: string): void | Promise<void>;
  /// An archived session's process is gone: its files may go to cold storage now (session.rs `clean_archive`).
  cleanArchive?(key: string): void | Promise<void>;
  /// A turn ended as its opener (an agent that opened its chat) is told: all_done or need_human with its words, or
  /// failed or stopped.
  settled?(key: string, state: "all_done" | "need_human" | "failed" | "stopped", words: string | null): void;
  /// Turns are held (the station is about to stop or hand over, or is out of the session's workspace): none starts,
  /// messages stay pending.
  held(key: string): boolean;
  /// What a chat stopped by a move answers, once a stop, as a person speaks in it (null: nothing now).
  stoppedNotice?(key: string): string | null;
  /// Stopped while it waits: ends the session's jobs that would bring it back.
  stopJobs(key: string): Promise<void>;
  /// Archived: ends every job and service of the session.
  endJobs(key: string): Promise<void>;
  toolStatus(tool: string): string;
  /// A session's page in still.fail, when the station is in a workspace: what a platform's status line points to.
  pageOf?(key: string): string | undefined;
  /// How a directory it is to run in is looked at (ops/places.ts); default: without still.fail Helper.
  places?: Places;
  /// Its runtime was not found on PATH as it started.
  runtimeMissing?(runtime: RuntimeKind): void;
  /// Updates the local Codex installation and waits until it can serve new turns.
  updateOldCodex?(runningVersion: string | null): Promise<void>;
  nextTs(): string;
  /// Its time (the hub's).
  clock: Clock.Clock;
};



/// What a next station takes up from this one (session.rs `HandedSession`, without the process: the runner keeps it).
export type Snapshot = {
  key: string;
  runtime: RuntimeKind;
  agent: unknown | null;
  turn: { id: string; authRetried: boolean; codexRetried?: boolean; by: TurnFor; declared: string | null; wait: number | null } | null;
  /// Undeclared turn end deferred while the session was held (optional: a station from before does not say).
  deferredEnd?: { lost: boolean; unheard?: boolean; recorded: string | null } | null;
  workingFor: Working[];
  notices: string[];
  waitingMs: number | null;
  waitingSeconds: number;
  nudges: number;
  stopRequested: boolean;
  /// Its allowance ran out with no account to move to: how long until it goes on (optional: a station from before
  /// it does not say).
  refillMs?: number | null;
  /// How long its process had been idle (optional: a station from before it does not say): taken up, it has been idle
  /// that long already, so a station updated often still ends idle processes (hub.ts `evictIdle`).
  idleMs?: number;
  /// Changed while busy (optional: a station from before it does not say).
  stale?: boolean;
  /// What it was changed in needs a new process, not one retuned (optional: a station from before it does not say).
  restart?: boolean;
  /// Its context was being compacted by hand (optional: a station from before it does not say).
  compacting?: boolean;
  /// Its process had not yet reached the station's tools as it was handed over (optional: a station from before does not say).
  toolsUnheard?: boolean;
  /// Its process made no tool requests before being nudged as it was handed over (optional: a station from before does not say).
  nudgeUnheard?: boolean;
  /// How many tools-lost restarts have already been attempted in this recovery sequence (optional: a station from before does not say).
  toolsRestarts?: number;
  /// Remaining backoff before a deferred toolsUnheard restart fires (optional: a station from before does not say).
  toolsRetryMs?: number | null;
  identity?: { model: string | null; effort: string | null; runtime: RuntimeKind } | null;
};

export const t = (key: string, args?: Record<string, unknown>) => tr(stationLang(), key, args);

let places: Places | null = null;
const defaultPlaces = () => (places ??= new Places());

/// The most of the agent's last words shown in its place.
export const FALLBACK_MOST = 4000;

/// A session's actor as the hub holds it: run by the MoonBit program (mb-actor.ts `MbActor`).
export type Actor = MbActor;

// ── what the actor asks of the station (mb-actor.ts answers the program with these) ────────────────────────────

/// The station's own words (not the agent's) go to the thread people spoke in last, and are recorded there; one about
/// a profile (`profile`, its id) is linked to that profile's page, one about a runtime not installed (`runtime`)
/// offers to install it; one that its run changed keeps how (`change`).
export async function postNotice(deps: SessionDeps, key: string, text: string, profile: string | null = null, runtime: RuntimeKind | null = null, recorded?: (where: [number, number, string]) => void, change?: RunChange) {
  const store = deps.store;
  const latest = store.latestThread(key);
  const chat = latest ? deps.chat(latest.connect) : undefined;
  if (!latest || !chat) {
    log.warn("session", "no thread to post a notice to", { session: key, text });
    return;
  }
  try {
    const ts = await chat.post({ channel: latest.thread.channel, threadTs: latest.thread.threadTs }, markNotice(text), []);
    const [n] = store.insertMessage({ thread: latest.thread.id, ts, authorKind: STATION_AUTHOR, author: STATION_AUTHOR, text, profile, runtime, attachments: [], quotes: [], declared: null, client: null, card: null, options: null, agentIdentity: null, ...(change !== undefined ? { change } : {}) });
    recorded?.([latest.thread.id, n, ts]);
  } catch (error) {
    log.warn("session", "notice failed", { session: key, error: (error as Error).message });
  }
}
/// What the thread people spoke in last ends with, where the station said it: nothing said since (actor.ts `saidLast`).
export function lastStationSaid(deps: SessionDeps, key: string): string | null {
  const latest = deps.store.latestThread(key);
  const last = latest ? deps.store.entriesBefore(latest.thread.id, null, 1).at(-1) : undefined;
  return last !== undefined && last.authorKind === STATION_AUTHOR ? last.text : null;
}

/// Its process takes how its session runs now in place, when it runs on the same profile (`profile`) and can: how it
/// runs then; else null (actor.ts `catchUp`).
export async function retuneAgent(deps: SessionDeps, key: string, session: AgentSession, runtime: RuntimeKind, profileNow: string | null, restart: boolean, holding: boolean) {
  const before = deps.store.getSession(key);
  let profile: ReturnType<SessionDeps["runOn"]> | null = null;
  try {
    profile = before ? deps.runOn(key, holding, true) : null;
  } catch {}
  // As it is now: moved to another runtime, its process cannot take it in place (it is ended and opened anew).
  const current = deps.store.getSession(key);
  const row = current && current.runtime === runtime ? current : undefined;
  const ready = row && profile && !restart && profile.id === profileNow && session.retune ? await deps.linkSkills(row) : "";
  if (!restart && row && profile && profile.id === profileNow && session.retune?.(await openOptions(row, profile, deps, ready))) {
    return { runtime, model: (row.model ?? null) as string | null, effort: (row.effort ?? null) as string | null };
  }
  return null;
}

/// How a session's runtime session is opened (actor.ts `ensureAgent`): `how`, what of the actor it needs.
export type OpenHow = {
  stopped: BackgroundTask[];
  readBack: boolean;
  /// the profile its process before ran on
  profile: string | null;
  /// bypasses account concurrency caps (manual jump-the-queue start)
  forceCap?: boolean;
  /// given up (a stop, a suspension, a close, its deadline: mb-actor.ts `cancelOpen`): it fails at once, a process that
  /// comes of it later ended, the session's row untouched
  signal?: AbortSignal;
  /// its runtime, once the session's row says it (before it is opened: what failing to start it is about)
  runtime(runtime: RuntimeKind): void;
  generation(): number;
  listener(generation: number): (event: RuntimeEvent) => void;
};

export type Opened = {
  session: AgentSession;
  generation: number;
  identity: { model: string | null; effort: string | null; runtime: RuntimeKind };
  profile: string;
  /// what it is told of going on afresh with its next prompt; its runtime session not resumed; its read-back told
  afresh: string | null;
  resumeLost: boolean;
  readBackTold: boolean;
  stoppedNote: string | null;
};

/// Opening a runtime session given up (`OpenHow.signal`).
export class OpenAborted extends Error {
  /// why (its signal's reason): "closed", "cancelled" (by the sessions' program), …
  readonly why: string;
  constructor(why = "cancelled") {
    super("open aborted");
    this.why = why;
  }
}

const abortedBy = (signal: AbortSignal) => new OpenAborted(typeof signal.reason === "string" ? signal.reason : "cancelled");

/// `opening`, a runtime session's process being opened, given up with `signal`: failing at once as it is, the process
/// that comes of it later ended.
function unlessAborted(opening: Promise<AgentSession>, signal: AbortSignal | undefined): Promise<AgentSession> {
  if (signal === undefined) return opening;
  const end = () => void opening.then((agent) => agent.dispose(), () => {}).catch(() => {});
  if (signal.aborted) {
    end();
    return Promise.reject(abortedBy(signal));
  }
  return new Promise((resolve, reject) => {
    const aborted = () => {
      end();
      reject(abortedBy(signal));
    };
    signal.addEventListener("abort", aborted, { once: true });
    opening.then(
      (agent) => {
        signal.removeEventListener("abort", aborted);
        // (given up meanwhile: `aborted` ends it)
        if (!signal.aborted) resolve(agent);
      },
      (error) => {
        signal.removeEventListener("abort", aborted);
        reject(signal.aborted ? abortedBy(signal) : error);
      },
    );
  });
}

/// Opens session `key`'s runtime session, as `how` has it (actor.ts `ensureAgent`).
export async function openAgent(deps: SessionDeps, key: string, how: OpenHow): Promise<Opened> {
  const told = { afresh: null as string | null, resumeLost: false, readBackTold: false, stoppedNote: null as string | null };
  if (await deps.archiveIsCold(key)) await deps.restoreArchive(key);
  const store = deps.store;
  const initial = store.getSession(key);
  if (!initial) throw new Error(`session ${key} disappeared`);
  const was = runtimeKind(initial.runtime);
  if (!was) throw new Error(`session ${key} runs an unknown runtime ${initial.runtime}`);
  how.runtime(was);
  // Its account first: none of its runtime's able to run it, it may go on on another runtime's (accounts.ts `runOn`),
  // whose driver then opens it, afresh.
  const profile = deps.runOn(key, false, true, how.forceCap === true);
  // (a login found over as it opens is said as the profile it is of, for the program to go on on another: mb-actor.ts
  // `errorOf`, actor_run.mbt `open_over`)
  try {
    const row = store.getSession(key);
    if (!row) throw new Error(`session ${key} disappeared`);
    const runtime = runtimeKind(row.runtime);
    if (!runtime) throw new Error(`session ${key} runs an unknown runtime ${row.runtime}`);
    if (runtime !== was) how.runtime(runtime);
    const driver = deps.driver(runtime);
    const memory = await deps.linkSkills(row);
    const base = await openOptions(row, profile, deps, memory);
    // Its context cleared by hand (clear): no runtime session now, those before on record. A new one, told so; one
    // continued from a terminal is given still.fail's instructions as a new session is (no cache of its own to keep).
    const wasCleared = row.runtimeSessionId === null && (store.runtimeSessions?.(key).length ?? 0) > 0;
    if (wasCleared && row.cwd) base.instructions = sessionInstructions(row.workspace, row.cwd, deps.reposDir(), deps.memoryPath(key), memory, deps.siteInstructions?.(), deps.ownName?.(), deps.moveOn?.() ?? true);
    // A runtime started where the station may not read exits at once with nothing to say why (macOS privacy protection
    // on a session continued in ~/Documents): told as it is instead. A directory someone named (one continued from a
    // terminal) is looked at as ops/places.ts does, never on this thread in a folder macOS protects (still.fail Helper
    // asked for it, its window put up for a grant it lacks); the session's own workspace is the station's.
    if (row.cwd) await (deps.places ?? defaultPlaces()).directory(row.cwd, { lang: stationLang() });
    else if (await unreadableDirAsync(base.cwd)) throw new Said(unreadableDirMessage(stationLang(), base.cwd));
    const generation = how.generation();
    let agent: AgentSession;
    // (its signal the driver's too: one opening again after a failure gives up with it, AgyDriver.begin)
    const open = (options: OpenOptions) => {
      if (how.signal?.aborted) return Promise.reject(abortedBy(how.signal));
      const withSignal = how.signal === undefined ? options : { ...options, signal: how.signal };
      return unlessAborted(driver.open(withSignal, how.listener(generation)), how.signal);
    };
    // Recorded before it may be left, so the history reads on from it.
    if (row.runtimeSessionId) deps.ranIn?.(key, row.runtimeSessionId, null);
    const afresh = row.runtimeSessionId ? (deps.startsAfresh?.(key, row.runtimeSessionId, profile, how.profile) ?? null) : null;
    // What its process before had going in the background, stopped with it: its subagents are taken up again in the
    // runtime session resumed, or taken to the new one.
    const stopped = how.stopped;
    const subagents = stopped.filter((t) => t.kind === "agent").map((t) => t.id);
    let resumable: string[] = [];
    if (afresh !== null) {
      log.info("session", "going on in a new runtime session on another account", { session: key, left: row.runtimeSessionId, profile: profile.id });
      agent = await open(base);
      told.afresh = afresh;
      const from = store.runtimeSessionSource ? store.runtimeSessionSource(key, row.runtimeSessionId!) ?? undefined
        : store.runtimeSessionSources?.(key).find((s) => s.id === row.runtimeSessionId);
      if (from === undefined || from.runtime === row.runtime) resumable = (await deps.carrySubagents?.(row.runtimeSessionId!, agent.id(), profile, subagents)) ?? [];
    } else if (row.runtimeSessionId) {
      try {
        agent = await open({ ...base, resume: row.runtimeSessionId });
        resumable = subagents;
      } catch (error) {
        // (given up, or timed out: nothing said of the conversation, which stays the session's)
        if (error instanceof OpenAborted || how.signal?.aborted) throw error;
        // Nothing wrong with the conversation (the network, the account, a borrowing): it stays the session's, opened
        // again with its next turn. Left for a new one, a long chat lost its whole conversation to a process that could
        // not reach its provider once (tokyo-mac-studio-0, 2026-11-16, as the machine came up).
        if (isNonSessionOpenError(error)) throw error;
        log.warn("session", "resume failed; starting a new runtime session", { session: key, id: row.runtimeSessionId, error: (error as Error).message });
        agent = await open(base);
        told.resumeLost = true;
      }
    } else {
      agent = await open(base);
      if (wasCleared) told.afresh = deps.cleared?.(key, how.readBack) ?? (how.readBack ? afreshNote(key, []) : cleared(key, []));
      told.readBackTold = true;
    }
    // (given up while its subagents were carried: ended, the session's row left as it was)
    if (how.signal?.aborted) {
      await agent.dispose().catch(() => {});
      throw abortedBy(how.signal);
    }
    // Recorded before it is the one gone on with: its conversation's calls are those from then (store.ts `conversationSince`).
    deps.ranIn?.(key, agent.id(), profile.id);
    if (row.runtimeSessionId !== agent.id()) {
      store.setRuntimeSessionId(key, agent.id());
      if (row.runtimeSessionId || wasCleared) deps.live?.moved?.(key);
    }
    if (stopped.length > 0) told.stoppedNote = backgroundStopped(stopped, resumable);
    return { ...told, session: agent, generation, identity: { runtime, model: row.model ?? null, effort: row.effort ?? null }, profile: profile.id };
  } catch (error) {
    if (error instanceof RenewRefused && error.profileId === null) error.profileId = profile.id;
    throw error;
  }
}

/// Whether opening a runtime session failed for something other than the conversation itself (`openAgent`): the
/// station's own words (`Said`: a sign-in not lent, a folder it may not read), its runtime not installed, or what the
/// failure says is the network, the account, the provider or a limit. Resuming again later may well work, so the
/// conversation is kept rather than left for a new one.
export function isNonSessionOpenError(error: unknown): boolean {
  if (error instanceof Said || error instanceof CommandMissing || error instanceof OpenAborted) return true;
  if ((error as { missing?: unknown } | null)?.missing === true) return true;
  // (its process not starting in time, the runner's or the runtime's own: nothing of the conversation)
  if (/timed out|did not start within/i.test((error as Error | null)?.message ?? String(error))) return true;
  const reason = failureOf((error as Error | null)?.message ?? String(error));
  return reason === "network" || reason === "auth" || reason === "refused" || reason === "blocked" || reason === "rate_limit" || reason === "overloaded";
}

/// What a turn is prompted with (actor.ts `startTurn`): what it is handed, after what it is told first (its resume
/// lost, what was stopped, a long chat, going on afresh, a session continued here, what changed in how it works since it
/// was last told), timed.
export async function promptFor(deps: SessionDeps, key: string, now: number, handed: string, lost: boolean, stopped: string | null, afresh: string | null, compacted: boolean): Promise<string> {
  const store = deps.store;
  const row = store.getSession(key);
  // A session begun in a terminal and continued here: its first turn here says so, with how still.fail works.
  const continued = row && row.cwd && !store.hasTurns(key) ? continuedHere(sessionInstructions(row.workspace, row.cwd, deps.reposDir(), deps.memoryPath(key), await deps.linkSkills(row), deps.siteInstructions?.(), deps.ownName?.(), deps.moveOn?.() ?? true)) : null;
  let prompt = lost ? `${(await deps.resumeLost?.(key)) ?? resumeLost(key, [])}\n\n${handed}` : handed;
  if (stopped !== null) prompt = `${stopped}\n\n${prompt}`;
  // Gone on in a new conversation, or compacted: in a long chat, told to read back what people said in it.
  const long = lost || afresh !== null || compacted ? (deps.longChat?.(key) ?? null) : null;
  if (long !== null) prompt = `${long}\n\n${prompt}`;
  if (afresh !== null) prompt = `${afresh}\n\n${prompt}`;
  if (continued !== null) prompt = `${continued}\n\n${prompt}`;
  // What changed in how it works since it was last told (migrations): once, before what it is handed.
  const told = store.toldNotes(key) ?? latestNote();
  if (told < latestNote()) {
    const full = row ? join(row.workspace, ".stillfail-instructions.md") : "";
    if (row) {
      try {
        const preset = row.cwd ? null : await presetCopyOf(row.workspace);
        const memory = await deps.linkSkills(row);
        await writeFile(full, sessionInstructions(row.workspace, row.cwd ?? null, deps.reposDir(), deps.memoryPath(key), memory, deps.siteInstructions?.(), deps.ownName?.(), deps.moveOn?.() ?? true) + (preset ? presetInstructions(preset) : ""));
      } catch {}
    }
    store.setToldNotes(key, latestNote());
    prompt = `${untold(told, full)}\n\n${prompt}`;
  }
  return timed(prompt, now);
}

export async function formatDelivery(deps: SessionDeps, key: string, said: any[], signal: AbortSignal): Promise<[string, [string, string][]]> {
  const store = deps.store;
  const threads: number[] = said.map((m) => m.message.thread);
  const heard = new Set(store.heardThreads(key, threads));
  const newThreads = new Set<number>(threads.filter((t) => !heard.has(t)));
  const names = new Map<string, string>();
  for (const m of said) {
    if (names.has(m.message.author)) continue;
    if (m.message.authorKind === "agent") {
      // A letter goes by the chat it came from, as its station marked it: its writer may be of another station.
      const letter = m.message.letter;
      names.set(m.message.author, letter?.way === "in" && letter.title !== "" ? letter.title : agentName(deps, m.message.author, m.message.thread));
      continue;
    }
    if (m.message.authorKind !== "person") continue;
    const name = await deps.chat(m.connect)?.userName?.(m.message.author);
    if (name) names.set(m.message.author, name);
  }
  // What the agent is called in each connect these came through: the bot's name there and its mention.
  const selves = new Map<string, string>();
  for (const m of said) {
    if (selves.has(m.connect)) continue;
    const chat = deps.chat(m.connect);
    const [name, user] = [chat?.botName?.() ?? "", chat?.botUserId?.() ?? ""];
    if (name !== "") selves.set(m.connect, user === "" ? name : `${name} (${chat?.mention?.(user) ?? `<@${user}>`})`);
  }
  // What it posted in a thread after a message there was said: the message was written without seeing that post.
  const posts = new Map<PendingMessage, string>();
  const fromChat = (said as PendingMessage[]).filter((m) => m.message.apart !== true);
  const positions = fromChat.map((m) => ({ thread: m.message.thread, n: m.message.n }));
  let laterPosts: (string | null)[];
  for (;;) {
    if (signal.aborted) throw new Error("delivery cancelled");
    try { laterPosts = store.postsAfter(key, positions); break; }
    catch (error) {
      if (!(error instanceof PostBlocksUnavailable) || !deps.preparePostsAfter) throw error;
      await deps.preparePostsAfter(error.positions, signal);
    }
  }
  fromChat.forEach((m, i) => { const ts = laterPosts[i]; if (ts !== undefined && ts !== null) posts.set(m, ts); });
  const cards = new Map<PendingMessage, { ended: DeliveryCardState["ended"]; current: DeliveryCardState["current"]; special: string | null }>();
  for (const m of said as PendingMessage[]) {
    if (m.message.apart === true || m.message.authorKind !== "person") continue;
    if (signal.aborted) throw new Error("delivery cancelled");
    const state = await deps.deliveryCardState(m.message.thread, m.message.n, signal);
    if (state === null) continue;
    const card = state.card;
    const special = typeof card?.vault?.request === "string" ? `Use secret_reask {request: ${JSON.stringify(card.vault.request)}} if the request is still needed.`
      : typeof card?.adb?.request === "string" ? `Use phone_use {reason: ${JSON.stringify(card.adb.reason ?? "")}, reask: true} if the request is still needed.`
      : typeof card?.signin?.site === "string" ? `Use sign_in {site: ${JSON.stringify(card.signin.site)}, reask: true} if the sign-in is still needed.`
      : card?.type === "login" ? "Check the login with its tool; if it still needs the person, post its login card again."
      : null;
    cards.set(m, { ended: state.ended, current: state.current, special });
  }
  const text = formatInbound(said, newThreads, names, selves, posts, cards, key);
  let models: any[];
  for (;;) {
    if (signal.aborted) throw new Error("delivery cancelled");
    try { models = store.untoldWidgetModels(key); break; }
    catch (error) {
      if (!(error instanceof WidgetSourcesUnavailable) || !deps.prepareWidgetSources) throw error;
      await deps.prepareWidgetSources(error.threads, signal);
    }
  }
  const widgets = models.map((w: any): [string, string] => [w.path, w.model]);
  const told = formatWidgetModels(models);
  return [told === "" ? text : text === "" ? told : `${text}\n\n${told}`, widgets];
}

/// `text` as the agent is handed it, after what people chose on its cards with an option that closes them (no message
/// was sent then, so it has not heard: store.ts closeCard), and what marks those told once it has been handed.
export async function handedWithChoices(deps: SessionDeps, key: string, now: number, text: string): Promise<[string, () => void]> {
  const store = deps.store;
  // (its chat moved here from a station retired: said once, before the rest)
  const moved = store.untoldMovedNote?.(key) ?? null;
  if (moved !== null) {
    const [rest, told] = await choicesWith(deps, key, now, text);
    return [rest === "" ? moved : `${moved}\n\n${rest}`, () => (told(), store.markMovedNoteTold?.(key))];
  }
  return choicesWith(deps, key, now, text);
}

async function choicesWith(deps: SessionDeps, key: string, now: number, text: string): Promise<[string, () => void]> {
  const store = deps.store;
  const chose = store.untoldCardChoices(key);
  if (chose.length === 0) return [text, () => {}];
  const names = new Map<string, string>();
  for (const c of chose) {
    if (names.has(c.by)) continue;
    const via = store.threadSessions(c.thread).find((m) => m.session === key)?.connect;
    const name = via === undefined ? undefined : await deps.chat(via)?.userName?.(c.by);
    if (name) names.set(c.by, name);
  }
  const said = formatCardChoices(chose, names, now);
  return [text === "" ? said : `${said}\n\n${text}`, () => store.markCardChoicesTold(key, chose)];
}

/// What another agent goes by in a thread: the bot of the connect it posts there through, with its mention; in the
/// station's own chats, its birth connect's bot name when born on an external connect, else its runtime and model.
function agentName(deps: SessionDeps, key: string, thread: number): string {
  const via = deps.store.threadSessions(thread).find((m) => m.session === key)?.connect;
  const row = deps.store.getSession(key);
  const externalVia = via && via !== INTERNAL_CONNECT ? via : undefined;
  const connect = externalVia ?? (row && row.connect !== INTERNAL_CONNECT ? row.connect : undefined);
  const chat = connect ? deps.chat(connect) : undefined;
  const name = chat?.botName?.() ?? "";
  if (name !== "") {
    if (externalVia !== undefined) {
      const user = chat?.botUserId?.() ?? "";
      return user === "" ? name : `${name} (<@${user}>)`;
    }
    return name;
  }
  return row ? `${runtimeLabel(runtimeKind(row.runtime) ?? "claude")}${row.model ? ` ${row.model}` : ""}` : "another agent";
}


/// How a session's runtime session is opened (or taken up) on `profile`: its directory, model as the profile spells it,
/// effort, instructions and MCP token.
/// What a session's process opening needs off the station's thread, before `openOptions`: its workspace's skills where
/// it runs (agent-home.ts), kept up with each time it is opened or retuned (a session continued from a terminal runs in
/// the person's own project, given none), and its workspace's memory as it is now, which it gives back.
export async function linkSkills(row: any, deps: Pick<SessionDeps, "memoryPath">): Promise<string> {
  const memory = readMemory(deps.memoryPath(row.key));
  if (!row.cwd) {
    try {
      await sessionSkills(row.workspace, join(dirname(deps.memoryPath(row.key)), "skills"));
    } catch (error) {
      log.warn("session", "its workspace's skills not linked where it runs", { session: row.key, error: (error as Error).message });
    }
  }
  return memory;
}

/// `memory`: its workspace's memory as `linkSkills` gave it.
export async function openOptions(row: any, profile: Profile & { spelling?(model: string): string | null }, deps: Pick<SessionDeps, "mcpUrl" | "reposDir" | "memoryPath" | "siteInstructions" | "ownName" | "moveOn">, memory: string): Promise<OpenOptions> {
  const skills = row.cwd ? undefined : join(dirname(deps.memoryPath(row.key)), "skills");
  // The model as this profile spells it (openai/gpt-6-astra on a router for gpt-6-astra).
  const model = row.model ? (profile.spelling?.(row.model) ?? row.model) : undefined;
  // What its chat was opened with (presets.ts): told after the station's own instructions (its folders' skills are in
  // its workspace already).
  const preset = row.cwd ? null : await presetCopyOf(row.workspace);
  return {
    key: row.key,
    profile,
    cwd: row.cwd ?? row.workspace,
    model,
    effort: row.effort ?? undefined,
    ...(typeof row.context === "number" ? { context: row.context } : {}),
    ...(row.tui ? { tui: true } : {}),
    ...(typeof row.fast === "boolean" ? { fast: row.fast } : {}),
    // A session continued from a terminal keeps the system prompt it began with (its cache holds).
    instructions: row.cwd ? "" : sessionInstructions(row.workspace, null, deps.reposDir(), deps.memoryPath(row.key), memory, deps.siteInstructions?.(), deps.ownName?.(), deps.moveOn?.() ?? true) + (preset ? presetInstructions(preset) : ""),
    ...(skills !== undefined ? { skills } : {}),
    mcpToken: row.token,
    mcpUrl: deps.mcpUrl(),
    route: row.key,
  };
}


export const SPENT_BEFORE = ["⚠️ 已达到额度或速率限制", "⚠️ Hit a usage or rate limit"];


/// Codex relays the provider's exact refusal inside its error message, sometimes wrapped in a JSON response.
export const codexTooOld = (message: string) => /\bmodel requires a newer version of Codex\.\s*Please upgrade to the latest app or CLI and try again\./i.test(message);

/// A failed turn as its chat is told it: what it means and what to do, by its reason, on its first line (what a
/// notice shows closed, and a push says); what the runtime said after it, as it said it (`withSaid`). A reason the
/// station cannot put in words of its own (the model's, any other) has the runtime's first line in it: "模型服务出错"
/// alone told people nothing (2026-11-05). A model's own limit names the model: "额度已用完" beside quota bars with room
/// left read as a mistake (#4365).
export function failureNotice(outcome: TurnOutcome): string {
  if (outcome.kind !== "failed") return "";
  const model = outcome.reason === "rate_limit" ? modelLimitOf(outcome.message) : null;
  if (model !== null) return `⚠️ ${withSaid(t("station.notice.modelLimit", { model }), outcome.message)}`;
  const key = outcome.reason === "rate_limit" ? "rateLimit" : outcome.reason === "other" ? "failed" : outcome.reason;
  const why = outcome.reason === "model" || outcome.reason === "other" ? firstLine(outcome.message) : "";
  return `⚠️ ${withSaid(why === "" ? t(`station.notice.${key}`) : t(`station.notice.${key}Why`, { why }), outcome.message)}`;
}

/// How a turn's detail begins where its failure's words named no limit and its allowance asked again showed one: the
/// model's name whose own limit it is, or nothing for the account's, then ": " and what failed said. Its notice offers
/// 重新分配账号 (`reassign`), not 重试: on the same account it would fail again.
export const LIMIT_SHOWN = "limit:";

/// What a turn's detail says its allowance showed (`LIMIT_SHOWN`): the model's own limit by its name, null the
/// account's, undefined none.
export function shownLimitOf(detail: string | null): string | null | undefined {
  if (detail === null || !detail.startsWith(LIMIT_SHOWN)) return undefined;
  const end = detail.indexOf(": ", LIMIT_SHOWN.length);
  const name = detail.slice(LIMIT_SHOWN.length, end < 0 ? undefined : end);
  return name === "" ? null : name;
}

/// The notice of such a failure: what the allowance shows, and the press that moves it (`reassign`).
export function limitShownNotice(model: string | null, said: string): string {
  return `⚠️ ${withSaid(model === null ? t("station.notice.limitShownAccount") : t("station.notice.limitShown", { model }), said)}`;
}

/// The first line of what failed said, short enough for a notice's line and a push.
function firstLine(said: string): string {
  const line = said.trim().split("\n")[0]!.trim();
  return line.length > FIRST_LINE ? `${line.slice(0, FIRST_LINE - 1).trimEnd()}…` : line;
}
const FIRST_LINE = 200;

/// `words`, and under them what failed said itself (a provider's, a process's, in its own words), as a code block: a
/// notice opened shows it, for whoever wants to see the error as it was (2026-11-03).
export function withSaid(words: string, said: string): string {
  const raw = said.trim().replace(/```/g, "ʼʼʼ");
  return raw === "" ? words : `${words}\n\n\`\`\`\n${raw}\n\`\`\``;
}

/// That its compaction failed, as its chat is told it.
export function compactFailedNotice(outcome: TurnOutcome & { kind: "failed" }): string {
  // Claude Code's own reason for compacting nothing is one people can act on.
  const why = /not enough messages/i.test(outcome.message) ? t("station.context.tooShort") : failureWords(outcome.reason);
  return `⚠️ ${withSaid(t("station.notice.compactFailed", { why }), outcome.message)}`;
}

/// A failure's reason in a few words, after what failed ("Couldn't compact the context: …").
const failureWords = (reason: FailureReason) => t(`station.failure.${reason === "rate_limit" ? "rateLimit" : reason}`);

/// Why its agent could not start, as its chat is told it: the station's own words as they are (`Said`); else what the
/// error means where that is the account, the provider or the network, and otherwise only that it could not.
export function cannotStartWords(error: unknown): string {
  if (error instanceof Said) return t("station.notice.cannotStartWhy", { why: error.message });
  const reason = failureOf((error as Error)?.message ?? "");
  const words = reason === "auth" || reason === "refused" || reason === "blocked" || reason === "network" ? t("station.notice.cannotStartWhy", { why: failureWords(reason) }) : t("station.notice.cannotStart");
  return withSaid(words, (error as Error)?.message ?? "");
}

/// Compaction that could not begin, in words: the station's own as they are, else what kind of failure it was.
export function compactFailed(error: unknown): string {
  if (error instanceof Said) return t("station.notice.compactFailed", { why: error.message });
  log.warn("session", "compaction could not begin", { error: (error as Error)?.message ?? String(error) });
  return t("station.notice.compactFailed", { why: failureWords(failureOf((error as Error)?.message ?? "")) });
}

/// Who wrote a message, as a creator reference: their email on the page, their Slack user through the connect it came by.
export const personRef = (m: any) => (m.surface === STILLFAIL_SURFACE ? m.message.author : `slack:${m.connect}:${m.message.author}`);
