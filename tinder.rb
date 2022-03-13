#!/usr/bin/env ruby2.7

require 'csv'

@get_elo = lambda {|row| row['Elo']}
@get_name = lambda {|row| row['Name']}

ADJUSTMENT_RANGE = 100
WEEKS_BEFORE_REMATCH = 6
MAX_RETRIES = 1000
LOG=true

def log(s)
  if LOG
    puts s
  end
end

# Standings are a Table, where rows contain name and elo
# Rankings are a hash of name => elo
# Yes, this is hacked together
def get_original_standings_and_rankings
  original_rankings_csv = CSV.read("week1elo.csv", headers: true, converters: %i[numeric] )
  original_standings_csv = CSV.read("week1matchrequest.csv", headers: true, converters: %i[numeric] )

  original_rankings = Hash.new
  original_rankings_csv.sort_by(&@get_elo).reverse.each {|row| original_rankings[row['Name']] = row['Elo']}

  original_standings = CSV.parse('Name,Elo', headers: true)
  original_standings_csv.each do |row|
    name = row['player_name']
    elo = original_rankings[name]
    num_matches = row['Number of Matches']
    for i in 1..num_matches
      original_standings << [name, elo]
    end
  end

  [original_standings, original_rankings]
end

def is_valid_matchups(matchups, schedules)
  matchups.each do |home, away|
    if schedules[home].last(WEEKS_BEFORE_REMATCH).include? away or schedules[away].last(WEEKS_BEFORE_REMATCH).include? home
      return false
    end

    if (home.eql? away)
      return false
    end
  end

  if matchups != matchups.uniq
    return false
  end

  true
end

def create_matchups_for_week(original_standings, schedules)
  for i in 1..MAX_RETRIES do
    # Adjust standings and resort based on new scores
    adjusted_standings = CSV::Table.new(original_standings)
    adjusted_standings.each do |row|
      score = row['Elo']
      adjustment_min = score - ADJUSTMENT_RANGE
      adjustment_max = score + ADJUSTMENT_RANGE

      # This ensures people at the top and bottom won't have their scores moved
      # above or below the current max/min in the table. They can still be adjusted,
      # 2*ADJUSTMENT_RANGE, but this limits the amount in each direction people can
      # move to avoid rematches.
      if adjustment_min < MIN_SCORE
        diff = MIN_SCORE - adjustment_min
        adjustment_min += diff
        adjustment_max += diff
      elsif adjustment_max > MAX_SCORE # vice versa
        diff = adjustment_max - MAX_SCORE
        adjustment_min -= diff
        adjustment_max -= diff
      end
      row['Elo'] = rand(adjustment_min...adjustment_max)
    end

    adjusted_standings = CSV::Table.new(adjusted_standings.sort_by(&@get_elo).reverse)

    matchups = Array.new
    adjusted_standings.each_slice(2) do |slice|
      #puts "%s, %s" % [slice.first['name'], slice.last['name']]
      matchups.push [slice.first['Name'], slice.last['Name']]
    end

    if is_valid_matchups(matchups, schedules)
      break
    end
  end

  log('ADJUSTED STANDINGS' + ' (' + (i - 1).to_s + ' retries)')
  log(adjusted_standings.to_s(write_headers: false))
  log('')
  matchups
end

# Main
seed = 696969
log('Using seed ' + seed.to_s)
log('')
srand(seed)

original_standings, original_rankings = get_original_standings_and_rankings
MIN_SCORE, MAX_SCORE = original_standings.map(&@get_elo).minmax

# TODO get this from CSV
schedules = Hash.new
original_standings.each do |row|
  schedules[row['Name']] = []
end

log('ORIGINAL STANDINGS' + ' (' + original_standings.length.to_s + ' matches)')
log(CSV::Table.new(original_standings.sort_by(&@get_elo).reverse))
log('')

matchups = create_matchups_for_week(original_standings, schedules)

log('MATCHUPS')
matchups.each {|matchup| log(matchup.first + ' vs. ' + matchup.last)}
