#!/usr/bin/env lsc
require! <[net events colors optimist bunyan bunyan-debug-stream async moment]>
{sprintf} = require \sprintf-js

DBG = -> global.logger.debug.apply global.logger, arguments
INFO = -> global.logger.info.apply global.logger, arguments
ERR = -> global.logger.error.apply global.logger, arguments




class BaseServer
  (@port) ->
    DBG "enter"
    @sockets = []
    @ee = new events.EventEmitter()

  startup: ->
    self = @
    {port} = @
    connectCB = -> self.onConnect.apply self, arguments
    opts = allowHalfOpen: no, pauseOnConnect: no
    server = @server = net.createServer opts, connectCB
    server.listen port, (err) ->
      return ERR "failed to listen port #{port}, err: #{err}" if err?
      return INFO "listening #{port}"

  writeAll: (data, callback) ->
    f = (socket, cb) -> return socket.write data, cb
    async.each @sockets, f, (err) ->
      ERR "failed to write data to data-server, err: #{err}" if err?
      return callback err if callback?

  addListener: (evt, listener) -> return @ee.addListener evt, listener

  onData: (c, buffer) -> return @ee.emit \data, c, buffer

  onConnect: (c) ->
    self = @
    INFO "incoming a connection: #{c.remoteAddress.yellow}"
    end = -> self.onDisconnect.call self, c
    incoming = (buffer) -> self.onData.call self, c, buffer
    c.on \end, end
    c.on \close, end
    c.on \data, incoming
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
  (@port) ->
    return super port

class MonitorServer extends BaseServer
  (@port, @alignments, @remote_address) ->
    return super port

  prefix: (time_str, to_remote) ->
    t0 = if to_remote then "<-".black.bgGreen else "->".black.bgWhite
    return "#{time_str.cyan} #{@remote_address.underline} [#{t0}]"

  format_buffer: (time_str, hex_array, char_array, to_remote) ->
    t1 = sprintf "%-#{@alignments * 3}s", hex_array.join " "
    t2 = char_array.join ""
    return "#{@.prefix time_str, to_remote} #{t1.gray} | #{t2}"

  restLines: -> @output_lines = []

  addLine: (line) -> return @output_lines.push line

  flushLines: (cb) ->
    @output_lines.push ""
    text = @output_lines.join "\r\n"
    return @.writeAll text, cb

  output_buffer: (data, to_remote, cb) ->
    {alignments} = @
    time_str = moment! .format 'YYYY/MM/DD hh:mm:ss'
    hex_array = []
    char_array = []
    count = 0
    @.restLines!
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
        @.addLine @.format_buffer time_str, hex_array, char_array, to_remote
        hex_array = []
        char_array = []
    @.addLine @.format_buffer time_str, hex_array, char_array, to_remote if hex_array.length > 0
    @.addLine "#{@.prefix time_str, to_remote} #{data.length} bytes"
    return @.flushLines cb

  to_remote: (data, cb) -> return @.output_buffer data, yes, cb
  from_remote: (data, cb) -> return @.output_buffer data, no, cb


main = ->
  opt = optimist.usage 'Usage: $0'
    .alias 'r', 'remote'
    .describe 'r', 'the remote destination server, e.g. 192.168.0.2:8080'
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
  DBG "remote = #{arg.r}"
  DBG "listen = #{arg.l}"
  DBG "monitor = #{arg.m}"

  monitor = global.monitor = new MonitorServer arg.m, 16, arg.r
  data_srv = global.data_srv = new DataServer arg.l

  data_srv.addListener \data, (c, buffer) ->
    data_srv.writeAll buffer
    monitor.to_remote buffer, (e0) ->
      return ERR "failed to send data to_remote(): #{e0}" if e0?
      INFO "success to_remote()"
      monitor.from_remote buffer, (e1) ->
        return ERR "failed to send data from_remote(): #{e1}" if e1?
        return INFO "success from_remote()"


  data_srv.startup!
  monitor.startup!


# Entry-point
#
main!