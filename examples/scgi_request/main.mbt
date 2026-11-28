///|
fn main raise {
  let fields : Array[@scgi.Header] = [
    { name: b"REQUEST_METHOD"[:], value: b"POST"[:], },
    { name: b"REQUEST_URI"[:], value: b"/upload"[:], },
  ]
  let payload = b"part:\x00,\xff"
  let wire = @scgi.encode_request(fields[:], payload[:])
  let decoder = @scgi.RequestDecoder::new()
  let body = @buffer.Buffer()
  let on_event = fn(event : @scgi.RequestEvent) {
    match event {
      Head(head) => {
        let uri = head.get(b"REQUEST_URI"[:]).unwrap_or(b""[:])
        println("request_uri=\{uri.to_owned()}")
        println("content_length=\{head.content_length()}")
      }
      Body(part) => body.write_bytesview(part)
      End => println("request_complete")
    }
  }
  for index in 0..<wire.length() {
    let consumed = decoder.feed(wire[index:index + 1], on_event)
    assert_eq(consumed, 1)
  }
  decoder.finish()
  assert_eq(body.to_bytes(), payload)
  println("body=\{body.to_bytes()}")
}
