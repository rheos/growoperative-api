require "rails_helper"
require "securerandom"
require "eth"
require "rake"

# Load the app's rake tasks exactly once for the whole process. load_tasks is
# not idempotent (it re-defines tasks and re-runs prerequisites), so guard it.
def load_foaf_custody_tasks!
  return if defined?($foaf_custody_tasks_loaded) && $foaf_custody_tasks_loaded

  Rails.application.load_tasks
  $foaf_custody_tasks_loaded = true
end

# Seam under test: the foaf_custody:migrate_keys rake task — its state-machine
# transitions (pending -> migrated, pending -> error), idempotency on re-run
# (already-migrated skipped; error users retried; already-adopted custodian
# returns "noop" then still nulls), and the no-key-in-logs guarantee. The
# custodian HTTP is stubbed at the task's single injectable adapter seam
# (`FoafCustodyMigration.custody_http_adapter`) — no live custodian, no new
# HTTP-mock gem (mirrors the gem's RemoteSignatureProvider, which injects its
# adapter the same way).
RSpec.describe "foaf_custody:migrate_keys", type: :task, skip_hooks: true do
  # A real key so derive-address parity and the probe-sign verify path exercise
  # the genuine Eth signing/recovery, not a mock of it.
  PRIV_KEY = "1" * 64
  ADDRESS  = Foaf::LedgerSigner.address(PRIV_KEY)

  before(:all) { load_foaf_custody_tasks! }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def run_task(name)
    task = Rake::Task["foaf_custody:#{name}"]
    task.reenable
    out = StringIO.new
    orig = $stdout
    $stdout = out
    begin
      task.invoke
    ensure
      $stdout = orig
    end
    out.string
  end

  def create_user(state:, key: PRIV_KEY, address: ADDRESS, seed: "seed words here")
    User.create!(
      user_name: "custody-#{SecureRandom.hex(3)}",
      password: "password123",
      foaf_address: address,
      foaf_private_key: key,
      foaf_seed_phrase: seed,
      custody_state: state
    )
  end

  # A fake HTTP adapter that answers the migrate and sign endpoints by path.
  # migrate_status: what /migrate returns ("adopted" | "noop" | "rejected").
  # sign: :real -> a genuine personal_sign that verifies; :bad -> a wrong signer.
  def fake_adapter(migrate_status:, sign: :real)
    adapter = instance_double(Foaf::NetHttpAdapter)
    allow(adapter).to receive(:request) do |method:, uri:, headers:, body: nil|
      if uri.path.end_with?("/migrate")
        Foaf::HttpResponse.new(status: 200, body: JSON.generate(status: migrate_status))
      elsif uri.path.end_with?("/sign")
        payload = JSON.parse(body)["exact_body"]
        signing_key = sign == :real ? PRIV_KEY : ("2" * 64)
        signature = Eth::Key.new(priv: signing_key).personal_sign(payload)
        Foaf::HttpResponse.new(status: 200, body: JSON.generate(signature: signature))
      else
        Foaf::HttpResponse.new(status: 404, body: "{}")
      end
    end
    adapter
  end

  around(:each) do |example|
    ENV["FOAF_AUTH_URL"] = "https://auth.foaf.test"
    ENV["FOAF_AUTH_SERVICE_TOKEN_GROWOP"] = "svc-token"
    example.run
  ensure
    ENV.delete("DRY_RUN")
    ENV.delete("FOAF_AUTH_URL")
    ENV.delete("FOAF_AUTH_SERVICE_TOKEN_GROWOP")
  end

  describe "DRY_RUN=true" do
    it "prints the foaf_id and address for each pending user and calls no HTTP" do
      user = create_user(state: "pending")
      ENV["DRY_RUN"] = "true"
      # If any adapter were built and called, this would blow up:
      expect(Foaf::NetHttpAdapter).not_to receive(:new)

      out = run_task("migrate_keys")

      expect(out).to include("would migrate foaf_id=#{user.foaf_id}")
      expect(out).to include("address=#{ADDRESS}")
      expect(out).to include("would migrate 1")
      # No key value anywhere in the captured output.
      expect(out).not_to include(PRIV_KEY)
      expect(user.reload.custody_state).to eq("pending")
      expect(user.foaf_private_key).to eq(PRIV_KEY)
    end
  end

  describe "derive-address mismatch (EC 3)" do
    it "sets custody_state=error and never calls the migrate endpoint" do
      # Key does not derive the stored address -> parity fails at step (a).
      user = create_user(state: "pending", address: "0x" + ("a" * 40))
      adapter = fake_adapter(migrate_status: "adopted")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      expect(adapter).not_to have_received(:request)
      user.reload
      expect(user.custody_state).to eq("error")
      # Not touched: still holds its key (skipped before nulling).
      expect(user.foaf_private_key).to eq(PRIV_KEY)
    end
  end

  describe "migrate returns adopted" do
    it "nulls both key and seed and sets custody_state=migrated" do
      user = create_user(state: "pending")
      adapter = fake_adapter(migrate_status: "adopted")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      user.reload
      expect(user.custody_state).to eq("migrated")
      expect(user.foaf_private_key).to be_nil
      expect(user.foaf_seed_phrase).to be_nil
    end
  end

  describe "migrate returns noop (crash-recovery re-run, W1)" do
    it "still nulls both columns and transitions to migrated" do
      user = create_user(state: "pending")
      adapter = fake_adapter(migrate_status: "noop")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      user.reload
      expect(user.custody_state).to eq("migrated")
      expect(user.foaf_private_key).to be_nil
      expect(user.foaf_seed_phrase).to be_nil
    end
  end

  describe "probe-sign verify fails (W5)" do
    it "sets custody_state=error and leaves the key in place" do
      user = create_user(state: "pending")
      # Custodian adopts, but the signature it returns recovers to a DIFFERENT
      # address -> verify_by_address fails at step (c).
      adapter = fake_adapter(migrate_status: "adopted", sign: :bad)
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      user.reload
      expect(user.custody_state).to eq("error")
      expect(user.foaf_private_key).to eq(PRIV_KEY)
    end
  end

  describe "already migrated user (idempotent skip, W1)" do
    it "is not reprocessed — no HTTP, state unchanged" do
      # Fixture deliberately still holds a key so the ONLY thing excluding it
      # from the migrate scope is custody_state != "pending". This pins the
      # custody_state skip guard itself: broadening the scope to include
      # "migrated" (the mutation) makes this row get reprocessed and fires the
      # no-HTTP assertion below.
      already = create_user(state: "migrated")
      adapter = fake_adapter(migrate_status: "adopted")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      expect(adapter).not_to have_received(:request)
      already.reload
      expect(already.custody_state).to eq("migrated")
    end
  end

  describe "error user retried on re-run (self-heal, W-error)" do
    it "reprocesses an error user (custodian called) and transitions error -> migrated with both columns nulled" do
      # A user parked in "error" by a prior transient failure still holds its
      # key (the error path never nulls it). On re-run it must be picked up
      # again, not stranded — the migrate scope includes "error", not just
      # "pending". Narrowing the scope back to ["pending"] makes this fail.
      user = create_user(state: "error")
      adapter = fake_adapter(migrate_status: "adopted")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      run_task("migrate_keys")

      expect(adapter).to have_received(:request).at_least(:once)
      user.reload
      expect(user.custody_state).to eq("migrated")
      expect(user.foaf_private_key).to be_nil
      expect(user.foaf_seed_phrase).to be_nil
    end
  end

  describe "no key material in logs (EC 7 / AC 9)" do
    it "never emits the private key to any captured log or stdout" do
      create_user(state: "pending")
      adapter = fake_adapter(migrate_status: "adopted")
      allow(FoafCustodyMigration).to receive(:custody_http_adapter).and_return(adapter)

      logged = []
      allow(Rails.logger).to receive(:info)  { |m| logged << m.to_s }
      allow(Rails.logger).to receive(:warn)  { |m| logged << m.to_s }
      allow(Rails.logger).to receive(:error) { |m| logged << m.to_s }

      out = run_task("migrate_keys")

      expect(out).not_to include(PRIV_KEY)
      expect(logged.join("\n")).not_to include(PRIV_KEY)
    end
  end
end

RSpec.describe "foaf_custody:check_nulled", type: :task, skip_hooks: true do
  before(:all) { load_foaf_custody_tasks! }

  after(:each) { DatabaseCleaner.clean_with(:truncation) }

  def run_check
    task = Rake::Task["foaf_custody:check_nulled"]
    task.reenable
    task.invoke
    nil
  rescue SystemExit => e
    e
  ensure
    $stdout = STDOUT
  end

  it "passes (no SystemExit) when every migrated user has key and seed nulled" do
    User.create!(user_name: "ok-#{SecureRandom.hex(3)}", password: "password123",
                 custody_state: "migrated", foaf_private_key: nil, foaf_seed_phrase: nil)
    silence_stream { expect(run_check).to be_nil }
  end

  it "exits 1 when a migrated user still holds a key" do
    User.create!(user_name: "leak-#{SecureRandom.hex(3)}", password: "password123",
                 custody_state: "migrated", foaf_private_key: "1" * 64, foaf_seed_phrase: nil)
    result = silence_stream { run_check }
    expect(result).to be_a(SystemExit)
  end

  def silence_stream
    orig = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = orig
  end
end
