#!/usr/bin/env ruby

require 'rubygems'
require File.expand_path('../config/initializers/mongo')

MONGODB.drop_database("logjam-2010-06-21")

# db = conn.db("logjam")

# stats = db["log_stats"]
# stats.remove

# totals = db["totals"]
# totals.remove

# requests = db["requests"]
# requests.remove