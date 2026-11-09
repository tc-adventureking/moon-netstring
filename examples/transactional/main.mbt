///|
/// Keep provisional metrics separate until End validates the frame terminator.
/// A real consumer can use the same boundary to commit a database transaction
/// or rename a temporary file; this portable example counts delivered bytes.
fn main raise {
  let parser = @netstring.StreamingDecoder::new(max_len=1024)
  let mut provisional = 0L
  let mut committed_bytes = 0L
  let mut committed_frames = 0
  try {
    for chunk in [b"5:he"[:], b"llo,3:ab"[:], b"!bad"[:]] {
      parser.feed(chunk, fn(event) {
        match event {
          Begin(_) => provisional = 0L
          Data(part) => provisional = provisional + part.length().to_int64()
          End => {
            committed_bytes = committed_bytes + provisional
            committed_frames = committed_frames + 1
            provisional = 0L
          }
        }
      })
    }
    parser.finish()
  } catch {
    error => {
      println("discarded_bytes=\{provisional}, error_offset=\{error.offset()}")
      provisional = 0L
    }
  }
  println(
    "committed_frames=\{committed_frames}, committed_bytes=\{committed_bytes}",
  )
  println("pending_transaction_bytes=\{provisional}")
}
