///|
/// Events for one request. Body views borrow the input chunk. End marks the
/// complete request, including requests with an empty body.
pub(all) enum RequestEvent {
  Head(RequestHead)
  Body(BytesView)
  End
}

///|
priv enum State {
  ReadingHead
  ReadingBody(Int64)
  Complete
  Failed(RequestError)
}

///|
struct RequestDecoder {
  head_decoder : @netstring.Decoder
  max_body_len : Int64
  mut state : State
  mut busy : Bool
}

///|
/// Decode a single SCGI request from arbitrary chunks without buffering its body.
pub fn RequestDecoder::new(
  max_header_len~ : Int32 = DEFAULT_HEADER_LIMIT,
  max_body_len~ : Int64 = DEFAULT_BODY_LIMIT,
) -> RequestDecoder raise RequestError {
  validate_limits(max_header_len, max_body_len)
  let head_decoder = @netstring.Decoder::new(max_len=max_header_len) catch {
    error => raise FramingError(error)
  }
  { head_decoder, max_body_len, state: ReadingHead, busy: false, }
}

///|
pub fn RequestDecoder::is_complete(self : RequestDecoder) -> Bool {
  self.state is Complete
}

///|
fn RequestDecoder::read_chunk(
  self : RequestDecoder,
  chunk : BytesView,
  on_event : (RequestEvent) -> Unit,
) -> Int32 raise RequestError {
  let mut consumed = 0
  if self.state is ReadingHead {
    let mut payload : BytesView? = None
    consumed = self.head_decoder.feed_some(chunk, fn(frame) {
      payload = Some(frame)
      false
    }) catch {
      error => raise FramingError(error)
    }
    guard payload is Some(payload) else { return consumed }
    let head = parse_head(payload, self.max_body_len)
    self.state = ReadingBody(head.content_length)
    on_event(Head(head))
  }
  guard self.state is ReadingBody(remaining) else { return consumed }
  let available = (chunk.length() - consumed).to_int64()
  let count = if available < remaining { available } else { remaining }
  if count > 0L {
    let end = consumed + count.to_int()
    on_event(Body(chunk[consumed:end]))
    consumed = end
  }
  let remaining = remaining - count
  if remaining == 0L {
    self.state = Complete
    on_event(End)
  } else {
    self.state = ReadingBody(remaining)
  }
  consumed
}

///|
/// Return the consumed prefix length. Once End is delivered, any trailing
/// bytes in the chunk remain available to the caller. A failed decoder
/// reports its first error on subsequent calls.
pub fn RequestDecoder::feed(
  self : RequestDecoder,
  chunk : BytesView,
  on_event : (RequestEvent) -> Unit,
) -> Int32 raise RequestError {
  if self.busy {
    raise Reentrant
  }
  match self.state {
    Complete => return 0
    Failed(error) => raise error
    _ => ()
  }
  self.busy = true
  defer {
    self.busy = false
  }
  let result = Ok(self.read_chunk(chunk, on_event)) catch {
    error => Err(error)
  }
  match result {
    Ok(consumed) => consumed
    Err(error) => {
      self.state = Failed(error)
      raise error
    }
  }
}

///|
/// Check EOF. End must have been emitted for the request to be complete.
pub fn RequestDecoder::finish(self : RequestDecoder) -> Unit raise RequestError {
  if self.busy {
    raise Reentrant
  }
  let error : RequestError = match self.state {
    Complete => return
    Failed(error) => raise error
    ReadingHead => TruncatedHead(self.head_decoder.offset())
    ReadingBody(remaining) => TruncatedBody(remaining)
  }
  self.state = Failed(error)
  raise error
}
