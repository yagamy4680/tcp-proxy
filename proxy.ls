#!/usr/bin/env lsc
require! <[net events url colors optimist async]>
commons = require \./lib/commons
{elem-index} = require \prelude-ls

OPT = optimist.usage 'Usage: $0'
  .alias \r, 'remote'
  .describe \r, 'the remote destination server, e.g. tcp:/192.168.0.2:8080, or just a port number to local server such as 10034'
  .alias \l, 'listen'
  .describe \l, 'listening port for data transmission, e.g. -l 8000'
  .default \l, 8000
  .alias \m, 'monitor'
  .describe \m, 'listening port for data monitoring, e.g. -m 8010'
  .default \m, 8010
  .alias \v, 'verbose'
  .describe \v, 'show more verbose messages'
  .alias \p, 'protocol'
  .describe \p, 'show line protocol verbose messages'
  .default \p, no
  .boolean <[h v p]>
  .demand <[r l m]>

EXIT = (msg) ->
  ERR msg
  return process.exit 127

DBG "hello"
