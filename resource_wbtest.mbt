///|
test "large declared payload does not allocate before data and errors release buffers" {
  let d = Decoder::new(max_len=2_147_483_647)
  d.feed(b"2147483647:", fn(_) {})
  assert_true(d.first is None)
  assert_true(d.buffer is None)
  d.feed(b"a", fn(_) {})
  assert_true(d.buffer is None)
  d.feed(b"b", fn(_) {})
  assert_eq(d.buffer.unwrap().length(), 2)
  let err = try { d.finish(); None } catch { e => Some(e) }
  assert_eq(err, Some(NetstringError(Truncated, 13L)))
  assert_true(d.first is None)
  assert_true(d.buffer is None)
  d.reset()
  d.feed(b"0:,", fn(_) {})
  d.finish()
}

///|
test "single block zero copy and bounded buffers across bytewise chunks" {
  let d = Decoder::new(max_len=4096)
  d.feed(b"4096:", fn(_) {})
  for i = 0; i < 4096; i = i + 1 {
    d.feed(b"x", fn(_) {})
    match d.buffer {
      Some(buf) => assert_eq(buf.length(), i + 1)
      None => assert_eq(i, 0)
    }
  }
  let mut size = 0
  d.feed(b",", fn(frame) { size = frame.length() })
  assert_eq(size, 4096)
  assert_true(d.first is None)
  assert_true(d.buffer is None)
  d.finish()
}
