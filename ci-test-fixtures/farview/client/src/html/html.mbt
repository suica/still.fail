pub(all) struct Node { tag : String; mut src_url : String?; mut natural : (Double, Double)?; children : Array[Node] }
pub fn parse(_s : String) -> Node { { tag: "", src_url: None, natural: None, children: [] } }
