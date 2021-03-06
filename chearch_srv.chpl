use Logging, Memory, LibEv, IO, Random, SearchIndex, SyntheticDataIndexer, Time;

// ****
// NOTE: this is very much in progress
// ****

// TODO: port to pure chapel
extern proc initialize_socket(port: c_int): c_int;

// trampolines
extern var c_accept_cb: opaque;

extern proc send(sockfd:c_int, buffer: c_ptr(c_char), len: size_t, flags: c_int);

config const port: c_int = 3033;
config const post_load_test: bool = false;
config const load_from_partitions: bool = true;

// TODO: is the fd unique enough to bind a multi-handle processing context to?
export proc handle_received_data(fd: c_int, tcp_buffer: c_ptr(c_char), read: size_t, buffer_size: size_t) {
  var instructionCount = tcp_buffer[0]: uint(8);

  if (read > (256 + 1)) {
    error("received query that was bigger than we can handle");
    return;
  }

  if (read < (instructionCount - 1): size_t) {
    // TODO: not all of the data is here.  the instructions may be split over multiple request buffers
    error("not yet implemented: spanning over multiple request buffers");
    return;
  }

  var buffer = new InstructionBuffer(instructionCount);
  for i in 0..instructionCount-1 {
    buffer.buffer[i] = tcp_buffer[i+1]: ChasmOp;
  }

  const record_size: uint = 4 + 1 + 8;
  const record_count: uint = 8;

  var cArray = c_calloc(c_char, record_size * record_count);
  var count = 0: uint;
  for result in query(new Query(buffer)) {
    if (count >= record_count) {
      break;
    }

    writeln(result);

    var offset = count * record_size;

    for i in 1..4 {
      cArray[offset] = ((result.term >> (32 - 8*i)) & 0xFF): c_char;
      offset += 1;
    }
    
    cArray[offset] = result.textLocation: c_char;
    offset += 1;
    
    for i in 1..8 {
      cArray[offset] = ((result.externalDocId >> (64 - 8*i)) & 0xFF): c_char;
      offset += 1;
    }

    count += 1;
  }

  send(fd, cArray, count * record_size, 0);

  c_free(cArray);
}

proc main() {

  info("initializing index");
  initPartitions();

  indexSyntheticDocuments();

  var t: Timer;

  info("initializing event loop...");

  info("creating socket...");
  var sd: ev_fd = initialize_socket(port);
  debug("socket id = ", sd);
  if (sd == -1) {
    error("socket error");
    return -1;
  }

  // port c_accept_cb, c_read_cb
  var w_accept = new ev_io();
  ev_io_init(w_accept, c_accept_cb, sd, EV_READ);
  ev_io_start(EV_DEFAULT, w_accept);

  while (1) {
    ev_loop_fn(EV_DEFAULT, 0);
  }

  return 0;
}
