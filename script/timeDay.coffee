_ = require('lodash')

api = module.exports = {}

###
  Each time we're performing date math (cron, task-due-days, etc), we need to take user preferences into consideration.
  Specifically {dayStart} (custom day start) and {timezoneOffset}. This function sanitizes / defaults those values.
  {now} is also passed in for various purposes, one example being the test scripts scripts testing different "now" times
###
sanitizeOptions = (o) ->
  dayStart = if (!_.isNaN(+o.dayStart) and 0 <= +o.dayStart <= 24) then +o.dayStart else 0
  timezoneOffset = if o.timezoneOffset then +(o.timezoneOffset) else +moment().zone()
  now = if o.now then moment(o.now).zone(timezoneOffset) else moment(+new Date).zone(timezoneOffset)
  # return a new object, we don't want to add "now" to user object
  {dayStart, timezoneOffset, now}

api.startOfWeek = api.startOfWeek = (options={}) ->
  o = sanitizeOptions(options)
  moment(o.now).startOf('week')

api.startOfDay = (options={}) ->
  o = sanitizeOptions(options)
  moment(o.now).startOf('day').add('h', o.dayStart)

api.dayMapping = {0:'su',1:'m',2:'t',3:'w',4:'th',5:'f',6:'s'}

###
  Absolute diff from "yesterday" till now
###
api.daysSince = (yesterday, options = {}) ->
  o = sanitizeOptions options
  Math.abs api.startOfDay(_.defaults {now:yesterday}, o).diff(o.now, 'days')

###
  Should the user do this taks on this date, given the task's repeat options and user.preferences.dayStart?
###
api.shouldDo = (day, repeat, options={}) ->
  return false unless repeat
  o = sanitizeOptions options
  selected = repeat[api.dayMapping[api.startOfDay(_.defaults {now:day}, o).day()]]
  return selected unless moment(day).zone(o.timezoneOffset).isSame(o.now,'d')
  if options.dayStart <= o.now.hour() # we're past the dayStart mark, is it due today?
    return selected
  else # we're not past dayStart mark, check if it was due "yesterday"
    yesterday = moment(o.now).subtract(1,'d').day() # have to wrap o.now so as not to modify original
    return repeat[api.dayMapping[yesterday]] # FIXME is this correct?? Do I need to do any timezone calcaulation here?