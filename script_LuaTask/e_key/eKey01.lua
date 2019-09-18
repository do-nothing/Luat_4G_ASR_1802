module(...,package.seeall)

require"pins"
require"aLiYun"
require"misc"
require"pm"

local PRODUCT_KEY = "IgW98z2NGr4"
local function getDeviceName()
    -- return misc.getImei()
    return "john"
end
local function setDeviceSecret(s)
    --默认使用设备的SN作为设备密钥，用户可以根据项目需求自行修改
    misc.setSn(s)
end

local function getDeviceSecret()
    -- return misc.getSn()
    return "Q10SL4aDu3JUPsdR6NYiIxUZ6PpKHl0P"
end

--阿里云客户端是否处于连接状态
local sConnected

local publishCnt = 1

--[[
函数名：pubqos1testackcb
功能  ：发布1条qos为1的消息后收到PUBACK的回调函数
参数  ：
		usertag：调用mqttclient:publish时传入的usertag
		result：true表示发布成功，false或者nil表示失败
返回值：无
]]
local function publishTestCb(result,para)
    log.info("testALiYun.publishTestCb",result,para)
    sys.timerStart(publishTest,20000)
    publishCnt = publishCnt+1
end

--发布一条QOS为1的消息
function publishTest()
    if sConnected then
        --注意：在此处自己去控制payload的内容编码，aLiYun库中不会对payload的内容做任何编码转换
        aLiYun.publish("/"..PRODUCT_KEY.."/"..getDeviceName().."/update","qos1data",1,publishTestCb,"publishTest_"..publishCnt)
    end
end


local setGpio53Fnc = pins.setup(pio.P1_21,0)
local setGpio65Fnc = pins.setup(pio.P2_1,0)

---数据接收的处理函数
-- @string topic，UTF8编码的消息主题
-- @number qos，消息质量等级
-- @string payload，原始编码的消息负载
local function rcvCbFnc(topic,qos,payload)
    log.info("testALiYun.rcvCbFnc",topic,qos,payload)
    setGpio53Fnc(1)
    log.info("testGpioSingle.setGpio53Fnc",1)
end

--- 连接结果的处理函数
-- @bool result，连接结果，true表示连接成功，false或者nil表示连接失败
local function connectCbFnc(result)
    log.info("testALiYun.connectCbFnc",result)
    sConnected = result
    if result then
        --订阅主题，不需要考虑订阅结果，如果订阅失败，aLiYun库中会自动重连
        aLiYun.subscribe({["/"..PRODUCT_KEY.."/"..getDeviceName().."/get"]=0, ["/"..PRODUCT_KEY.."/"..getDeviceName().."/get"]=1})
        --注册数据接收的处理函数
        aLiYun.on("receive",rcvCbFnc)
        --PUBLISH消息测试
        publishTest()
        setGpio65Fnc(1)
    end
end

-- 认证结果的处理函数
-- @bool result，认证结果，true表示认证成功，false或者nil表示认证失败
local function authCbFnc(result)
    log.info("testALiYun.authCbFnc",result)
end

--采用一机一密认证方案时：
--配置：ProductKey、获取DeviceName的函数、获取DeviceSecret的函数；其中aLiYun.setup中的第二个参数必须传入nil
aLiYun.setup(PRODUCT_KEY,nil,getDeviceName,getDeviceSecret)

--采用一型一密认证方案时：
--配置：ProductKey、ProductSecret、获取DeviceName的函数、获取DeviceSecret的函数、设置DeviceSecret的函数
--aLiYun.setup(PRODUCT_KEY,PRODUCE_SECRET,getDeviceName,getDeviceSecret,setDeviceSecret)

--setMqtt接口不是必须的，aLiYun.lua中有这个接口设置的参数默认值，如果默认值满足不了需求，参考下面注释掉的代码，去设置参数
--aLiYun.setMqtt(0)
aLiYun.on("auth",authCbFnc)
aLiYun.on("connect",connectCbFnc)


--要使用阿里云OTA功能，必须参考本文件124或者126行aLiYun.setup去配置参数
--然后加载阿里云OTA功能模块(打开下面的代码注释)
require"aLiYunOta"

-------------------------------------------------


function gpio54IntFnc(msg)
    if msg==cpu.INT_GPIO_POSEDGE then
        setGpio65Fnc(0)
        setGpio53Fnc(0)
    else
        setGpio65Fnc(1)
    end
end

--GPIO54配置为中断，可通过getGpio54Fnc()获取输入电平，产生中断时，自动执行gpio54IntFnc函数
getGpio54Fnc = pins.setup(pio.P1_22,gpio54IntFnc)

