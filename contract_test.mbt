///|
test "binary, batch and byte lengths" {
  let output = @buffer.Buffer()
  output.write_bytesview(b"prefix:")
  @netstring.encode_to(output, b"hi")
  assert_eq(output.to_bytes(), b"prefix:2:hi,")
  assert_eq(@netstring.encode(b"A\x00:,"), b"4:A\x00:,,")
  assert_eq(@netstring.encode_all([b""[:], b"hi"[:]]), b"0:,2:hi,")
  let frames = @netstring.decode(b"0:,2:hi,")
  assert_eq(frames, [b""[:], b"hi"[:]])
  assert_eq(@netstring.decode(b""), [])
}

///|
fn error_for(bytes : BytesView, limit : Int) -> @netstring.NetstringError? {
  try {
    ignore(@netstring.decode(bytes, max_len=limit))
    None
  } catch { error => Some(error) }
}

///|
test "strict syntax and exact errors" {
  let cases : Array[(BytesView, @netstring.ErrorKind, Int64)] = [
    (b":"[:], EmptyLength, 0L),
    (b"00:,"[:], LeadingZero, 1L),
    (b"01:a,"[:], LeadingZero, 1L),
    (b"+1:a,"[:], InvalidByte, 0L),
    (b"1:a!"[:], MissingComma, 3L),
    (b"1:a"[:], Truncated, 3L),
    (b"1"[:], Truncated, 1L),
    (b"4:"[:], TooLong, 0L),
  ]
  for (wire, kind, offset) in cases {
    assert_eq(error_for(wire, 3), Some(@netstring.NetstringError(kind, offset)))
  }
  assert_eq(error_for(b"1:a,", 0), Some(@netstring.NetstringError(TooLong, 0L)))
  assert_eq(@netstring.decode(b"0:,", max_len=0), [b""[:]])
  assert_eq(error_for(b"2147483648:", 2_147_483_647), Some(@netstring.NetstringError(TooLong, 9L)))
}

///|
test "all cuts deliver the same frames" {
  let wire = b"0:,5:he\x00lo,3::,,," // payload ':,,' plus terminator
  let expected : Array[Bytes] = [b"", b"he\x00lo", b":,,"]
  for split = 0; split <= wire.length(); split = split + 1 {
    let decoder = @netstring.Decoder::new()
    let frames = []
    decoder.feed(wire[:split], fn(frame) { frames.push(frame.to_owned()) })
    decoder.feed(b"", fn(frame) { frames.push(frame.to_owned()) })
    decoder.feed(wire[split:], fn(frame) { frames.push(frame.to_owned()) })
    decoder.finish()
    assert_eq(frames, expected)
    assert_false(decoder.pending())
  }
}

///|
test "whole-batch codec preserves frame boundaries in both directions" {
  let frames = [b""[:], b":\xff,\x00"[:], b"0123456789"[:], b""[:]]
  let wire = b"0:,4::\xff,\x00,10:0123456789,0:,"
  assert_eq(@netstring.encode_all(frames), wire)
  assert_eq(@netstring.decode(wire, max_len=10), frames)
}

///|
test "whole-batch decode rejects a bad or truncated suffix after a valid frame" {
  let cases : Array[(Bytes, @netstring.ErrorKind, Int64)] = [
    (b"1:a,00:,", LeadingZero, 5L),
    (b"1:a,2:xy!", MissingComma, 8L),
    (b"1:a,2", Truncated, 5L),
    (b"1:a,2:x", Truncated, 7L),
    (b"1:a,2:xy", Truncated, 8L),
    (b"1:a,3:abc,", TooLong, 4L),
  ]
  for (wire, kind, offset) in cases {
    assert_eq(error_for(wire[:], 2), Some(@netstring.NetstringError(kind, offset)))
  }
}

///|
test "all cuts preserve first error and prior frames" {
  let wire = b"1:a,2:xy!0:,"
  for split = 0; split <= wire.length(); split = split + 1 {
    let decoder = @netstring.Decoder::new()
    let frames = []
    let error = try {
      decoder.feed(wire[:split], fn(frame) { frames.push(frame.to_owned()) })
      decoder.feed(wire[split:], fn(frame) { frames.push(frame.to_owned()) })
      None
    } catch { e => Some(e) }
    assert_eq(frames, [b"a"])
    assert_eq(error, Some(@netstring.NetstringError(MissingComma, 8L)))
    let again = try { decoder.finish(); None } catch { e => Some(e) }
    assert_eq(again, error)
    let feed_again = try { decoder.feed(b"0:,", fn(_) {}); None } catch { e => Some(e) }
    assert_eq(feed_again, error)
    decoder.reset()
    assert_eq(decoder.offset(), 0L)
    decoder.feed(b"0:,", fn(frame) { frames.push(frame.to_owned()) })
    assert_eq(frames, [b"a", b""])
  }
}

///|
test "stream data is provisional and end commits" {
  let decoder = @netstring.StreamingDecoder::new()
  let events = []
  decoder.feed(b"3:ab", fn(e) { events.push(e) })
  decoder.feed(b"c", fn(e) { events.push(e) })
  assert_eq(events, [@netstring.Begin(3), Data(b"ab"[:]), Data(b"c"[:])])
  let error = try { decoder.feed(b"!", fn(e) { events.push(e) }); None } catch { e => Some(e) }
  assert_eq(error, Some(@netstring.NetstringError(MissingComma, 5L)))
  assert_eq(events.length(), 3)
}

///|
test "empty, closed and reset lifecycles" {
  let decoder = @netstring.StreamingDecoder::new(max_len=0)
  let events = []
  decoder.feed(b"0:,", fn(e) { events.push(e) })
  assert_eq(events, [@netstring.Begin(0), End])
  decoder.finish()
  decoder.finish()
  let closed = try { decoder.feed(b"", fn(_) {}); None } catch { e => Some(e) }
  assert_eq(closed, Some(@netstring.NetstringError(Closed, 3L)))
  decoder.finish()
  decoder.reset()
  decoder.feed(b"0", fn(_) {})
  assert_true(decoder.pending())
  let truncated = try { decoder.finish(); None } catch { e => Some(e) }
  assert_eq(truncated, Some(@netstring.NetstringError(Truncated, 1L)))
}

///|
test "invalid limits are errors" {
  let error = try { ignore(@netstring.Decoder::new(max_len=-1)); None } catch { e => Some(e) }
  assert_eq(error, Some(@netstring.NetstringError(InvalidLimit, 0L)))
}

///|
test "reentrant mutations cannot corrupt active frames" {
  let decoder = @netstring.StreamingDecoder::new()
  let errors = []
  decoder.feed(b"1:a,", fn(_) {
    try decoder.reset() catch { e => errors.push(e) }
    try decoder.finish() catch { e => errors.push(e) }
    try decoder.feed(b"0:,", fn(_) {}) catch { e => errors.push(e) }
  })
  assert_eq(errors.length(), 9)
  for error in errors { assert_eq(error.kind(), @netstring.Reentrant) }
  decoder.finish()
}

///|
test "bytewise buffered decoder and provisional bytes never deliver early" {
  let decoder = @netstring.Decoder::new()
  let frames = []
  let wire = b"4:abc!,"
  for i = 0; i < wire.length() - 1; i = i + 1 {
    decoder.feed(wire[i:i + 1], fn(f) { frames.push(f.to_owned()) })
    assert_eq(frames.length(), 0)
  }
  decoder.feed(wire[wire.length() - 1:], fn(f) { frames.push(f.to_owned()) })
  assert_eq(frames, [b"abc!"])
  decoder.finish()
}

///|
test "generated binary roundtrips and streaming agree" {
  for n = 0; n < 1024; n = n + 1 {
    let bytes = Bytes::from_array(Array::makei(n, fn(i) { ((i * 79 + n * 31) % 256).to_byte() })[:])
    let wire = @netstring.encode(bytes)
    assert_eq(@netstring.decode(wire), [bytes[:]])
    let decoder = @netstring.Decoder::new(max_len=1024)
    let stream = @netstring.StreamingDecoder::new(max_len=1024)
    let mut frame = b""
    let data : Array[BytesView] = []
    let mut ends = 0
    let chunk = 1 + n % 17
    let mut start = 0
    while start < wire.length() {
      let end = if start + chunk > wire.length() { wire.length() } else { start + chunk }
      decoder.feed(wire[start:end], fn(b) { frame = b.to_owned() })
      stream.feed(wire[start:end], fn(event) {
        match event {
          Data(part) => data.push(part)
          End => ends = ends + 1
          _ => ()
        }
      })
      start = end
    }
    decoder.finish()
    stream.finish()
    assert_eq(frame, bytes)
    assert_eq(ends, 1)
    let merged = Bytes::from_iter(data.iter().flat_map(fn(view) { view.iter() }))
    assert_eq(merged, bytes)
  }
}
