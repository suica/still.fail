///|
pub(all) struct Node {
  tag : String
  mut src_url : String?
  mut natural : (Double, Double)?
  children : Array[Node]
}

///|
pub fn parse(s : String) -> Node {
  ignore(s)
  { tag: "", src_url: None, natural: None, children: [] }
}
