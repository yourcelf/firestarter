base_config = require '../base_config'
_           = require 'underscore'

conf = _.extend {}, base_config
conf.port = 9002
conf.intertwinkles.api_key = "one"
conf.dbname = "firestarter"
module.exports = conf