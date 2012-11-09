mongoose    = require 'mongoose'
Schema      = mongoose.Schema

ResponseSchema = new Schema
  firestarter: {type: Schema.ObjectId, ref: 'Firestarter'}
  created: Date
  response: String
  user: {
    intertwinkles_user_id: String
    name: String
    session_id: String
  }
ResponseSchema.pre 'save', (next) ->
  @set 'created', new Date().getTime() unless @created
Response = mongoose.model("Response", ResponseSchema)

FirestarterSchema = new Schema
  created: Date
  modified: Date
  intertwinkles_group_id: String
  slug: {type: String, unique: true, required: true}
  name: {type: String, required: true}
  prompt: {type: String, required: true}
  responses: [{type: Schema.ObjectId, ref: 'Response'}]
  public: Boolean
FirestarterSchema.pre 'save', (next) ->
  @set 'created', new Date().getTime() unless @created
  @set 'modified', new Date().getTime()
  next()
Firestarter = mongoose.model("Firestarter", FirestarterSchema)
Firestarter.with_responses = (constraint, cb) ->
  return Firestarter.findOne(constraint).populate('responses')

module.exports = { Firestarter, Response }
