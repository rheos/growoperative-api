class ClearCurrentCoreDemoUserAvatars < ActiveRecord::Migration[5.2]
  CORE_DEMO_USERNAMES = %w[
    bob dianna peter paul sara mary bruce arthur clark oliver barry mark john
  ].freeze
  DEMO_GROUP_LABEL = 6

  def up
    names = quoted_demo_names

    execute <<~SQL.squish
      UPDATE users
      INNER JOIN user_groups ON user_groups.user_id = users.id
      SET users.image = NULL
      WHERE user_groups.group_label = #{DEMO_GROUP_LABEL}
        AND users.user_name IN (#{names})
        AND users.image IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE notifications
      SET actor_avatar_url = NULL
      WHERE actor_name IN (#{names})
        AND actor_avatar_url LIKE '%/uploads/user/image/%'
    SQL
  end

  def down
    # No-op. These were demo placeholders; future user uploads will populate
    # users.image through the normal avatar upload flow.
  end

  private

  def quoted_demo_names
    CORE_DEMO_USERNAMES.map { |name| ActiveRecord::Base.connection.quote(name) }.join(',')
  end
end
