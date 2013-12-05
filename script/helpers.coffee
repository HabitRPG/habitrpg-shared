moment = require 'moment'
_ = require 'lodash'
items = require('./items.coffee')

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

startOfWeek = (options={}) ->
  o = sanitizeOptions(options)
  moment(o.now).startOf('week')

startOfDay = (options={}) ->
  o = sanitizeOptions(options)
  moment(o.now).startOf('day').add('h', o.dayStart)

dayMapping = {0:'su',1:'m',2:'t',3:'w',4:'th',5:'f',6:'s'}

###
  Absolute diff from "yesterday" till now
###
daysSince = (yesterday, options = {}) ->
  o = sanitizeOptions options
  Math.abs startOfDay(_.defaults {now:yesterday}, o).diff(o.now, 'days')

###
  Should the user do this taks on this date, given the task's repeat options and user.preferences.dayStart?
###
shouldDo = (day, repeat, options={}) ->
  return false unless repeat
  o = sanitizeOptions options
  selected = repeat[dayMapping[startOfDay(_.defaults {now:day}, o).day()]]
  return selected unless moment(day).zone(o.timezoneOffset).isSame(o.now,'d')
  if options.dayStart <= o.now.hour() # we're past the dayStart mark, is it due today?
    return selected
  else # we're not past dayStart mark, check if it was due "yesterday"
    yesterday = moment(o.now).subtract(1,'d').day() # have to wrap o.now so as not to modify original
    return repeat[dayMapping[yesterday]] # FIXME is this correct?? Do I need to do any timezone calcaulation here?

uuid = ->
  "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace /[xy]/g, (c) ->
    r = Math.random() * 16 | 0
    v = (if c is "x" then r else (r & 0x3 | 0x8))
    v.toString 16

module.exports =

  ###
    Moment
  ###
  moment: moment

  ###
    Lodash
  ###
  _: _

  uuid: uuid

  taskDefaults: (task, filters={}) ->
    self = @
    defaults =
      id: self.uuid()
      type: 'habit'
      text: ''
      notes: ''
      priority: '!'
      challenge: {}
      tags: _.transform(filters, (m,v,k) -> m[k]=v if v)
    _.defaults task, defaults
    _.defaults(task, {up:true,down:true}) if task.type is 'habit'
    _.defaults(task, {history: []}) if task.type in ['habit', 'daily']
    _.defaults(task, {completed:false}) if task.type in ['daily', 'todo']
    _.defaults(task, {streak:0, repeat: {su:1,m:1,t:1,w:1,th:1,f:1,s:1}}) if task.type is 'daily'
    task._id = task.id # may need this for TaskSchema if we go back to using it, see http://goo.gl/a5irq4
    task.value ?= if task.type is 'reward' then 10 else 0
    task

  # FIXME - should we remove this completely, since all defaults are accounted for in mongoose?
  # Or should we keep it so mobile can create an offline new user in the future?
  newUser: () ->
    userSchema =
    # _id / id handled by Racer
      stats: { gp: 0, exp: 0, lvl: 1, hp: 50 }
      invitations: {party:null, guilds: []}
      items:
        weapon: 0
        armor: 0
        head: 0
        shield: 0
        lastDrop: { date: +new Date, count: 0 }
        eggs: {}
        food: {}
        hatchingPotions: {}
        pets: {}
        mounts: {}

      preferences: { gender: 'm', skin: 'white', hair: 'blond', armorSet: 'v1', dayStart:0, showHelm: true }
      apiToken: uuid() # set in newUserObject below
      lastCron: +new Date
      balance: 0
      flags:
        partyEnabled: false
        itemsEnabled: false
        ads: 'show'
      tags: []

    userSchema.habits = []
    userSchema.dailys = []
    userSchema.todos = []
    userSchema.rewards = []

    # deep clone, else further new users get duplicate objects
    newUser = _.cloneDeep userSchema

    repeat = {m:true,t:true,w:true,th:true,f:true,s:true,su:true}
    defaultTasks = [
      {type: 'habit', text: '1h Productive Work', notes: '-- Habits: Constantly Track --\nFor some habits, it only makes sense to *gain* points (like this one).', value: 0, up: true, down: false }
      {type: 'habit', text: 'Eat Junk Food', notes: 'For others, it only makes sense to *lose* points', value: 0, up: false, down: true}
      {type: 'habit', text: 'Take The Stairs', notes: 'For the rest, both + and - make sense (stairs = gain, elevator = lose)', value: 0, up: true, down: true}

      {type: 'daily', text: '1h Personal Project', notes: '-- Dailies: Complete Once a Day --\nAt the end of each day, non-completed Dailies damage your Health.', value: 0, completed: false, repeat: repeat }
      {type: 'daily', text: 'Exercise', notes: "If you are doing well, they turn green and are less valuable (experience, Gold) and less damaging (Health). This means you can ease up on them for a bit.", value: 3, completed: false, repeat: repeat }
      {type: 'daily', text: '45m Reading', notes: 'But if you are doing poorly, they turn red. The worse you do, the more valuable (Experience, Gold) and more damaging (Health) these goals become. This encourages you to focus on your shortcomings, the reds.', value: -10, completed: false, repeat: repeat }

      {type: 'todo', text: 'Call Mom', notes: "-- To-Dos: Complete Eventually --\nNon-completed To-Dos won't hurt you, but they will become more valuable over time. This will encourage you to wrap up stale To-Dos.", value: -3, completed: false }

      {type: 'reward', text: '1 Episode of Game of Thrones', notes: '-- Rewards: Treat Yourself! --\nAs you complete goals, you earn Gold to buy rewards. Buy them liberally - rewards are integral in forming good habits.', value: 20 }
      {type: 'reward', text: 'Cake', notes: 'But only indulge if you have enough Gold!', value: 10 }
    ]

    defaultTags = [
      {name: 'morning'}
      {name: 'afternoon'}
      {name: 'evening'}
    ]

    for task in defaultTasks
      guid = task.id = uuid()
      newUser["#{task.type}s"].push task

    for tag in defaultTags
      tag.id = uuid()
      newUser.tags.push tag

    newUser

  percent: (x,y) ->
    x=1 if x==0
    Math.round(x/y*100)

  ###
    This allows you to set object properties by dot-path. Eg, you can run pathSet('stats.hp',50,user) which is the same as
    user.stats.hp = 50. This is useful because in our habitrpg-shared functions we're returning changesets as {path:value},
    so that different consumers can implement setters their own way. Derby needs model.set(path, value) for example, where
    Angular sets object properties directly - in which case, this function will be used.
  ###
  dotSet: (path, val, obj) ->
    return if ~path.indexOf('undefined')
    try
      arr = path.split('.')
      _.reduce arr, (curr, next, index) ->
        if (arr.length - 1) == index
          curr[next] = val
        (curr[next] ?= {})
      , obj
    catch err
      console.error {err, path, val, _id:obj._id}

  dotGet: (path, obj) ->
    return undefined if ~path.indexOf('undefined')
    try
      _.reduce path.split('.'), ((curr, next) -> curr?[next]), obj
    catch err
      console.error {err, path, val, _id:obj._id}

  daysSince: daysSince
  startOfWeek: startOfWeek
  startOfDay: startOfDay

  shouldDo: shouldDo

  ###
    Get a random property from an object
    http://stackoverflow.com/questions/2532218/pick-random-property-from-a-javascript-object
    returns random property (the value)
  ###
  randomVal: (obj) ->
    result = undefined
    count = 0
    for key, val of obj
      result = val if Math.random() < (1 / ++count)
    result

  ###
    Remove whitespace #FIXME are we using this anywwhere? Should we be?
  ###
  removeWhitespace: (str) ->
    return '' unless str
    str.replace /\s/g, ''

  ###
    Generate the username, since it can be one of many things: their username, their facebook fullname, their manually-set profile name
  ###
  username: (auth, override) ->
    #some people define custom profile name in Avatar -> Profile
    return override if override

    if auth?.facebook?.displayName?
      auth.facebook.displayName
    else if auth?.facebook?
      fb = auth.facebook
      if fb._raw then "#{fb.name.givenName} #{fb.name.familyName}" else fb.name
    else if auth?.local?
      auth.local.username
    else
      'Anonymous'

  ###
    Encode the download link for .ics iCal file
  ###
  encodeiCalLink: (uid, apiToken) ->
    loc = window?.location.host or process?.env?.BASE_URL or ''
    encodeURIComponent "http://#{loc}/v1/users/#{uid}/calendar.ics?apiToken=#{apiToken}"

  equipped: items.equipped

  ###
    Gold amount from their money
  ###
  gold: (num) ->
    if num
      return Math.floor num
    else
      return "0"

  ###
    Silver amount from their money
  ###
  silver: (num) ->
    if num
      ("0" + Math.floor (num - Math.floor(num))*100).slice -2
    else
      return "00"

  ###
    Task classes given everything about the class
  ###
  taskClasses: (task, filters=[], dayStart=0, lastCron=+new Date, showCompleted=false, main=false) ->
    return unless task
    {type, completed, value, repeat} = task

    # completed / remaining toggle
    return 'hidden' if (type is 'todo') and (completed != showCompleted)

    # Filters
    if main # only show when on your own list
      for filter, enabled of filters
        if enabled and not task.tags?[filter]
          # All the other classes don't matter
          return 'hidden'

    classes = type

    # show as completed if completed (naturally) or not required for today
    if type in ['todo', 'daily']
      if completed or (type is 'daily' and !shouldDo(+new Date, task.repeat, {dayStart}))
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
  friendlyTimestamp: (timestamp) -> moment(timestamp).format('MM/DD h:mm:ss a')

  ###
    Does user have new chat messages?
  ###
  newChatMessages: (messages, lastMessageSeen) ->
    return false unless messages?.length > 0
    messages?[0] and (messages[0].id != lastMessageSeen)

  ###
    are any tags active?
  ###
  noTags: (tags) -> _.isEmpty(tags) or _.isEmpty(_.filter( tags, (t) -> t ) )

  ###
    Are there tags applied?
  ###
  appliedTags: (userTags, taskTags) ->
    arr = []
    _.each userTags, (t) ->
      return unless t?
      arr.push(t.name) if taskTags?[t.id]
    arr.join(', ')

  ###
    User stats
  ###

  userStr: (level) ->
    (level-1) / 2

  totalStr: (level, weapon=0) ->
    str = (level-1) / 2
    (str + items.getItem('weapon', weapon).strength)

  userDef: (level) ->
    (level-1) / 2

  totalDef: (level, armor=0, head=0, shield=0) ->
    totalDef =
      (level - 1) / 2 + # defense
      items.getItem('armor', armor).defense +
      items.getItem('head', head).defense +
      items.getItem('shield', shield).defense
    return totalDef

  itemText: (type, item=0) ->
    items.getItem(type, item).text

  itemStat: (type, item=0) ->
    i = items.getItem(type, item)
    if type is 'weapon' then i.strength else i.defense

  countPets: (originalCount, pets) ->
    count = if originalCount? then originalCount else _.size(pets)
    for pet of items.items.specialPets
      count-- if pets[pet]
    count

  ###
  ----------------------------------------------------------------------
  Derby-specific helpers. Will remove after the rewrite, need them here for now
  ----------------------------------------------------------------------
  ###

  ###
  Make sure model.get() returns all properties, see https://github.com/codeparty/racer/issues/116
  ###
  hydrate: (spec) ->
    if _.isObject(spec) and !_.isArray(spec)
      hydrated = {}
      keys = _.keys(spec).concat(_.keys(spec.__proto__))
      keys.forEach (k) => hydrated[k] = @hydrate(spec[k])
      hydrated
    else spec
