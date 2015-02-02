require "spec_helper"

describe Redic::Client do
  let(:client) { double("Client", :reconnect => true) }
  let(:current_sentinel)  { double("Redis", :client => client) }

  let(:sentinels) do
    [
      { :host => "localhost", :port => 26379 },
      'sentinel://localhost:26380',
      { :url => 'sentinel://localhost:26381' },
    ]
  end

  let(:slaves_reply) do
    [
      ["ip", "slave-0", "port", "6379"],
      ["ip", "slave-1", "port", "6380"],
      ["ip", "slave-2", "port", "6381"]
    ]
  end

  subject { Redic::Client.new("redis://test.host:6379/", 10_000_000, :master_name => "master", :master_password => "foobar",
                              :sentinels => sentinels) }

  context "new instances" do
    it "should parse sentinel options" do
      expect(subject.instance_variable_get(:@sentinels_options)).to match_array [
        {:host=>"localhost", :port=>26379},
        {:host=>"localhost", :port=>26380},
        {:host=>"localhost", :port=>26381}
      ]
    end
  end

  context "#sentinel?" do
    it "should be true if passing sentiels and master_name options" do
      expect(subject).to be_sentinel
    end

    it "should not be true if not passing sentinels and master_name options" do
      expect(Redic::Client.new("redis://test.host:6379/", 10_000_000)).not_to be_sentinel
    end

    it "should not be true if passing sentinels option but not master_name option" do
      client = Redic::Client.new(
        "redis://test.host:6379/", 10_000_000,
        :sentinels => [
          {:host => "localhost", :port => 26379},
          {:host => "localhost", :port => 26380}
        ])
      expect(client).not_to be_sentinel
    end

    it "should not be true if passing master_name option but not sentinels option" do
      client = Redic::Client.new("redis://test.host:6379/", 10_000_000, :master_name => "master")
      expect(client).not_to be_sentinel
    end

    it "should be true if passing master_name, and sentinels as uri" do
      client = Redic::Client.new("redis://test.host:6379/", 10_000_000, :master_name => "master",
        :sentinels => %w(sentinel://localhost:26379 sentinel://localhost:26380))
      expect(client).to be_sentinel
    end
  end

  context "#try_next_sentinel" do
    before { allow(Redis).to receive(:new).and_return(current_sentinel) }

    it "returns next sentinel server" do
      expect(subject.try_next_sentinel).to eq current_sentinel
    end
  end

  context "#refresh_sentinels_list" do
    it "gets all sentinels list" do
      allow(subject).to receive(:current_sentinel).and_return(current_sentinel)
      expect(current_sentinel).to receive(:sentinel).with("sentinels", "master").and_return([
        ["name", "localhost:26381", "ip", "localhost", "port", 26380],
        ["name", "localhost:26381", "ip", "localhost", "port", 26381],
        ["name", "localhost:26381", "ip", "localhost", "port", 26382],
      ])
      subject.refresh_sentinels_list
      expect(subject.instance_variable_get(:@sentinels_options)).to eq [
        {:host => "localhost", :port => 26379},
        {:host => "localhost", :port => 26380},
        {:host => "localhost", :port => 26381},
        {:host => "localhost", :port => 26382},
      ]
    end
  end

  context "#discover_master" do
    before do
      allow(subject).to receive(:try_next_sentinel)
      allow(subject).to receive(:refresh_sentinels_list)
      allow(subject).to receive(:current_sentinel).and_return(current_sentinel)
    end

    it "updates master config options" do
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_return(["master", 8888])
      subject.discover_master
      expect(subject.uri.to_s).to eq "redis://master:8888/"
    end

    it "selects next sentinel if failed to connect to current_sentinel" do
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_raise(Redis::ConnectionError)
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_return(["master", 8888])
      subject.discover_master
      expect(subject.uri.to_s).to eq "redis://master:8888/"
    end

    it "selects next sentinel if sentinel doesn't know" do
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_raise(Redis::CommandError.new("IDONTKNOW: No idea"))
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_return(["master", 8888])
      subject.discover_master
      expect(subject.uri.to_s).to eq "redis://master:8888/"
    end

    it "raises error if try_next_sentinel raises command error" do
      expect(current_sentinel).to receive(:sentinel).with("get-master-addr-by-name", "master").and_raise(Redis::CommandError)
      expect { subject.discover_master }.to raise_error(Redis::CommandError)
    end

    it "raises error if try_next_sentinel raises connection error" do
      expect(subject).to receive(:try_next_sentinel).and_raise(Redis::CannotConnectError)
      expect { subject.discover_master }.to raise_error(Redis::CannotConnectError)
    end
  end

  context "#auto_retry_with_timeout" do
    context "no failover reconnect timeout set" do
      subject { Redic::Client.new("redis://test.host:6379/", 10_000_000) }

      it "does not sleep" do
        expect(subject).not_to receive(:sleep)
        expect {
          subject.auto_retry_with_timeout { raise Errno::ECONNREFUSED }
        }.to raise_error(Errno::ECONNREFUSED)
      end
    end

    context "the failover reconnect timeout is set" do
      subject { Redic::Client.new("redis://test.host:6379/", 10_000_000, :failover_reconnect_timeout => 3) }

      before(:each) do
        allow(subject).to receive(:sleep)
      end

      it "only raises after the failover_reconnect_timeout" do
        called_counter = 0
        allow(Time).to receive(:now).and_return(100, 101, 102, 103, 104, 105)

        begin
          subject.auto_retry_with_timeout do
            called_counter += 1
            raise Errno::ECONNREFUSED
          end
        rescue Errno::ECONNREFUSED
        end

        expect(called_counter).to eq(4)
      end

      it "sleeps the default wait time" do
        allow(Time).to receive(:now).and_return(100, 101, 105)
        expect(subject).to receive(:sleep).with(0.1)
        begin
          subject.auto_retry_with_timeout { raise Errno::ECONNREFUSED }
        rescue Errno::ECONNREFUSED
        end
      end

      it "does not catch other errors" do
        expect(subject).not_to receive(:sleep)
        expect do
          subject.auto_retry_with_timeout { raise "Some other error" }
        end.to raise_error("Some other error")
      end

      context "configured wait time" do
        subject { Redic::Client.new("redis://test.host:6379/", 10_000_000, :failover_reconnect_timeout => 3,
                                    :failover_reconnect_wait => 0.01) }

        it "uses the configured wait time" do
          allow(Time).to receive(:now).and_return(100, 101, 105)
          expect(subject).to receive(:sleep).with(0.01)
          begin
            subject.auto_retry_with_timeout { raise Errno::ECONNREFUSED }
          rescue Errno::ECONNREFUSED
          end
        end
      end
    end
  end
end
