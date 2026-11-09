///|
/// Read the first complete frame without examining its suffix. Return its
/// borrowed payload and consumed byte count, or None for a valid incomplete
/// prefix (including empty input). Malformed or oversized prefixes raise.
pub fn try_decode_prefix(
  input : BytesView,
  max_len~ : Int32 = 2_147_483_647,
) -> (BytesView, Int32)? raise NetstringError {
  let decoder = Decoder::new(max_len~)
  let mut first : BytesView? = None
  let consumed = decoder.feed_some(input, fn(payload) {
    first = Some(payload)
    false
  })
  first.map(fn(payload) { (payload, consumed) })
}

///|
/// Require one complete first frame. Any suffix is left unexamined; valid but
/// incomplete input raises Truncated at its end. Returned payload borrows input.
pub fn decode_prefix(
  input : BytesView,
  max_len~ : Int32 = 2_147_483_647,
) -> (BytesView, Int32) raise NetstringError {
  match try_decode_prefix(input, max_len~) {
    Some(frame) => frame
    None => raise NetstringError(Truncated, input.length().to_int64())
  }
}
