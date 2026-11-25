///|
test "decimal headers match standard decimal conversion across UInt32" {
  fn check_value(n : UInt) -> Unit raise {
    let expected = @buffer.Buffer()
    expected.write_string_utf8(n.to_string()[:])
    expected.write_byte(b':')
    let header = @netstring.encode_header(n)
    assert_eq(header, expected.to_bytes())
    assert_eq(@netstring.encoded_length(n), n.to_int64() + header.length().to_int64() + 1L)
  }
  let mut power = 1U
  for i in 0..<10 {
    check_value(power - 1U)
    check_value(power)
    check_value(power + 1U)
    if i < 9 { power *= 10U }
  }
  for n in [2_147_483_647U, 2_147_483_648U, 4_294_967_295U] { check_value(n) }
  let mut state = 19U
  for _ in 0..<8192 {
    state = state * 1664525U + 1013904223U
    check_value(state)
  }
}
