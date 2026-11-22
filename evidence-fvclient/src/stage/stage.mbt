pub struct Stage { dummy : Bool }
pub(all) struct MenuHit { x : Double; y : Double; link : String; image : String; image_bytes : Bytes?; selection : String; can_back : Bool; can_forward : Bool }
pub fn Stage::new(_send : (Bytes) -> Unit, forget~ : (String) -> Unit, fonts~ : Array[Bytes]) -> Stage { ignore(forget); ignore(fonts); { dummy: false } }
pub fn Stage::feed(_self : Stage, _bytes : Bytes) -> Unit { () }
pub fn Stage::opened(_self : Stage) -> Unit { () }
pub fn Stage::closed(_self : Stage) -> Unit { () }
pub fn Stage::find(_self : Stage, _query : String) -> Unit { () }
pub fn Stage::find_clear(_self : Stage) -> Unit { () }
pub fn Stage::find_step(_self : Stage, _delta : Int) -> Unit { () }
pub fn Stage::find_place(_self : Stage) -> (Int, Int) { (0, 0) }
pub fn Stage::zoom(_self : Stage) -> Double { 1.0 }
pub fn Stage::zoom_reset(_self : Stage) -> Unit { () }
pub fn Stage::zoom_in(_self : Stage) -> Unit { () }
pub fn Stage::zoom_out(_self : Stage) -> Unit { () }
pub fn Stage::back(_self : Stage) -> Unit { () }
pub fn Stage::forward(_self : Stage) -> Unit { () }
pub fn Stage::reload(_self : Stage) -> Unit { () }
pub fn Stage::can_back(_self : Stage) -> Bool { false }
pub fn Stage::can_forward(_self : Stage) -> Bool { false }
pub fn Stage::go(_self : Stage, _url : String) -> Unit { () }
pub fn Stage::url(_self : Stage) -> String { "" }
pub fn Stage::agent(_self : Stage) -> Bool { false }
pub fn Stage::take_over(_self : Stage) -> Unit { () }
pub fn Stage::open_link_new_tab(_self : Stage, _url : String) -> Unit { () }
pub fn Stage::copy_selection(_self : Stage) -> Bool { false }
pub fn Stage::cancel_file_pick(_self : Stage, _id : Int) -> Unit { () }
pub fn Stage::give_files(_self : Stage, _id : Int, _files : Array[(String, String, Bytes)]) -> Unit { () }
pub fn Stage::file_pick(_self : Stage) -> (Int, Int, String, Bool)? { None }
pub fn Stage::take_downloads(_self : Stage) -> Array[(String, String, String, Bytes)] { [] }
pub fn Stage::downloads_seq(_self : Stage) -> Int { 0 }
pub fn Stage::opens_seq(_self : Stage) -> (Int, String) { (0, "") }
pub fn Stage::closed_by_page(_self : Stage) -> Int { 0 }
pub fn Stage::add_font(_self : Stage, _font : Bytes) -> Unit { () }
pub fn stage_node(v : @view.View, _stage : Stage, height~ : (() -> Double)?, on_menu~ : ((MenuHit) -> Unit)?) -> @view.View { ignore(height); ignore(on_menu); v }
pub fn page_keys() -> Array[@view.Binding] { [] }
