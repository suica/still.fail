///|
/// Local stand-in for Farview's stage (the real one is the private AFK-surf/farview).
pub struct Stage {
  send : (Bytes) -> Unit
  mut url_ : String
}

///|
pub fn Stage::new(send : (Bytes) -> Unit, forget? : (String) -> Unit = fn(_) { () }, fonts? : Array[Bytes] = []) -> Stage {
  ignore(forget)
  ignore(fonts)
  { send, url_: "" }
}

///|
pub fn Stage::feed(self : Stage, b : Bytes) -> Unit {
  ignore(self)
  ignore(b)
}

///|
pub fn Stage::opened(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn Stage::closed(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn Stage::add_font(self : Stage, f : Bytes) -> Unit {
  ignore(self)
  ignore(f)
}

///|
pub fn Stage::reload(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn Stage::back(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn Stage::forward(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn Stage::go(self : Stage, url : String) -> Unit {
  self.url_ = url
}

///|
pub fn Stage::url(self : Stage) -> String {
  self.url_
}

///|
pub fn Stage::can_back(self : Stage) -> Bool {
  ignore(self)
  false
}

///|
pub fn Stage::can_forward(self : Stage) -> Bool {
  ignore(self)
  false
}

///|
pub fn Stage::agent(self : Stage) -> Bool {
  ignore(self)
  false
}

///|
pub fn Stage::take_over(self : Stage) -> Unit {
  ignore(self)
}

///|
pub fn page_keys() -> Array[@view.Binding] {
  []
}

///|
pub fn phase_mark(s : Stage) -> String {
  ignore(s)
  ""
}

///|
pub fn stage_node(p : @view.View, stage : Stage, height? : (() -> Double)? = None, on_menu? : ((MenuHit) -> Unit)? = None) -> @view.View {
  ignore(stage)
  ignore(height)
  ignore(on_menu)
  p
}

///|
pub(all) struct MenuHit {
  x : Double
  y : Double
  link : String
  image : String
  image_bytes : Bytes?
  selection : String
  can_back : Bool
  can_forward : Bool
}
pub fn Stage::find(self : Stage, q : String) -> Unit { ignore(self); ignore(q) }
pub fn Stage::find_clear(self : Stage) -> Unit { ignore(self) }
pub fn Stage::find_step(self : Stage, d : Int) -> Unit { ignore(self); ignore(d) }
pub fn Stage::find_place(self : Stage) -> (Int, Int) { ignore(self); (0, 0) }
pub fn Stage::zoom(self : Stage) -> Double { ignore(self); 1.0 }
pub fn Stage::zoom_in(self : Stage) -> Unit { ignore(self) }
pub fn Stage::zoom_out(self : Stage) -> Unit { ignore(self) }
pub fn Stage::zoom_reset(self : Stage) -> Unit { ignore(self) }
pub fn Stage::open_link_new_tab(self : Stage, l : String) -> Unit { ignore(self); ignore(l) }
pub fn Stage::copy_selection(self : Stage) -> Bool { ignore(self); false }
pub fn Stage::cancel_file_pick(self : Stage, i : Int) -> Unit { ignore(self); ignore(i) }
pub fn Stage::give_files(self : Stage, i : Int, f : Array[(String, String, Bytes)]) -> Unit { ignore(self); ignore(i); ignore(f) }
pub fn Stage::take_downloads(self : Stage) -> Array[(String, String, String, Bytes)] { ignore(self); [] }
pub fn Stage::file_pick(self : Stage) -> (Int, Int, String, Bool)? { ignore(self); None }
pub fn Stage::downloads_seq(self : Stage) -> Int { ignore(self); 0 }
pub fn Stage::opens_seq(self : Stage) -> (Int, String) { ignore(self); (0, "") }
pub fn Stage::closed_by_page(self : Stage) -> Int { ignore(self); 0 }
