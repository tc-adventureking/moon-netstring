///|
test "encoding a subview excludes both surrounding bytes" {
  let input = b"L\x00:,\xffR"
  let payload = input[1:5]
  let wire = b"4:\x00:,\xff,"
  assert_eq(@netstring.encode(payload), wire)
  let output = @buffer.Buffer()
  output.write_byte(b'!')
  @netstring.encode_to(output, payload)
  assert_eq(output.to_bytes(), b"!4:\x00:,\xff,")
}

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
    output.write_bytesview(@netstring.encode_header(n.reinterpret_as_uint()))
    output.write_bytesview(payload)
    output.write_byte(b',')
    assert_eq(output.to_bytes(), @netstring.encode(payload))
  }
}
