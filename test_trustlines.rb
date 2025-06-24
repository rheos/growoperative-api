# Test script for trustline functionality
# Run this in Rails console with: load 'test_trustlines.rb'

puts "🧪 Testing Trustline System..."

# Get some test users
alice = User.find_by(user_name: 'dianna') || User.first
bob = User.find_by(user_name: 'peter') || User.second
charlie = User.find_by(user_name: 'paul') || User.third

if !alice || !bob || !charlie
  puts "❌ Need at least 3 users in the system to test"
  exit
end

puts "👥 Testing with users: #{alice.user_name}, #{bob.user_name}, #{charlie.user_name}"

# Test 1: Create a trustline between Alice and Bob
puts "\n📋 Test 1: Creating trustline between #{alice.user_name} and #{bob.user_name}"

trustline_ab = alice.establish_trustline_with(
  bob, 
  my_credit_limit: 1000, 
  their_credit_limit: 500,
  notes: "Trading relationship for produce"
)

if trustline_ab
  puts "✅ Trustline created successfully"
  puts "   - Alice can borrow up to $1000 from Bob"
  puts "   - Bob can borrow up to $500 from Alice"
  puts "   - Current balance: $#{trustline_ab.current_balance}"
else
  puts "❌ Failed to create trustline"
end

# Test 2: Check available credit
puts "\n💰 Test 2: Checking available credit"
puts "   - Alice available credit: $#{alice.available_credit_total}"
puts "   - Bob available credit: $#{bob.available_credit_total}"

# Test 3: Process a payment
puts "\n💸 Test 3: Alice pays Bob $300"
begin
  if trustline_ab.can_handle_payment?(300, alice)
    result = trustline_ab.process_payment!(
      300, 
      alice, 
      bob, 
      description: "Payment for organic tomatoes"
    )
    puts "✅ Payment successful - new balance: $#{result}"
    puts "   - Alice now owes Bob: $#{trustline_ab.balance_for(alice)}"
    puts "   - Bob is owed by Alice: $#{trustline_ab.balance_for(bob)}"
  else
    puts "❌ Payment failed - insufficient credit"
  end
rescue => e
  puts "❌ Payment error: #{e.message}"
end

# Test 4: Check user net positions
puts "\n📊 Test 4: User financial positions"
puts "   - Alice total owed: $#{alice.total_credit_owed}"
puts "   - Alice total owed to her: $#{alice.total_credit_owed_to_me}"
puts "   - Alice net position: $#{alice.net_credit_position}"
puts "   - Bob total owed: $#{bob.total_credit_owed}"
puts "   - Bob total owed to him: $#{bob.total_credit_owed_to_me}"
puts "   - Bob net position: $#{bob.net_credit_position}"

# Test 5: Create another trustline for network testing
puts "\n🌐 Test 5: Creating network with Charlie"
trustline_bc = bob.establish_trustline_with(
  charlie,
  my_credit_limit: 750,
  their_credit_limit: 1000,
  notes: "Broker to broker relationship"
)

if trustline_bc
  puts "✅ Bob-Charlie trustline created"
  
  # Test path finding
  puts "\n🗺️  Test 6: Finding payment path from Alice to Charlie"
  path = Trustline.find_payment_path(alice, charlie, 200)
  
  if path
    puts "✅ Path found: #{path.map(&:user_name).join(' → ')}"
    
    # Test multi-hop payment
    puts "\n⚡ Test 7: Executing multi-hop payment"
    begin
      result = Trustline.execute_payment_path(
        path, 
        200, 
        description: "Multi-hop payment for specialty herbs"
      )
      
      if result
        puts "✅ Multi-hop payment successful!"
        puts "   - Alice → Bob balance: $#{trustline_ab.reload.balance_for(alice)}"
        puts "   - Bob → Charlie balance: $#{trustline_bc.reload.balance_for(bob)}"
      end
    rescue => e
      puts "❌ Multi-hop payment failed: #{e.message}"
    end
  else
    puts "❌ No payment path found"
  end
else
  puts "❌ Failed to create Bob-Charlie trustline"
end

# Test 8: Transaction history
puts "\n📜 Test 8: Transaction history"
total_transactions = TrustlineTransaction.count
puts "   - Total transactions in system: #{total_transactions}"

if total_transactions > 0
  puts "   - Recent transactions:"
  TrustlineTransaction.recent.limit(3).each do |tx|
    puts "     * $#{tx.amount} - #{tx.description} (#{tx.transaction_type})"
  end
end

puts "\n🎉 Trustline system test completed!"
puts "💡 To explore further, try:"
puts "   - Trustline.all"
puts "   - TrustlineTransaction.all"
puts "   - alice.trustlines"
puts "   - alice.net_credit_position" 