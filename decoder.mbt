///|
/// Complete-frame delivery over the same strict streaming parser.
struct Decoder {
  parser : StreamingDecoder
  mut first : BytesView?
  mut buffer : @buffer.Buffer?
}

///|
/// Buffer at most max_len payload bytes. Zero permits only empty payloads.
pub fn Decoder::new(max_len~ : Int32 = 99_999) -> Decoder raise NetstringError {
  { parser: StreamingDecoder::new(max_len~), first: None, buffer: None, }
}

///|
/// True for a partial active frame. Use finish() to validate EOF.
pub fn Decoder::pending(self : Decoder) -> Bool {
  self.parser.pending()
}

///|
pub fn Decoder::offset(self : Decoder) -> Int64 {
  self.parser.offset()
}

///|
/// Valid frames before an error are delivered before feed raises. Views backed
/// by a single input chunk are returned without copying. Callbacks may retain
/// views, which also retain their backing Bytes. Reentrant mutation is rejected.
pub fn Decoder::feed(
  self : Decoder,
  chunk : BytesView,
  on_frame : (BytesView) -> Unit,
) -> Unit raise NetstringError {
  self.parser.feed(chunk, fn(event) {
    match event {
      Begin(_) => {
        self.first = None
        self.buffer = None
      }
      Data(part) =>
        match self.buffer {
          Some(buffer) => buffer.write_bytes(part)
          None =>
            match self.first {
              None => self.first = Some(part)
              Some(first) => {
                let buffer = @buffer.Buffer()
                buffer.write_bytes(first)
                buffer.write_bytes(part)
                self.first = None
                self.buffer = Some(buffer)
              }
            }
        }
      End => {
        let payload = match self.buffer {
          Some(buffer) => buffer.to_bytes()[:]
          None => self.first.unwrap_or(b""[:])
        }
        self.first = None
        self.buffer = None
        on_frame(payload)
      }
    }
  }) catch {
    NetstringError(kind, offset) => {
      // A rejected reentrant call must not clear the active frame.
      if kind != Reentrant {
        self.first = None
        self.buffer = None
      }
      raise NetstringError(kind, offset)
    }
  }
}

///|
pub fn Decoder::finish(self : Decoder) -> Unit raise NetstringError {
  self.parser.finish() catch {
    NetstringError(kind, offset) => {
      if kind != Reentrant {
        self.first = None
        self.buffer = None
      }
      raise NetstringError(kind, offset)
    }
  }
}

///|
pub fn Decoder::reset(self : Decoder) -> Unit raise NetstringError {
  self.parser.reset()
  self.first = None
  self.buffer = None
}
