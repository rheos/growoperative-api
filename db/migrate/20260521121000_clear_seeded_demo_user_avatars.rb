class ClearSeededDemoUserAvatars < ActiveRecord::Migration[5.2]
  CORE_DEMO_USERNAMES = %w[
    bob dianna peter paul sara mary bruce arthur clark oliver barry mark john
  ].freeze

  def up
    names = quoted_demo_names

    execute <<~SQL.squish
      UPDATE users
      SET image = NULL
      WHERE user_name IN (#{names})
        AND users.image = 'avatar.jpg'
    SQL

    execute <<~SQL.squish
      UPDATE notifications
      SET actor_avatar_url = NULL
      WHERE actor_name IN (#{names})
        AND actor_avatar_url LIKE '%/uploads/user/image/%/thumb500_avatar.jpg'
    SQL
  end

  def down
    # Intentionally no-op: the old demo avatars were seeded placeholders, not
    # authoritative user data. Future uploads still populate users.image.
  end

  private

  def quoted_demo_names
    CORE_DEMO_USERNAMES.map { |name| ActiveRecord::Base.connection.quote(name) }.join(',')
  end
end
