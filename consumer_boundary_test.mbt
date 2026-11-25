///|
suberror StoreError { Refused }

///|
fn store(frame : BytesView, saved : Array[Bytes]) -> Unit raise StoreError {
  if frame == b"bad"[:] { raise Refused }
  saved.push(frame.to_owned())
}

///|
test "business failure stops at frame boundary and supports resume or reset" {
  let wire = b"2:ok,3:bad,5:later,"
  for should_continue in [true, false] {
    let d = @netstring.Decoder::new()
    let saved = []
    let mut business_error : StoreError? = None
    let n = d.feed_some(wire, fn(frame) {
      try { store(frame, saved); true } catch {
        e => { business_error = Some(e); false }
      }
    })
    assert_true(business_error is Some(Refused))
    assert_eq(saved, [b"ok"])
    assert_eq(n, 11)
    assert_eq(d.offset(), 11L)
    assert_false(d.pending())
    if should_continue {
      d.feed(wire[n:], fn(f) { saved.push(f.to_owned()) })
      assert_eq(saved, [b"ok", b"later"])
      assert_eq(d.offset(), 19L)
    } else {
      d.reset()
      d.feed(b"1:z,", fn(f) { saved.push(f.to_owned()) })
      assert_eq(saved, [b"ok", b"z"])
      assert_eq(d.offset(), 4L)
    }
    d.finish()
  }
}

///|
test "prefix default accepts valid huge header while explicit cap rejects it" {
  assert_eq(@netstring.try_decode_prefix(b"2147483647:"), None)
  let error = try {
    ignore(@netstring.try_decode_prefix(b"2147483647:", max_len=1024))
    None
  } catch { e => Some(e) }
  assert_eq(error, Some(@netstring.NetstringError(TooLong, 3L)))
}

///|
test "error kind and error are directly loggable through Debug" {
  assert_eq(@debug.to_string(@netstring.InvalidByte), "InvalidByte")
  assert_eq(@debug.to_string(@netstring.NetstringError(InvalidByte, 2L)), "NetstringError(InvalidByte, 2)")
}
