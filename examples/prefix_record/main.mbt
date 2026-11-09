///|
/// A framed metadata record followed by a body that is not itself a netstring.
/// Prefix decoding determines the boundary without interpreting body bytes.
fn main raise {
  let metadata = b"kind=blob;bytes=8"
  let body = b"\x00raw:,\xff!"
  let record = @buffer.Buffer()
  @netstring.encode_to(record, metadata)
  record.write_bytes(body)
  let input = record.to_bytes()
  let (header, consumed) = @netstring.decode_prefix(input, max_len=1024)
  println("metadata=\{header.to_owned()}")
  println("header_wire_bytes=\{consumed}")
  println("opaque_body=\{input[consumed:].to_owned()}")
}
