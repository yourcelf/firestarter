fs = require 'fs'

try
    config = JSON.parse(fs.readFileSync(__dirname + '/../config.json', 'utf-8'))
catch e
    config =
        host: "localhost"
        port: 8000
        secret: "this is mah sekrit"
        dbhost: '127.0.0.1'
        dbport: '27017'
        dbname: 'firestarter'
        dbopts: {}
    console.log "WARNING: Skipping config file", e
    console.log "Using defaults:", config

module.exports = config
