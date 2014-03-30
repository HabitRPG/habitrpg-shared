_ = require('lodash')

api = module.exports = {}

api.tnl = (lvl) ->
  if lvl >= 100 then 0
  else Math.round(((Math.pow(lvl, 2) * 0.25) + (10 * lvl) + 139.75) / 10) * 10
  # round to nearest 10?

###
  A hyperbola function that creates diminishing returns, so you can't go to infinite (eg, with Exp gain).
  {max} The asymptote
  {bonus} All the numbers combined for your point bonus (eg, task.value * user.stats.int * critChance, etc)
  {halfway} (optional) the point at which the graph starts bending
###
api.diminishingReturns = (bonus, max, halfway=max/2) ->
  max*(bonus/(bonus+halfway))

api.monod = (bonus, rateOfIncrease, max) ->
  rateOfIncrease*max*bonus/(rateOfIncrease*bonus+max)

###
Preen history for users with > 7 history entries
This takes an infinite array of single day entries [day day day day day...], and turns it into a condensed array
of averages, condensing more the further back in time we go. Eg, 7 entries each for last 7 days; 1 entry each week
of this month; 1 entry for each month of this year; 1 entry per previous year: [day*7 week*4 month*12 year*infinite]
###
api.preenHistory = (history) ->
  history = _.filter(history, (h) -> !!h) # discard nulls (corrupted somehow)
  newHistory = []
  preen = (amount, groupBy) ->
    groups = _.chain(history)
      .groupBy((h) -> moment(h.date).format groupBy) # get date groupings to average against
      .sortBy((h, k) -> k) # sort by date
      .value() # turn into an array
    groups = groups.slice(-amount)
    groups.pop() # get rid of "this week", "this month", etc (except for case of days)
    _.each groups, (group) ->
      newHistory.push
        date: moment(group[0].date).toDate()
        #date: moment(group[0].date).format('MM/DD/YYYY') # Use this one when testing
        value: _.reduce(group, ((m, obj) -> m + obj.value), 0) / group.length # average
      true

  # Keep the last:
  preen 50, "YYYY" # 50 years (habit will toootally be around that long!)
  preen moment().format('MM'), "YYYYMM" # last MM months (eg, if today is 05, keep the last 5 months)

  # Then keep all days of this month. Note, the extra logic is to account for Habits, which can be counted multiple times per day
  # FIXME I'd rather keep 1-entry/week of this month, then last 'd' days in this week. However, I'm having issues where the 1st starts mid week
  thisMonth = moment().format('YYYYMM')
  newHistory = newHistory.concat _.filter(history, (h)-> moment(h.date).format('YYYYMM') is thisMonth)
  #preen Math.ceil(moment().format('D')/7), "YYYYww" # last __ weeks (# weeks so far this month)
  #newHistory = newHistory.concat(history.slice -moment().format('D')) # each day of this week

  newHistory

###
  Update the in-browser store with new gear. FIXME this was in user.fns, but it was causing strange issues there
###
api.updateStore = (user) ->
  return unless user
  changes = []
  _.each ['weapon', 'armor', 'shield', 'head', 'back', 'headAccessory'], (type) ->
    found = _.find content.gear.tree[type][user.stats.class], (item) ->
      !user.items.gear.owned[item.key]
    changes.push(found) if found
    true
  # Add special items (contrib gear, backer gear, etc)
  changes = changes.concat _.filter content.gear.flat, (v) ->
    v.klass in ['special','mystery'] and !user.items.gear.owned[v.key] and v.canOwn?(user)
  changes.push content.potion
  # Return sorted store (array)
  _.sortBy changes, (item) ->
    switch item.type
      when 'weapon' then 1
      when 'armor'  then 2
      when 'head'   then 3
      when 'shield' then 4
      when 'back'   then 5
      when 'headAccessory'   then 6
      when 'potion' then 7
      else               8