package dev.mbui;

import android.content.Context;
import android.opengl.GLSurfaceView;
import android.os.Looper;
import android.icu.text.BreakIterator;
import android.text.Editable;
import android.text.InputType;
import android.text.Selection;
import android.view.Choreographer;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.ViewTreeObserver;
import android.view.inputmethod.BaseInputConnection;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;
import android.view.inputmethod.InputMethodManager;

import java.util.ArrayDeque;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * The surface the MoonBit app draws on. Everything MoonBit runs on the app's
 * own thread (the logic thread, one for the process: its frames there, and
 * input handed to it); the GL context is the GL thread's, which draws each
 * frame the app made and swaps it. A GPU slowed by its heat, or a display's
 * buffers all taken, holds only the GL thread in eglSwapBuffers: the app goes
 * on taking the touches and laying out the next frame meanwhile, and the GL
 * thread draws the newest it was handed (the frame waiting: android_host.c),
 * never a queue of old ones. What the app asks of the GL context (a picture's
 * texture made, a stream's frame latched) is put on the GL thread's queue
 * (toRender) in its order among the frames: done before the frame handed over
 * after it is drawn, and after the one handed over before it; what lets go of
 * what a frame draws, once a frame handed over after it is on the screen
 * (toRetire). FrameMail keeps what the two threads hand each other. Frames are
 * paced by the display's vsync (Choreographer), one per vsync at most, each
 * told that vsync's time, as Compose's frames are: a frame asked for while
 * touches are handled (the input phase of a vsync) is made at that vsync, one
 * asked for by a frame (an animation) at the next; the system's back, said in
 * a vsync's animation phase, is made by the next (back()). A run to a declared
 * moment (Host.shotAt) and mbui-render's (MBUI_DL) make and draw each frame on
 * the GL thread, as one did before (ONE).
 */
public class MBView extends GLSurfaceView implements GLSurfaceView.Renderer {
    private static boolean started;  // MoonBit's main runs once per process
    /**
     * Whose GL context the host's drawing (its programs, textures, atlas: android_host.c) was last set up in: a count,
     * each view's own set when it set it up. Two views (MainActivity's and an OverActivity's) each have a context of
     * their own; one drawn after the other set it up in its own sets it up again in its own first.
     */
    private static int setUp;
    private int mine;
    final float density;

    /**
     * The app made and drawn on the GL thread alone, as before there were two (a run to a declared moment: its frames
     * on a clock of their own, each drawn as it is made; mbui-render's, whose MoonBit main holds that thread while it
     * draws): decided as the first view is made, once the activity has taken its hooks (MainActivity).
     */
    static boolean ONE;
    private static boolean decided;

    /** The app's thread (null with ONE): MoonBit's frames, input and what it is told run here, one at a time. */
    private static android.os.HandlerThread logicThread;
    private static android.os.Handler logic;
    private static int logicTid;

    public MBView(Context c) {
        super(c);
        density = c.getResources().getDisplayMetrics().density;
        if (!decided) {
            decided = true;
            ONE = Host.shotAt >= 0 || System.getenv("MBUI_DL") != null;
            if (!ONE) {
                logicThread = new android.os.HandlerThread("mbui-logic", android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY);
                logicThread.start();
                logic = new android.os.Handler(logicThread.getLooper());
                logic.post(() -> logicTid = android.os.Process.myTid());
            }
        }
        setEGLContextClientVersion(3);
        setEGLConfigChooser(8, 8, 8, 8, 0, 0);
        // On top of the window, translucent: the app over another app (OverActivity) draws over that app, nothing of
        // its own ground; native views (NativeViews: a player, a page) are drawn in it, by their pictures.
        getHolder().setFormat(android.graphics.PixelFormat.TRANSLUCENT);
        setZOrderOnTop(true);
        setPreserveEGLContextOnPause(true);
        setRenderer(this);
        setRenderMode(RENDERMODE_WHEN_DIRTY);
        setFocusable(true);
        setFocusableInTouchMode(true);
    }

    /** The app's widgets for Android's accessibility (A11y): made as the app first tells them. */
    private A11y a11y;

    A11y a11y() {
        if (a11y == null) a11y = new A11y(this);
        return a11y;
    }

    @Override
    public android.view.accessibility.AccessibilityNodeProvider getAccessibilityNodeProvider() {
        if (!A11y.isScreenReaderOn()) return null;
        return a11y != null && a11y.any() ? a11y : super.getAccessibilityNodeProvider();
    }

    @Override
    protected boolean dispatchHoverEvent(android.view.MotionEvent e) {
        // a finger exploring the screen with a screen reader on: the widget under it (A11y)
        if (A11y.isScreenReaderOn() && a11y != null && a11y.any() && a11y.hover(e)) return true;
        return super.dispatchHoverEvent(e);
    }

    /** A login form of a site the app asks the autofill service for, while it does (Autofills); none else. */
    @Override
    public void onProvideAutofillVirtualStructure(android.view.ViewStructure structure, int flags) {
        Autofills.provide(this, structure);
    }

    /** The login the autofill service filled into that form (Autofills). */
    @Override
    public void autofill(android.util.SparseArray<android.view.autofill.AutofillValue> values) {
        Autofills.filled(values);
    }

    // ---- its surface (main thread) ----

    /** Whether its GL thread draws: its surface there and the view not paused (onStop to onResume). */
    private volatile boolean glAlive, paused;

    /** Its surface made: the streams' layers (StreamLayer) put under it, where it is the host's. */
    @Override
    public void surfaceCreated(android.view.SurfaceHolder holder) {
        super.surfaceCreated(holder);
        if (Host.view == this) StreamLayer.parentFrom(this);
    }

    /** Its surface gone: the streams' layers off the screen with it (kept, to be put under the next). */
    @Override
    public void surfaceDestroyed(android.view.SurfaceHolder holder) {
        glAlive = false;
        StreamLayer.parentGone(this);
        super.surfaceDestroyed(holder);
    }

    /** Its drawing paused (MainActivity's onStop): the app makes no frame for it till it is resumed. */
    @Override
    public void onPause() {
        paused = true;
        if (settleScheduled.getAndSet(false)) {
            Host.main.post(() -> Choreographer.getInstance().removeFrameCallback(settleVsync));
        }
        pacer.setImeMoving(false);
        // queued before the GL thread pauses (it takes its queue first): its context still current there
        trim();
        if (!ONE && logic != null) {
            logic.post(this::closeHints);
        } else {
            queueEvent(this::closeHints);
        }
        super.onPause();
    }

    /** Its drawing resumed: ADPF session recreated before the first frame so PowerHAL raises uclamp promptly. */
    @Override
    public void onResume() {
        super.onResume();
        paused = false;
        if (!ONE && logic != null) {
            logic.post(this::wakeHints);
        } else {
            queueEvent(this::wakeHints);
        }
        wantFrame();
    }

    /**
     * What drawing holds beyond its frames given back on the GL thread (android_host.c's mb_render_trim: glass's
     * textures, the read back's framebuffer), made again as a frame needs them. Only with the context current there:
     * paused, the GL thread lets its surface go and nothing is current (the context, kept, keeps them till then).
     */
    void trim() {
        queueEvent(() -> {
            if (android.opengl.EGL14.eglGetCurrentContext() != android.opengl.EGL14.EGL_NO_CONTEXT) Native.trim();
        });
    }

    // ---- the app's thread ----

    /** {@code r} run on the app's thread (MoonBit's), after what is there now: the GL thread's with ONE. */
    static void onApp(Runnable r) {
        if (logic != null) {
            logic.post(r);
            return;
        }
        MBView v = Host.view;
        if (v != null) v.queueEvent(r);
    }

    /** Runs r on the app's thread and asks for a frame. */
    void toApp(Runnable r) {
        onApp(r);
        wantFrame();
    }

    // ---- the GL thread's queue: what the app asks of the GL context, in its order among the frames ----

    /** The frame waiting, the GL thread's queue and what is let go once no frame on the screen uses it (FrameMail). */
    private static final FrameMail<MBText.Placed> mail = new FrameMail<>(new FrameMail.Frames<MBText.Placed>() {
        @Override public boolean publish() { return Native.publish(); }

        @Override public boolean take(boolean shown) { return Native.take(shown); }

        @Override public void dropPending() { Native.dropPending(); }

        @Override public int built() { return Latency.frameBuilt(); }

        @Override public void merged(int from, int to) { Latency.merged(from, to); }

        @Override public String frameName() { return MBText.takeFrameName(); }

        @Override public void dropped(java.util.List<MBText.Placed> glyphs) {
            for (MBText.Placed g : glyphs) g.release();
        }

        @Override public void failed(RuntimeException e) {
            Host.log("gl: " + e);
            android.util.Log.e("mbui", "gl task", e);
        }
    });

    /**
     * {@code r} run on the GL thread (its context current): after the frames handed over before it are drawn, before
     * those handed over after it (from the app's thread: a texture made; a stream's frame latched for the frame that
     * shows it); from another thread (a picture decoded), as soon as it can. With ONE, the GL thread's queue as it was.
     */
    static void toRender(Runnable r) {
        MBView v = Host.view;
        if (ONE) {
            if (v != null) v.queueEvent(r);
            return;
        }
        mail.task(r);
        if (v != null) v.queueEvent(MBView::glTasksDue);
    }

    /**
     * {@code r}, which lets go of what a frame draws (a picture's texture, a native view's, a stream's), run on the GL
     * thread once a frame the app's thread hands over after it is drawn on the screen: the frame kept till then is
     * drawn again as a native view's picture changes or the surface asks, and still draws it (FrameMail.retire). With
     * ONE, after the frame being made, which is drawn as it is made.
     */
    static void toRetire(Runnable r) {
        if (ONE) {
            MBView v = Host.view;
            if (v != null) v.queueEvent(r);
            return;
        }
        mail.retire(r);
    }

    /**
     * The tasks of the GL thread's queue that may run now: all those before the frame pending (all of them, none). Not
     * while its context is not current (the view paused: its events still run, its surface let go): the next frame
     * drawn does them, where the app's thread made them while it was (a stream's frame latched on a SurfaceTexture of
     * a context not current fails).
     */
    private static void glTasksDue() {
        if (!glCurrent()) return;
        mail.runTasks(mail.pendingSeqNow());
    }

    /** Whether a GL context is current on this thread. */
    private static boolean glCurrent() {
        return android.opengl.EGL14.eglGetCurrentContext() != android.opengl.EGL14.EGL_NO_CONTEXT;
    }

    // ---- GL thread ----

    @Override
    public void onSurfaceCreated(GL10 gl, EGLConfig config) {
        drawingThread();
        boolean lost = Native.surfaceCreated();
        NativeViews.textureMostRead();
        mine = ++setUp;
        glAlive = true;
        if (ONE) {
            MBText.reset();
            if (!started) {
                started = true;
                // (a run to a declared moment: the app's clock is its frames' from the start, shotFrame below)
                if (Host.shotAt >= 0) Native.ownClock();
                Native.start();
            }
            return;
        }
        contextMade(lost);
        if (!started) {
            started = true;
            Native.twoThreads();
            logic.post(Native::start);
        }
        // (the first frame the app makes, waited for a while before the surface is shown without one: frameFirst)
        fresh = 1000;
    }

    /**
     * Drawing set up in a context made anew (GL thread): what the app's thread keeps of what was in the old one let go
     * there (the glyphs' places in the atlases, MBText.reset; the images' textures, to be told again as each is
     * uploaded anew: Native.imagesUntold, then decoded again), and a frame of the app's made, drawn whole. No frame
     * made before the app's thread let go of the old atlas is drawn in the new context (FrameMail.contextMade).
     */
    private void contextMade(boolean lost) {
        // (the frame waiting let go: its glyphs are in the old atlas; so are those of any the app hands over till it is
        // told, FrameMail)
        long gen = mail.contextMade();
        logic.post(() -> {
            MBText.reset();
            if (lost) {
                Native.imagesUntold();
                // (decoded again after the told are cleared: an upload's telling can only come after, on this thread)
                Images.reload();
            }
            mail.contextTold(gen);
            pacer.appWanted.set(true);
            wantFrame();
        });
    }

    @Override
    public void onSurfaceChanged(GL10 gl, int w, int h) {
        // a surface again, its context kept from before it went (setPreserveEGLContextOnPause: onSurfaceCreated is not
        // told again as the app comes back from the background), so the GL thread draws again from here
        glAlive = true;
        Native.resize(w, h);
        // (a new surface, told after it is made, or the same at another size: whatever was said of the rate, nothing said)
        if (ONE) {
            pacer.sayRate(false);
            return;
        }
        logic.post(() -> pacer.sayRate(false));
        // (the frame of the new size waited for a while: the one the surface shows next is the app's at that size)
        fresh = Math.max(fresh, 100);
        wantFrame();
    }

    /**
     * How long the next frame drawn waits for one the app makes (ms; 0: none): the first a surface shows, and one at a
     * new size, are the app's made for it, not the frame kept (none yet, or at the old size) drawn again. A while at
     * most: the app's thread may be busy (a long first frame), or wait on this thread itself (glSync).
     */
    private int fresh;

    /** Which vsync the next frame is made for, and the rate the surface says of the display (FramePacer). */
    private final FramePacer pacer = new FramePacer(new FramePacer.Platform() {
        @Override public long nanoTime() { return System.nanoTime(); }

        @Override public boolean onMain() { return Looper.myLooper() == Looper.getMainLooper(); }

        @Override public void postMain(Runnable r) { Host.main.post(r); }

        @Override public void postVsync() { postVsync.run(); }

        @Override public void atNextVsyncOnDrawing(Runnable r) {
            Host.main.post(() -> Choreographer.getInstance().postFrameCallback(t -> onApp(r)));
        }

        @Override public void requestRender() { makeFrame(); }

        @Override public boolean setRate(float rate) { return surfaceRate(rate); }

        @Override public boolean typing() { return MBView.typing(); }
    });

    /** A frame made as soon as the app's thread can (FramePacer's requestRender): drawn on the GL thread with ONE. */
    private final java.util.concurrent.atomic.AtomicBoolean making = new java.util.concurrent.atomic.AtomicBoolean();

    private void makeFrame() {
        if (ONE) {
            requestRender();
            return;
        }
        if (making.compareAndSet(false, true)) logic.post(this::frameOnApp);
    }

    // A picture at a declared moment (Host.shotAt, --ei shot_at MS: scripts/shots.sh android): the run's frames are on
    // a clock of their own, 1/60 s a frame from 0, as a stable run's on macOS (mac_app.m) and the browser's
    // (web/host.js shot_at), each drawn at the next vsync whether the app asks for it or not, until that clock reaches
    // MS; that frame drawn, no other ("SHOT n t" on the log: adb's screencap takes it), and a frame the system asks
    // for after it drawn at the same moment. The clock stands still while the app awaits the host (an image decoding:
    // what its last frame said), so the picture is of the app at MS on its own clock, however fast the machine is.
    // Never "once the app is at rest": that is settling by another name (a moment is declared, or a drive waits for the
    // page's own named event). Both on the GL thread (ONE).
    private double shotClock;
    private int shotFrames;
    private volatile boolean shotTaken;

    private void shotFrame(float w, float h) {
        double t = shotClock;
        takeBacks(Long.MAX_VALUE);
        Native.frame(w, h, density, t, 0);
        // (a run to a moment: the native views' frames put where they show at once)
        NativeViews.framed(false);
        Script.frameDrawn();
        if (shotTaken) return;
        shotFrames++;
        // (the run's way to its moment said every half second of its clock: a machine drawing slowly, the emulator's
        // software renderer on a runner's CPU, is told from one that stopped by these, not by how long it took)
        if (shotFrames % 30 == 0) Host.log("shot: frame " + shotFrames + " at " + t);
        if (Native.awaiting() > 0) {
            // the clock stands still; the host's answer asks for the next frame
            return;
        }
        if (t >= Host.shotAt) {
            shotTaken = true;
            // said once it is on the screen: swapped as this returns, taken by the compositor at the next vsync,
            // shown by the one after
            final String said = "SHOT " + shotFrames + " " + t;
            // (and not before the window is the one shown: the system's starting window, its splash, is over the
            // app's until the app's has drawn and taken the focus, a picture as early as the first frame would be of
            // the splash; and the system fades that out after it, so a picture is taken once its window is gone too:
            // scripts/android.sh shown)
            Runnable say = () -> Choreographer.getInstance().postFrameCallback(a ->
                    Choreographer.getInstance().postFrameCallback(b -> Host.log(said)));
            Host.main.post(() -> {
                if (hasWindowFocus()) {
                    say.run();
                    return;
                }
                // (said, so a picture that never comes is told by what it waits for)
                Host.log("shot: " + said.substring(5) + " waits for the window's focus");
                getViewTreeObserver().addOnWindowFocusChangeListener(new ViewTreeObserver.OnWindowFocusChangeListener() {
                    @Override
                    public void onWindowFocusChanged(boolean focused) {
                        if (!focused) return;
                        getViewTreeObserver().removeOnWindowFocusChangeListener(this);
                        say.run();
                    }
                });
            });
            return;
        }
        shotClock = shotFrames * (1000.0 / 60.0);
        wantFrame();
    }

    @Override
    public void onDrawFrame(GL10 gl) {
        // a view not the host's (its activity paused under another of the app's: an OverActivity's draws), kept as it
        // last drew: one thread draws the app at a time
        if (Host.view != this) return;
        if (!ONE) {
            drawOnGl();
            return;
        }
        Latency.frameBegins();
        boolean app = pacer.appWanted.getAndSet(false), pictured = pacer.picturesOnly.getAndSet(false);
        // another view set the drawing up in its own context since this one did (an OverActivity came and went): set
        // up again here, at this view's size
        if (mine != setUp) {
            Native.surfaceCreated();
            MBText.reset();
            Native.resize(getWidth(), getHeight());
            mine = ++setUp;
            app = true;
        }
        // the native views' pictures come since the last frame, for this one to draw where it shows them
        NativeViews.latch();
        // the soft keyboard's height off the bottom (Host.imeBottom, as it moves): the app lays out above it, the
        // surface keeps its size (resizing it with each step of the keyboard's motion would be far too slow)
        float w = getWidth() / density, h = Math.max(1, getHeight() - Host.imeBottom) / density;
        if (Host.shotAt >= 0) {
            shotFrame(w, h);
            return;
        }
        // only a view's picture changed (pictureFrame): the last frame drawn again with it, the app not asked; a frame
        // the app or the system asked for is the app's
        long[] at = pacer.vsyncAt();
        if (pictured && !app) {
            Native.redraw();
            showAt(at[1]);
            NativeViews.framed(false);
            pacer.redrawn();
            Latency.frameEnds(Latency.frameBuilt());
            return;
        }
        long began = System.nanoTime();
        FramePacer.Begun b = pacer.begin(at, began);
        // the system's back said before this frame's vsync (back(), below); what was said after it, the next frame's
        boolean later = takeBacks(b.vsync != 0 ? b.vsync : began);
        // (what it waits for said again by the frame, if it still does: Host.wakeAfter, from its time)
        wakeFor = -1;
        buildingFor = b.now;
        pacedRate = 0;
        boolean more = Native.frame(w, h, density, b.now, b.late);
        buildingFor = -1;
        // (a stream's frame shown in it whose view did not move: put on its layer now, StreamLayer.show)
        StreamLayer.frameEnded();
        showAt(b.shows);
        pacer.ended(more, later, b.following, pacedRate);
        // (the native views moved in it: their frames follow once they rest)
        NativeViews.framed(more || later);
        Script.frameDrawn();
        frameWorked(System.nanoTime() - began, 0);
        Latency.frameEnds(Latency.frameBuilt());
    }

    /**
     * A frame of the app's made (its thread, as the pacer asks: FramePacer's requestRender), as the GL thread made one
     * with ONE (onDrawFrame above), and handed over to be drawn (handOver); only the last drawn again where only a
     * native view's picture changed. None while its drawing is paused, or it is not the host's: asked for again as it
     * is resumed (onResume).
     */
    private void frameOnApp() {
        making.set(false);
        if (Host.view != this || paused) return;
        Latency.frameBegins();
        boolean app = pacer.appWanted.getAndSet(false), pictured = pacer.picturesOnly.getAndSet(false);
        final int imeUsed = Host.imeBottom;
        float w = getWidth() / density, h = Math.max(1, getHeight() - imeUsed) / density;
        long[] at = pacer.vsyncAt();
        if (pictured && !app) {
            if (mail.redrawAsked(at[1])) requestRender();
            NativeViews.framed(false);
            pacer.redrawn();
            return;
        }
        long began = System.nanoTime();
        FramePacer.Begun b = pacer.begin(at, began);
        boolean later = takeBacks(b.vsync != 0 ? b.vsync : began);
        wakeFor = -1;
        buildingFor = b.now;
        pacedRate = 0;
        boolean more = Native.frame(w, h, density, b.now, b.late);
        buildingFor = -1;
        // (a stream's frame shown in it whose view did not move: put on its layer now, StreamLayer.show)
        StreamLayer.frameEnded();
        handOver(b.shows);
        pacer.ended(more, later, b.following, pacedRate);
        NativeViews.framed(more || later);
        frameWorked(System.nanoTime() - began, glWorked);
        if (Host.imeBottom != imeUsed && Host.view == this && !paused) {
            pacer.appWanted.set(true);
            makeFrame();
        }
    }

    /**
     * The frame the app made handed over to the GL thread (the app's thread), to be shown at {@code shows}: with the
     * glyphs it put in the atlases, the picture of it asked (MBText.refFrame) and its frame of a latency run; one still
     * waiting there replaced by it (FrameMail.handOver).
     */
    private void handOver(long shows) {
        if (mail.handOver(shows, MBText.placed)) requestRender();
    }

    /** VSync-paced settle wakeup for adaptive glass (main thread Choreographer -> GLThread requestRender). */
    private final java.util.concurrent.atomic.AtomicBoolean settleScheduled = new java.util.concurrent.atomic.AtomicBoolean();
    private final Choreographer.FrameCallback settleVsync = t -> {
        settleScheduled.set(false);
        if (!paused && Host.view == this && Native.adaptiveSettling()) requestRender();
    };

    private void scheduleAdaptiveSettle() {
        if (paused) return;
        if (settleScheduled.compareAndSet(false, true)) {
            Host.main.post(() -> {
                if (paused || Host.view != this) {
                    settleScheduled.set(false);
                    return;
                }
                Choreographer.getInstance().postFrameCallback(settleVsync);
            });
        }
    }

    /** The GL thread's time drawing the last frame (ns), told to the system with the app's (frameWorked). */
    private volatile long glWorked;

    // Pending post-eglSwapBuffers timing (GL thread only): GLSurfaceView.GLThread drains mEventQueue right after
    // mEglHelper.swap() without triggering another render, so afterSwap captures GPU backpressure in eglSwapBuffers.
    private boolean swapPending;
    private long swapT0, swapD0, swapEnd;
    private int swapDropped, swapCtx;
    private final Runnable afterSwap = this::finishSwap;

    private void finishSwap() {
        if (!swapPending) return;
        swapPending = false;
        if (paused || mine != swapCtx || !glCurrent()) return;
        long s1 = System.nanoTime();
        glWorked = s1 - swapT0;
        glDrawn((s1 - swapD0) / 1e6, swapDropped);
    }

    /**
     * A frame drawn on the GL thread in {@code ms}, {@code dropped} frames handed over since the last never drawn
     * (android_host.c: what the app reads of it, @hostapi.gpu_ms and frames_dropped).
     */
    private static native void glDrawn(double ms, int dropped);

    /**
     * The frame handed over drawn (GL thread), the GL thread's queue's tasks before it done first and those after it
     * after, and what the frames it took the place of used let go once it is drawn; else the frame kept drawn again (a
     * native view's picture changed, or the surface asks for a frame: GLSurfaceView swaps whatever this draws). A new
     * surface's first frame, or one at a new size, waits a while for the app's.
     */
    private void drawOnGl() {
        if (swapPending) {
            swapPending = false;
            if (!paused && mine == swapCtx) {
                glWorked = swapEnd - swapT0;
                glDrawn((swapEnd - swapD0) / 1e6, swapDropped);
            }
        }
        if (mine != setUp) {
            // another view set the drawing up in its own context since this one did (an OverActivity came and went):
            // set up again here, at this view's size, and the app's frame made for it
            Native.surfaceCreated();
            Native.resize(getWidth(), getHeight());
            mine = ++setUp;
            contextMade(true);
            fresh = Math.max(fresh, 100);
        }
        long t0 = System.nanoTime();
        mail.awaitFresh(fresh);
        fresh = 0;
        long d0 = System.nanoTime();
        FrameMail.Taken<MBText.Placed> t = mail.take();
        // what the app asked of the context before this frame: done first (a stream's frame latched, a texture made)
        if (t.took) mail.runTasks(t.seq);
        // the native views' pictures come since the last frame, for this one to draw where it shows them
        NativeViews.latch();
        if (t.took) {
            MBText.upload(t.glyphs);
            Native.draw();
        } else {
            Native.redraw();
        }
        if (Native.adaptiveSettling()) scheduleAdaptiveSettle();
        // what the frames it took the place of on the screen used, and this one does not: let go now
        mail.runAll(t.retire);
        showAt(t.shows);
        if (t.ref != null) MBText.frameDrawn(t.ref);
        Latency.frameEnds(t.lat);
        // what the app asked of it after: done now, but for what follows a frame handed over meanwhile
        mail.runTasks(mail.pendingSeqNow());
        // (the GL thread's time drawing and swapping it, its waiting for the app's frame left out, and the frames
        // handed over never drawn since the last: @hostapi.gpu_ms, @hostapi.frames_dropped)
        swapT0 = t0;
        swapD0 = d0;
        swapEnd = System.nanoTime();
        swapDropped = mail.takeDropped();
        swapCtx = mine;
        swapPending = true;
        queueEvent(afterSwap);
    }

    /**
     * What the app's thread waits for of the GL context (android_host.c gl_sync: a read back): done on the GL thread,
     * the frame pending taken first as the one presented last, to read back (drawn on the screen as the next frame:
     * FrameMail.takeForSync); false where there is no GL thread to do it (no surface, paused) or it did not in a while
     * (it waits on the app's: no frame comes), which the app reads as nothing read.
     */
    static boolean glSync() {
        MBView v = Host.view;
        if (v == null || !v.glAlive || v.paused) return false;
        final Object done = new Object();
        final boolean[] state = {false, false};  // ran, given up
        v.queueEvent(() -> {
            synchronized (done) {
                if (state[1]) return;
                // (its context not current, the view paused meanwhile: nothing read)
                if (!glCurrent()) {
                    state[0] = true;
                    done.notify();
                    return;
                }
                FrameMail.Taken<MBText.Placed> t = mail.takeForSync();
                if (t.took) {
                    Latency.frameEnds(t.lat);
                    mail.runTasks(t.seq);
                    MBText.upload(t.glyphs);
                }
                Native.glSync();
                state[0] = true;
                done.notify();
            }
            v.requestRender();
        });
        synchronized (done) {
            long until = System.nanoTime() + 2_000_000_000L;
            for (long left = 2000; !state[0] && left > 0; left = (until - System.nanoTime()) / 1_000_000L) {
                try {
                    done.wait(left);
                } catch (InterruptedException e) {
                    break;
                }
            }
            if (!state[0]) state[1] = true;
            return state[0];
        }
    }

    // ---- the drawing threads, as the system's own ----

    /**
     * The app's thread builds and lays out every frame, the GL thread draws it: what Compose's UI thread and HWUI's
     * RenderThread do between them. GLSurfaceView makes the GL thread a plain thread (nice 0), while the system raises
     * the app in front's UI thread and RenderThread (THREAD_PRIORITY_TOP_APP_BOOST, or SCHED_FIFO) and its scheduler
     * and governor favour them: a frame could wait behind the core's thread, pictures decoding and the system's own
     * work, on whatever core and clock the phone gave it. Both raised as display threads, and their work per frame
     * told to the system together (ADPF's PerformanceHintManager, as HWUI tells its frames' since Android 12: one
     * session of both threads) against the display's frame, so the CPUs they run on are clocked for it as it heats.
     */
    private void drawingThread() {
        try {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_URGENT_DISPLAY);
        } catch (RuntimeException e) {
            Host.log("drawing thread: priority: " + e);
        }
        int tid = android.os.Process.myTid();
        lastGlTid = tid;
        if (ONE) {
            hintsFor(new int[] {tid});
            return;
        }
        // (the app's thread's id first: its post ahead of this one)
        logic.post(() -> hintsFor(new int[] {logicTid, tid}));
    }

    private void closeHints() {
        if (android.os.Build.VERSION.SDK_INT >= 31 && hints != null) {
            hints.close();
            hints = null;
        }
        hintTids = null;
    }

    private void wakeHints() {
        if (ONE) {
            if (lastGlTid > 0) hintsFor(new int[] {lastGlTid});
        } else if (logicTid > 0) {
            int gl = lastGlTid;
            hintsFor(gl > 0 && glAlive ? new int[] {logicTid, gl} : new int[] {logicTid});
        }
        if (android.os.Build.VERSION.SDK_INT >= 31 && hints != null) {
            long target = pacer.framePeriod * 7 / 10;
            if (target > 0 && target != hintTarget) {
                hintTarget = target;
                hints.updateTargetWorkDuration(target);
            }
            if (hintTarget > 0) {
                hints.reportActualWorkDuration(hintTarget);
            }
        }
    }

    /** One session of the threads {@code tids} (a session per thread set: GLSurfaceView starts another GL thread as the view is shown again). */
    private void hintsFor(int[] tids) {
        if (android.os.Build.VERSION.SDK_INT < 31 || java.util.Arrays.equals(tids, hintTids)) return;
        if (hints != null) hints.close();
        hints = null;
        hintTids = tids;
        android.os.PerformanceHintManager pm = getContext().getSystemService(android.os.PerformanceHintManager.class);
        long target = pacer.framePeriod * 7 / 10;
        try {
            hints = pm == null ? null : pm.createHintSession(tids, target);
        } catch (RuntimeException e) {
            Host.log("drawing thread: hints: " + e);
        }
        hintTarget = target;
    }

    /** The system told what the drawing threads' work over a frame (null: Android before 12, or a phone without ADPF). */
    private android.os.PerformanceHintManager.Session hints;
    private int[] hintTids;
    private long hintTarget;
    private volatile int lastGlTid;
    /** The display's frame, ms (FramePacer's framePeriod). */
    double framePeriodMs() {
        return pacer.framePeriod / 1e6;
    }

    private final android.hardware.display.DisplayManager.DisplayListener displays =
            new android.hardware.display.DisplayManager.DisplayListener() {
                @Override public void onDisplayAdded(int id) {}

                @Override public void onDisplayRemoved(int id) {}

                @Override public void onDisplayChanged(int id) {
                    readFramePeriod();
                }
            };

    private void readFramePeriod() {
        android.view.Display d = getDisplay();
        if (d != null && d.getRefreshRate() > 1) pacer.framePeriod = (long) (1e9 / d.getRefreshRate());
        if (d == null) return;
        // the highest rate the display shows at the size it has now (another size is another mode, not a rate)
        android.view.Display.Mode m = d.getMode();
        float top = 0;
        for (android.view.Display.Mode o : d.getSupportedModes()) {
            if (o.getPhysicalWidth() == m.getPhysicalWidth() && o.getPhysicalHeight() == m.getPhysicalHeight())
                top = Math.max(top, o.getRefreshRate());
        }
        pacer.topRate = top;
    }

    // ---- the display's rate ----

    /** The surface says the display's rate {@code rate} (0: nothing), as FramePacer asks (drawing thread). */
    private boolean surfaceRate(float rate) {
        if (android.os.Build.VERSION.SDK_INT < 30) return false;
        android.view.Surface s = getHolder().getSurface();
        if (s == null || !s.isValid()) return false;
        try {
            s.setFrameRate(rate, android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
            return true;
        } catch (RuntimeException e) {
            Host.log("display rate: " + e);
            return false;
        }
    }

    /**
     * Whether the app's field is being typed into: it has the focus, or the soft keyboard is up over it. Its frames come
     * as keys are struck, its fingers on the keyboard's window, so neither a motion nor a touch of this surface says the
     * display's highest rate for them: this does, as a finger down does, and lets it go as the field does.
     */
    private static boolean typing() {
        return Host.imeActive || Host.imeVisible;
    }

    /** The field's typing begun or ended (MainActivity, as the keyboard shows or goes): the rate said or let go from now. */
    void typingChanged() {
        onApp(pacer::typingChanged);
    }

    void setImeMoving(boolean moving) {
        pacer.setImeMoving(moving);
    }

    /**
     * The soft keyboard asked to show or beginning to move (main thread): ADPF session woken with a full target budget
     * and the display's highest rate asked before its first inset step arrives, so the logic and GL threads are not
     * preempted while the input method starts up.
     */
    void imeMovingStarted() {
        if (paused) return;
        if (!ONE && logic != null) {
            logic.post(() -> {
                wakeHints();
                pacer.sayRate(true);
            });
        } else {
            queueEvent(() -> {
                wakeHints();
                pacer.sayRate(true);
            });
        }
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        readFramePeriod();
        android.hardware.display.DisplayManager dm = getContext().getSystemService(android.hardware.display.DisplayManager.class);
        if (dm != null) dm.registerDisplayListener(displays, Host.main);
    }

    @Override
    protected void onDetachedFromWindow() {
        android.hardware.display.DisplayManager dm = getContext().getSystemService(android.hardware.display.DisplayManager.class);
        if (dm != null) dm.unregisterDisplayListener(displays);
        super.onDetachedFromWindow();
    }

    /**
     * A frame's work done (the app's thread; with ONE the GL thread): how long making it took and how long the GL
     * thread took drawing the last ({@code gl}), the longer told, against 70% of the display's frame as it is now. The
     * system clocks the CPUs so that a frame takes about as long as its target, one a little over as often as one a
     * little under; one over the display's frame misses the next vsync, so the target leaves room under it, as HWUI's
     * does (its frames' targets are 70% of their time).
     */
    private void frameWorked(long nanos, long gl) {
        if (hints == null) return;
        nanos = Math.max(nanos, gl);
        long target = pacer.framePeriod * 7 / 10;
        if (target != hintTarget) {
            hintTarget = target;
            hints.updateTargetWorkDuration(target);
        }
        if (nanos > 0) hints.reportActualWorkDuration(nanos);
    }

    // ---- the system's back ----

    /** What the system's back said (main thread), each with when (System.nanoTime) and its kind, x, progress, edge. */
    private final ArrayDeque<double[]> backs = new ArrayDeque<>();

    /**
     * The system's back (MainActivity's OnBackAnimationCallback, main thread), x in dp: drawn by the first frame whose
     * vsync is later than when it was said. Its gesture's steps come from the system's spring (BackProgressAnimator)
     * in a vsync's animation phase, as that vsync's frame (asked for in the same phase: vsync, below) may already be
     * drawing on the GL thread. Handed to the GL thread at once, a step went into that frame or the next as the two
     * threads raced: a frame got none, the next two, and the page following the finger stood still for a frame and
     * jumped two. A finger's touches come in the vsync's input phase, before its frame is asked for, and do not race.
     */
    void back(int kind, float x, float progress, int edge) {
        synchronized (backs) {
            backs.add(new double[] {System.nanoTime(), kind, x, progress, edge});
        }
        wantFrame();
    }

    /** Hands MoonBit the backs said before {@code before} (ns), in order (GL thread); whether any is left for later. */
    private boolean takeBacks(long before) {
        while (true) {
            double[] b;
            synchronized (backs) {
                b = backs.peek();
                if (b == null) return false;
                if (b[0] >= before) return true;
                backs.poll();
            }
            Native.back((int) b[1], (float) b[2], (float) b[3], (int) b[4]);
        }
    }

    // ---- vsync ----

    /** A vsync asked for (FramePacer's postVsync) told to the pacer as it comes, with its timelines where it has them. */
    private final Choreographer.FrameCallback vsync = t -> pacer.vsyncCame(t, 0);
    /** The vsync told with its frame's timelines (Timelines: Android 13's), made as first asked for. */
    private Object vsyncTimed;
    private final Runnable postVsync = () -> {
        if (android.os.Build.VERSION.SDK_INT >= 33) Timelines.post(this);
        else Choreographer.getInstance().postFrameCallback(vsync);
    };

    /** Android 13's vsync with its frame's timelines: a class of its own, loaded only there (older have no VsyncCallback). */
    private static final class Timelines {
        static void post(MBView v) {
            if (v.vsyncTimed == null) {
                v.vsyncTimed = (Choreographer.VsyncCallback) d -> {
                    long shows = d.getPreferredFrameTimeline().getExpectedPresentationTimeNanos();
                    // the display's frame now, as far apart as its timelines are: the rate the app's frames are shown
                    // at (since Android 16 the display's listener is told no change of rate unless it asks, so the
                    // frame read as the view was shown, at 60 Hz, stayed while the display went to 120 as the app
                    // moved); taken as the rate changes, not as the compositor's guess of it moves by a little
                    Choreographer.FrameTimeline[] tl = d.getFrameTimelines();
                    long period = tl.length > 1
                            ? tl[1].getExpectedPresentationTimeNanos() - tl[0].getExpectedPresentationTimeNanos() : 0;
                    if (period > 0 && Math.abs(period - v.pacer.framePeriod) * 16 > v.pacer.framePeriod) v.pacer.framePeriod = period;
                    v.pacer.vsyncCame(d.getFrameTimeNanos(), shows);
                };
            }
            Choreographer.getInstance().postVsyncCallback((Choreographer.VsyncCallback) v.vsyncTimed);
        }
    }

    /**
     * The frame being drawn (GL thread, before GLSurfaceView swaps it) shown at the refresh its vsync's timeline says
     * ({@code shows}, vsyncAt's), not sooner; at once where none is said (0: before Android 13, the keyboard's frames).
     * A frame of the system's own carries its vsync's timeline, and the compositor holds it until that refresh however
     * soon it is ready. One drawn here carried nothing and was shown at the first refresh after it was ready: at 120 Hz,
     * a frame drawn in a little less than a refresh was shown a refresh sooner after its vsync than one drawn in a little
     * more, so what moved went by uneven steps and the words shook. Held so, every frame is shown as long after its
     * vsync as the others. (Said half a refresh before it, as the compositor takes a frame at the first refresh after
     * the time it is given and its moments and the timeline's may be apart by a little; said on every frame, as the
     * surface keeps the last time given.)
     */
    private void showAt(long shows) {
        if (android.os.Build.VERSION.SDK_INT < 33) return;
        long at = shows != 0 ? shows - pacer.framePeriod / 2 : System.nanoTime();
        android.opengl.EGLExt.eglPresentationTimeANDROID(android.opengl.EGL14.eglGetCurrentDisplay(),
                android.opengl.EGL14.eglGetCurrentSurface(android.opengl.EGL14.EGL_DRAW), at);
    }

    /**
     * A frame now, at the vsync being drawn (main thread, within a Choreographer frame: the keyboard's motion said by
     * WindowInsetsAnimation's onProgress), not the next: what rides on the keyboard drawn in the frame the system
     * moves the keyboard in, not a vsync behind it.
     */
    void frameNow() {
        if (shotTaken) return;
        pacer.frameNow();
    }

    /**
     * The frame the app waits for (Host.wakeAfter: a resident cycle's next step), by its time (ms, System.nanoTime's
     * clock as the vsyncs'), or -1; and the time of the frame being built (GL thread), what a wait counts from.
     */
    volatile double wakeFor = -1;
    volatile double buildingFor = -1;

    /** The rate the frame being built said what moves on by the clock needs (framesPaced; 0: none), GL thread. */
    private float pacedRate;

    /**
     * A frame for what moves on by the clock that needs only {@code hz} frames a second (Host.framesPaced, GL thread, in
     * the frame being built): woken for (Host.wakeAfter) at the vsync a whole number of the display's fastest frames on,
     * as near {@code hz} as they come, the vsyncs between drawing nothing, and that rate said of the display as the
     * frame ends (FramePacer.ended); false where that is every vsync (the display no faster than it), the next asked.
     */
    boolean framesPaced(double hz) {
        float top = pacer.topRate > 0 ? pacer.topRate : (float) (1000.0 / framePeriodMs());
        long every = hz > 0 ? Math.round(top / hz) : 1;
        if (every <= 1 || buildingFor < 0) return false;
        pacedRate = top / every;
        // (half a display frame short of it: the vsync at it, whatever its time's rounding)
        Host.wakeAfter((every - 0.5) * 1000.0 / top);
        return true;
    }

    /**
     * The frame for time `at` drawn (main thread, a little before it): asked for at the vsync before the first at or past
     * it, so drawn for that one, the vsyncs before it drawing nothing (not the vsync after a timer happens to fire: a step a frame or two late by as much as that
     * falls, a resident cycle's steps unevenly apart).
     */
    void wakeAt(double at) {
        if (wakeFor != at) return;
        Choreographer.getInstance().postFrameCallback(new Choreographer.FrameCallback() {
            @Override
            public void doFrame(long t) {
                if (wakeFor != at) return;
                // (the vsync after this one is the frame's: asked for as any other, with its timelines)
                if ((t + pacer.framePeriod) / 1e6 < at - 0.5) {
                    Choreographer.getInstance().postFrameCallback(this);
                    return;
                }
                wakeFor = -1;
                wantFrame();
            }
        });
    }

    /** A frame at the next vsync (from any thread). */
    void wantFrame() {
        if (shotTaken) return;
        pacer.wantFrame();
    }

    /**
     * A native view's new picture to show (NativeViews.Picture, from any thread): the last frame drawn again at the next
     * vsync, with it, unless the app has asked for a frame by then.
     */
    void pictureFrame() {
        if (shotTaken) return;
        pacer.pictureFrame();
    }



    // ---- input ----

    @Override
    public boolean onTouchEvent(MotionEvent e) {
        // each finger by its pointer id (an index is only its place in this event): handed on as it comes, down, moved,
        // up or called off (pointer kinds 10-14, the id where a button goes), what they come to the app's to work out
        // (touches.mbt: two of them its, the first let go the second the first, one called off all of it)
        final int a = e.getActionMasked();
        final double t = e.getEventTime();
        switch (a) {
            case MotionEvent.ACTION_DOWN:
                // (the display's highest from a finger going down: what it moves moves at it from its first frame)
                pacer.touching = true;
                onApp(() -> pacer.sayRate(true));
                requestFocus();
                break;
            case MotionEvent.ACTION_UP: Host.lifts++; pacer.touching = false; break;
            case MotionEvent.ACTION_CANCEL: pacer.touching = false; break;
            default: break;
        }
        switch (a) {
            case MotionEvent.ACTION_DOWN:
            case MotionEvent.ACTION_POINTER_DOWN:
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_POINTER_UP: {
                final int i = e.getActionIndex();
                final int id = e.getPointerId(i);
                final float x = e.getX(i) / density, y = e.getY(i) / density;
                final int phase = a == MotionEvent.ACTION_DOWN || a == MotionEvent.ACTION_POINTER_DOWN ? 10 : 12;
                toApp(() -> Native.touch(phase, id, x, y, t));
                return true;
            }
            case MotionEvent.ACTION_CANCEL: {
                // (called off: each finger it had, all of it)
                final int n = e.getPointerCount();
                final int[] ids = new int[n];
                final float[] xs = new float[n], ys = new float[n];
                for (int p = 0; p < n; p++) {
                    ids[p] = e.getPointerId(p);
                    xs[p] = e.getX(p) / density;
                    ys[p] = e.getY(p) / density;
                }
                toApp(() -> { for (int p = 0; p < n; p++) Native.touch(13, ids[p], xs[p], ys[p], t); });
                return true;
            }
            case MotionEvent.ACTION_MOVE: {
                // each finger's samples batched into the move (MotionEvent's history) and the event itself, each at its
                // own time (uptime ms, as Compose's PointerInputChange has them); each but the last of them all as 14,
                // more of the batch after it, so what they do is laid out once, as the last is taken (touches.mbt)
                final int n = e.getPointerCount(), h = e.getHistorySize();
                final int[] ids = new int[n];
                final float[] xs = new float[n * (h + 1)], ys = new float[n * (h + 1)];
                final double[] ts = new double[h + 1];
                for (int k = 0; k < h; k++) ts[k] = e.getHistoricalEventTime(k);
                ts[h] = t;
                for (int p = 0; p < n; p++) {
                    ids[p] = e.getPointerId(p);
                    for (int k = 0; k < h; k++) {
                        xs[p * (h + 1) + k] = e.getHistoricalX(p, k) / density;
                        ys[p * (h + 1) + k] = e.getHistoricalY(p, k) / density;
                    }
                    xs[p * (h + 1) + h] = e.getX(p) / density;
                    ys[p * (h + 1) + h] = e.getY(p) / density;
                }
                toApp(() -> {
                    for (int k = 0; k <= h; k++)
                        for (int p = 0; p < n; p++) {
                            final int kind = k == h && p == n - 1 ? 11 : 14;
                            Native.touch(kind, ids[p], xs[p * (h + 1) + k], ys[p * (h + 1) + k], ts[k]);
                        }
                });
                return true;
            }
            default: return true;
        }
    }

    /** What the clipboard holds, as words, into the focused field (a paste: KEYCODE_PASTE, the keyboard's menu). */
    // ── the floating text menu (Host.textMenu): the system's text toolbar over a field's words ──

    private android.view.ActionMode textMenu;
    private final android.graphics.Rect textMenuRect = new android.graphics.Rect();
    private int textMenuCan;
    /** The words of the app's own items in their order (Host.textMenuOwn), offered where textMenuCan says 64. */
    String[] textMenuOwn = new String[0];
    /** The app's own first item's id among the menu's (none of the system's android.R.id), the k-th this + k. */
    private static final int TEXT_MENU_OWN = 0x6d620001;

    /** Shown over (x, y, w, h) in dp with what {@code can} offers, moved there when it is up; or put away. */
    void textMenu(boolean shown, double x, double y, double w, double h, int can) {
        if (!shown) {
            if (textMenu != null) textMenu.finish();
            textMenu = null;
            return;
        }
        textMenuRect.set((int) Math.floor(x * density), (int) Math.floor(y * density),
                (int) Math.ceil((x + w) * density), (int) Math.ceil((y + h) * density));
        textMenuCan = can;
        if (textMenu != null) {
            textMenu.invalidate();
            textMenu.invalidateContentRect();
            return;
        }
        textMenu = startActionMode(new android.view.ActionMode.Callback2() {
            private void items(android.view.Menu m) {
                m.clear();
                if ((textMenuCan & 1) != 0) m.add(0, android.R.id.cut, 0, android.R.string.cut);
                if ((textMenuCan & 2) != 0) m.add(0, android.R.id.copy, 1, android.R.string.copy);
                // nothing on the clipboard: no 粘贴 (as Compose's text toolbar offers it only then)
                if ((textMenuCan & 4) != 0 && clipHasText()) m.add(0, android.R.id.paste, 2, android.R.string.paste);
                if ((textMenuCan & 8) != 0) m.add(0, android.R.id.selectAll, 3, android.R.string.selectAll);
                // (the app's own after the system's, in their order: those that do not fit in the toolbar's overflow)
                if ((textMenuCan & 64) != 0) {
                    for (int k = 0; k < textMenuOwn.length; k++) {
                        if (!textMenuOwn[k].isEmpty()) m.add(0, TEXT_MENU_OWN + k, 4 + k, textMenuOwn[k]);
                    }
                }
            }

            @Override public boolean onCreateActionMode(android.view.ActionMode mode, android.view.Menu m) { items(m); return true; }

            @Override public boolean onPrepareActionMode(android.view.ActionMode mode, android.view.Menu m) { items(m); return true; }

            @Override public boolean onActionItemClicked(android.view.ActionMode mode, android.view.MenuItem item) {
                int id = item.getItemId();
                // as the input method's own (MBInput.performContextMenuAction): the keys and the paste the field takes
                if (id == android.R.id.paste) paste();
                else if (id == android.R.id.selectAll) toApp(() -> Native.key(12, 0));
                else if (id == android.R.id.copy) toApp(() -> Native.key(13, 0));
                else if (id == android.R.id.cut) toApp(() -> Native.key(14, 0));
                else if (id >= TEXT_MENU_OWN && id < TEXT_MENU_OWN + 8) {
                    int k = id - TEXT_MENU_OWN;
                    toApp(() -> Native.key(60 + k, 0));
                }
                mode.finish();
                return true;
            }

            @Override public void onDestroyActionMode(android.view.ActionMode mode) {
                if (textMenu == mode) textMenu = null;
            }

            @Override public void onGetContentRect(android.view.ActionMode mode, android.view.View v, android.graphics.Rect out) {
                out.set(textMenuRect);
            }
        }, android.view.ActionMode.TYPE_FLOATING);
    }

    /** Whether the clipboard holds something to paste (ClipboardManager.hasPrimaryClip). */
    private boolean clipHasText() {
        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        return cm != null && cm.hasPrimaryClip();
    }

    void paste() {
        android.content.ClipboardManager cm = (android.content.ClipboardManager)
                getContext().getSystemService(Context.CLIPBOARD_SERVICE);
        android.content.ClipData clip = cm.getPrimaryClip();
        if (clip == null || clip.getItemCount() == 0) return;
        CharSequence t = clip.getItemAt(0).coerceToText(getContext());
        if (t == null || t.length() == 0) return;
        String s = t.toString();
        // (text kind 8: put in as typed, a step of its own to undo)
        toApp(() -> Native.text(8, s, 0, 0));
    }

    /** A key with the focus a key catcher's (Device.catching): its named keys and shortcuts as keys, a character as
     * text; false for what is not the catcher's (Back). */
    boolean catchKey(KeyEvent e) {
        if (e.getKeyCode() == KeyEvent.KEYCODE_BACK) return false;
        int[] k = Device.catchKey(e);
        if (k != null) {
            toApp(() -> Native.key(k[0], k[1]));
            return true;
        }
        int ch = e.getUnicodeChar();
        if (ch <= 0) return false;
        String s = new String(Character.toChars(ch));
        toApp(() -> Native.text(0, s, 0, 0));
        return true;
    }

    @Override
    public boolean onKeyDown(int code, KeyEvent e) {
        if (Device.catching && Host.imeActive && catchKey(e)) return true;
        if (code == KeyEvent.KEYCODE_PASTE || (code == KeyEvent.KEYCODE_V && e.isCtrlPressed())) {
            if (Host.imeActive) paste();
            return true;
        }
        int sk = shortcutKey(e);
        if (sk != 0) {
            int mods = Device.keyMods(e);
            toApp(() -> Native.key(sk, mods));
            return true;
        }
        int k = keyCode(code);
        if (k != 0) {
            int mods = Device.keyMods(e);
            toApp(() -> Native.key(k, mods));
            return true;
        }
        int ch = e.getUnicodeChar();
        if (ch != 0 && Host.imeActive) {
            String s = new String(Character.toChars(ch));
            toApp(() -> Native.text(0, s, 0, 0));
            return true;
        }
        return super.onKeyDown(code, e);
    }

    /** A letter or digit with Ctrl or Meta held (a hardware keyboard's shortcut, which types no character): Ctrl+A, C
     * and X the field's select all, copy and cut (12, 13, 14, as Windows' host sends them), any other the app's or the
     * field's key as 1000 + the character (Ctrl+Z, Ctrl+Y to undo and do again, Ctrl+K); 0 for none. */
    static int shortcutKey(KeyEvent e) {
        if (!e.isCtrlPressed() && !e.isMetaPressed()) return 0;
        int k = e.getKeyCode();
        int ch;
        if (k >= KeyEvent.KEYCODE_A && k <= KeyEvent.KEYCODE_Z) ch = 'a' + (k - KeyEvent.KEYCODE_A);
        else if (k >= KeyEvent.KEYCODE_0 && k <= KeyEvent.KEYCODE_9) ch = '0' + (k - KeyEvent.KEYCODE_0);
        else return 0;
        if (e.isCtrlPressed()) {
            if (ch == 'a') return 12;
            if (ch == 'c') return 13;
            if (ch == 'x') return 14;
        }
        return 1000 + ch;
    }

    static int keyCode(int code) {
        switch (code) {
            case KeyEvent.KEYCODE_DEL: return 1;
            case KeyEvent.KEYCODE_FORWARD_DEL: return 2;
            case KeyEvent.KEYCODE_DPAD_LEFT: return 3;
            case KeyEvent.KEYCODE_DPAD_RIGHT: return 4;
            case KeyEvent.KEYCODE_DPAD_UP: return 5;
            case KeyEvent.KEYCODE_DPAD_DOWN: return 6;
            case KeyEvent.KEYCODE_ENTER: return 7;
            case KeyEvent.KEYCODE_MOVE_HOME: return 8;
            case KeyEvent.KEYCODE_MOVE_END: return 9;
            default: return 0;
        }
    }

    @Override
    public boolean onCheckIsTextEditor() {
        return Host.imeActive;
    }

    /** The field's input connection, the last made (null while a key catcher has the focus). */
    MBInput input;

    @Override
    public InputConnection onCreateInputConnection(EditorInfo out) {
        if (Device.catching) {
            // a key catcher's (Device): no text of its own, no suggestions, the keyboard's Enter a key (as still.fail's
            // KeyCatcher)
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
            out.imeOptions = EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN | EditorInfo.IME_ACTION_NONE;
            out.initialSelStart = 0;
            out.initialSelEnd = 0;
            input = null;
            return new CatchInput(this);
        }
        // multi-line, with no action of the keyboard's own: its Enter is a key the field decides on (a new line in
        // still.fail's composer, as its Android app's field does; the demo sends)
        out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE;
        out.imeOptions = EditorInfo.IME_ACTION_NONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION
                | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        if (Device.imeAction == 1) {
            // a search field's (hostapi ime_action): one line, its Enter the keyboard's search key, which comes as Enter
            // (performEditorAction)
            out.inputType = InputType.TYPE_CLASS_TEXT;
            out.imeOptions = EditorInfo.IME_ACTION_SEARCH | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 2) {
            // an address's: the keyboard's for addresses, its Enter a go key (Compose's ImeAction.Go, KeyboardType.Uri)
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI;
            out.imeOptions = EditorInfo.IME_ACTION_GO | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 3) {
            // a number's: digits, its Enter a done key (Compose's ImeAction.Done, KeyboardType.Number)
            out.inputType = InputType.TYPE_CLASS_NUMBER;
            out.imeOptions = EditorInfo.IME_ACTION_DONE | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 4) {
            // a secret's (a token, a password): a password's keyboard, nothing of it learnt or suggested (Compose's
            // KeyboardType.Password); its Enter as the field's own
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD;
            out.imeOptions = EditorInfo.IME_ACTION_NONE | EditorInfo.IME_FLAG_NO_ENTER_ACTION
                    | EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                    | EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_FLAG_NO_FULLSCREEN;
        } else if (Device.imeAction == 5) {
            // an email address's: the keyboard's for addresses with @, nothing suggested; its Enter as the field's own
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS;
        } else if (Device.imeAction == 6) {
            // words taken as typed (a server's id, a code): nothing corrected or suggested; its Enter as the field's own
            out.inputType = InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
        }
        out.initialSelStart = Host.selStart;
        out.initialSelEnd = Host.selEnd;
        input = new MBInput(this);
        return input;
    }

    /**
     * What an input method talks to while a key catcher has the focus (Device): no text of its own; what it commits,
     * composes and deletes goes to MoonBit as events (src/ui/device.mbt takes them).
     */
    static class CatchInput extends BaseInputConnection {
        final MBView view;
        volatile boolean composing;
        /** What is being composed (shown at the caret, not yet in MoonBit's text). */
        volatile String composingText = "";

        CatchInput(MBView v) {
            super(v, false);
            view = v;
        }

        @Override
        public boolean commitText(CharSequence text, int pos) {
            String s = text.toString();
            if (Host.imeLog()) Host.log("ime: commitText " + s);
            composing = false;
            composingText = "";
            if (s.equals("\n")) {
                view.toApp(() -> Native.key(7, 0));
            } else {
                view.toApp(() -> Native.text(0, s, 0, 0));
            }
            return true;
        }

        @Override
        public boolean setComposingText(CharSequence text, int pos) {
            String s = text.toString();
            if (Host.imeLog()) Host.log("ime: setComposingText " + s);
            composingText = s;
            composing = s.length() > 0;
            view.toApp(() -> Native.text(1, s, s.length(), 0));
            return true;
        }

        @Override
        public boolean finishComposingText() {
            if (Host.imeLog()) Host.log("ime: finishComposingText (composing " + composing + ")");
            if (composing) {
                composing = false;
                composingText = "";
                view.toApp(() -> Native.text(2, "", 0, 0));
            }
            return true;
        }

        @Override
        public boolean setSelection(int start, int end) {
            view.toApp(() -> Native.text(3, "", start, end));
            return true;
        }

        @Override
        public boolean deleteSurroundingText(int before, int after) {
            // (a field takes it as its Backspace, its Delete; a key catcher as that many: src/ui/device.mbt)
            if (before > 0 || after > 0) view.toApp(() -> Native.text(4, "", before, after));
            return true;
        }

        @Override
        public boolean sendKeyEvent(KeyEvent e) {
            if (e.getAction() != KeyEvent.ACTION_DOWN) return true;
            if (Device.catching) {
                view.catchKey(e);
                return true;
            }
            if (e.getKeyCode() == KeyEvent.KEYCODE_PASTE) { view.paste(); return true; }
            int k = keyCode(e.getKeyCode());
            if (k == 0) k = shortcutKey(e);
            if (k != 0) {
                int kk = k, mods = Device.keyMods(e);
                view.toApp(() -> Native.key(kk, mods));
                return true;
            }
            int ch = e.getUnicodeChar();
            if (ch != 0) {
                String s = new String(Character.toChars(ch));
                view.toApp(() -> Native.text(0, s, 0, 0));
            }
            return true;
        }

        @Override
        public boolean performContextMenuAction(int id) {
            if (id == android.R.id.paste || id == android.R.id.pasteAsPlainText) {
                view.paste();
                return true;
            }
            // a key catcher has no text of its own to select, copy or cut
            if (Device.catching) return false;
            if (id == android.R.id.selectAll) view.toApp(() -> Native.key(12, 0));
            else if (id == android.R.id.copy) view.toApp(() -> Native.key(13, 0));
            else if (id == android.R.id.cut) view.toApp(() -> Native.key(14, 0));
            return true;
        }

        @Override
        public boolean performEditorAction(int action) {
            view.toApp(() -> Native.key(7, 0));
            return true;
        }

        @Override
        public CharSequence getTextBeforeCursor(int n, int flags) {
            String t = Host.imeText;
            int a = Math.max(0, Math.min(Host.selStart, t.length()));
            return t.substring(Math.max(0, a - n), a);
        }

        @Override
        public CharSequence getTextAfterCursor(int n, int flags) {
            String t = Host.imeText;
            int b = Math.max(0, Math.min(Host.selEnd, t.length()));
            return t.substring(b, Math.min(t.length(), b + n));
        }

        @Override
        public CharSequence getSelectedText(int flags) {
            String t = Host.imeText;
            int a = Math.max(0, Math.min(Host.selStart, t.length()));
            int b = Math.max(a, Math.min(Host.selEnd, t.length()));
            return a == b ? null : t.substring(a, b);
        }
    }

    /**
     * What an input method talks to while a field has the focus: the field's words kept here as well, in an Editable
     * the input method's edits are made on at once, as a TextView's are. An input method reads what it just did right
     * after doing it (the word before the caret, to put a space after a full stop or between Chinese and English;
     * where the caret is, which it is told after each edit): answered from words MoonBit had not taken in yet, it
     * read the field as before its edit, took the caret as moved by someone else and forgot the space it owed. Each
     * edit (a batch of them: once the batch ends) goes to MoonBit as the field's whole state (src/ui/editor.mbt
     * text_set), and the input method is told the selection then, as a TextView tells it; what MoonBit changes itself
     * (a key, the app clearing the field once sent) comes back after its frame (Host.setIme) and is put in here.
     */
    static final class MBInput extends BaseInputConnection {
        final MBView view;
        final Editable ed;
        private int batch;
        /** What MoonBit was last told, or last told this: the state it has (once it has taken what it was sent). */
        String saidText;
        int saidA, saidB, saidCs = -1, saidCe = -1;

        MBInput(MBView v) {
            super(v, true);
            view = v;
            String t = Host.imeText;
            ed = Editable.Factory.getInstance().newEditable(t);
            int a = Math.max(0, Math.min(Host.selStart, t.length())), b = Math.max(0, Math.min(Host.selEnd, t.length()));
            Selection.setSelection(ed, a, b);
            saidText = t;
            saidA = a;
            saidB = b;
        }

        @Override
        public Editable getEditable() {
            return ed;
        }

        @Override
        public boolean beginBatchEdit() {
            batch++;
            return true;
        }

        @Override
        public boolean endBatchEdit() {
            if (batch > 0) batch--;
            if (batch == 0) edited();
            return batch > 0;
        }

        /** The field's state after the input method's edits, to MoonBit and to the input method, when it changed. */
        void edited() {
            if (batch > 0) return;
            String t = ed.toString();
            int a = Selection.getSelectionStart(ed), b = Selection.getSelectionEnd(ed);
            int cs = getComposingSpanStart(ed), ce = getComposingSpanEnd(ed);
            if (cs > ce) { int x = cs; cs = ce; ce = x; }
            if (t.equals(saidText) && a == saidA && b == saidB && cs == saidCs && ce == saidCe) return;
            saidText = t;
            saidA = a;
            saidB = b;
            saidCs = cs;
            saidCe = ce;
            final int seq = ++Host.imeSent;
            final int fa = a, fb = b, fcs = cs, fce = ce;
            if (Host.imeLog()) Host.log("ime: edited " + a + "," + b + " composing " + cs + "," + ce + " (" + t.length() + ")");
            view.toApp(() -> {
                Native.text(6, "", fcs, fce);
                Native.text(5, t, fa, fb);
                Host.imeTaken = seq;
            });
            imm().updateSelection(view, a, b, cs, ce);
        }

        InputMethodManager imm() {
            return (InputMethodManager) view.getContext().getSystemService(Context.INPUT_METHOD_SERVICE);
        }

        /**
         * MoonBit's own change to the field (Host.setIme, on the main thread): its words `text` (without what is
         * composed) and selection, once it has taken every edit sent it. Put in here when they are not what it was
         * told; true then (the input method to be told).
         */
        boolean took(String text, int a, int b) {
            int cs = saidCs, ce = saidCe;
            // what it was told, as MoonBit keeps it: a composition holding the caret apart from its words (editor.mbt)
            String has = saidText;
            int ha = saidA, hb = saidB;
            boolean comp = cs >= 0 && ce > cs && ha == hb && ha >= cs && ha <= ce;
            if (comp) {
                has = saidText.substring(0, cs) + saidText.substring(ce);
                ha = cs;
                hb = cs;
            }
            if (text.equals(has) && Math.min(a, b) == Math.min(ha, hb) && Math.max(a, b) == Math.max(ha, hb)) return false;
            removeComposingSpans(ed);
            ed.replace(0, ed.length(), text);
            int n = text.length();
            Selection.setSelection(ed, Math.max(0, Math.min(a, n)), Math.max(0, Math.min(b, n)));
            saidText = text;
            saidA = Selection.getSelectionStart(ed);
            saidB = Selection.getSelectionEnd(ed);
            saidCs = -1;
            saidCe = -1;
            return true;
        }

        @Override
        public boolean commitText(CharSequence text, int pos) {
            if (Host.imeLog()) Host.log("ime: commitText " + text);
            if (text.toString().equals("\n")) {
                // Enter: the field's to decide (a new line, or sent), after what is composed is in
                finishComposingText();
                view.toApp(() -> Native.key(7, 0));
                return true;
            }
            return super.commitText(text, pos);
        }

        @Override
        public boolean setComposingText(CharSequence text, int pos) {
            if (Host.imeLog()) Host.log("ime: setComposingText " + text);
            return super.setComposingText(text, pos);
        }

        @Override
        public boolean finishComposingText() {
            if (Host.imeLog()) Host.log("ime: finishComposingText");
            boolean r = super.finishComposingText();
            edited();
            return r;
        }

        @Override
        public boolean setComposingRegion(int start, int end) {
            boolean r = super.setComposingRegion(start, end);
            edited();
            return r;
        }

        @Override
        public boolean setSelection(int start, int end) {
            boolean r = super.setSelection(start, end);
            edited();
            return r;
        }

        @Override
        public boolean deleteSurroundingText(int before, int after) {
            boolean r = super.deleteSurroundingText(before, after);
            edited();
            return r;
        }

        @Override
        public boolean deleteSurroundingTextInCodePoints(int before, int after) {
            boolean r = super.deleteSurroundingTextInCodePoints(before, after);
            edited();
            return r;
        }

        /** Backspace (`back`) or Delete sent as a key by the input method: made here, as a TextView makes it. */
        void deleteKey(boolean back) {
            removeComposingSpans(ed);
            int a = Selection.getSelectionStart(ed), b = Selection.getSelectionEnd(ed);
            if (a > b) { int x = a; a = b; b = x; }
            if (a == b) {
                // a grapheme cluster (an emoji of several code points, a letter and its marks)
                BreakIterator g = BreakIterator.getCharacterInstance();
                g.setText(ed.toString());
                if (back) {
                    if (a == 0) { edited(); return; }
                    a = g.preceding(a);
                } else {
                    if (b >= ed.length()) { edited(); return; }
                    b = g.following(b);
                }
            }
            ed.delete(a, b);
            Selection.setSelection(ed, a);
            edited();
        }

        @Override
        public boolean sendKeyEvent(KeyEvent e) {
            if (e.getAction() != KeyEvent.ACTION_DOWN) return true;
            if (e.getKeyCode() == KeyEvent.KEYCODE_PASTE) { view.paste(); return true; }
            if ((e.getKeyCode() == KeyEvent.KEYCODE_DEL || e.getKeyCode() == KeyEvent.KEYCODE_FORWARD_DEL)
                    && !e.isShiftPressed() && !e.isCtrlPressed() && !e.isAltPressed()) {
                deleteKey(e.getKeyCode() == KeyEvent.KEYCODE_DEL);
                return true;
            }
            int k = keyCode(e.getKeyCode());
            if (k != 0) {
                int mods = Device.keyMods(e);
                view.toApp(() -> Native.key(k, mods));
                return true;
            }
            int ch = e.getUnicodeChar();
            if (ch != 0) super.commitText(new String(Character.toChars(ch)), 1);
            return true;
        }

        @Override
        public boolean performContextMenuAction(int id) {
            if (id == android.R.id.paste || id == android.R.id.pasteAsPlainText) view.paste();
            else if (id == android.R.id.selectAll) view.toApp(() -> Native.key(12, 0));
            else if (id == android.R.id.copy) view.toApp(() -> Native.key(13, 0));
            else if (id == android.R.id.cut) view.toApp(() -> Native.key(14, 0));
            return true;
        }

        @Override
        public boolean performEditorAction(int action) {
            view.toApp(() -> Native.key(7, 0));
            return true;
        }

        @Override
        public ExtractedText getExtractedText(ExtractedTextRequest req, int flags) {
            ExtractedText x = new ExtractedText();
            x.text = ed.toString();
            x.startOffset = 0;
            x.partialStartOffset = -1;
            x.partialEndOffset = -1;
            x.selectionStart = Selection.getSelectionStart(ed);
            x.selectionEnd = Selection.getSelectionEnd(ed);
            x.flags = 0;
            return x;
        }
    }
}
