///|
fn main raise {
  let wire = @netstring.encode_all([b"hello"[:], b""[:]])
  println(wire)
  let decoder = @netstring.Decoder::new(max_len=1024)
  decoder.feed(wire[:4], fn(frame) { println(frame.to_owned()) })
  decoder.feed(wire[4:], fn(frame) { println(frame.to_owned()) })
  decoder.finish()
  let stream = @netstring.StreamingDecoder::new(max_len=1024)
  stream.feed(wire, fn(event) {
    match event {
      Begin(length) => println("begin \{length}")
      Data(bytes) => println(bytes.to_owned())
      End => println("end")
    }
  })
  stream.finish()
}
