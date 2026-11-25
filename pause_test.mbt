///|
fn paused_stream(
  wire : BytesView,
  split : Int,
  stop : Int,
) -> (Array[@netstring.Event], @netstring.NetstringError?) raise {
  let parser = @netstring.StreamingDecoder::new(max_len=100)
  let events = []
  let mut total = 0L
  let mut accurate = true
  let error = try {
    for chunk in [wire[:split], wire[split:]] {
      let mut consumed = 0
      while consumed < chunk.length() {
        let count = parser.feed_some(chunk[consumed:], fn(event) {
          events.push(event)
          events.length() != stop
        })
        if count <= 0 { accurate = false; break }
        consumed = consumed + count
        total = total + count.to_int64()
        accurate = accurate && parser.offset() == total
      }
    }
    parser.finish()
    None
  } catch { e => Some(e) }
  assert_true(accurate)
  (events, error)
}

///|
test "event backpressure preserves all cuts, stop points and first errors" {
  for wire in [b"0:,3:a\x00b,2:cd,"[:], b"1:a,2:bc!bad"[:], b"3:ab"[:], b"01:a,"[:]] {
    for split = 0; split <= wire.length(); split = split + 1 {
      let parser = @netstring.StreamingDecoder::new(max_len=100)
      let expected = []
      let expected_error = try {
        parser.feed(wire[:split], fn(e) { expected.push(e) })
        parser.feed(wire[split:], fn(e) { expected.push(e) })
        parser.finish()
        None
      } catch { e => Some(e) }
      for stop = 0; stop <= expected.length() + 1; stop = stop + 1 {
        let (events, error) = paused_stream(wire, split, stop)
        assert_eq(events, expected)
        assert_eq(error, expected_error)
      }
    }
  }
}

///|
test "stream pause consumes exact prefix and does not examine suffix" {
  let d = @netstring.StreamingDecoder::new()
  let wire = b"1:a,x"
  let n = d.feed_some(wire, fn(e) { e != @netstring.End })
  assert_eq(n, 4)
  assert_eq(d.offset(), 4L)
  assert_false(d.pending())
  d.finish()
  d.reset()
  let m = d.feed_some(wire, fn(_) { false })
  assert_eq(m, 2)
  assert_eq(d.offset(), 2L)
  assert_true(d.pending())
  let err = try { d.finish(); None } catch { e => Some(e) }
  assert_eq(err, Some(@netstring.NetstringError(Truncated, 2L)))
}

///|
test "frame backpressure handles every split and validates only consumed prefix" {
  let wire = b"0:,3:a\x00b,1:c,x"
  for split = 0; split <= wire.length(); split = split + 1 {
    let d = @netstring.Decoder::new()
    let frames = []
    let mut total = 0
    let err = try {
      for part in [wire[:split], wire[split:]] {
        let mut i = 0
        while i < part.length() {
          let n = d.feed_some(part[i:], fn(f) { frames.push(f.to_owned()); false })
          i = i + n
          total = total + n
        }
      }
      None
    } catch { e => Some(e) }
    assert_eq(frames, [b"", b"a\x00b", b"c"])
    assert_eq(err, Some(@netstring.NetstringError(InvalidByte, 13L)))
    assert_eq(total, 13)
  }
  let d = @netstring.Decoder::new()
  let consumed = d.feed_some(b"1:a,x", fn(_) { false })
  assert_eq(consumed, 4)
  assert_eq(d.offset(), 4L)
  d.finish()
}

///|
test "paused buffered decoder rejects reentrant mutations without losing frames" {
  let d = @netstring.Decoder::new()
  let errors = []
  let n = d.feed_some(b"2:ab,1:c,", fn(_) {
    try d.reset() catch { e => errors.push(e) }
    try { ignore(d.feed_some(b"0:,", fn(_) { true })) } catch { e => errors.push(e) }
    false
  })
  assert_eq(n, 5)
  assert_eq(errors.length(), 2)
  for e in errors { assert_eq(e.kind(), @netstring.Reentrant) }
  let frames = []
  d.feed(b"1:c,", fn(f) { frames.push(f.to_owned()) })
  assert_eq(frames, [b"c"])
  d.finish()
}
