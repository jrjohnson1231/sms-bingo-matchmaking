#!/usr/bin/env ruby2.7

require 'csv'
require './tinder'

original_standings, original_rankings = get_original_standings_and_rankings
NUM_WEEKS_IN_SEASON = 6

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

def simulate_week(previous_standings, previous_rankings, schedules)

  matchups = create_matchups_for_week(previous_standings, schedules)

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

def adjust_standings_after_week(previous_standings, new_rankings)
  new_standings = CSV::Table.new(previous_standings)
  new_standings.each do |row|
    row['Elo'] = new_rankings[row['Name']]
  end
  new_standings
end

def simulate_season(original_standings, original_rankings)
  previous_standings = original_standings
  previous_rankings = original_rankings
  schedules = Hash.new
  original_standings.each do |row|
    schedules[row['Name']] = []
  end
  for _ in 1..NUM_WEEKS_IN_SEASON do
      new_standings, new_rankings = simulate_week(previous_standings, previous_rankings, schedules)
      previous_standings = new_standings
      previous_rankings = new_rankings
  end
  season_standings = CSV::Table.new(previous_standings.sort_by(&@get_elo).reverse)

  [season_standings, schedules]
end

def simulate_multiple_seasons(num_seasons, original_standings, original_rankings)
  total_dups = 0
  total_matches = 0
  player_stats = Hash.new
  original_standings.each do |row|
    player_stats[row['Name']] = {dups: 0, place: 0}
  end

  peaches_opponents = Hash.new
  original_standings.each do |row|
    peaches_opponents[row['Name']] = 0
  end

  for i in 1..num_seasons do
    if (i % 100 == 0)
      puts "Season " + i.to_s
    end
    season_standings, schedules = simulate_season(original_standings, original_rankings)
    season_standings.each_with_index do |row, i|
      player_stats[row['Name']][:place] += (i + 1)
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

    schedules['JJsrl'].each do |opponent|
      peaches_opponents[opponent] += 1
    end

  end
  total_dups /= 2
  total_matches /=2

  puts "Total matches per season: %.2f" % (total_matches.to_f / num_seasons.to_f)
  puts "Average duplicate matches per season: %.2f" % (total_dups.to_f / num_seasons.to_f)

  average_player_dups = Hash[player_stats.map{|k, v| [k, v[:dups] / num_seasons.to_f]}]
  average_player_place = Hash[player_stats.map{|k, v| [k, v[:place] / num_seasons.to_f]}]

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

  puts
  print 'JJ\'s opponents: ', peaches_opponents.sort_by {|k,v| v}.reverse
end

simulate_multiple_seasons(1000, original_standings, original_rankings)
