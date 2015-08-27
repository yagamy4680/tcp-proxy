#!/usr/bin/env lsc
require! <[net events url colors optimist bunyan bunyan-debug-stream async moment]>
{sprintf} = require \sprintf-js
{elem-index} = require \prelude-ls

CHECK_INTERVAL = 2000ms
DBG = -> global.logger.debug.apply global.logger, arguments
INFO = -> global.logger.info.apply global.logger, arguments
ERR = -> global.logger.error.apply global.logger, arguments
EXIT = (msg) ->
  ERR msg
  return process.exit 127


class RemoteClient
  (@url_tokens, @monitor) ->
    @connected = no
    @client = null
    @checkObject = null
    @ee = new events.EventEmitter()

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
    @client = new net.Socket!
    @client.on \error, (err) -> self.onError.apply self, [err]
    @client.on \close, -> self.onClosed.apply self, []
    @client.on \data, (data) -> self.onData.apply self, [data]
    @client.connect port, hostname, -> self.onConnected.apply self, []
    INFO "trying to connect to #{hostname}:#{port}"

  onCheck: -> return @.startConnection! if not @client? and not @connected

  onError: (err) ->
    {host, hostname, port} = @url_tokens
    ERR "failed to connect #{host.yellow}, err: #{err}"
    @.cleanup!

  onData: (data) -> return @ee.emit \data, data

  onConnected: ->
    {host, hostname, port} = @url_tokens
    INFO "connected to #{host.yellow}:#{port.green}"
    @connected = yes

  onClosed: ->
    {host, hostname, port} = @url_tokens
    INFO "disconnected from #{host.yellow}:#{port.green}"
    @.cleanup!

  cleanup: ->
    if @client?
      @client.removeAllListeners \data
      @client.removeAllListeners \error
      @client.removeAllListeners \close
      @client = null
    @connected = no


class BaseServer
  (@port) ->
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

  onConnect: (c) ->
    self = @
    INFO "incoming a connection: #{c.remoteAddress.yellow}"
    c.on \end, -> return self.onDisconnect.call self, c
    c.on \close, -> return self.onDisconnect.call self, c
    c.on \data, (buffer) -> self.onData.call self, c, buffer
    @sockets.push c

  onDisconnect: (c) ->
    {sockets} = @
    found = no
    for let s, i in @sockets
      if not found
        if c == s
          sockets.splice i, 1
          found := true
          INFO "data_srv[#{i}] disconnected and removed"


class DataServer extends BaseServer
  (@port, @monitor) ->
    super port
    @name = \data-srv

  writeAll: (data, cb) ->
    {monitor} = @
    super data, (err) ->
      return cb err if err?
      return monitor.from_remote data, cb


class Formatter
  -> return
  format: (buffer, to_remote) -> return


class HexFormatter extends Formatter
  (@alignments, @remote_tokens) ->
    @counter = 0
    return super!

  padding: (num) ->
    t0 = "#{num}"
    char_array = []
    for i from 1 to (6 - t0.length)
      char_array.push "0"
    char_array.push t0
    return char_array.join ""

  prefix: (time_str, to_remote) ->
    t0 = if to_remote then "<-".black.bgRed else "->".black.bgWhite
    return "#{time_str.cyan} (#{@padding @counter}) #{@remote_tokens.hostname.underline}:#{@remote_tokens.port.green} [#{t0}]"

  format_buffer: (hex_array, char_array) ->
    t1 = sprintf "%-#{@alignments * 3}s", hex_array.join " "
    t2 = char_array.join ""
    return "#{t1.yellow} | #{t2}"

  restLines: (time_str, to_remote) ->
    @prefix_str = @.prefix time_str, to_remote
    @output_lines = []

  addLine: (line) ->
    @output_lines.push "#{@prefix_str} #{line}"

  format: (data, to_remote) ->
    @counter = @counter + 1
    {alignments} = @
    time_str = moment! .format 'MM/DD hh:mm:ss'
    hex_array = []
    char_array = []
    count = 0
    @.restLines time_str, to_remote
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
    @.addLine "#{data.length} bytes".gray
    @output_lines.push ""
    return @output_lines.join "\r\n"


class MonitorServer extends BaseServer
  (@port, @alignments, @remote_tokens) ->
    super port
    @name = \monitor
    @hex = new HexFormatter alignments, remote_tokens

  output_buffer: (data, to_remote, cb) ->
    text = @hex.format data, to_remote
    return @.writeAll text, cb

  to_remote: (data, cb) -> return @.output_buffer data, yes, cb
  from_remote: (data, cb) -> return @.output_buffer data, no, cb


main = ->
  opt = optimist.usage 'Usage: $0'
    .alias 'r', 'remote'
    .describe 'r', 'the remote destination server, e.g. tcp:/192.168.0.2:8080, or just a port number to local server such as 10034'
    .alias 'l', 'listen'
    .describe 'l', 'listening port for data transmission, e.g. -l 8000'
    .alias 'm', 'monitor'
    .describe 'm', 'listening port for data monitoring, e.g. -m 8010'
    .alias 'v', 'verbose'
    .describe 'v', 'show more verbose messages'
    .boolean <[h v]>
    .demand <[r l m]>
  arg = global.argv = opt.argv

  if global.argv.h
    opt.showHelp!
    process.exit 0

  log_level = if arg.v then \debug else \info
  log_opts =
    name: \tcp-proxy
    serializers: bunyan-debug-stream.serializers
    streams: [
      * level: log_level
        type: \raw
        stream: bunyan-debug-stream do
          out: process.stderr
          showProcess: no
          colors:
            debug: \gray
            info: \white
    ]

  logger = global.logger = bunyan.createLogger log_opts
  arg.r = "tcp://127.0.0.1:#{arg.r}" if \number == typeof arg.r
  DBG "remote = #{arg.r}, listen = #{arg.l}, monitor = #{arg.m}"

  # Make sure the remote server is TCP or SSL-based.
  url_tokens = url.parse arg.r
  DBG "url_tokens.protocol = #{url_tokens.protocol}"
  EXIT "invalid protocol #{url_tokens.protocol.red} for remote destination server" unless (elem-index url_tokens.protocol, <[tcp: ssl:]>)?

  monitor = new MonitorServer arg.m, 16, url_tokens
  data_srv = new DataServer arg.l, monitor
  client = new RemoteClient url_tokens, monitor

  data_srv.addListener \data, (c, data) ->
    client.write data, (err) ->
      return ERR "failed to send #{data.length} bytes (from #{c.remoteAddress}) to remote server, err: #{err}" if err?
      return INFO "successfully send #{data.length} bytes to remote. (from #{c.remoteAddress})"

  client.addListener \data, (data) ->
    data_srv.writeAll data, (err) ->
      return ERR "failed to send #{data.length} bytes to local connections, err: #{err}" if err?
      return INFO "successfully send #{data.length} bytes to local connections"

  s = (srv, cb) -> return srv.startup cb
  async.each [monitor, data_srv, client], s, (err) ->
    EXIT "failed to startup all services, err: #{err}" if err?
    INFO "server is ready".yellow


# Entry-point
#
main!