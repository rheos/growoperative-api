FROM ruby:3.2.11

WORKDIR /app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    default-libmysqlclient-dev \
    default-mysql-client \
    imagemagick \
    libmagickwand-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install bundler
RUN gem install bundler -v 2.4.22

# Copy Gemfile and install dependencies
COPY Gemfile* ./
RUN bundle install

# Copy the rest of the application
COPY . .

# Precompile assets only in production
ARG RAILS_ENV=development
RUN if [ "$RAILS_ENV" = "production" ]; then \
    SECRET_KEY_BASE=dummy bundle exec rake assets:precompile; \
    fi

# Use different entrypoints based on environment
ENV RAILS_ENV=${RAILS_ENV:-development}
ENV PORT=8080
ENTRYPOINT ["./docker-entrypoint.sh"]

# Start the Rails server
#CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "8080"]
