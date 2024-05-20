-- 初始化全局变量以存储最新的游戏状态和游戏主机进程
LatestGameState = {}  -- 存储所有游戏数据
InAction = false      -- 防止你的机器人执行多个动作

-- 定义终端颜色代码
colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- 检查两个点是否在指定范围内
-- @param x1, y1: 第一个点的坐标
-- @param x2, y2: 第二个点的坐标
-- @param range: 两点之间的最大允许距离
-- @return: 布尔值，表示两点是否在指定范围内
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- 根据玩家的接近度、能量、生命值和地图分析来决定下一步动作
-- 根据生命值（优先攻击弱者）、距离（优先攻击近距离）和战略位置来确定目标
-- 分析地图以找到瓶颈位置或有利位置
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local bestTarget = nil  -- 存储最佳目标玩家的ID（考虑生命值、距离）
  local lowHealthThreshold = 20  -- 低生命值阈值

  -- 如果玩家生命值低于阈值，优先寻找掩护
  if player.health < lowHealthThreshold then
    print(colors.blue .. "生命值低，寻找掩护。" .. colors.reset)
    -- 在4个方向中随机选择一个方向移动
    local directionRandom = {"Up", "Down", "Left", "Right"}
    local randomIndex = math.random(#directionRandom)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionRandom[randomIndex]})
    InAction = false
    return
  end

  -- 寻找攻击范围内最近且最弱的目标
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      if not bestTarget or state.health < bestTarget.health or (state.health == bestTarget.health and inRange(player.x, player.y, state.x, state.y, 1) < inRange(player.x, player.y, bestTarget.x, bestTarget.y, 1)) then
        bestTarget = state
      end
    end
  end

  if player.energy > 5 and targetInRange then
    print(colors.red .. "目标在范围内，进行攻击。" .. colors.reset)
    ao.send({  -- 用所有能量攻击最接近的玩家
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(player.energy),
    })
  else
    print(colors.red .. "没有目标在范围内或能量不足，随机移动。" .. colors.reset)
    -- 在4个方向中随机选择一个方向移动
    local directionRandom = {"Up", "Down", "Left", "Right"}
    local randomIndex = math.random(#directionRandom)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionRandom[randomIndex]})
  end
  InAction = false -- 重置InAction标志
end

-- 处理器，用于打印游戏公告并触发游戏状态更新
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- 添加InAction逻辑
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- 添加InAction逻辑
      print("上一个动作仍在进行，跳过。")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- 处理器，用于触发游戏状态更新
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- 添加InAction逻辑
      InAction = true -- 添加InAction逻辑
      print(colors.gray .. "获取游戏状态..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("上一个动作仍在进行，跳过。")
    end
  end
)

-- 处理器，在等待期开始时自动确认支付
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("自动确认支付费用。")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- 处理器，接收到游戏状态信息后更新游戏状态
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("游戏状态已更新。打印'LatestGameState'以查看详细信息。")
  end
)

-- 处理器，决定下一个最佳动作
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- 添加InAction逻辑
      return
    end
    print("决定下一个动作。")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- 处理器，当被其他玩家击中时自动反击
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- 添加InAction逻辑
      InAction = true -- 添加InAction逻辑
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == undefined then
        print(colors.red .. "无法读取能量。" .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "无法读取能量。"})
      elseif playerEnergy == 0 then
        print(colors.red .. "玩家能量不足。" .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "玩家没有能量。"})
      else
        print(colors.red .. "反击。" .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- 添加InAction逻辑
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("上一个动作仍在进行，跳过。")
    end
  end
)
