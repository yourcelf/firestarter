fs = require 'fs'

try
    config = JSON.parse(fs.readFileSync(__dirname + '/../config.json', 'utf-8'))
catch e
    console.log "WARNING: Config file missing.", e
    process.exit(1)

module.exports = config
