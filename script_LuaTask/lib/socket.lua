--- 模块功能：数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.25
require "link"
require "utils"
module(..., package.seeall)

local sockets = {}
-- 单次发送数据最大值
local SENDSIZE = 1400
-- 缓冲区最大下标
local INDEX_MAX = 128

--- SOCKET 是否有可用
-- @return 可用true,不可用false
socket.isReady = link.isReady

local function errorInd(error)
    for _, c in pairs(sockets) do -- IP状态出错时，通知所有已连接的socket
        c.error = error
        c.connected = false
        if error == 'CLOSED' then
            sys.publish("SOCKET" .. c.id .. "_ACTIVE", false)
        end
        if c.co and coroutine.status(c.co) == "suspended" then coroutine.resume(c.co, false) end
    end
end

sys.subscribe("IP_ERROR_IND", function()errorInd('IP_ERROR_IND') end)
sys.subscribe('IP_SHUT_IND', function()errorInd('CLOSED') end)

-- 创建socket函数
local mt = {__index = {}}
local function socket(protocol, cert)
    local ssl = protocol:match("SSL")
    local co = coroutine.running()
    if not co then
        log.warn("socket.socket: socket must be called in coroutine")
        return nil
    end
    -- 实例的属性参数表
    local o = {
        id = nil,
        protocol = protocol,
        ssl = ssl,
        cert = cert,
        co = co,
        input = {},
        output = {},
        wait = "",
        connected = false,
        iSubscribe = false,
    }
    return setmetatable(o, mt)
end

--- 创建基于TCP的socket对象
-- @bool[opt=nil] ssl，是否为ssl连接，true表示是，其余表示否
-- @table[opt=nil] cert，ssl连接需要的证书配置，只有ssl参数为true时，才参数才有意义，cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
-- }
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage
-- c = socket.tcp()
-- c = socket.tcp(true)
-- c = socket.tcp(true, {caCert="ca.crt"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key", clientPassword="123456"})
function tcp(ssl, cert)
    return socket("TCP" .. (ssl == true and "SSL" or ""), (ssl == true) and cert or nil)
end

--- 创建基于UDP的socket对象
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage c = socket.udp()
function udp()
    return socket("UDP")
end

--- 连接服务器
-- @string address 服务器地址，支持ip和域名
-- @param port string或者number类型，服务器端口
-- @return bool result true - 成功，false - 失败
-- @return string ,id '0' -- '8' ,返回通道ID编号
-- @usage  c = socket.tcp(); c:connect();
function mt.__index:connect(address, port)
    assert(self.co == coroutine.running(), "socket:connect: coroutine mismatch")
    
    if not link.isReady() then
        log.info("socket.connect: ip not ready")
        return false
    end
    if self.protocol == 'TCP' then
        self.id = socketcore.sock_conn(0, address, port)
    elseif self.protocol == 'TCPSSL' then
        local cert = {hostName = address}
        if self.cert then
            if self.cert.caCert then
                if self.cert.caCert:sub(1, 1) ~= "/" then self.cert.caCert = "/lua/" .. self.cert.caCert end
                cert.caCert = io.readFile(self.cert.caCert)
            end
            if self.cert.clientCert then
                if self.cert.clientCert:sub(1, 1) ~= "/" then self.cert.clientCert = "/lua/" .. self.cert.clientCert end
                cert.clientCert = io.readFile(self.cert.clientCert)
            end
            if self.cert.clientKey then
                if self.cert.clientKey:sub(1, 1) ~= "/" then self.cert.clientKey = "/lua/" .. self.cert.clientKey end
                cert.clientKey = io.readFile(self.cert.clientKey)
            end
        end
        self.id = socketcore.sock_conn(2, address, port, cert)
    else
        self.id = socketcore.sock_conn(1, address, port)
    end
    if not self.id then
        log.info("socket:connect: core sock conn error")
        return false
    end
    log.info("socket:connect-coreid,prot,addr,port,cert", self.id, self.protocol, address, port, self.cert)
    sockets[self.id] = self
    self.wait = "SOCKET_CONNECT"
    if not coroutine.yield() then return false end
    log.info("socket:connect: connect ok")
    self.connected = true
    sys.publish("SOCKET" .. self.id .. "_ACTIVE", true)
    return true, self.id
end
--- 发送数据
-- @string data 数据
-- @return result true - 成功，false - 失败
-- @usage  c = socket.tcp(); c:connect(); c:send("12345678");
function mt.__index:send(data)
    if self.id == nil then
        log.warn('socket.client:send', 'closed')
        return false
    end
    if data and data ~= "" then table.insert(self.output, data) end
    if self.wait == "+RECEIVE" then coroutine.resume(self.co, false) end
    return true
end
--- 接收数据
-- @number[opt=0] timeout 可选参数，接收超时时间，单位毫秒
-- @string[opt=nil] msg 可选参数，控制socket所在的线程退出recv阻塞状态
-- @return result 数据接收结果，true表示成功，false表示失败
-- @return data 如果成功的话，返回接收到的数据；超时时返回错误为"timeout"；msg控制退出时返回msg
-- @usage c = socket.tcp(); c:connect()
-- @usage result, data = c:recv()
-- @usage false,msg,param = c:recv(60000,"publish_msg")
function mt.__index:recv(timeout, msg)
    assert(self.co == coroutine.running(), "socket:recv: coroutine mismatch")
    if self.error then
        log.warn('socket.client:recv', 'error', self.error)
        return false
    end
    if msg and not iSubscribe then
        iSubscribe = true
        sys.subscribe(msg, function(data)
            table.insert(self.output, data)
            log.info("当前self.wait的状态:", self.wait)
            if self.wait == "+RECEIVE" then coroutine.resume(self.co, false) end
        end)
    end
    local data = table.concat(self.output)
    self.output = {}
    for i = 1, string.len(data), SENDSIZE do
        -- 按最大MTU单元对data分包
        self.wait = "SOCKET_SEND"
        socketcore.sock_send(self.id, data:sub(i, i + SENDSIZE - 1))
        if not coroutine.yield() then return false end
    end
    
    if #self.input == 0 then
        self.wait = "+RECEIVE"
        if timeout and timeout > 0 then
            local r, s = sys.wait(timeout)
            if r == nil then
                return false, "timeout"
            elseif r == false then
                return false, msg, ""
            else
                return r, s
            end
        else
            return coroutine.yield()
        end
    end
    
    if self.protocol == "UDP" then
        return true, table.remove(self.input)
    else
        local s = table.concat(self.input)
        self.input = {}
        return true, s
    end
end

--- 销毁一个socket
-- @return nil
-- @usage  c = socket.tcp(); c:connect(); c:send("123"); c:close()
function mt.__index:close()
    assert(self.co == coroutine.running(), "socket:close: coroutine mismatch")
    if self.connected then
        log.info("socket:sock_close", self.id)
        self.connected = false
        socketcore.sock_close(self.id)
        self.wait = "SOCKET_CLOSE"
        coroutine.yield()
        sys.publish("SOCKET" .. self.id .. "_ACTIVE", false)
    end
    if self.id ~= nil then
        sockets[self.id] = nil
    end
end

local function on_response(msg)
    local t = {
        [rtos.MSG_SOCK_CLOSE_CNF] = 'SOCKET_CLOSE',
        [rtos.MSG_SOCK_SEND_CNF] = 'SOCKET_SEND',
        [rtos.MSG_SOCK_CONN_CNF] = 'SOCKET_CONNECT',
    }
    if not sockets[msg.socket_index] then
        log.warn('response on nil socket', msg.socket_index, msg.id)
        return
    end
    if sockets[msg.socket_index].wait ~= t[msg.id] then
        log.warn('response on invalid wait', sockets[msg.socket_index].id, sockets[msg.socket_index].wait, t[msg.id], msg.socket_index)
        return
    end
    log.info("socket:on_response:", msg.socket_index, t[msg.id], msg.result)
    coroutine.resume(sockets[msg.socket_index].co, msg.result == 0)
end

rtos.on(rtos.MSG_SOCK_CLOSE_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CONN_CNF, on_response)
rtos.on(rtos.MSG_SOCK_SEND_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CLOSE_IND, function(msg)
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    sockets[msg.socket_index].connected = false
    sockets[msg.socket_index].error = 'CLOSED'
    sys.publish("SOCKET" .. sockets[msg.socket_index].id .. "_ACTIVE", false)
    coroutine.resume(sockets[msg.socket_index].co, false)
end)
rtos.on(rtos.MSG_SOCK_RECV_IND, function(msg)
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    
    local s = socketcore.sock_recv(msg.socket_index, msg.recv_len)
    if sockets[msg.socket_index].wait == "+RECEIVE" then
        coroutine.resume(sockets[msg.socket_index].co, true, s)
    else -- 数据进缓冲区，缓冲区溢出采用覆盖模式
        if #sockets[msg.socket_index].input > INDEX_MAX then
            log.error("socket recv", "out of stack")
            sockets[msg.socket_index].input = {}
        end
        table.insert(sockets[msg.socket_index].input, s)
    end
end)

function printStatus()
    for _, client in pairs(sockets) do
        for k, v in pairs(client) do
            log.info('socket.printStatus', 'client', client.id, k, v)
        end
    end
end
