#!/usr/bin/env lsc
require! <[net events url colors optimist async moment byline]>
commons = require \./lib/commons
{sprintf} = require \sprintf-js
{elem-index} = require \prelude-ls

OPT = optimist.usage 'Usage: $0'
  .alias \r, \remote
  .describe \r, 'the remote destination server, e.g. tcp:/192.168.0.2:8080, or just a port number to local server such as 10034'
  .alias \l, \listen
  .describe \l, 'listening port for data transmission, e.g. -l 8000'
  .default \l, 8000
  .alias \m, \monitor
  .describe \m, 'listening port for data monitoring, e.g. -m 8010'
  .default \m, 8010
  .alias \v, \verbose
  .describe \v, 'show more verbose messages'
  .alias \c, \command
  .describe \c, 'listening port for command monitoring, e.g. -c 8011'
  .default \c, 8011
  .default \p, no
  .boolean <[h v]>
  .demand <[r l m]>

CHECK_INTERVAL = 2000ms
EXIT = (msg) ->
  ERR msg
  return process.exit 127


class RemoteClient
  (@url_tokens, @monitor, @line_proto = no) ->
    @connected = no
    @client = null
    @checkObject = null
    @ee = new events.EventEmitter()
    @line_stream = null

  addListener: (evt, listener) -> return @ee.addListener evt, listener

  write: (data, cb) ->
    {monitor} = @
    return cb "#{@url_tokens.host} disconnected!!" unless @connected
    @client.write data, (err) ->
      return cb err if err?
      return monitor.to_remote data, cb

  startup: (cb) ->
    self = @
    @.startConnection!
    check = -> return self.onCheck.apply self, []
    @checkObject = setInterval check, CHECK_INTERVAL
    return cb!

  startConnection: ->
    self = @
    {host, hostname, port} = @url_tokens
    opts = readable: yes, writable: yes
    @client = new net.Socket opts
    @client.on \error, (err) -> self.onError.apply self, [err]
    @client.on \close, -> self.onClosed.apply self, []
    @client.on \data, (data) -> self.onData.apply self, [data]
    @client.connect port, hostname, -> self.onConnected.apply self, []
    INFO "trying to connect to #{hostname}:#{port} with read/writeable options"

  onCheck: -> return @.startConnection! if not @client? and not @connected

  onError: (err) ->
    {host, hostname, port} = @url_tokens
    ERR "failed to connect #{host.yellow}, err: #{err}"
    @.cleanup!

  onData: (data) -> return @ee.emit \data, data
  onLine: (line) ->
    {ee} = @
    return setImmediate -> return ee.emit \line, line

  onConnected: ->
    self = @
    {host, hostname, port} = @url_tokens
    INFO "connected to #{host.yellow}:#{port.green}"
    @connected = yes
    if @line_proto
      @line_stream = byline @client
      @line_stream.on \data (line) -> self.onLine.apply self, [line]

  onClosed: ->
    {host, hostname, port} = @url_tokens
    INFO "disconnected from #{host.yellow}:#{port.green}"
    @.cleanup!

  cleanup: ->
    if @line_stream?
      @line_stream.removeAllListeners \data
      @line_stream = null

    if @client?
      @client.removeAllListeners \data
      @client.removeAllListeners \error
      @client.removeAllListeners \close
      @client = null
    @connected = no


class BaseServer
  (@port, @line_proto = no) ->
    @name = \base
    @sockets = []
    @ee = new events.EventEmitter()

  startup: (cb) ->
    self = @
    {port, name} = @
    connectCB = -> self.onConnect.apply self, arguments
    opts = allowHalfOpen: no, pauseOnConnect: no
    server = @server = net.createServer opts, connectCB
    server.listen port, (err) ->
      p = "#{port}"
      INFO "listening #{p.green} for #{name.cyan}" unless err?
      return cb err

  writeAll: (data, cb) ->
    f = (socket, callback) -> return socket.write data, callback
    async.each @sockets, f, (err) ->
      ERR "failed to write data to data-server, err: #{err}" if err?
      return cb err if cb?

  addListener: (evt, listener) -> return @ee.addListener evt, listener

  onData: (c, buffer) -> return @ee.emit \data, c, buffer
  onLine: (c, line) ->
    {ee} = @
    return setImmediate -> return ee.emit \line, c, line

  onConnect: (c) ->
    {name} = @
    self = @
    INFO "[#{name.cyan}] incoming a connection: #{c.remoteAddress.yellow}"
    c.on \end, -> return self.onDisconnect.call self, c
    c.on \close, -> return self.onDisconnect.call self, c
    c.on \data, (buffer) -> self.onData.call self, c, buffer
    if @line_proto
      ls = c.line_stream = byline c
      ls.on \data (line) -> self.onLine.apply self, [c, line]
    @sockets.push c

  onDisconnect: (c) ->
    {sockets} = @
    if @line_proto
      c.line_stream.removeAllListeners \data
      c.line_stream = null
    c.removeAllListeners \data
    c.removeAllListeners \close
    c.removeAllListeners \end
    idx = sockets |> elem-index c
    if idx?
      sockets.splice idx, 1
      INFO "data_srv[#{idx}] disconnected and removed"


class DataServer extends BaseServer
  (@port, @monitor, line_proto) ->
    super port, line_proto
    @name = \data-srv

  writeAll: (data, cb) ->
    {monitor} = @
    super data, (err) ->
      return cb err if err?
      return monitor.from_remote data, cb


class DataFormatter
  (@alignments, @remote_tokens) ->
    @counter = 0

  padding: (num) ->
    t0 = "#{num}"
    char_array = []
    for i from 1 to (6 - t0.length)
      char_array.push "0"
    char_array.push t0
    return char_array.join ""

  prefix: (time_str, to_remote) ->
    t0 = if to_remote then "<-".black.bgRed else "->".black.bgWhite
    return "#{time_str.cyan} #{@remote_tokens.hostname.underline}:#{@remote_tokens.port.green} (#{@padding @counter}) [#{t0}]"

  format_buffer: (hex_array, char_array) ->
    t1 = sprintf "%-#{@alignments * 3}s", hex_array.join " "
    t2 = char_array.join ""
    return "#{t1.yellow} | #{t2}"

  restLines: (to_remote) ->
    time_str = moment! .format 'MM/DD hh:mm:ss'
    @prefix_str = @.prefix time_str, to_remote
    @output_lines = []

  addLine: (line) ->
    @output_lines.push "#{@prefix_str} #{line}"

  format_bytes: (data, to_remote) ->
    @counter = @counter + 1
    {alignments} = @
    hex_array = []
    char_array = []
    count = 0
    @.restLines to_remote
    for b in data
      count = count + 1
      t = if b < 16 then "0#{b.toString 16}" else b.toString 16
      c = if b >= 0x20 and b < 0x7F then String.fromCharCode b else " ".bgWhite
      c = "t".bgMagenta.cyan.underline if b == '\t'.charCodeAt!
      c = "n".bgMagenta.cyan.underline if b == '\n'.charCodeAt!
      c = "r".bgMagenta.cyan.underline if b == '\r'.charCodeAt!
      hex_array.push t.toUpperCase!
      char_array.push c
      if count >= alignments
        count = 0
        @.addLine @.format_buffer hex_array, char_array
        hex_array = []
        char_array = []
    @.addLine @.format_buffer hex_array, char_array if hex_array.length > 0
    @.addLine "#{data.length} bytes".gray if global.argv.v
    @output_lines.push ""
    return @output_lines.join "\r\n"


  format_line: (line, to_remote) ->
    @counter = @counter + 1
    @.restLines to_remote
    char_array = []
    # `line` is a Buffer object
    for let c, i in line
      x = if c >= 0x20 and c < 0x7F then String.fromCharCode c else " ".bgWhite
      x = " #{'\\t'.blue.bgGreen} " if c == '\t'.charCodeAt!
      x = "r".bgMagenta.cyan.underline if c == '\r'.charCodeAt!
      x = "n".bgMagenta.cyan.underline if c == '\n'.charCodeAt!
      char_array.push x
    @.addLine char_array.join ""
    @output_lines.push ""
    return @output_lines.join "\r\n"


  format_command: (line, to_remote) ->
    @counter = @counter + 1
    @.restLines to_remote
    char_array = []
    for let c, i in line
      x = if c >= 0x20 and c < 0x7F then String.fromCharCode c else " ".bgWhite
      x = " #{'\\t'.blue.bgGreen} " if c == '\t'.charCodeAt!
      char_array.push x
    @.addLine char_array.join ""
    @output_lines.push ""
    return @output_lines.join "\r\n"



class DataMonitorServer extends BaseServer
  (@port, @alignments, @remote_tokens) ->
    super port
    @name = \data-monitor
    @df = new DataFormatter alignments, remote_tokens

  output_buffer: (data, to_remote, cb) ->
    text = @df.format_bytes data, to_remote
    return @.writeAll text, cb

  output_line: (line, to_remote, cb) ->
    text = @df.format_line line, to_remote
    return @.writeAll text, cb

  to_remote: (data, cb) -> return @.output_buffer data, yes, cb
  from_remote: (data, cb) -> return @.output_buffer data, no, cb

  to_remote_line: (line, cb) -> return @.output_line line, yes, cb
  from_remote_line: (line, cb) -> return @.output_line line, no, cb


class CommandMonitorServer extends DataMonitorServer
  (@port, @alignments, @remote_tokens) ->
    super port
    @name = \command-monitor
    @df = new DataFormatter alignments, remote_tokens

  output_line: (line, to_remote, cb) ->
    text = @df.format_command line, to_remote
    return @.writeAll text, cb



main = ->
  argv = global.argv = OPT.argv

  if global.argv.h
    opt.showHelp!
    process.exit 0

  argv.r = "tcp://127.0.0.1:#{argv.r}" if \number == typeof argv.r
  DBG "remote = #{argv.r}, listen = #{argv.l}, monitor = #{argv.m}"

  # Make sure the remote server is TCP or SSL-based.
  url_tokens = url.parse argv.r
  DBG "url_tokens.protocol = #{url_tokens.protocol}"
  EXIT "invalid protocol #{url_tokens.protocol.red} for remote destination server" unless (elem-index url_tokens.protocol, <[tcp: ssl:]>)?

  data_monitor = new DataMonitorServer argv.m, 16, url_tokens
  data_srv = new DataServer argv.l, data_monitor, argv.c?
  client = new RemoteClient url_tokens, data_monitor, argv.c?

  command_monitor = null
  if argv.c?
    command_monitor := new CommandMonitorServer argv.c, 16, url_tokens

  data_srv.addListener \data, (c, data) ->
    client.write data, (err) ->
      return ERR "failed to send #{data.length} bytes (from #{c.remoteAddress}) to remote server, err: #{err}" if err?
      return DBG "successfully send #{data.length} bytes to remote. (from #{c.remoteAddress})"

  data_srv.addListener \line, (c, line) ->
    if command_monitor?
      command_monitor.to_remote_line line, (err) -> return
    data_monitor.to_remote_line line, (err) ->
      return ERR "failed to dump a line (#{line.length} bytes) sending to remote, err: #{err}" if err?
      return DBG "successfully dump a line (#{line.length} bytes) sending to remote"

  client.addListener \line, (line) ->
    if command_monitor?
      command_monitor.from_remote_line line, (err) -> return
    data_monitor.from_remote_line line, (err) ->
      return ERR "failed to dump a line (#{line.length} bytes) receiving from remote, err: #{err}" if err?
      return DBG "successfully dump a line (#{line.length} bytes) receiving from remote"

  client.addListener \data, (data) ->
    data_srv.writeAll data, (err) ->
      return ERR "failed to send #{data.length} bytes to local connections, err: #{err}" if err?
      return DBG "successfully send #{data.length} bytes to local connections"

  s = (srv, cb) -> return srv.startup cb
  servers = [data_monitor, data_srv, client]
  servers = [command_monitor] ++ servers if command_monitor?
  async.each servers, s, (err) ->
    EXIT "failed to startup all services, err: #{err}" if err?
    INFO "server is ready".yellow


# Entry-point
#
main!