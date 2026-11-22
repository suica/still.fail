///|
pub(all) struct DocState {
  base : String
  root : @html.Node
  frames : Array[DocState]
  sheets : Array[(String, String)]
  cssom : Array[String]
  defined : (String) -> Bool
  states : (@html.Node) -> Int
  target : String
}

///|
pub struct Mirror {
  mut n : Int
}

///|
pub fn Mirror::new() -> Mirror {
  { n: 0 }
}

///|
pub fn Mirror::reset(self : Mirror, state : DocState) -> Bytes {
  ignore(state)
  self.n += 1
  b""
}
