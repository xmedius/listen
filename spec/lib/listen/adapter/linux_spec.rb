RSpec.describe Listen::Adapter::Linux do
  describe 'class' do
    subject { described_class }

    if linux?
      it { should be_usable }
    else
      it { should_not be_usable }
    end
  end

  if linux?
    let(:dir1) do
      instance_double(
        Pathname,
        'dir1',
        to_s: '/foo/dir1',
        cleanpath: real_dir1
      )
    end

    # just so cleanpath works in above double
    let(:real_dir1) { instance_double(Pathname, 'dir1', to_s: '/foo/dir1') }

    let(:config) { instance_double(Listen::Adapter::Config) }
    let(:queue) { instance_double(Queue) }
    let(:silencer) { instance_double(Listen::Silencer) }
    let(:snapshot) { instance_double(Listen::Change) }
    let(:record) { instance_double(Listen::Record) }

    # TODO: fix other adapters too!
    subject { described_class.new(config) }

    describe 'inotify limit message' do
      let(:directories) { [Pathname.pwd] }
      let(:adapter_options) { {} }

      before do
        require 'rb-inotify'
        fake_worker = double(:fake_worker)
        allow(fake_worker).to receive(:watch).and_raise(Errno::ENOSPC)

        fake_notifier = double(:fake_notifier, new: fake_worker)
        stub_const('INotify::Notifier', fake_notifier)

        allow(config).to receive(:directories).and_return(directories)
        allow(config).to receive(:adapter_options).and_return(adapter_options)
      end

      it 'should be shown before calling abort' do
        expected_message = described_class.const_get('INOTIFY_LIMIT_MESSAGE')
        expect { subject.start }.to raise_error SystemExit, expected_message
      end
    end

    # TODO: should probably be adapted to be more like adapter/base_spec.rb
    describe '_callback' do
      let(:directories) { [dir1] }
      let(:adapter_options) { { events: [:recursive, :close_write] } }

      before do
        allow(Kernel).to receive(:require).with('rb-inotify')
        fake_worker = double(:fake_worker)
        events = [:recursive, :close_write]
        allow(fake_worker).to receive(:watch).with('/foo/dir1', *events)

        fake_notifier = double(:fake_notifier, new: fake_worker)
        stub_const('INotify::Notifier', fake_notifier)

        allow(config).to receive(:directories).and_return(directories)
        allow(config).to receive(:adapter_options).and_return(adapter_options)
        allow(config).to receive(:queue).and_return(queue)
        allow(config).to receive(:silencer).and_return(silencer)

        allow(Listen::Record).to receive(:new).with(dir1).and_return(record)
        allow(Listen::Change::Config).to receive(:new).with(queue, silencer).
          and_return(config)
        allow(Listen::Change).to receive(:new).with(config, record).
          and_return(snapshot)

        subject.configure
      end

      let(:expect_change) do
        lambda do |change|
          expect(snapshot).to receive(:invalidate).with(
            :file,
            'path/foo.txt',
            cookie: 123,
            change: change
          )
        end
      end

      let(:event_callback) do
        lambda do |flags|
          callbacks = subject.instance_variable_get(:'@callbacks')
          callbacks.values.flatten.each do |callback|
            callback.call double(
              :inotify_event,
              name: 'foo.txt',
              watcher: double(:watcher, path: '/foo/dir1/path'),
              flags: flags,
              cookie: 123)
          end
        end
      end

      # TODO: get fsevent adapter working like INotify
      unless /1|true/ =~ ENV['LISTEN_GEM_SIMULATE_FSEVENT']
        it 'recognizes close_write as modify' do
          expect_change.call(:modified)
          event_callback.call([:close_write])
        end

        it 'recognizes moved_to as moved_to' do
          expect_change.call(:moved_to)
          event_callback.call([:moved_to])
        end

        it 'recognizes moved_from as moved_from' do
          expect_change.call(:moved_from)
          event_callback.call([:moved_from])
        end
      end
    end
  end
end
