# -*- coding: utf-8 -*-
require 'smalruby'

car1 = Character.new(x: 0, y: 0, costume: 'car1.png')

car1.on(:start) do
  loop do
    move(5)
    turn_if_reach_wall
  end
end

car1.on(:click) do
  rotate(45)
end
