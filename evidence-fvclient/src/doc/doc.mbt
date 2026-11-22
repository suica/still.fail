pub(all) struct DocState { base : String; root : @html.Node; frames : Array[String]; sheets : Array[(String, String)]; cssom : Array[String]; defined : (String) -> Bool; states : (String) -> Int; target : String }
pub struct Mirror { dummy : Bool }
pub fn Mirror::new() -> Mirror { { dummy: false } }
pub fn Mirror::reset(_self : Mirror, _state : DocState) -> Bytes { b"" }
