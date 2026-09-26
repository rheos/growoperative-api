FROM ruby:3.4.11

WORKDIR /app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    autoconf \
    automake \
    build-essential \
    libpq-dev \
    imagemagick \
    git \
    libmagickwand-dev \
    libssl-dev \
    libtool \
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
