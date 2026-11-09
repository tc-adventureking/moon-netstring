///|
/// Strictly decode all frames and reject any incomplete trailing frame.
/// The default limit is Int's maximum. Returned views retain input backing Bytes.
pub fn decode(
  input : BytesView,
  max_len~ : Int32 = 2_147_483_647,
) -> Array[BytesView] raise NetstringError {
  let parser = Decoder::new(max_len~)
  let frames = []
  parser.feed(input, fn(frame) { frames.push(frame) })
  parser.finish()
  frames
}
