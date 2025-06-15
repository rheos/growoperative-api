FROM ruby:2.7.8

WORKDIR /app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Install bundler
RUN gem install bundler -v 2.2.16

# Copy Gemfile and install dependencies
COPY Gemfile* ./
RUN bundle install

# Copy the rest of the application
COPY . .

# Make scripts executable
RUN chmod +x bin/wait-for-db.sh
RUN chmod +x entrypoint.sh
RUN chmod +x entrypoint.prod.sh

# Precompile assets for production
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production bundle exec rake assets:precompile

# Use different entrypoints based on environment
ENV RAILS_ENV=${RAILS_ENV:-development}
ENTRYPOINT ["./entrypoint.sh"]

# Start the Rails server
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
