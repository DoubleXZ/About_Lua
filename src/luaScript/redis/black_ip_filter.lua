---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by xuexiao.
--- DateTime: 2022/2/19 下午2:54
---
-- 导入自定义模块
local basic = require("luaScript.module.common.basic")
local redisOp = require("luaScript.redis.RedisOperator")

local ip = basic.getClientIP();
basic.log("获取到客户端IP: "..ip);

basic.log("首先获取Nginx共享内存中的黑名单列表，并判断...")
-- 此处获取Nginx配置文件中定义的共享内存内存变量：black_ip_list
local black_ip_list = ngx.shared.black_ip_list;
basic.log("Nginx共享内存中的黑名单列表【black_ip_list】 type is "..type(black_ip_list))
basic.log("Nginx共享内存中的黑名单列表【black_ip_list】: "..basic.tableToStr(black_ip_list));

-- 获取本地缓存的刷新时间
local last_update_time = black_ip_list:get("last_update_time");
basic.log("Nginx共享内存中的黑名单列表last_update_time type is "..type(last_update_time))
basic.log("Nginx共享内存中的黑名单列表last_update_time: "..basic.toStringEx(last_update_time))


if last_update_time ~= nil then  -- last_update_time不等于nil
    basic.log("last_update_time不等于nil...")
    local now = ngx.now();
    basic.log("now() result type is ".. type(now)..", and now = "..now);
    local dif_time = ngx.now() - last_update_time;
    basic.log("dif_time = "..dif_time);
    if dif_time < 60 then --缓存1分钟，未过期
        if black_ip_list:get(ip) then -- 命中Nginx本地缓存的黑名单
            basic.log("IP: "..ip.."命中Nginx本地缓存的黑名单!")
            return ngx.exit(ngx.HTTP_FORBIDDEN);
        end
        return;
    end
end

basic.log("未命中Nginx本地缓存黑名单，继续判断是否命中Redis中的黑名单...")
local KEY = "limit:ip:blacklist";
local red = redisOp:new();

red:open();

local ip_blacklist = red:getSmembers(KEY);
red:close();
basic.log("Redis缓存中的黑名单列表【ip_blacklist】 type is "..type(ip_blacklist))
basic.log("Redis缓存中的黑名单列表【ip_blacklist】: "..basic.tableToStr(ip_blacklist));
basic.log("Redis缓存中的黑名单列表【ip_blacklist】长度为: "..basic.table_length(ip_blacklist))

if basic.table_length(ip_blacklist) == 0 then
    --此处这么写有问题，ip_blacklist是table，not ip_blacklist 不能判断出table是空的，改为使用table的长度来获得
    --但是使用table.getn(tableName)方法只能获得有序table的大小，对于无序table，需要遍历累加获得长度
--if not ip_blacklist then
    basic.log("Redis缓存中的黑名单列表为空，不拦截...")
    basic.log("black ip set is null");
    return;
else
    basic.log("Redis缓存中的黑名单列表不为空，刷新本地缓存...")
    --刷新本地缓存
    black_ip_list:flush_all();

    basic.log("同步Redis黑名单到本地缓存...")
    for i, ip in ipairs(ip_blacklist) do
        basic.log("第"..i.."个IP:"..ip.."同步成功");
        black_ip_list:set(ip, true);
    end

    basic.log("设置本地缓存的最新更新时间")
    black_ip_list:set("last_update_time", ngx.now());
end

if black_ip_list:get(ip) then
    return ngx.exit(ngx.HTTP_FORBIDDEN); --直接返回403
end

