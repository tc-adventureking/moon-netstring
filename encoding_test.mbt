///|
test "wire sizes are exact across decimal boundaries without Int overflow" {
  let cases : Array[(UInt, Int64)] = [
    (0U, 3L), (9U, 12L), (10U, 14L), (99U, 103L),
    (100U, 105L), (999U, 1004L), (1000U, 1006L),
    (2_147_483_647U, 2_147_483_659L), (4_294_967_295U, 4_294_967_307L),
  ]
  for (length, expected) in cases { assert_eq(@netstring.encoded_length(length), expected) }
  for n in [0, 1, 9, 10, 99, 100, 999, 1000, 9999, 10000, 99999, 100000] {
    let payload = Bytes::from_array(Array::make(n, b'x')[:])
    assert_eq(@netstring.encoded_length(n.reinterpret_as_uint()), @netstring.encode(payload).length().to_int64())
    assert_eq(@netstring.decode(@netstring.encode(payload)), [payload[:]])
  }
}

///|
test "scatter send header matches contiguous encoding for arbitrary binary" {
  assert_eq(@netstring.encode_header(0U), b"0:")
  assert_eq(@netstring.encode_header(4_294_967_295U), b"4294967295:")
  for n in [0, 1, 9, 10, 99, 100, 255, 999, 1000, 9999, 10000] {
    let payload = Bytes::from_array(Array::makei(n, fn(i) { ((i * 71) % 256).to_byte() })[:])
    let output = @buffer.Buffer()
    output.write_bytes(@netstring.encode_header(n.reinterpret_as_uint()))
    output.write_bytes(payload)
    output.write_byte(b',')
    assert_eq(output.to_bytes(), @netstring.encode(payload))
  }
}
