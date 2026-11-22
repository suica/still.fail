///|
pub const VERSION : Int = 1

///|
pub const NAV_GO : Int = 0

///|
pub const NAV_BACK : Int = 1

///|
pub const NAV_FORWARD : Int = 2

///|
pub const POINTER_DOWN : Int = 0

///|
pub const POINTER_MOVE : Int = 1

///|
pub const POINTER_UP : Int = 2

///|
pub(all) enum HostMsg {
  Meta(String, String, Bool, Bool, Bool)
  Reset(Int, Int, Bytes)
  AgentOn(Bool)
  Asset(String, Int, Double, Double, Bytes)
  Downloaded(String, String, String, Bytes)
}

///|
pub(all) enum ClientMsg {
  Nav(Int, String)
  Pointer(Int, Double, Double)
}

///|
pub fn encode_host(m : HostMsg) -> Bytes {
  ignore(m)
  b""
}

///|
pub fn decode_client(b : BytesView) -> ClientMsg? {
  ignore(b)
  None
}

///|
pub struct Framer {
  buf : Array[Byte]
}

///|
pub fn Framer::new() -> Framer {
  { buf: [] }
}

///|
pub fn Framer::push(self : Framer, b : BytesView) -> Unit {
  for x in b {
    self.buf.push(x)
  }
}

///|
pub fn Framer::next(self : Framer) -> BytesView? {
  ignore(self)
  None
}
