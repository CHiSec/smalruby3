# -*- coding: utf-8 -*-
require 'forwardable'
require 'mutex_m'

module Smalruby
  # キャラクターを表現するクラス
  class Character < Sprite
    extend Forwardable

    cattr_accessor :font_cache
    self.font_cache = {}
    font_cache.extend(Mutex_m)

    cattr_accessor :hardware_cache
    self.hardware_cache = {}
    hardware_cache.extend(Mutex_m)

    attr_accessor :event_handlers
    attr_accessor :threads
    attr_accessor :checking_hit_targets
    attr_accessor :angle unless Util.windows?

    def initialize(option = {})
      defaults = {
        x: 0,
        y: 0,
        costume: nil,
        angle: 0,
        visible: true
      }
      opt = process_optional_arguments(option, defaults)

      # TODO: コスチュームの配列に対応する
      if opt[:costume].is_a?(String)
        opt[:costume] = Image.load(asset_path(opt[:costume]))
      end
      super(opt[:x], opt[:y], opt[:costume])

      @event_handlers = {}
      @threads = []
      @checking_hit_targets = []
      @angle = 0 unless Util.windows?

      self.scale_x = 1.0
      self.scale_y = 1.0
      @vector = { x: 1, y: 0 }

      [:visible].each do |k|
        if opt.key?(k)
          send("#{k}=", opt[k])
        end
      end

      if opt[:angle] != 0
        rotate(opt[:angle])
      end

      World.instance.objects << self
    end

    # @!group 動き

    # (  )歩動かす
    def move(val = 1)
      self.x += @vector[:x] * val
      self.y += @vector[:y] * val
    end

    # (  )歩後ろに動かす
    def move_back(val = 1)
      move(-val)
    end

    # 振り返る
    def turn
      @vector[:x] *= -1
      @vector[:y] *= -1
      self.scale_x *= -1
    end

    # もし端に着いたら、跳ね返る
    def turn_if_reach_wall
      turn if reach_wall?
    end

    # (  )度回転する
    def rotate(angle)
      self.angle += angle
    end

    # (　)度に向ける
    def angle=(val)
      val %= 360
      radian = val * Math::PI / 180
      @vector[:x] = self.scale_x * Math.cos(radian)
      @vector[:y] = self.scale_x * Math.sin(radian)
      super(val)
    end

    # (  )に向ける
    def point_towards(target)
      if target == :mouse
        tx = Input.mouse_pos_x
        ty = Input.mouse_pos_y
      else
        tx = target.x
        ty = target.y
      end
      dx = tx - x
      dy = ty - y
      self.angle = Math.atan2(dy, dx) * 180 / Math::PI
    end

    # @!endgroup

    # @!group 見た目

    def say(options = {})
      defaults = {
        message: '',
        second: 0,
      }
      opts = process_optional_arguments(options, defaults)

      if @balloon
        @balloon.vanish
        @balloon = nil
      end

      message = opts[:message].to_s
      return if message.empty?

      lines = message.to_s.lines.map { |l| l.scan(/.{1,10}/) }.flatten
      font = new_font(16)
      width = lines.map { |l| font.get_width(l) }.max
      height = lines.length * (font.size + 1)
      frame_size = 3
      margin_size = 3
      image = Image.new(width + (frame_size + margin_size) * 2,
                        height + (frame_size + margin_size) * 2)
      image.box_fill(0,
                     0,
                     width + (frame_size + margin_size) * 2 - 1,
                     height + (frame_size + margin_size) * 2 - 1,
                     [125, 125, 125])
      image.box_fill(frame_size,
                     frame_size,
                     width + (frame_size + margin_size) + margin_size - 1,
                     height + (frame_size + margin_size) + margin_size - 1,
                     [255, 255, 255])
      lines.each.with_index do |line, row|
        image.draw_font(frame_size + margin_size,
                        frame_size + margin_size + (font.size + 1) * row,
                        line, font, [0, 0, 0])
      end
      @balloon = Sprite.new(self.x, self.y, image)
    end

    # @!endgroup

    # @!group 調べる

    # 距離
    def distance(x, y)
      Math.sqrt((self.x + center_x - x).abs**2 +
                (self.y + center_y - y).abs**2).to_i
    end

    # 端に着いた
    def reach_wall?
      self.x < 0 || self.x >= (Window.width - image.width) ||
        self.y < 0 || self.y >= (Window.height - image.height)
    end

    def hit?(other)
      check([other]).length > 0
    end

    # @!endgroup

    # @!group 音

    def play(option = {})
      defaults = {
        name: 'piano_do.wav'
      }
      opt = process_optional_arguments(option, defaults)

      @sound_cache ||= {}
      (@sound_cache[opt[:name]] ||= Sound.new(asset_path(opt[:name])))
        .play
    end

    # @!endgroup

    # @!group ハードウェア

    # LED
    def led(pin)
      Hardware.create_hardware(Hardware::Led, pin)
    end

    # RGB LED(アノード)
    def rgb_led_anode(pin)
      Hardware.create_hardware(Hardware::RgbLedAnode, pin)
    end

    # RGB LED(カソード)
    def rgb_led_cathode(pin)
      Hardware.create_hardware(Hardware::RgbLedCathode, pin)
    end

    # サーボモーター
    def servo(pin)
      Hardware.create_hardware(Hardware::Servo, pin)
    end

    # 2WD車
    def two_wheel_drive_car(pin)
      Hardware.create_hardware(Hardware::TwoWheelDriveCar, pin)
    end

    # ボタン
    def button(pin)
      Hardware.create_hardware(Hardware::Button, pin)
    end

    # 汎用的なセンサー
    def sensor(pin)
      Hardware.create_hardware(Hardware::Sensor, pin)
    end

    # @!endgroup

    def draw
      draw_balloon

      if self.x < 0
        self.x = 0
      elsif self.x + image.width >= Window.width
        self.x = Window.width - image.width
      end
      if self.y < 0
        self.y = 0
      elsif self.y + image.height >= Window.height
        self.y = Window.height - image.height
      end
      super
    end

    def on(event, *options, &block)
      event = event.to_sym
      @event_handlers[event] ||= []
      h = EventHandler.new(self, options, &block)
      @event_handlers[event] << h

      case event
      when :start
        @threads << h.call if Smalruby.started?
      when :hit
        @checking_hit_targets << options
        @checking_hit_targets.flatten!
        @checking_hit_targets.uniq!
      when :sensor_change
        sensor(options.first)
      when :button_up, :button_down
        button(options.first)
      end
    end

    def start
      @event_handlers[:start].try(:each) do |h|
        @threads << h.call
      end
    end

    def key_down(keys)
      @event_handlers[:key_down].try(:each) do |h|
        if h.options.length > 0 && !h.options.any? { |k| keys.include?(k) }
          next
        end
        @threads << h.call
      end
    end

    def key_push(keys)
      @event_handlers[:key_push].try(:each) do |h|
        if h.options.length > 0 && !h.options.any? { |k| keys.include?(k) }
          next
        end
        @threads << h.call
      end
    end

    def click(buttons)
      @event_handlers[:click].try(:each) do |h|
        if h.options.length > 0 && !h.options.any? { |b| buttons.include?(b) }
          next
        end
        @threads << h.call(Input.mouse_pos_x, Input.mouse_pos_y)
      end
    end

    def hit
      # TODO: なんでもいいからキャラクターに当たった場合に対応する
      @checking_hit_targets &= World.instance.objects
      objects = check(@checking_hit_targets)
      return if objects.empty?
      @event_handlers[:hit].try(:each) do |h|
        if h.options.length > 0 && !h.options.any? { |o| objects.include?(o) }
          next
        end
        @threads << h.call(h.options & objects)
      end
    end

    def sensor_change(pin, value)
      @event_handlers[:sensor_change].try(:each) do |h|
        next unless h.options.include?(pin)
        @threads << h.call(value)
      end
    end

    def button_up(pin)
      @event_handlers[:button_up].try(:each) do |h|
        next unless h.options.include?(pin)
        @threads << h.call
      end
    end

    def button_down(pin)
      @event_handlers[:button_down].try(:each) do |h|
        next unless h.options.include?(pin)
        @threads << h.call
      end
    end

    def alive?
      @threads.delete_if { |t|
        if t.alive?
          false
        else
          begin
            t.join
          rescue => e
            Util.print_exception(e)
            exit(1)
          end
          true
        end
      }
      @threads.length > 0
    end

    def join
      @threads.each(&:join)
    end

    def loop
      Kernel.loop do
        yield
        Smalruby.await
      end
    end

    private

    def asset_path(name)
      program_path = Pathname($PROGRAM_NAME).expand_path(Dir.pwd)
      paths = [Pathname("../#{name}").expand_path(program_path),
               Pathname("../../../assets/#{name}").expand_path(__FILE__)]
      paths.find { |path| path.file? }.to_s
    end

    def new_font(size)
      self.class.font_cache.synchronize do
        self.class.font_cache[size] ||= Font.new(size)
      end
      return self.class.font_cache[size]
    end

    def draw_balloon
      if @balloon
        @balloon.x = self.x + image.width / 2
        if @balloon.x < 0
          @balloon.x = 0
        elsif @balloon.x + @balloon.image.width >= Window.width
          @balloon.x = Window.width - @balloon.image.width
        end
        @balloon.y = self.y - @balloon.image.height
        if @balloon.y < 0
          @balloon.y = 0
        elsif @balloon.y + @balloon.image.height >= Window.height
          @balloon.y = Window.height - @balloon.image.height
        end
        @balloon.draw
      end
    end

    def process_optional_arguments(options, defaults)
      unknown_keys = options.keys - defaults.keys
      if unknown_keys.length > 0
        s = unknown_keys.map { |k| "#{k}: #{options[k].inspect}" }.join(', ')
        fail ArgumentError, "Unknown options: #{s}"
      end
      defaults.merge(options)
    end

    def print_exception(exception)
      $stderr.puts("#{exception.class}: #{exception.message}")
      $stderr.puts("        #{exception.backtrace.join("\n        ")}")
    end
  end
end
