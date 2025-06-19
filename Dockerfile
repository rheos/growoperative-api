FROM ruby:2.7.8

WORKDIR /app

# Install system dependencies
RUN apt-get update -qq && apt-get install -y \
    build-essential \
    libpq-dev \
    nodejs \
    default-mysql-client \
    curl \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y yarn \
    && rm -rf /var/lib/apt/lists/*

# Install bundler
RUN gem install bundler -v 2.2.16

# Copy Gemfile and install dependencies
COPY Gemfile* ./
RUN bundle install

# Copy the rest of the application
COPY . .

# Install React dependencies
RUN yarn install

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
