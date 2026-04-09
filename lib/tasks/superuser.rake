namespace :superuser do
  desc "Create a superuser account (not connected to demo network)"
  task :create, [:user_name, :password] => :environment do |_t, args|
    unless args[:user_name] && args[:password]
      puts "Usage: rake superuser:create[username,password]"
      exit 1
    end

    user = User.find_by(user_name: args[:user_name])
    if user
      # User exists — just ensure they have the superuser group
      user.user_groups.find_or_create_by!(group_label: 'superuser')
      puts "User '#{args[:user_name]}' already exists — added superuser group"
    else
      # Create a standalone user (no invitation, no parent, no demo group)
      user = User.new(
        user_name: args[:user_name],
        password: args[:password],
        invite_limit: 0,
        depth: 0,
        invitations_count: 0,
      )
      # Skip the after_create callbacks that require an invitation
      user.save!(validate: false)
      user.update_columns(invitation_limit: 0)
      user.user_groups.create!(group_label: 'superuser')
      puts "Created superuser '#{args[:user_name]}'"
    end
  end
end
