require! <[colors moment]>

verbose = (level, message) ->
  now = moment! .format "MM/DD hh:mm:ss"
  console.log "#{now.blue} [#{level}] #{message}"

INFO = global.INFO = (message) -> return verbose "INF", message
DBG = global.DBG = (message) -> return verbose "DBG".gray, message
ERR = global.ERR = (message) -> return verbose "ERR".red, message
EMP = global.EMP = (message) -> return console.log "                     #{message}"
NXT = global.NXT = -> return console.log ""

