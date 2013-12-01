# -*- coding: utf-8 -*-
require 'forwardable'

module Smalruby
  # キャラクターを表現するクラス
  class Character < Sprite
    extend Forwardable

    attr_accessor :event_handlers
    attr_accessor :threads

    def initialize(option = {})
      opt = {
        x: 0,
        y: 0,
        costume: nil,
        visible: true
      }.merge(option)

      # TODO: コスチュームの配列に対応する
      if opt[:costume].is_a?(String)
        opt[:costume] = Image.load(asset_path(opt[:costume]))
      end
      super(opt[:x], opt[:y], opt[:costume])

      @event_handlers = {}
      @threads = []

      self.scale_x = 1.0
      self.scale_y = 1.0
      @vector = { x: 1, y: 0 }

      [:visible].each do |k|
        if opt.key?(k)
          send("#{k}=", opt[k])
        end
      end

      World.instance.objects << self
    end

    # @!group 動き

    # (  )歩動かす
    def move(val = 1)
      self.x += @vector[:x] * val
      self.y += @vector[:y] * val
    end

    # 振り返る
    def turn
      @vector[:x] *= -1
      @vector[:y] *= -1
      self.scale_x *= -1
    end

    # もし端に着いたら、跳ね返る
    def turn_if_reach_wall
      max_width = Window.width - image.width
      if self.x < 0
        self.x = 0
        turn
      elsif self.x >= max_width
        self.x = max_width - 1
        turn
      end
    end

    # @!endgroup

    # @!group 見た目

    def say(message)
      lines = message.to_s.lines.map { |l| l.scan(/.{1,10}/) }.flatten
      font = Font.new(16)
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
      image.draw_font(frame_size + margin_size,
                      frame_size + margin_size,
                      lines.join("\n"), font, [0, 0, 0])
      @balloon = Sprite.new(self.x, self.y, image)
    end

    # @!endgroup

    # @!group 調べる

    def distance(x, y)
      res = Math.sqrt((self.x + center_x - x).abs**2 +
                      (self.y + center_y - y).abs**2).to_i
      return res
    end

    # @!endgroup

    # @!group 音

    def play(option = {})
      @sound_cache ||= {}
      (@sound_cache[option[:name]] ||= Sound.new(asset_path(option[:name]))).play
    end

    # @!endgroup

    def draw
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

      if Smalruby.started?
        @threads << h.call
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

    def alive?
      return @threads.any?(&:alive?)
    end

    def join
      @threads.each(&:join)
    end

    def loop(&block)
      Kernel.loop do
        yield
        Smalruby.await
      end
    end

    private

    def asset_path(name)
      return File.expand_path("../../../assets/#{name}", __FILE__)
    end
  end
end
