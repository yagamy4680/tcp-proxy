#!/usr/bin/env lsc -cj
#

# Known issue:
#   when executing the `package.ls` directly, there is always error
#   "/usr/bin/env: lsc -cj: No such file or directory", that is because `env`
#   doesn't allow space.
#
#   More details are discussed on StackOverflow:
#     http://stackoverflow.com/questions/3306518/cannot-pass-an-argument-to-python-with-usr-bin-env-python
#
#   The alternative solution is to add `envns` script to /usr/bin directory
#   to solve the _no space_ issue.
#
#   Or, you can simply type `lsc -cj package.ls` to generate `package.json`
#   quickly.
#

# package.json
#
name: \tcp-proxy

author:
  name: ['Yagamy']
  email: 'yagamy@gmail.com'

description: 'A tcp-tunnel proxy with monitor functionalities'

version: \0.0.1

repository:
  type: \git
  url: ''

main: \app.ls

engines:
  node: \0.10.x
  npm: \1.4.x

dependencies:
  async: \*
  optimist: \*
  colors: \*
  bunyan: \*
  byline: \*
  moment: \*
  'bunyan-debug-stream': \*
  'sprintf-js': \*
  'prelude-ls': \*


devDependencies: {}

optionalDependencies: {}
