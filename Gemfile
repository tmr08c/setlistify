source 'https://rubygems.org'

gem 'puma'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '4.2.4'
gem 'pg'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5.0'
# Use Uglifier as compressor for JavaScript assets
gem 'uglifier', '>= 1.3.0'
# Use CoffeeScript for .coffee assets and views
gem 'coffee-rails', '~> 4.1.0'
# See https://github.com/rails/execjs#readme for more supported runtimes
# gem 'therubyracer', platforms: :ruby

# Use jquery as the JavaScript library
gem 'jquery-rails'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.0'
# bundle exec rake doc:rails generates the API under doc/api.
gem 'sdoc', '~> 0.4.0', group: :doc

# Use React for frontend view logic
gem 'react-rails', '~> 1.5.0'
gem 'sprockets-coffee-react'
gem 'react-router-rails'

# Materialze for Style
gem 'materialize-sass'
gem 'material_icons'

# Use ActiveModel has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Unicorn as the app server
# gem 'unicorn'

# Use Capistrano for deployment
# gem 'capistrano-rails', group: :development

group :production do
  # To enable features such as static asset serving and logging on Heroku
  gem 'rails_12factor'
end

group :development do
  # Access an IRB console on exception pages or by using <%= console %> in views
  gem 'web-console', '~> 2.0'

  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'

  gem 'irbtools', require: 'irbtools/binding'
end

group :development, :test do
  gem 'rspec-rails', '~> 3.0', require: 'rspec/rails'
  gem 'pry', git: 'git@github.com:pry/pry.git'
  gem 'pry-rescue'
  gem 'pry-doc'
  gem 'pry-byebug'
  gem 'pry-stack_explorer'
  gem 'rubocop'
  gem 'json_matchers'
  gem 'git_version_bumper'
end

group :test do
  gem 'vcr'
  gem 'webmock'
  gem "codeclimate-test-reporter", require: nil
end

gem 'figaro'
gem 'httparty'

# Ruby Version
ruby '2.2.3'
