require 'rexml/text'

module AllureRSpec

  class Builder
    class << self
      attr_accessor :suites
      MUTEX = Mutex.new

      def init_suites
        MUTEX.synchronize {
          self.suites ||= {}
        }
      end

      def start_suite(title)
        init_suites
        MUTEX.synchronize do
          puts "Starting suite #{title}"
          self.suites[title] = {
              :title => title,
              :start => timestamp,
              :tests => {},
          }
        end
      end

      def start_test(suite, test, severity = :normal)
        MUTEX.synchronize do
          puts "Starting test #{suite}.#{test}"
          self.suites[suite][:tests][test] = {
              :title => test,
              :start => timestamp,
              :severity => severity,
              :failure => nil,
              :steps => {},
              :attachments => []
          }
        end
      end

      def stop_test(suite, test, result = {})
        self.suites[suite][:tests][test][:steps].each do |step_title, step|
          if step[:stop].nil? || step[:stop] == 0
            stop_step(suite, test, step_title, result[:status])
          end
        end
        MUTEX.synchronize do
          puts "Stopping test #{suite}.#{test}"
          self.suites[suite][:tests][test][:stop] = timestamp(result[:started_at])
          self.suites[suite][:tests][test][:start] = timestamp(result[:finished_at])
          self.suites[suite][:tests][test][:status] = result[:status]
          if (result[:status].to_sym != :passed)
            self.suites[suite][:tests][test][:failure] = {
                :stacktrace => escape((result[:caller] || []).map { |s| s.to_s }.join("\r\n")),
                :message => escape(result[:exception].to_s),
            }
          end

        end
      end

      def escape(text)
        REXML::Text.new(text, false, nil, false)
      end

      def start_step(suite, test, step, severity = :normal)
        MUTEX.synchronize do
          puts "Starting step #{suite}.#{test}.#{step}"
          self.suites[suite][:tests][test][:steps][step] = {
              :title => step,
              :start => timestamp,
              :severity => severity || :normal,
              :attachments => []
          }
        end
      end

      def add_attachment(suite, test, attachment, step = nil)
        attach = {
            :title => attachment[:title],
            :source => attachment[:source],
            :type => attachment[:type],
        }
        if step.nil?
          self.suites[suite][:tests][test][:attachments] << attach
        else
          self.suites[suite][:tests][test][:steps][step][:attachments] << attach
        end
      end

      def stop_step(suite, test, step, status = :passed)
        MUTEX.synchronize do
          puts "Stopping step #{suite}.#{test}.#{step}"
          self.suites[suite][:tests][test][:steps][step][:stop] = timestamp
          self.suites[suite][:tests][test][:steps][step][:status] = status
        end
      end

      def stop_suite(title)
        init_suites
        MUTEX.synchronize do
          puts "Stopping suite #{title}"
          self.suites[title][:stop] = timestamp
        end
      end

      def timestamp(time = nil)
        ((time || Time.now).to_f * 1000).to_i
      end

      def each_suite_build(&block)
        suites_xml = []
        self.suites.each do |suite_title, suite|
          builder = Nokogiri::XML::Builder.new do
            send "test-suite", :start => suite[:start] || 0, :stop => suite[:stop] || 0 do
              title suite_title
              suite[:tests].each do |test_title, test|
                send "test-cases", :start => test[:start] || 0, :stop => test[:stop] || 0, :status => test[:status], :severity => test[:severity] do
                  title test_title
                  unless test[:failure].nil?
                    failure do
                      message test[:failure][:message]
                      send "stack-trace", test[:failure][:stacktrace]
                    end
                  end
                  test[:steps].each do |step_title, step_obj|
                    steps(:start => step_obj[:start] || 0, :stop => step_obj[:stop] || 0, :status => step_obj[:status]) do
                      title step_title
                      step_obj[:attachments].each do |attach|
                        attachment :source => attach[:source], :title => attach[:title], :type => attach[:type]
                      end
                    end
                  end
                  test[:attachments].each do |attach|
                    attachment :source => attach[:source], :title => attach[:title], :type => attach[:type]
                  end
                end
              end
            end
          end
          xml = builder.to_xml
          yield suite, xml
          suites_xml << xml
        end
        suites_xml
      end
    end
  end
end