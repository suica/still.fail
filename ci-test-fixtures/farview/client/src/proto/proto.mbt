pub(all) enum HostMsg { Meta(String, String, Bool, Bool, Bool); Reset(Int, Int, Bytes); Asset(String, Int, Double, Double, Bytes); AgentOn(Bool); Downloaded(String, String, String, Bytes) }
pub(all) enum ClientMsg { Nav(Int, String) }
pub const NAV_GO : Int = 0
pub const NAV_BACK : Int = 1
pub const NAV_FORWARD : Int = 2
pub fn encode_host(_msg : HostMsg) -> Bytes { b"" }
pub fn decode_client(_bytes : Bytes) -> ClientMsg? { None }
pub struct Framer { dummy : Bool }
pub fn Framer::new() -> Framer { { dummy: false } }
pub fn Framer::push(_self : Framer, _bytes : BytesView) -> Unit { () }
pub fn Framer::next(_self : Framer) -> Bytes? { None }
