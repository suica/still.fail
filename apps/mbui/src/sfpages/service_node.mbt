// A web service an agent started, or a visualization it posted, as nodes of the window's tree, made once (service.mbt's
// head says what it is and how it answers; what serves its page and what it keeps is sfbase's): the page's bar, over it
// or (with touch, as narrow as a phone's) under it in a thumb's reach, and its stage, each bound to what it is worked
// out of (the job as the core says it, where its page is as its host says, what its page keeps in no signal as it is
// told: ServicePage::said) and doing what it does in a handler at the moment of its cause. Its marks over the page
// (service_marks_node.mbt). The frame puts it where it goes: the phone's stack a page of its own under a bar with its
// way back (service_page_node, preview_file_page_node), a chat's side panel its tab (service_tab_node, file_tab_node).

///|
/// The job a service's view shows as the core says it: the port its page is on, its name, whether it is being started
/// again and how often it was, its chat's agent (marks go into that chat: none, nothing to mark for).
#derive(Eq)
pub(all) struct ServiceNow {
  port : Int
  name : String
  restarting : Bool
  restarts : Int
  session : String
}

///|
/// The service `job` of `station` as its view in `parent` (all of its room; service_view's, ServiceFrame), as the job is
/// `now()`: its bar and its stage. `file`: a visualization's page, served from here (its bar names it, nowhere else to
/// go). `close`: what closes the panel it is alone in (its bar the panel's: the × at its end, the page a card in it).
/// `width()`: how wide it is given to be (where its bar goes: under it with touch, as narrow as a phone's). `round`: the
/// corners of the panel it is alone in (its bar's ends and the page's corners concentric with them). `full`: what puts
/// it over the whole window (its 全屏 at its bar's end, before the panel's ×: a chat's side panel's tab).
#callsite(autofill(loc))
pub fn service_view_node(
  parent : @view.View,
  src : Source,
  station : String,
  job : String,
  now : () -> ServiceNow,
  width : () -> Double,
  file? : FilePage? = None,
  close? : (() -> Unit)? = None,
  full? : (() -> Unit)? = None,
  round? : FixedArray[@ui.CornerOf]? = None,
  tips? : @sf.TipLayer,
  beside? : (() -> Unit)? = None,
  loc~ : SourceLoc,
) -> Unit {
  svc_keep.val = fn(patch) { (src.call)("prefs.set", patch, @sfbase.answer_unread) }
  src_now.val = src.now
  let first = @signals.untracked(now)
  let p = @signals.untracked(fn() { @sfbase.service_page_held(parent, src, station, job, prefs=src.topic("prefs", {}).get().value) })
  p.port = first.port
  p.name = first.name
  p.session = first.session
  let site = service_site(src, p, file, fn(url) {
    // a link elsewhere: one of still.fail's opened here as the core says, any other handed to the system
    open_link_in(src, url, or_else=fn() {
      if !@ui.open_url(url) {
        toast_later(svc("android-chat.link.failed"))
      }
    })
  })
  let fixed = file is Some(_)
  parent.box(made_for=loc, fn(v) {
    v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    // the job as it changes: up again after a restart, the page loads anew
    v.reacts(now, fn(n) {
      p.port = n.port
      p.name = n.name
      p.session = n.session
      if p.restarting && !n.restarting {
        site.reload()
      }
      p.restarting = n.restarting
      p.tell()
    })
    // what marking has for the page, sent as it is said; its pictures taken as the host gives them (by how many were
    // sent before as well: another as many as the last, said after those were sent, is a change)
    v.reacts(
      fn() {
        p.said()
        (p.marks.sent, p.marks.out.length())
      },
      fn(told) {
        if told.1 > 0 {
          let out = p.marks.out.copy()
          p.marks.out.clear()
          p.marks.sent += 1
          for js in out {
            site.script(js)
          }
        }
      },
    )
    v.reacts(
      fn() {
        p.said()
        let drawn = match p.marks.shot {
          Some({ wait: Draw(job), .. }) => job.ready()
          _ => false
        }
        (site.grabs_told(), drawn)
      },
      fn(_) { page_marks_frame(p, site) },
    )
    // (said on the log as the page moves: e2e/flows check where it went)
    v.reacts(fn() { site.page_at().0 }, fn(at) {
      if at != p.logged_path {
        p.logged_path = at
        @ui.log("service: at \{at}")
      }
    })
    // the system's back steps the page back first; at its first page it leaves (Preview.kt BackHandler(canBack))
    v.show(at_once=true, fn() { site.page_at().1 }, fn(b) {
      b.width(Is(Some(0.0))).height(Is(Some(0.0))).takes_back(fn() { site.go_back() }) |> ignore
    })
    let tips = match tips {
      Some(t) => t
      None => {
        let at : Ref[@view.View?] = Ref(None)
        let t = @sf.TipLayer::new(fn() { at.val })
        v.owns(fn() { at.val = None }) |> ignore
        at.val = Some(v.box(fn(l) { l.over(Is(true)).stacked(Is(1)) |> ignore }))
        t
      }
    }
    // (in a panel of its own: the page a card in it, in from the panel's sides and the side its bar is not on)
    let in_panel = close is Some(_)
    let corners = match round {
      Some(k) if in_panel => Some(@sf.corner_radii(k))
      _ => None
    }
    // (its stage made once, never again as the width moves its bar over or under it: the page's native view stays
    // open, its room and corners bound to where the bar is; each bar there at once as the width says, no motion of
    // its own: #5767)
    let at_foot = fn() { @sf.keys_at_foot(width()) }
    // (which bar holds the address's one Field now, 0 none, 1 over, 2 under: the one going lets it go before the other
    // is made, in whatever order the width tells the two)
    let held : @signals.Signal[Int] = @signals.signal(0)
    let bar = fn(parent : @view.View, foot : Bool, make : (@view.View) -> Unit) {
      let mine = if foot { 2 } else { 1 }
      parent.show(at_once=true, fn() { at_foot() == foot && held.get() != 3 - mine }, fn(b) {
        held.set(mine)
        b.owns(fn() { held.set(0) }) |> ignore
        make(b)
      })
    }
    v.box(fn(col) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      bar(col, false, fn(top) { service_page_bar_node(top, src, p, site, station, fixed, close, full, corners, tips, beside~) })
      col.box(fn(st) {
        st.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        if in_panel {
          let room = stage_in_panel_room
          st.padding(By(fn() { if at_foot() { (room, room, room, 0.0) } else { (room, 0.0, room, room) } })) |> ignore
          service_stage_node(st, p, site, Some(fn() { stage_in_panel(bar_at_foot=at_foot(), round~).1 }), now)
        } else {
          service_stage_node(st, p, site, None, now)
        }
      })
      |> ignore
      bar(col, true, fn(foot) { service_foot_bar_node(foot, src, p, site, station, fixed, close, full, tips) })
    })
    |> ignore
  })
  |> ignore
}

///|
/// How far the page's resources came (the `previewLoad` topic), followed; a visualization's page has none.
fn load_now(src : Source, p : ServicePage, station : String, fixed : Bool) -> Json? {
  if fixed {
    None
  } else {
    p.said()
    src.topic("previewLoad", { "station": Json::string(station), "port": Json::number(p.port.to_double()) }).get().value
  }
}

///|
/// The bar over the page in `parent` (service_page_bar's, PreviewBar): back and forward, reload, how far its resources
/// came, where it is (typed to go elsewhere) or what marking says in its place, its size, marking it; short of room
/// what leaves first (how far it came, then its size, then reload) offered in its ⋯ at its end; the panel's × where it
/// is alone in one (`corners`: the panel's top corners its first and last keys are concentric with), its 全屏 before it
/// (`full`).
fn service_page_bar_node(
  parent : @view.View,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  station : String,
  fixed : Bool,
  close : (() -> Unit)?,
  full : (() -> Unit)?,
  corners : FixedArray[Double]?,
  tips : @sf.TipLayer,
  beside? : (() -> Unit)? = None,
) -> Unit {
  let at = match (close, corners) {
    (Some(_), Some(k)) => Some((k[0], k[1]))
    _ => None
  }
  // (a window of its own's one bar, `beside` its 移到侧边 at its end: the window's top row, a bar's height, what of it
  // takes no press moving the window, clear of its buttons, the system's at its left (a Mac's) and the app's at its right (Windows', Linux's: its
  // last key past the window's corner where they are not))
  let parent = match beside {
    None => parent
    Some(_) =>
      parent.box(fn(w) {
        w
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .height(Is(Some(@sf.wide_bar_h)))
        .shrink(Is(0.0))
        .moves_window(By(@ui.window_inset_now))
        .padding(By(fn() {
          let pad = @ui.Space::px(S2)
          let start = if @ui.window_keys_left_now() { window_bar_buttons_in } else { window_bar_in }
          // (its last key a bar key of its own size, not the window's corner key: past the corner's arc, not following
          // it; before the window's own buttons where they are the app's)
          let roots = @ui.tree_corner_roots_now()
          let end = if @ui.window_keys_own() {
            @sf.window_keys_room(roots~) + window_bar_in
          } else {
            @sf.window_corner_past(window_bar_in, roots~)
          }
          (dmax(0.0, start - pad), 0.0, dmax(0.0, end - pad), 0.0)
        }))
        |> ignore
      })
  }
  @sf.page_bar_node(parent, corners=at, fn(row) {
    if beside is Some(_) {
      row.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    }
    row.fits(Is(true)) |> ignore
    back_forward_node(row, site, tips)
    let reload_slot : Ref[@view.View?] = Ref(None)
    row.box(fn(slot) {
      slot.drops(Is(bar_drop_reload)) |> ignore
      reload_slot.val = Some(slot)
      reload_key_node(slot, site, tips)
    })
    |> ignore
    let load_slot : Ref[@view.View?] = Ref(None)
    if !fixed {
      row.box(fn(slot) {
        slot.drops(Is(bar_drop_load)) |> ignore
        load_slot.val = Some(slot)
        load_key_node(slot, src, p, station)
      })
      |> ignore
    }
    // (a window of its own at its least: the place given way to further, what is beside it gone into its ⋯ first)
    if beside is Some(_) {
      address_or_marking_node(row, src, p, site, fixed, least=window_bar_field_least)
    } else {
      address_or_marking_node(row, src, p, site, fixed)
    }
    let size_slot : Ref[@view.View?] = Ref(None)
    row.box(fn(slot) {
      slot.drops(Is(bar_drop_size)) |> ignore
      size_slot.val = Some(slot)
      size_key_node(slot, p, tips)
    })
    |> ignore
    mark_key_node(row, p, site, tips)
    // what left it, in its ⋯ at its end (there only while something did)
    let left = fn(slot : Ref[@view.View?]) {
      match slot.val {
        Some(s) => s.left_out()
        None => false
      }
    }
    row.box(fn(slot) {
      slot.drops(Is(-1)) |> ignore
      // (what its menu and the panels of its lines stand beside: key_beside's)
      let k : Ref[@view.View?] = Ref(Some(key_beside(slot)))
      k.val.map(fn(at) {
        @sf.bar_key_node(at, fn() { "more" }, fn() { @sf.t("web-main.menu.more") }, fn() {
          let gone : Array[@sf.MenuItem?] = []
          if left(reload_slot) {
            gone.push(Some(bar_line(@sf.t("web-main.preview.reload"), "refresh", disabled=false, on_press=fn() { site.reload() })))
          }
          let load = @signals.untracked(fn() { load_now(src, p, station, fixed) })
          if left(load_slot) {
            gone.push(
              Some(
                bar_line(load_label(load), "", disabled=false, on_press=fn() {
                  match k.val {
                    Some(n) => service_load_panel(src, station, p.port, Node(n))
                    None => ()
                  }
                }),
              ),
            )
          }
          if left(size_slot) {
            gone.push(
              Some(
                bar_line(size_said(p), if p.moving.untracked() { "move" } else { "devices" }, disabled=false, on_press=fn() {
                  if p.moving.untracked() {
                    p.moving.set(false)
                  } else {
                    match k.val {
                      Some(n) => service_sizes_panel(service_key(p.station, p.job), Node(n))
                      None => ()
                    }
                  }
                }),
              ),
            )
          }
          match k.val {
            Some(n) => @sf.menu(gone, from=Node(n))
            None => ()
          }
        }, tips~)
      })
      |> ignore
    })
    |> ignore
    full_key_node(row, full, tips)
    panel_close_key_node(row, close, tips)
    // 移到侧边, a window of its own's last
    match beside {
      // (round, as big as the bar's other keys, lit round where the pointer is on it: in from the window's corner as far
      // as it is from the bar's top, a circle stands clear of the corner's arc as the rule holds it)
      Some(b) =>
        @sf.icon_button_node(
          row,
          "panel-open",
          fn() { @sf.t("web-main.preview.moveBeside") },
          b,
          tips~,
          size=@sf.theme().bars.key,
          icon_size=@sf.theme().bars.icon,
        )
        |> ignore
      None => ()
    }
  })
  |> ignore
}

///|
/// How far in from the window's sides a window of its own's one bar stands (service_page_bar_node's `beside`): past its
/// corner (@sf.window_corner_past), after a Mac's own buttons at its left.
let window_bar_in : Double = 12.0

///|
let window_bar_buttons_in : Double = 84.0

///|
/// The least a window of its own's place gives way to (address_or_marking_node's `least`): its ← → and its keys
/// beside it whole in a window at its least, 420 wide.
let window_bar_field_least : Double = 72.0

///|
/// The same under the page in `parent` (service_foot_bar's, Safari's compact bar at the foot), in one row in a thumb's
/// reach: back and forward, where it is with reload at its end (marking's say in its place while marking) and how far
/// the page came along its foot, marking it, its ⋯ (its size, how far each of its resources came); while a finger
/// moves the page, the size key in the ⋯'s place, a press stopping it. In a panel of its own the first and last keys
/// concentric with its foot corners (@sf.foot_capsule), its 全屏 before its × (`full`).
fn service_foot_bar_node(
  parent : @view.View,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  station : String,
  fixed : Bool,
  close : (() -> Unit)?,
  full : (() -> Unit)?,
  tips : @sf.TipLayer,
) -> Unit {
  parent.box(fn(row) {
    @sf.style_node(row, fn() {
      let key = @sf.theme().bars.key
      // (each key in the row's middle, as far over its foot as its room leaves under it)
      let under = (@ui.room_least() - key) / 2.0
      let (left, right, foot) = @sf.foot_capsule(key, foot_keys_in, under)
      let lifted = dmax(0.0, foot - under)
      foot_row_look.then(
        @ui.style(
          h=Fixed(@ui.room_least() + lifted),
          pl=@sf.room_of(left),
          pr=@sf.room_of(right),
          pb=@sf.room_of(lifted),
          gap=@sf.keys_gap(size=key),
        ),
      )
    })
    back_forward_node(row, site, tips)
    // (nothing of this row leaves: the address gives way, its words cut short, down to what the row leaves it, a
    // panel beside the column of the system's bars on an iPhone Duo's outer screen on its side as narrow as 318)
    address_or_marking_node(row, src, p, site, fixed, end=Some(fn(e) { reload_key_node(e, site, tips) }), part=fn() {
      load_part(load_now(src, p, station, fixed))
    }, least=0.0)
    mark_key_node(row, p, site, tips)
    row.pick(at_once=true, fn() { p.moving.get() }, fn(k, moving) {
      k.row(Is(true)) |> ignore
      if moving {
        size_key_node(k, p, tips)
      } else {
        foot_more_node(k, src, p, station, fixed, tips)
      }
    })
    full_key_node(row, full, tips)
    panel_close_key_node(row, close, tips)
  })
  |> ignore
}

///|
/// The foot bar's ⋯ in `parent` (foot_more's): its size (its choices in the presenters' panel), how far each of its
/// resources came (a panel).
fn foot_more_node(parent : @view.View, src : Source, p : ServicePage, station : String, fixed : Bool, tips : @sf.TipLayer) -> Unit {
  // (what its menu and the panels of its lines stand beside: key_beside's)
  let k : Ref[@view.View?] = Ref(Some(key_beside(parent)))
  k.val.map(fn(at) {
    @sf.bar_key_node(at, fn() { "more" }, fn() { @sf.t("web-main.menu.more") }, fn() {
      guard k.val is Some(n) else { return }
      let lines : Array[@sf.MenuItem?] = [
        Some(bar_line(size_said(p), "devices", disabled=false, on_press=fn() {
          service_sizes_panel(service_key(p.station, p.job), Node(n))
        })),
      ]
      let load = @signals.untracked(fn() { load_now(src, p, station, fixed) })
      if load is Some(Object(_)) {
        lines.push(Some(bar_line(load_label(load), "", disabled=false, on_press=fn() { service_load_panel(src, station, p.port, Node(n)) })))
      }
      @sf.menu(lines, from=Node(n))
    }, tips~)
  })
  |> ignore
}

///|
/// Back and forward in the page's own history, in `parent`, each able as the page says it can go there.
fn back_forward_node(parent : @view.View, site : @ui.NativeView, tips : @sf.TipLayer) -> Unit {
  @sf.bar_key_node(parent, fn() { "arrow-left" }, fn() { @sf.t("web-main.keymap.nav.back") }, fn() { site.go_back() }, enabled=fn() {
    site.page_at().1
  }, tips~)
  |> ignore
  @sf.bar_key_node(parent, fn() { "arrow-right" }, fn() { @sf.t("web-main.keymap.nav.forward") }, fn() { site.go_forward() }, enabled=fn() {
    site.page_at().2
  }, tips~)
  |> ignore
}

///|
fn reload_key_node(parent : @view.View, site : @ui.NativeView, tips : @sf.TipLayer) -> Unit {
  @sf.bar_key_node(parent, fn() { "refresh" }, fn() { @sf.t("web-main.preview.reload") }, fn() { site.reload() }, tips~) |> ignore
}

///|
/// The × of the panel the page is alone in, at its bar's end, in `parent` (where it is: `close`).
fn panel_close_key_node(parent : @view.View, close : (() -> Unit)?, tips : @sf.TipLayer) -> Unit {
  match close {
    Some(f) => @sf.bar_key_node(parent, fn() { "close" }, fn() { @sf.t("web-pages.chat.closePanel") }, f, tips~) |> ignore
    None => ()
  }
}

///|
/// 全屏 at the bar's end, in `parent` (`full`: what puts it over the whole window; none there already, or on a page of its
/// own).
fn full_key_node(parent : @view.View, full : (() -> Unit)?, tips : @sf.TipLayer) -> Unit {
  match full {
    Some(f) => @sf.bar_key_node(parent, fn() { "expand" }, fn() { @sf.t("web-main.preview.fullWindow") }, f, tips~) |> ignore
    None => ()
  }
}

///|
/// How far the page's resources came in `parent` (load_key's): a ring in a key's room, red with one failed; pressed,
/// each of them in a panel beside it. Read out a button by its name whatever has come, its ring a progress bar of how
/// far it came.
fn load_key_node(parent : @view.View, src : Source, p : ServicePage, station : String) -> Unit {
  let load = fn() { load_now(src, p, station, false) }
  // (its panel beside the box it is in, which takes no focus: closed, the focus goes back to what had it as it opened,
  // the address being typed in with the mouse's press, the key itself from the keyboard; key_beside)
  let at = key_beside(parent)
  // (to a screen reader one key whatever has come: its name, and its ring how far it came, said as that changes; none
  // said till the station says)
  @sf.bar_meter_button_node(
    at,
    fn() { svc("android-chat.load.name") },
    fn(_) { service_load_panel(src, station, p.port, Node(at)) },
    ring=load_ring_side,
    part=fn() { number(load(), "percent") },
    value=fn() {
      let l = load()
      if l is Some(Object(_)) { load_label(l) } else { "" }
    },
    color=fn() {
      if number(load(), "failed") > 0.0 {
        @sf.theme().p.red
      } else {
        @sf.theme().p.muted
      }
    },
  )
  |> ignore
}

///|
/// A box in `parent` as big as the key made in it, which a menu or a panel the key opens stands beside (@sf.Beside's Node): it
/// takes no focus, so the panel closed gives the focus back to what had it as it opened (View::opened_by), the page's
/// address where it was being typed in as the mouse pressed the key (the web's toolbar keys, which take no focus from
/// it), the key where the keyboard pressed it.
fn key_beside(parent : @view.View) -> @view.View {
  parent.box(fn(at) { at.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore })
}

///|
/// How big the ring of how far the page came is (load_key's 20).
let load_ring_side : Double = 20.0

///|
/// Where it is in `parent` (address_or_marking's, previewAddress: its name, then its path, typed to go elsewhere, a tap
/// anywhere on it typing there where it holds its end key, the foot's), or what marking says in its place while marking or its marks are there; `end` and
/// `part` as @sf.bar_field_node has them (reload at its end, how far the page came along its foot).
fn address_or_marking_node(
  parent : @view.View,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  fixed : Bool,
  end? : ((@view.View) -> Unit)? = None,
  part? : () -> (Double, @ui.Color)? = fn() { None },
  least? : Double = @sf.bar_field_least,
) -> Unit {
  // (its least the place's (@sf.bar_field_node's 160): what may leave the bar leaves before it gives way; `least`
  // where nothing of its row leaves)
  parent.box(fn(slot) {
    slot.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(least))).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
    slot.pick(
      at_once=true,
      fn() {
        p.said()
        p.session != "" && (p.marks.marking || p.marks.marks.length() > 0)
      },
      fn(k, marking) {
        k.grow(Is(1.0)).shrink(Is(1.0)).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
        if marking {
          k.box(fn(m) {
            @sf.style_node(m, fn() { mark_mode_place }, in_row=true)
            page_mark_mode_node(m, src, p, site)
          })
          |> ignore
        } else {
          address_node(k, p, site, fixed, end, part, least)
        }
      },
    )
  })
  |> ignore
}

///|
/// The address in `parent`: the place's capsule (@sf.address_field_node), the web's mark and the service's name, then
/// where its page is, followed while nobody types there; pressed into, its caret at its end (a path after the name, not
/// picked whole: what is typed goes after it), typed to go there (Enter goes; the keyboard's 前往), Escape giving it
/// up; nowhere else to go (a visualization) its name alone.
fn address_node(
  parent : @view.View,
  p : ServicePage,
  site : @ui.NativeView,
  fixed : Bool,
  end : ((@view.View) -> Unit)?,
  part : () -> (Double, @ui.Color)?,
  least : Double,
) -> Unit {
  if fixed {
    @sf.bar_field_node(
      parent,
      fn() { false },
      fn(b) {
        @sf.icon_node(b, "web", @sf.theme().bars.icon, By(fn() { @sf.theme().p.muted })) |> ignore
        b.box(fn(n) {
          @sf.style_node(n, fn() { file_name_box }, in_row=true)
          @sf.words_node(n, fn() {
            p.said()
            p.name
          }, fn() { file_name_words })
          |> ignore
        })
        |> ignore
      },
      end~,
      part~,
      least~,
    )
    |> ignore
    return
  }
  @sf.address_field_node(
    parent,
    p.address,
    fn() { site.page_at().0 },
    fn(path) { site.load(if path.has_prefix("/") { path } else { "/" + path }) },
    fn() { @sf.t("web-main.preview.path") },
    selects=false,
    lead=fn(b) {
      @sf.icon_node(b, "web", @sf.theme().bars.icon, By(fn() { @sf.theme().p.muted })) |> ignore
      @sf.words_node(b, fn() {
        p.said()
        p.name
      }, fn() { address_name_words })
      .shrink(Is(1.0))
      |> ignore
    },
    end~,
    progress=part,
    least~,
    // (a press anywhere on the capsule, its lead too, writes there: @sf.address_field_node)
    anywhere=true,
  )
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let address_name_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false, w=Cut)

///|
/// Its size in `parent` (size_key_of's), on every screen: what it is laid out at (none: as the room is) after its icon,
/// its words the first to leave short of room; its choices pressed open (the presenters' panel); while a finger moves
/// the page in place of using it, said here in the accent with the move icon, and pressed it lets go of moving at once.
fn size_key_node(parent : @view.View, p : ServicePage, tips : @sf.TipLayer) -> Unit {
  let moving = fn() { p.moving.get() }
  // (its panel beside the box it is in: load_key_node's)
  let at = key_beside(parent)
  @sf.action_box_node(
    at,
    fn() { size_said(p) },
    fn(_) {
      if p.moving.untracked() {
        p.moving.set(false)
      } else {
        service_sizes_panel(service_key(p.station, p.job), Node(at))
      }
    },
    fn(v) {
      @sf.style_node(v, fn() {
        if moving() {
          size_key_moving
        } else if p.viewport.get() is Some(_) {
          size_key_sized
        } else {
          size_key
        }
      })
      v.fits(Is(true)) |> ignore
      @sf.hover_ground_node(v, on=fn() { p.viewport.get() is None && !moving() }, lit=Some(fn() {
        v.pointed() || v.pressed() || v.focus_shown()
      }))
      @sf.icon_node(
        v,
        "devices",
        bar_icon_size,
        By(fn() { if moving() { @sf.theme().p.accent_text } else { @sf.theme().p.text } }),
        name_now=fn() { if moving() { "move" } else { "devices" } },
      )
      |> ignore
      v.show(at_once=true, fn() { p.viewport.get() is Some(_) }, fn(w) {
        w.drops(Is(bar_drop_size_words)) |> ignore
        @sf.words_node(w, fn() {
          match p.viewport.get() {
            Some(vp) => dims(vp.width, vp.height)
            None => ""
          }
        }, fn() { if moving() { size_key_words_moving } else { size_key_words } })
        |> ignore
      })
      @sf.tip_node(tips, v, fn() { size_said(p) }) |> ignore
    },
  )
  |> ignore
}

///|
/// Marking the page for the chat's agent in `parent` (mark_key_of's): its edit key, lit while picking; none where the
/// page has no chat to put marks in, nor in a frame of the browser's (marking is page.js's, which it does not run).
fn mark_key_node(parent : @view.View, p : ServicePage, site : @ui.NativeView, tips : @sf.TipLayer) -> Unit {
  parent.show(
    at_once=true,
    fn() {
      p.said()
      p.session != "" && !site.framed()
    },
    fn(k) {
      k.row(Is(true)) |> ignore
      let picking = fn() {
        p.said()
        p.marks.marking
      }
      @sf.bar_key_node(
        k,
        fn() { "edit" },
        fn() { @sf.t(if picking() { "web-main.annotate.stopPicking" } else { "web-main.annotate.mark" }) },
        fn() { page_marks_toggle(p, site) },
        lit=picking,
        ripples=true,
        tips~,
      )
      |> ignore
    },
  )
}

///|
/// All of the room for the page in `parent`, or (laid out at a size of its own) a canvas with the page on it
/// (service_stage's, Preview.kt Stage): fitted (100% at most) and centred, 16 round it, its screen's corners under it;
/// the ground dragged (or, moving it, the page) moves it, two fingers anywhere zoom and move it, a double tap on the
/// ground fits it again; its marks over it; a restart said over it. Its own corners `corners` where it is alone in a
/// panel.
fn service_stage_node(
  parent : @view.View,
  p : ServicePage,
  site : @ui.NativeView,
  corners : (() -> FixedArray[@ui.CornerOf])?,
  now : () -> ServiceNow,
) -> Unit {
  let radii = fn() {
    match corners {
      Some(k) => {
        let r = @sf.corner_radii(k())
        (r[0], r[1], r[2], r[3])
      }
      None => (0.0, 0.0, 0.0, 0.0)
    }
  }
  // who takes a finger on the page: all its own fitted; a sized page's two fingers the canvas's, all of it while it is
  // moved by a finger (told the host as it changes)
  parent.reacts(
    fn() {
      match p.viewport.get() {
        None => @ui.Touch::All
        Some(_) if p.moving.get() => @ui.Touch::Through
        Some(_) => @ui.Touch::PinchOut
      }
    },
    fn(touch) { site.touch(touch) },
  )
  parent.by_room(fn(held, room) {
    let size = fn() { (room.width(), room.height().unwrap_or(0.0)) }
    held.box(fn(st) {
      st
      .height(By(fn() { Some(size().1) }))
      .clips(Is(true))
      .corners(By(fn() { Some(radii()) }))
      // (a sized page on the canvas's grey; one filling it, once drawn, on nothing of the stage's: a ground under it
      // showed along its edges, where the host's cut and the hole's meet within a pixel)
      .ground(By(fn() {
        let t = @sf.theme()
        match p.viewport.get() {
          Some(_) => @sf.mix(t.p.chip, 0.55, t.p.card)
          None => if site.shown() { @sf.no_ground } else { t.p.card }
        }
      }))
      .cursor(Is(Some(Arrow)))
      |> ignore
      stage_fingers(st, p)
      st.pick(at_once=true, fn() { p.viewport.get() is Some(_) }, fn(k, sized) {
        k.over(Is(true)) |> ignore
        if sized {
          sized_page_node(k, p, site, size)
        } else {
          k.reacts(fn() { () }, fn(_) { site.set_scale(1.0) })
          p.placed = None
          @ui.native(k, site, corners=radii, kept=true).over(Is(true)) |> ignore
        }
      })
      // the marks over the page, where it is drawn
      service_marks_over_node(st, p, site, size)
      // over the page while its service starts again (Restart)
      st.show(
        at_once=true,
        fn() {
          p.said()
          p.restarting
        },
        fn(r) {
          r.over(Is(true)).presses(Is(false)) |> ignore
          @sf.style_node(r, fn() { service_restart_room })
          r.box(fn(pill) {
            @sf.style_node(pill, fn() { service_restart_pill })
            @sf.glass_capsule_node(pill) |> ignore
            @sf.first_line_node(pill, Ui, fn(l) {
              l.box(fn(d) { @sf.style_node(d, fn() { service_restart_dot }, in_row=true) }) |> ignore
            })
            |> ignore
            pill.box(fn(w) {
              @sf.style_node(w, fn() { service_restart_words }, in_row=true)
              @sf.words_node(w, fn() {
                p.said()
                @sf.t("web-main.preview.restarting", args=[("name", p.name)])
              }, fn() { service_restart_title })
              |> ignore
              @sf.words_node(w, fn() {
                let n = now().restarts
                if n > 0 {
                  @sf.t("web-main.preview.restartAgain", args=[("n", n.to_string())])
                } else {
                  @sf.t("web-main.preview.restartNote")
                }
              }, fn() { service_restart_note })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        },
      )
    })
    |> ignore
  })
  .grow(Is(1.0))
  .basis(Is(Some(0.0)))
  .min_height(Is(Some(0.0)))
  |> ignore
}

///|
/// Where a page laid out at a size of its own stands on its canvas `size()` as node `n` is drawn: its zoom told the
/// canvas's size and the page's (a page of no height of its own as high as the canvas leaves it at the scale its width
/// is fitted at), its place as its zoom has it then (fitted: on whole points), what it is laid out at.
fn placed_on(p : ServicePage, n : @view.View, size : () -> (Double, Double)) -> Placed? {
  match p.viewport.get() {
    Some(vp) => {
      let z = p.view
      z.told()
      let w = vp.width.to_double()
      let (sw, sh) = size()
      let h = match vp.height {
        Some(x) => x.to_double()
        None => {
          let fitted = dmax(stage_min_scale, (dmin(1.0, (sw - 32.0) / w) * 1000.0).floor() / 1000.0)
          dmax(240.0, ((sh - 32.0) / fitted).floor())
        }
      }
      let t = n.drawn_while(fn(at) { z.goes_at(at) })
      match z.rect_at(t) {
        Some((x, y, rw, _)) if z.fitted => Some({ x: x.round(), y: y.round(), scale: rw / w, w, h })
        Some((x, y, rw, _)) => Some({ x, y, scale: rw / w, w, h })
        None => None
      }
    }
    None => None
  }
}

///|
/// A page laid out at a size of its own on its canvas in `parent` (service_stage's `placed`): its zoom told the canvas's
/// size and the page's as either changes; its white, its shadow and its screen's corners under it, the page where they
/// are, cut round as its screen is; its scale told the host as it changes.
fn sized_page_node(parent : @view.View, p : ServicePage, site : @ui.NativeView, size : () -> (Double, Double)) -> Unit {
  parent.reacts(
    fn() {
      let (sw, sh) = size()
      let vp = p.viewport.get()
      (sw, sh, vp)
    },
    fn(told) {
      let (sw, sh, vp) = told
      match vp {
        Some(vp) => {
          let w = vp.width.to_double()
          let h = match vp.height {
            Some(x) => x.to_double()
            None => {
              let fitted = dmax(stage_min_scale, (dmin(1.0, (sw - 32.0) / w) * 1000.0).floor() / 1000.0)
              dmax(240.0, ((sh - 32.0) / fitted).floor())
            }
          }
          let at = parent.cause_at()
          p.view.boxed(sw, sh, at~)
          p.view.natural(w, h, at~)
        }
        None => ()
      }
    },
  )
  let placed = fn(n : @view.View) { placed_on(p, n, size) }
  parent.reacts(
    fn() {
      p.view.told()
      p.view.scale
    },
    fn(scale) { site.set_scale(scale) },
  )
  let corner = fn(n : @view.View) {
    match placed(n) {
      Some(pl) => corner_of(p.viewport.get().map(fn(v) { v.width }).unwrap_or(0), pl.scale) * pl.scale
      None => 0.0
    }
  }
  let place = fn(b : @view.View) {
    b
    .over(Is(true))
    .offset(By(fn() {
      match placed(b) {
        Some(pl) => {
          p.placed = Some(pl)
          (pl.x, pl.y)
        }
        None => (0.0, 0.0)
      }
    }))
    .width(By(fn() { placed(b).map(fn(pl) { pl.w * pl.scale }) }))
    .height(By(fn() { placed(b).map(fn(pl) { pl.h * pl.scale }) }))
    |> ignore
  }
  parent.box(fn(card) {
    place(card)
    card
    .radius(By(fn() { corner(card) }))
    .shadow(By(fn() { (@sf.bubble_raised.sigma, @sf.bubble_raised.dy, @sf.bubble_raised.color) }))
    .ground(Is(0xFFFFFFFFL))
    |> ignore
  })
  |> ignore
  parent.box(fn(k) {
    place(k)
    k.presses(Is(false)) |> ignore
    @ui.native(k, site, corners=fn() {
      let r = corner(k)
      (r, r, r, r)
    }, kept=true).over(Is(true)) |> ignore
  })
  |> ignore
}

///|
/// The stage's fingers in `st` (stage_gestures's, at their moments): on a sized page the ground's (or, moving it, the
/// page's) one finger moves the page, two anywhere zoom and move it about the point between them, a double tap on the
/// ground fits it again; what the canvas is given of a finger on the page (two fingers; all, moving it) its to handle.
fn stage_fingers(st : @view.View, p : ServicePage) -> Unit {
  let fingers : Map[Int, (Double, Double)] = Map([])
  st.on_drag(
    fn(d) {
      guard p.viewport.untracked() is Some(_) else { return }
      let at = d.at
      let (ox, oy) = (d.x - d.wx, d.y - d.wy)
      let now = fn() { fingers.values().map(fn(f) { (f.0 + ox, f.1 + oy) }).to_array() }
      match d.kind {
        Down => {
          fingers[d.finger] = (d.wx, d.wy)
          if fingers.length() == 1 {
            let on_page = match p.placed {
              Some(pl) => d.x >= pl.x && d.x <= pl.x + pl.w * pl.scale && d.y >= pl.y && d.y <= pl.y + pl.h * pl.scale
              None => false
            }
            p.hold = Some({ was: now(), travelled: 0.0, on_page })
          } else {
            match p.hold {
              Some(h) => h.was = now()
              None => ()
            }
          }
        }
        Moved => {
          fingers[d.finger] = (d.wx, d.wy)
          match p.hold {
            Some(h) => {
              let pts = now()
              if pts.length() != h.was.length() {
                h.was = pts
              } else if pts.length() == 1 {
                let (x0, y0) = h.was[0]
                let (x1, y1) = pts[0]
                h.travelled = h.travelled + ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
                p.view.pan(x1 - x0, y1 - y0, at~)
                h.was = pts
              } else {
                let mid = fn(ps : Array[(Double, Double)]) { ((ps[0].0 + ps[1].0) / 2.0, (ps[0].1 + ps[1].1) / 2.0) }
                let apart = fn(ps : Array[(Double, Double)]) {
                  let dx = ps[0].0 - ps[1].0
                  let dy = ps[0].1 - ps[1].1
                  dmax(1.0, (dx * dx + dy * dy).sqrt())
                }
                let (m0x, m0y) = mid(h.was)
                let (m1x, m1y) = mid(pts)
                p.view.transform(m0x, m0y, apart(pts) / apart(h.was), m1x - m0x, m1y - m0y, at~)
                h.was = pts
              }
            }
            None => ()
          }
        }
        Up | Off => {
          fingers.remove(d.finger)
          if fingers.is_empty() {
            // a double tap on the ground (not the page, a finger hardly moved) fits it again
            match p.hold {
              Some(h) if d.kind == Up && !h.on_page && h.travelled < stage_tap_slop && st.twice(d) => p.view.fit_now(at~)
              _ => ()
            }
            p.hold = None
          } else {
            match p.hold {
              Some(h) => h.was = now()
              None => ()
            }
          }
        }
      }
    },
    fingers=2,
    whole=true,
  )
  |> ignore
}

///|
/// What is said where the page would be, in `parent` (service_note's, PreviewNote): 13, muted, centred.
fn service_note_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(n) {
    @sf.style_node(n, fn() { file_wait })
    @sf.words_node(n, words, fn() { note_words }) |> ignore
  })
  |> ignore
}

///|
/// What it waits on where its note would be, in `parent` (PreviewWait: 20 in, 8 over and under, in the middle).
fn service_wait_node(parent : @view.View, words : () -> String) -> Unit {
  parent.box(fn(n) {
    @sf.style_node(n, fn() { file_wait })
    @sf.wait_line_node(n, words) |> ignore
  })
  |> ignore
}

///|
/// A station's name as the workspace's stations say it ("" where they say none).
fn station_label(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.exact_view(end=i).to_owned()
    None => station
  }
  match @sfbase.station_marks(src, scope).iter().find_first(fn(s) { s.address == station }) {
    Some(s) => s.name
    None => ""
  }
}

///|
/// A page's compact bar in `parent` (the phone's service_bar): 对话 back in the accent (`on_back`), the page's name and
/// its station on one line, from `top` above it down (the status bar's height as it is).
fn service_page_top_node(parent : @view.View, src : Source, station : String, name : () -> String, on_back : () -> Unit, top : () -> Double) -> Unit {
  @sf.nav_bar_node(parent, fn() { svc("android-chat.preview.back") }, fn() {
    let s = station_label(src, station)
    if s == "" {
      name()
    } else {
      name() + " · " + s
    }
  }, on_back, top~)
}

///|
/// The service `job` of `station`'s page in `v` (the phone's stack's, service_page's: Preview.kt PreviewScreen), found
/// by its job (the `job` topic), known by its name: its bar under the status bar (`top`), its way back `on_back`; the
/// page while it is up (and as it starts again), what stopped it, that it is not found, or that it is read, said in its
/// place; over the navigation bar (`foot`).
pub fn service_page_node(
  v : @view.View,
  src : Source,
  station : String,
  job : String,
  on_back : () -> Unit,
  top : () -> Double,
  foot : () -> Double,
) -> Unit {
  let found = fn() { src.topic("job", { "station": Json::string(station), "id": Json::string(job) }).get().snapshot() }
  let name = fn() {
    match text(found().value, "name") {
      "" => svc("android-chat.preview.service")
      n => n
    }
  }
  v
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .ground(By(fn() { @sf.theme().p.bg }))
  .padding(By(fn() { (0.0, 0.0, 0.0, foot()) }))
  |> ignore
  service_page_top_node(v, src, station, name, on_back, top)
  // what it shows: 0 read, 1 not found, 2 stopped, 3 up
  let state = fn() {
    let f = found()
    let j = f.value
    match (j, f.error) {
      (None, Some(_)) | (Some(Null), Some(_)) => 1
      (None, _) | (Some(Null), _) => 0
      _ => if number(j, "port").to_int() > 0 && flag(j, "open") { 3 } else { 2 }
    }
  }
  v.pick(at_once=true, state, fn(b, what) {
    b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    match what {
      0 => service_wait_node(b, fn() { svc("common.reading") })
      1 => service_note_node(b, fn() { svc("android-chat.preview.notFound", args=[("error", text(found().error, "message"))]) })
      2 => service_note_node(b, fn() { svc("android-chat.preview.stopped", args=[("name", name())]) })
      _ =>
        service_view_node(
          b,
          src,
          station,
          job,
          fn() {
            let j = found().value
            {
              port: number(j, "port").to_int(),
              name: name(),
              restarting: text(j, "state") == "exited",
              restarts: number(j, "restarts").to_int(),
              session: text(j, "session"),
            }
          },
          fn() { b.window_w() },
        )
    }
  })
}

///|
/// The visualization at `path` of the session `key` of `station` as a page of its own in `v` (preview_file_page's, web
/// mobile's Preview.tsx for a `file:` service): the file served to the page from here with what its widget kept (and
/// keeps from now on); its bar has only its name. Read as it is made; what it waits on, or that it could not be read,
/// said in its place.
pub fn preview_file_page_node(
  v : @view.View,
  src : Source,
  station : String,
  key : String,
  path : String,
  name : String,
  on_back : () -> Unit,
  top : () -> Double,
  foot : () -> Double,
) -> Unit {
  v
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .ground(By(fn() { @sf.theme().p.bg }))
  .padding(By(fn() { (0.0, 0.0, 0.0, foot()) }))
  |> ignore
  service_page_top_node(v, src, station, fn() { name }, on_back, top)
  file_view_node(v, src, station, key, path, name, None)
}

///|
/// A visualization's view in `parent` (its page, or a chat's side panel's tab: file_pane's): read as it is made, the
/// file's page served from here as its service's view (kept by its station and job while its page is in the stack),
/// what it waits on or that it could not be read said in its place; `close` and `full` as service_view_node has them.
pub fn file_view_node(
  parent : @view.View,
  src : Source,
  station : String,
  key : String,
  path : String,
  name : String,
  close : (() -> Unit)?,
  full? : (() -> Unit)? = None,
  tips? : @sf.TipLayer,
  beside? : (() -> Unit)? = None,
  bar? : ((@view.View) -> Unit)? = None,
) -> Unit {
  let loaded = @sfbase.viz_load_node(parent, src, station, key, path)
  // (a window of its own's bar over what is said while it is not read: `bar`; read, its page's own bar the window's)
  let barred = fn(b : @view.View) {
    match bar {
      Some(make) => make(b)
      None => ()
    }
  }
  parent.pick(
    at_once=true,
    fn() {
      match loaded() {
        Some(Err(_)) => 1
        None => 0
        Some(Ok(_)) => 2
      }
    },
    fn(b, what) {
      b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      match what {
        0 => {
          service_wait_node(b, fn() { @sfbase.viz_tr("common.opening") })
          barred(b)
        }
        1 => {
          service_note_node(b, fn() { @sfbase.viz_tr("android-chat.preview.unreadable", args=[("name", name)]) })
          barred(b)
        }
        _ => {
          let job = "file:" + key + "\n" + path
          let f = match @sfbase.service_files.get(service_key(station, job)) {
            Some(f) => f
            None =>
              match @signals.untracked(loaded) {
                Some(Ok((html, state))) => {
                  let f : FilePage = { html, state, station, key, path }
                  @sfbase.service_files[service_key(station, job)] = f
                  f
                }
                _ => return
              }
          }
          service_view_node(
            b,
            src,
            station,
            job,
            fn() { { port: 0, name, restarting: false, restarts: 0, session: key } },
            fn() { b.window_w() },
            file=Some(f),
            close~,
            full~,
            tips?,
            beside~,
          )
        }
      }
    },
  )
}
