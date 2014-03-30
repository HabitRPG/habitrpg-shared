_ = require('lodash')
content = require('./content.coffee')

api = module.exports = {}

api.uuid = ->
  "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace /[xy]/g, (c) ->
    r = Math.random() * 16 | 0
    v = (if c is "x" then r else (r & 0x3 | 0x8))
    v.toString 16

api.countExists = (items)-> _.reduce(items,((m,v)->m+(if v then 1 else 0)),0)

###
Even though Mongoose handles task defaults, we want to make sure defaults are set on the client-side before
sending up to the server for performance
###
api.taskDefaults = (task={}) ->
  task.type = 'habit' unless task.type and task.type in ['habit','daily','todo','reward']
  defaults =
    id: api.uuid()
    text: if task.id? then task.id else ''
    notes: ''
    priority: 1
    challenge: {}
    attribute: 'str'
    dateCreated: new Date()
  _.defaults task, defaults
  _.defaults(task, {up:true,down:true}) if task.type is 'habit'
  _.defaults(task, {history: []}) if task.type in ['habit', 'daily']
  _.defaults(task, {completed:false}) if task.type in ['daily', 'todo']
  _.defaults(task, {streak:0, repeat: {su:1,m:1,t:1,w:1,th:1,f:1,s:1}}) if task.type is 'daily'
  task._id = task.id # may need this for TaskSchema if we go back to using it, see http://goo.gl/a5irq4
  task.value ?= if task.type is 'reward' then 10 else 0
  task.priority = 1 unless _.isNumber(task.priority) # hotfix for apiv1. once we're off apiv1, we can remove this
  task

api.percent = (x,y, dir) ->
  switch dir
    when "up" then roundFn = Math.ceil
    when "down" then roundFn = Math.floor
    else roundFn = Math.round
  x=1 if x==0
  roundFn(x/y*100)

###
Remove whitespace #FIXME are we using this anywwhere? Should we be?
###
api.removeWhitespace = (str) ->
  return '' unless str
  str.replace /\s/g, ''

###
Encode the download link for .ics iCal file
###
api.encodeiCalLink = (uid, apiToken) ->
  loc = window?.location.host or process?.env?.BASE_URL or ''
  encodeURIComponent "http://#{loc}/v1/users/#{uid}/calendar.ics?apiToken=#{apiToken}"

###
Gold amount from their money
###
api.gold = (num) ->
  if num
    return Math.floor num
  else
    return "0"

###
Silver amount from their money
###
api.silver = (num) ->
  if num
    ("0" + Math.floor (num - Math.floor(num))*100).slice -2
  else
    return "00"

###
Task classes given everything about the class
###
api.taskClasses = (task, filters=[], dayStart=0, lastCron=+new Date, showCompleted=false, main=false) ->
  return unless task
  {type, completed, value, repeat} = task

  # completed / remaining toggle
  return 'hidden' if (type is 'todo' and completed != showCompleted) and main

  # Filters
  if main # only show when on your own list
    for filter, enabled of filters
      if enabled and not task.tags?[filter]
        # All the other classes don't matter
        return 'hidden'

  classes = type

  # show as completed if completed (naturally) or not required for today
  if type in ['todo', 'daily']
    if completed or (type is 'daily' and !api.shouldDo(+new Date, task.repeat, {dayStart}))
      classes += " completed"
    else
      classes += " uncompleted"
  else if type is 'habit'
    classes += ' habit-wide' if task.down and task.up

  if value < -20
    classes += ' color-worst'
  else if value < -10
    classes += ' color-worse'
  else if value < -1
    classes += ' color-bad'
  else if value < 1
    classes += ' color-neutral'
  else if value < 5
    classes += ' color-good'
  else if value < 10
    classes += ' color-better'
  else
    classes += ' color-best'
  return classes

###
Friendly timestamp
###
api.friendlyTimestamp = (timestamp) -> moment(timestamp).format('MM/DD h:mm:ss a')

###
Does user have new chat messages?
###
api.newChatMessages = (messages, lastMessageSeen) ->
  return false unless messages?.length > 0
  messages?[0] and (messages[0].id != lastMessageSeen)

###
are any tags active?
###
api.noTags = (tags) -> _.isEmpty(tags) or _.isEmpty(_.filter(tags, (t)->t))

###
Are there tags applied?
###
api.appliedTags = (userTags, taskTags) ->
  arr = []
  _.each userTags, (t) ->
    return unless t?
    arr.push(t.name) if taskTags?[t.id]
  arr.join(', ')

api.countPets = (originalCount, pets) ->
  count = if originalCount? then originalCount else _.size(pets)
  for pet of content.questPets
    count-- if pets[pet]
  for pet of content.specialPets
    count-- if pets[pet]
  count

api.countMounts= (originalCount, mounts) ->
  count = if originalCount? then originalCount else _.size(mounts)
  for mount of content.specialMounts
    count-- if mounts[mount]
  count