# Be sure to restart your server when you modify this file.

# Master plan §Logging and Audit / Job 12: redact every credential or
# bearer token shape that could land in `params` or query strings, plus
# the personally-identifying handle/email pair so log shipping is safe
# to send to third parties without a reactive redaction layer.
#
# Rails 5.2 matches each entry against the param key as a substring,
# so :password covers password / current_password / password_confirmation
# automatically — but we list the exact keys here for explicitness and
# to catch any future renames.
Rails.application.config.filter_parameters += %i[
  password
  current_password
  password_confirmation
  password_conformation
  user_name
  username
  email
  token
  jwt
  authorization
  authentication
  recovery_phrase
  seed_phrase
  invitation_code
  invited_code
  invite_code
  latitude
  longitude
]
