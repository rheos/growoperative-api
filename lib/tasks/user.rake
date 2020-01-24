namespace :user do
  desc "Update user password"
  task :update_password => [:environment] do
    user_id = ARGV[1]
    password = ARGV[2]
    puts "Looking for user with id #{user_id}"
    user = User.find(user_id)
    puts "user #{user.user_name} found"
    user.update(password: password)
    puts "user's passwod changed to #{password}"
    exit
  end
end
