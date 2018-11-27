--- testSocket
-- @module testSocket
-- @author AIRM2M
-- @license MIT
-- @copyright openLuat.com
-- @release 2018.10.27
require "socket"
module(..., package.seeall)

-- 此处的IP和端口请填上你自己的socket服务器和端口
local ip, port ,c = "36.7.87.100", "6500"

-- tcp test
sys.taskInit(function()
    local r, s, p
    local recv_cnt, send_cnt = 0, 0
    while true do
        while not socket.isReady() do sys.wait(1000) end
        c = socket.tcp()
        while not c:connect(ip, port) do sys.wait(2000) end
        while true do
            r, s, p = c:recv(120000, "pub_msg")
            if r then
                recv_cnt = recv_cnt + #s
                log.info("这是收到的服务器下发的数据统计:", recv_cnt, "和前30个字节:", s:sub(1, 30))
            elseif s == "pub_msg" then
                log.info("这是收到别的线程发来的数据消息!")
            elseif s == "timeout" then
                log.info("这是等待超时发送心跳包的显示!")
                if not c:send("ping") then break end
            else
                log.info("这是socket连接错误的显示!")
                break
            end
        end
        c:close()
    end
end)

-- 测试代码,用于发送消息给socket
sys.taskInit(function()
    while not socket.isReady() do sys.wait(2000) end
    sys.wait(10000)
    for i = 1, 2 do
        log.info("这是第" .. i .. "次发布的消息!")
        sys.publish("pub_msg", string.rep("0123456789", 1024))
        sys.wait(100)
    end
    local function send(c, msg)
        c:send(msg)
    end
    sys.timerLoopStart(send, 10000, c, string.rep("0123456789", 10))
end)

sys.timerLoopStart(function()
    log.info("打印占用的内存:", _G.collectgarbage("count"))-- 打印占用的RAM
    log.info("打印可用的空间", rtos.get_fs_free_size())-- 打印剩余FALSH，单位Byte
end, 1000)
