///|
test "prefix parsing preserves opaque tail and supports incomplete probing" {
  let input = b"3:a\x00b,not a netstring"
  let (payload, consumed) = @netstring.decode_prefix(input)
  assert_eq(payload, b"a\x00b"[:])
  assert_eq(consumed, 6)
  assert_eq(input[consumed:], b"not a netstring"[:])
  for n = 0; n < consumed; n = n + 1 {
    assert_eq(@netstring.try_decode_prefix(input[:n]), None)
    let err = try { ignore(@netstring.decode_prefix(input[:n])); None } catch { e => Some(e) }
    assert_eq(err, Some(@netstring.NetstringError(Truncated, n.to_int64())))
  }
  assert_eq(@netstring.try_decode_prefix(b"0:,x"), Some((b""[:], 3)))
  let err = try { ignore(@netstring.try_decode_prefix(b"10:", max_len=9)); None } catch { e => Some(e) }
  assert_eq(err, Some(@netstring.NetstringError(TooLong, 1L)))
}

///|
test "prefix success and errors agree with first streaming end" {
  for input in [b"0:,x"[:], b"1:a,00bad"[:], b"1:a!"[:], b"01:a,"[:], b"3:ab"[:], b""[:], b"99999:"[:]] {
    let p = @netstring.StreamingDecoder::new(max_len=100)
    let mut saw_end = false
    let mut body = b""[:]
    let mut consumed = 0
    let expected_error = try {
      consumed = p.feed_some(input, fn(e) {
        match e {
          Data(part) => body = part
          End => saw_end = true
          _ => ()
        }
        !saw_end
      })
      None
    } catch { e => Some(e) }
    let mut actual : (BytesView, Int)? = None
    let actual_error = try {
      actual = @netstring.try_decode_prefix(input, max_len=100)
      None
    } catch { e => Some(e) }
    assert_eq(actual_error, expected_error)
    if saw_end {
      assert_eq(actual, Some((body, consumed)))
    } else {
      assert_eq(actual, None)
    }
  }
}
