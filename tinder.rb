#!/usr/bin/env ruby2.7

require 'csv'

@get_score = lambda {|row| row['score']}
@get_name = lambda {|row| row['name']}

ADJUSTMENT_RANGE = 40
WEEKS_BEFORE_REMATCH = 3
MAX_RETRIES = 1000
NUM_WEEKS_IN_SEASON = 6

# Parse players
original_standings = CSV.read("players.csv", headers: true, converters: %i[numeric] )
MIN_SCORE, MAX_SCORE = original_standings.map(&@get_score).minmax
original_rankings = Hash.new
original_standings.each {|row| original_rankings[row['name']] = row['score']}

def create_matchups_for_week(original_standings)
  # Adjust standings and resort based on new scores
  adjusted_standings = CSV::Table.new(original_standings)
  adjusted_standings.each do |row|
    score = row['score']
    adjustment_min = score - ADJUSTMENT_RANGE
    adjustment_max = score + ADJUSTMENT_RANGE
    # If someone should not have their score moved down, increase the upper range
    if adjustment_min < MIN_SCORE
      diff = MIN_SCORE - adjustment_min
      adjustment_min += diff
      adjustment_max += diff
    elsif adjustment_max > MAX_SCORE # vice versa
      diff = adjustment_max - MAX_SCORE
      adjustment_min -= diff
      adjustment_max -= diff
    end
    #puts "%s %d, (%d %d)" % [row['name'], row['score'], adjustment_min, adjustment_max]
    row['score'] = rand(adjustment_min...adjustment_max)
  end

  adjusted_standings = CSV::Table.new(adjusted_standings.sort_by(&@get_score).reverse)

  matchups = Array.new
  adjusted_standings.each_slice(2) do |slice|
    #puts "%s, %s" % [slice.first['name'], slice.last['name']]
    matchups.push [slice.first['name'], slice.last['name']]
  end
  matchups
end

def is_valid_matchups(matchups, schedules)
  matchups.each do |home, away|
    if schedules[home].last(WEEKS_BEFORE_REMATCH).include? away or schedules[away].last(WEEKS_BEFORE_REMATCH).include? home
      return false
    end
  end

  true
end

def play_week_and_adjust_rankings(matchups, previous_rankings)
  new_rankings = Hash.new
  matchups.each do |home, away|
    rating_home = previous_rankings[home]
    rating_away = previous_rankings[away]
    expected_home = 1.to_f/(1+10**((rating_away - rating_home)/150.to_f))
    expected_away = 1.to_f/(1+10**((rating_home - rating_away)/150.to_f))

    # Home wins
    if rand() < expected_home
      new_rating_home = rating_home + 20*(1 - expected_home)
      new_rating_away = rating_away + 20*(0 - expected_away)
    else # Away wins
      new_rating_home = rating_home + 20*(0 - expected_home)
      new_rating_away = rating_away + 20*(1 - expected_away)
    end
    new_rankings[home] = new_rating_home.to_i
    new_rankings[away] = new_rating_away.to_i
  end

  new_rankings
end

def adjust_standings_after_week(previous_standings, new_rankings)
  new_standings = CSV::Table.new(previous_standings)
  new_standings.each do |row|
    row['score'] = new_rankings[row['name']]
  end
  new_standings
end

def simulate_week(previous_standings, previous_rankings, schedules)

  matchups = create_matchups_for_week(previous_standings)
  for i in 1..MAX_RETRIES do
    if not is_valid_matchups(matchups, schedules)
      matchups = create_matchups_for_week(previous_standings)
    else
      break
    end
  end
  matchups.each do |match|
    home = match.first
    away = match.last

    schedules[home].push away
    schedules[away].push home
  end

  new_rankings = play_week_and_adjust_rankings(matchups, previous_rankings)
  new_standings = adjust_standings_after_week(previous_standings, new_rankings)

  [new_standings, new_rankings]
end

total_dups = 0
total_matches = 0
player_stats = Hash.new
original_standings.each do |row|
  player_stats[row['name']] = {dups: 0, place: 0}
end
NUM_SEASONS = 1000
for _ in 1..NUM_SEASONS do
  previous_standings = original_standings
  previous_rankings = original_rankings
  schedules = Hash.new
  original_standings.each do |row|
    schedules[row['name']] = []
  end
  for _ in 1..NUM_WEEKS_IN_SEASON do
      new_standings, new_rankings = simulate_week(previous_standings, previous_rankings, schedules)
      previous_standings = new_standings
      previous_rankings = new_rankings
  end
  season_standings = CSV::Table.new(previous_standings.sort_by(&@get_score).reverse)
  season_standings.each_with_index do |row, i|
    player_stats[row['name']][:place] += (i + 1)
  end
  #puts schedules

  # Count duplicates
  schedules.each do |player, schedule|
    total_matches += schedule.size
    # Start with -1, if someone is in a schedule twice it will be 1 duplicate
    dups_per_opponent = schedule.each_with_object(Hash.new(-1)) { |opponent, hash| hash[opponent] += 1 }
    #puts "%s: %s" % [player, dups]
    dups = dups_per_opponent.values.inject(0) {|sum, v| sum += v}
    player_stats[player][:dups] += dups
    total_dups += dups
  end

end
total_dups /= 2
total_matches /=2

puts "Total matches per season: %.2f" % (total_matches.to_f / NUM_SEASONS.to_f)
puts "Average duplicate matches per season: %.2f" % (total_dups.to_f / NUM_SEASONS.to_f)

average_player_dups = Hash[player_stats.map{|k, v| [k, v[:dups] / NUM_SEASONS.to_f]}]
average_player_place = Hash[player_stats.map{|k, v| [k, v[:place] / NUM_SEASONS.to_f]}]

puts
puts "Average duplicate matches per player:"
average_player_dups.each do |name, dups|
  puts "\t%s, %.2f" % [name, dups]
end

puts
puts "Average place per player:"
average_player_place.each do |name, place|
  puts "\t%s, %.2f" % [name, place]
end
