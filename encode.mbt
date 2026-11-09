///|
/// Append one netstring. Length counts payload bytes, not text characters.
pub fn encode_to(output : @buffer.Buffer, payload : BytesView) -> Unit {
  output.write_string_utf8(payload.length().to_string()[:])
  output.write_byte(b':')
  output.write_bytes(payload)
  output.write_byte(b',')
}

///|
/// Encode one binary payload as decimal-length:payload,.
pub fn encode(payload : BytesView) -> Bytes {
  let output = @buffer.Buffer()
  encode_to(output, payload)
  output.to_bytes()
}

///|
/// Concatenate the encodings of an ordered batch of payloads.
pub fn encode_all(payloads : Array[BytesView]) -> Bytes {
  let output = @buffer.Buffer()
  for payload in payloads {
    encode_to(output, payload)
  }
  output.to_bytes()
}
